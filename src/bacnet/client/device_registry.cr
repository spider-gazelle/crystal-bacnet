require "./*"

class BACnet::Client::DeviceRegistry
  class DeviceInfo
    def initialize(@object_ptr, @network, @address, @max_adpu_length = nil, @segmentation_supported = nil, @vendor_id = nil, link_address : Socket::IPAddress | Bytes? = nil)
      case link_address
      in Socket::IPAddress
        @ip_address = link_address
      in Bytes
        @vmac = link_address
      in Nil
      end
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
    property ip_address : Socket::IPAddress? = nil
    property vmac : Bytes? = nil
    property network : UInt16?
    property address : String?

    def link_address
      ip_address || vmac
    end

    def link_address_friendly
      addr = link_address
      case addr
      in Socket::IPAddress
        addr.to_s
      in Bytes
        addr.hexstring
      in Nil
      end
    end

    def to_address_str
      address ? "#{link_address_friendly}[#{network}:#{address}]" : link_address_friendly
    end

    def instance_id
      object_ptr.instance_number
    end

    def object_type
      object_ptr.object_type
    end
  end

  class ObjectInfo
    def initialize(@object_ptr, @network, @address, link_address : Socket::IPAddress | Bytes? = nil)
      case link_address
      in Socket::IPAddress
        @ip_address = link_address
      in Bytes
        @vmac = link_address
      in Nil
      end
    end

    property? ready : Bool = false

    property name : String = ""
    property unit : BACnet::Unit? = nil
    property value : BACnet::Object? = nil
    property changed : ::Time = ::Time.utc

    def value=(value)
      @value = value
      @changed = ::Time.utc
    end

    # Connection details
    property object_ptr : BACnet::ObjectIdentifier
    property ip_address : Socket::IPAddress? = nil
    property vmac : Bytes? = nil
    property network : UInt16?
    property address : String?

    def link_address
      ip_address || vmac
    end

    def link_address_friendly
      addr = link_address
      case addr
      in Socket::IPAddress
        addr.to_s
      in Bytes
        addr.hexstring
      in Nil
      end
    end

    def to_address_str
      address ? "#{link_address_friendly}[#{network}:#{address}]" : link_address_friendly
    end

    def instance_id
      object_ptr.instance_number
    end

    def object_type
      object_ptr.object_type
    end

    def sync_value(client)
      value_resp = client.read_property(@object_ptr, BACnet::PropertyIdentifier::PropertyType::PresentValue, nil, @network, @address, link_address: link_address).get
      self.value = client.parse_complex_ack(value_resp)[:objects][0]?.try &.as(BACnet::Object)
    rescue unknown : BACnet::UnknownPropertyError
    end
  end

  def initialize(@client : BACnet::Client::IPv4 | BACnet::Client::SecureConnect, @log = ::BACnet.logger)
    @devices = {} of UInt32 => DeviceInfo
    @new_device_callbacks = [] of DeviceInfo -> Nil
    @client.on_broadcast do |message, remote_address|
      app = message.application.as(BACnet::UnconfirmedRequest)
      case app.service
      when .i_am?
        details = client.parse_i_am(message)
        log.info { "received IAm message #{details}" }
        inspect_device(**details, link_address: remote_address)
      when .i_have?
        details = client.parse_i_have(message)
        log.info { "received IHave message #{details}" }
        inspect_device details[:device_id], details[:network], details[:address], link_address: remote_address
      end
    end
  end

  @mutex : Mutex = Mutex.new(:reentrant)
  getter log : ::Log

  # returns a list of the devices found
  def devices
    @mutex.synchronize { @devices.compact_map { |(_key, device)| device if device.objects_listed? } }
  end

  # register to be informed when a new device is found
  def on_new_device(&callback : DeviceInfo -> Nil)
    @new_device_callbacks << callback
  end

  def inspect_device(object_id, network, address, max_adpu_length = nil, segmentation_supported = nil, vendor_id = nil, link_address : Socket::IPAddress | Bytes? = nil)
    device_id = object_id.instance_number

    @mutex.synchronize do
      if @devices.has_key?(device_id)
        log.debug { "ignoring inspect request as already parsed #{device_id} (#{link_address})" }
        return
      end
    end

    device = DeviceInfo.new(object_id, network, address, max_adpu_length, segmentation_supported, vendor_id, link_address: link_address)
    @mutex.synchronize { @devices[device_id] = device }

    begin
      name_resp = @client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, network, address, link_address: link_address).get
      device.name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      log.warn(exception: error) { "failed to obtain device name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    begin
      name_resp = @client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::VendorName, nil, network, address, link_address: link_address).get
      device.vendor_name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      log.warn(exception: error) { "failed to obtain vendor name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    begin
      name_resp = @client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ModelName, nil, network, address, link_address: link_address).get
      device.model_name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      log.warn(exception: error) { "failed to obtain model name for #{print_addr(device)}: #{device.object_type}[#{device.instance_id}]" }
    end

    # Grab the number of properties
    response = @client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, network, address, link_address: link_address).get
    max_properties = @client.parse_complex_ack(response)[:objects][0].to_u64

    # Grab the object details of all the properties
    # Index 0 == max index
    # Index 1 == device info
    # Index 2..max == object info
    failed = 0
    (2..max_properties).each do |index|
      success = query_device(device, index, max_properties)

      # Some devices specify more objects than actually exist
      unless success
        failed += 1
        break if failed > 2
      end
    end

    # obtain object information
    device.objects_listed = true
    device.objects.each { |object| parse_object_info(object) }

    # notify listeners
    @new_device_callbacks.each &.call(device)
    device
  rescue error
    @mutex.synchronize { @devices.delete(device_id) }
    log.debug(exception: error) { "failed to obtain object list for #{device_id} (#{link_address})" }
    nil
  end

  protected def query_device(device, index, max_index)
    response = @client.read_property(device.object_ptr, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, device.network, device.address, link_address: device.link_address).get
    details = @client.parse_complex_ack(response)
    object = ObjectInfo.new(details[:objects][0].to_object_id, device.network, device.address, link_address: device.link_address)
    device.objects << object

    log.trace { "new object found at address #{print_addr(object)}: #{object.object_type}-#{object.instance_id}" }
    true
  rescue error
    log.error(exception: error) { "failed to query device at address #{print_addr(device)}: ObjectList[#{index}]" }
    false
  end

  alias ObjectType = ::BACnet::ObjectIdentifier::ObjectType

  # TODO:: map these fields out more
  OBJECTS_WITH_UNITS = [
    ObjectType::AnalogInput, ObjectType::AnalogOutput, ObjectType::AnalogValue,
    ObjectType::IntegerValue, ObjectType::LargeAnalogValue, ObjectType::PositiveIntegerValue,
    ObjectType::Accumulator, ObjectType::PulseConverter, ObjectType::Loop,
  ]

  OBJECTS_WITH_VALUES = OBJECTS_WITH_UNITS + [
    ObjectType::BinaryInput, ObjectType::BinaryOutput, ObjectType::BinaryValue,
    ObjectType::Calendar, ObjectType::Command, ObjectType::LoadControl, ObjectType::AccessDoor,
    ObjectType::LifeSafetyPoint, ObjectType::LifeSafetyZone, ObjectType::MultiStateInput,
    ObjectType::MultiStateOutput, ObjectType::MultiStateValue, ObjectType::Schedule,
    ObjectType::DatetimeValue, ObjectType::BitstringValue, ObjectType::OctetstringValue,
    ObjectType::DateValue, ObjectType::DatetimePatternValue, ObjectType::TimePatternValue,
    ObjectType::DatePatternValue, ObjectType::AlertEnrollment, ObjectType::Channel,
    ObjectType::LightingOutput, ObjectType::CharacterStringValue, ObjectType::TimeValue,
  ]

  def parse_object_info(object)
    log.trace { "parsing object info for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }

    # All objects have a name
    begin
      name_resp = @client.read_property(object.object_ptr, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, object.network, object.address, link_address: object.link_address).get
      object.name = @client.parse_complex_ack(name_resp)[:objects][0].value.as(String)
    rescue error
      log.error(exception: error) { "failed to obtain object information for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }
      return
    end

    # Not all objects have a unit
    if OBJECTS_WITH_UNITS.includes? object.object_ptr.object_type
      begin
        unit_resp = @client.read_property(object.object_ptr, BACnet::PropertyIdentifier::PropertyType::Units, nil, object.network, object.address, link_address: object.link_address).get
        object.unit = BACnet::Unit.new @client.parse_complex_ack(unit_resp)[:objects][0].to_i
      rescue unknown : BACnet::UnknownPropertyError
      rescue error
        log.error(exception: error) { "failed to obtain unit for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }
      end
    end

    # Not all objects have a value
    if OBJECTS_WITH_VALUES.includes? object.object_ptr.object_type
      begin
        value_resp = @client.read_property(object.object_ptr, BACnet::PropertyIdentifier::PropertyType::PresentValue, nil, object.network, object.address, link_address: object.link_address).get
        object.value = @client.parse_complex_ack(value_resp)[:objects][0]?.try &.as(BACnet::Object)
      rescue unknown : BACnet::UnknownPropertyError
      rescue error
        log.error(exception: error) { "failed to obtain value for #{print_addr(object)}: #{object.object_type}[#{object.instance_id}]" }
      end
    end

    object.ready = true
    log.trace { "object #{print_addr(object)}: #{object.object_type}-#{object.instance_id} parsing complete" }
  end

  protected def print_addr(object)
    object.to_address_str
  end
end
