require "./*"

class BACnet::Client::DeviceRegistry
  Log = ::Log.for("bacnet.registry")

  class DeviceInfo
    def initialize(@ip_address, @object_ptr, @network, @address, @max_adpu_length = nil, @segmentation_supported = nil, @vendor_id = nil)
    end

    property? objects_listed : Bool = false

    # Device properties
    property objects : Array(ObjectInfo) = [] of ObjectInfo
    property name : String = ""
    property vendor_name : String = ""
    property model_name : String = ""

    # Device IAm details
    property object_ptr : BACnet::ObjectIdentifier
    property max_adpu_length : UInt64? = nil
    property segmentation_supported : BACnet::SegmentationSupport? = nil
    property vendor_id : UInt64? = nil

    # Connection details
    property ip_address : Socket::IPAddress
    property network : UInt16?
    property address : String?

    def instance_id
      object_ptr.instance_number
    end

    def object_type
      object_ptr.object_type
    end
  end

  class ObjectInfo
    def initialize(@ip_address, @object_ptr, @network, @address)
    end

    property? ready : Bool = false

    property name : String = ""
    property unit : BACnet::Unit? = nil
    property! value : BACnet::Object
    property changed : ::Time = ::Time.utc

    def value=(value)
      @changed = ::Time.utc
      @value = value
    end

    # Connection details
    property object_ptr : BACnet::ObjectIdentifier
    property ip_address : Socket::IPAddress
    property network : UInt16?
    property address : String?

    def instance_id
      object_ptr.instance_number
    end

    def object_type
      object_ptr.object_type
    end
  end

  def initialize(@client : BACnet::Client::IPv4)
    @devices = {} of UInt32 => DeviceInfo
    @new_device_callbacks = [] of DeviceInfo -> Nil
    @client.on_broadcast do |message, remote_address|
      app = message.application.as(BACnet::UnconfirmedRequest)
      case app.service
      when .i_am?
        details = client.parse_i_am(message)
        Log.info { "received IAm message #{details}" }
        inspect_device remote_address, **details
      when .i_have?
        details = client.parse_i_have(message)
        Log.info { "received IHave message #{details}" }
        inspect_device remote_address, details[:device_id], details[:network], details[:address]
      end
    end
  end

  def on_new_device(&callback : DeviceInfo -> Nil)
    @new_device_callbacks << callback
  end

  def inspect_device(ip_address, object_id, network, address, max_adpu_length = nil, segmentation_supported = nil, vendor_id = nil)
    device_id = object_id.instance_number
    if @devices.has_key?(device_id)
      Log.debug { "ignoring inspect request as already parsed #{device_id} (#{ip_address})" }
      return
    end

    device = DeviceInfo.new(ip_address, object_id, network, address, max_adpu_length, segmentation_supported, vendor_id)
    @devices[device_id] = device

    begin
      name_resp = @client.read_property(ip_address, object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, network, address).get
      device.name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      Log.warn(exception: error) { "failed to obtain device name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    begin
      name_resp = @client.read_property(ip_address, object_id, BACnet::PropertyIdentifier::PropertyType::VendorName, nil, network, address).get
      device.vendor_name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      Log.warn(exception: error) { "failed to obtain vendor name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    begin
      name_resp = @client.read_property(ip_address, object_id, BACnet::PropertyIdentifier::PropertyType::ModelName, nil, network, address).get
      device.model_name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      Log.warn(exception: error) { "failed to obtain model name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    # Grab the number of properties
    response = @client.read_property(ip_address, object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, network, address).get
    max_properties = @client.parse_complex_ack(response)[:objects][0].to_u64

    # Grab the object details of all the properties
    # Index 0 == max index
    # Index 1 == device info
    # Index 2..max == object info
    (2..max_properties).each do |index|
      query_device(device, index, max_properties)
    end

    # obtain object information
    device.objects_listed = true
    device.objects.each { |object| parse_object_info(object) }

    # notify listeners
    @new_device_callbacks.each &.call(device)
    device
  rescue error
    @devices.delete(device_id)
    Log.debug(exception: error) { "failed to obtain object list for #{device_id} (#{ip_address})" }
    nil
  end

  protected def query_device(device, index, max_index)
    response = @client.read_property(device.ip_address, device.object_ptr, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, device.network, device.address).get
    details = @client.parse_complex_ack(response)
    object = ObjectInfo.new(device.ip_address, details[:objects][0].to_object_id, device.network, device.address)
    device.objects << object

    Log.trace { "new object found at address #{print_addr(object)}: #{object.object_type}-#{object.instance_id}" }
  rescue error
    Log.error(exception: error) { "failed to query device at address #{print_addr(device)}: ObjectList[#{index}]" }
  end

  def parse_object_info(object)
    Log.trace { "parsing object info for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }

    begin
      name_resp = @client.read_property(object.ip_address, object.object_ptr, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, object.network, object.address).get
      object.name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      Log.error(exception: error) { "failed to obtain object information for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }
      return
    end

    begin
      unit_resp, value_resp = Promise.all(
        @client.read_property(object.ip_address, object.object_ptr, BACnet::PropertyIdentifier::PropertyType::Units, nil, object.network, object.address),
        @client.read_property(object.ip_address, object.object_ptr, BACnet::PropertyIdentifier::PropertyType::PresentValue, nil, object.network, object.address)
      ).get

      object.unit = BACnet::Unit.from_value @client.parse_complex_ack(unit_resp)[:objects][0].to_u64
      object.value = @client.parse_complex_ack(value_resp)[:objects][0].as(BACnet::Object)
    rescue unknown : BACnet::UnknownPropertyError
    rescue error
      Log.error(exception: error) { "failed to obtain object information for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }
      return
    end

    object.ready = true
    Log.trace { "object #{print_addr(object)}: #{object.object_type}-#{object.instance_id} parsing complete" }
  end

  protected def print_addr(object)
    object.address ? "#{object.ip_address}[#{object.network}:#{object.address}]" : object.ip_address.to_s
  end
end