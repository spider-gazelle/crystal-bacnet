require "../src/bacnet"
require "promise"
require "socket"
require "log"
require "set"

class BACnet::Client
  Log = ::Log.for("bacnet.client")

  class Tracker
    def initialize(@request_id, @address, @request)
      @promise = Promise.new(Message::IPv4?)
    end

    property request_id : UInt8
    property promise : Promise::DeferredPromise(Message::IPv4?)
    property address : Socket::IPAddress
    property request : Message::IPv4
    property attempt : Int32 = 0
  end

  class ObjectInfo
    property? ready : Bool = false

    property name : String = ""
    property unit : Unit? = nil
    property! value : Object
    property changed : ::Time = ::Time.utc

    def value=(value)
      @changed = ::Time.utc
      @value = value
    end

    property instance : UInt32 = 0_u32
    property object_type : ObjectIdentifier::ObjectType = ObjectIdentifier::ObjectType::AnalogInput
  end

  class DeviceInfo
    property? objects_listed : Bool = false

    property objects : Array(ObjectInfo) = [] of ObjectInfo
    property name : String = ""
    property vendor_name : String = ""
    property model_name : String = ""

    property instance : UInt32 = 0_u32

    def object_type
      ObjectIdentifier::ObjectType::Device
    end
  end

  def initialize(
    @retries : Int32 = 3,
    @timeout : ::Time::Span = 5.seconds,
    &@transmit : (Bytes, Socket::IPAddress) -> Nil
  )
    @invoke_id = rand(0xFF).to_u8
    @in_flight = {} of UInt8 => Tracker
    @devices = Hash(Socket::IPAddress, DeviceInfo).new do |hash, ip|
      hash[ip] = DeviceInfo.new
    end
  end

  @invoke_id : UInt8
  @mutex : Mutex = Mutex.new(:reentrant)
  @parsing : Set(String) = Set(String).new

  property devices : Hash(Socket::IPAddress, DeviceInfo)

  protected def perform_transmit(message : Message::IPv4, address : Socket::IPAddress)
    bytes = message.to_slice

    # add the size header
    size = bytes.size.to_u16
    io = IO::Memory.new(bytes[2, 2])
    io.write_bytes(size, IO::ByteFormat::BigEndian)

    @transmit.call(bytes, address)
  end

  protected def send_and_retry(tracker : Tracker)
    promise = Promise.new(Message::IPv4?, @timeout)
    tracker.promise.then { |message| promise.resolve(message) }
    tracker.promise.catch { |error| promise.reject(error); raise error }
    promise.catch do |error|
      case error
      when Promise::Timeout
        Log.debug { "timeout sending message to #{tracker.address.inspect}" }
        tracker.attempt += 1
        if tracker.attempt <= @retries
          send_and_retry(tracker)
        else
          @mutex.synchronize { @in_flight.delete(tracker.request_id) }
          tracker.promise.reject(error)
          error
        end
      else # propagate the error (this shouldn't happen)
        raise error
      end
    end

    @mutex.synchronize { @in_flight[tracker.request_id] = tracker }
    perform_transmit(tracker.request, tracker.address)
    tracker.promise
  end

  protected def next_invoke_id
    @mutex.synchronize do
      next_id = @invoke_id &+ 1
      @invoke_id = next_id
    end
  end

  def who_is(destination : Int = 0xFFFF_u16)
    data_link = Message::IPv4::BVLCI.new
    data_link.request_type = Message::IPv4::Request::OriginalBroadcastNPDU

    # broadcast
    network = NPDU.new
    network.destination_specifier = true
    network.destination.address = 0xFFFF_u16
    network.hop_count = 255_u8

    request = UnconfirmedRequest.new
    request.service = UnconfirmedService::WhoIs

    message = Message::IPv4.new(data_link, network, request)
    perform_transmit(message, Socket::IPAddress.new("255.255.255.255", 0xBAC0))
    message
  end

  def who_is(address : Socket::IPAddress)
    data_link = Message::IPv4::BVLCI.new
    data_link.request_type = Message::IPv4::Request::OriginalUnicastNPDU

    network = NPDU.new
    request = UnconfirmedRequest.new
    request.service = UnconfirmedService::WhoIs

    message = Message::IPv4.new(data_link, network, request)
    perform_transmit(message, address)
    message
  end

  def read_property(
    address : Socket::IPAddress,
    object_type : ObjectIdentifier::ObjectType,
    instance : Int,
    property : PropertyIdentifier::PropertyType,
    index : Int? = nil
  )
    data_link = Message::IPv4::BVLCI.new
    data_link.request_type = Message::IPv4::Request::OriginalUnicastNPDU

    network = NPDU.new
    network.expecting_reply = true

    request = ConfirmedRequest.new
    request.max_size_indicator = 5_u8
    request.invoke_id = next_invoke_id
    request.service = ConfirmedService::ReadProperty

    object_id = ObjectIdentifier.new
    object_id.object_type = object_type
    object_id.instance_number = instance.to_u32
    object = Object.new.set_value(object_id)
    object.context_specific = true
    object.short_tag = 0_u8

    property_id = PropertyIdentifier.new
    property_id.property_type = property
    property_obj = Object.new.set_value(property_id)
    property_obj.context_specific = true
    property_obj.short_tag = 1_u8

    objects = [object, property_obj]
    if index
      index_obj = Object.new.set_value(index.to_u32)
      index_obj.context_specific = true
      index_obj.short_tag = 2_u8
      objects << index_obj
    end

    message = Message::IPv4.new(data_link, network, request, objects)
    tracker = Tracker.new(request.invoke_id, address, message)
    send_and_retry(tracker).catch do |error|
      if error.is_a?(UnknownPropertyError) # We want to return nil if this is the case
        nil
      else
        raise Error.new("failed to read #{object_type}:#{instance}##{property} with #{error.message}", error)
      end
    end
  end

  def self.parse_i_am(objects)
    obj_id = objects[0].value.as(BACnet::ObjectIdentifier)
    {
      object_type:            obj_id.object_type,
      object_instance:        obj_id.instance_number,
      max_adpu_length:        objects[1].to_u64,
      segmentation_supported: SegmentationSupport.from_value(objects[2].to_u64),
      vendor_id:              objects[3].to_u64,
    }
  end

  def self.read_complex_ack(objects)
    obj_id = objects[0].to_object_id
    props = {
      object_type:     obj_id.object_type,
      object_instance: obj_id.instance_number,
      property:        objects[1].to_property_id.property_type,
      data:            objects[-1].objects,
    }
    objects.size > 3 ? props.merge({index: objects[2].to_u64}) : props
  end

  def parse_object_info(address, object)
    Log.trace { "parsing object info for #{address}: #{object.object_type}[#{object.instance}]" }
    begin
      name_resp, unit_resp, value_resp = Promise.all(
        read_property(address, object.object_type, object.instance, BACnet::PropertyIdentifier::PropertyType::ObjectName),
        read_property(address, object.object_type, object.instance, BACnet::PropertyIdentifier::PropertyType::Units),
        read_property(address, object.object_type, object.instance, BACnet::PropertyIdentifier::PropertyType::PresentValue)
      ).get
    rescue error
      Log.error { "failed to obtain object information for #{address}: #{object.object_type}[#{object.instance}]\n#{error.message}" }
      return
    end

    object.name = Client.read_complex_ack(name_resp.not_nil!.objects)[:data][0].value.as(String)
    object.unit = Unit.from_value Client.read_complex_ack(unit_resp.objects)[:data][0].to_u64 if unit_resp
    object.value = Client.read_complex_ack(value_resp.objects)[:data][0].as(BACnet::Object) if value_resp

    object.ready = true
    Log.trace { "object #{address}: #{object.object_type}-#{object.instance} parsing complete" }
  rescue error
    Log.error { "error applying object values for #{address}: #{object.object_type}[#{object.instance}]\n#{error.message}" }
  end

  # Index 0 == max index
  # Index 1 == device info
  # Index 2..max == object info
  protected def query_device(address, object_type, object_instance, index, max_index)
    device = @devices[address]

    begin
      response = read_property(address, object_type, object_instance, BACnet::PropertyIdentifier::PropertyType::ObjectList, index).get
      unless response
        Log.debug { "property not found #{address}: #{object_type}-#{object_instance}.ObjectList[#{index}]" }
        return unless response # property did not exist
      end
      details = Client.read_complex_ack(response.objects)

      obj_id = details[:data][0].to_object_id
      object = ObjectInfo.new
      object.object_type = obj_id.object_type
      object.instance = obj_id.instance_number
      device.objects << object

      Log.trace { "new object found at address #{address}: #{object.object_type}-#{object.instance}" }
    rescue error
      Log.error { "failed to query device at address #{address}: #{object_type}-#{object_instance}" }
    end
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def received(message : BACnet::Message::IPv4, address : Socket::IPAddress)
    Log.trace { "received #{message.data_link.request_type} message from #{address.inspect} - #{message.application.class}" }

    # Nil | ConfirmedRequest | UnconfirmedRequest | SimpleAck | ComplexAck | SegmentAck | ErrorResponse | RejectResponse | AbortResponse
    app = message.application
    case app
    in Nil, ConfirmedRequest
      Log.debug { "ignoring request\n#{message.inspect}" }
    in UnconfirmedRequest
      case app.service
      when .i_am?
        details = Client.parse_i_am(message.objects)

        # ignore duplicate requests
        device_id = "#{address}-#{details[:object_instance]}"
        if @parsing.includes?(device_id)
          Log.debug { "ignoring duplicate iam request\n#{message.inspect}" }
          return
        end
        @parsing << device_id

        device = @devices[address]
        device.instance = details[:object_instance]
        promise = read_property(address, details[:object_type], details[:object_instance], BACnet::PropertyIdentifier::PropertyType::ObjectList, 0)
        promise.then do |response|
          raise "property missing" unless response
          list_details = Client.read_complex_ack(response.objects)
          max_properties = list_details[:data][0].to_u64

          (2..max_properties).each do |index|
            query_device(
              address,
              list_details[:object_type],
              list_details[:object_instance],
              index,
              max_properties
            )
          end

          # obtain object information
          device = @devices[address]
          device.objects_listed = true
          device.objects.each { |object| parse_object_info(address, object) }
        end
      else
        Log.debug { "ignoring unconfirmed request\n#{message.inspect}" }
      end
    in ErrorResponse, AbortCode, RejectResponse
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        if app.is_a?(ErrorResponse)
          klass = ErrorClass.from_value message.objects[0].to_u64
          code = ErrorCode.from_value message.objects[1].to_u64

          error_message = "request failed with #{app.class} - #{klass}: #{code}"

          error = case code
                  when ErrorCode::UnknownProperty
                    UnknownPropertyError.new(error_message)
                  else
                    Error.new(error_message)
                  end
          tracker.promise.reject(error)
        else
          tracker.promise.reject(Error.new("request failed with #{app.class} - #{app.reason}"))
        end
      else
        Log.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in ComplexAck, SimpleAck, SegmentAck
      # TODO:: handle segmented responses
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        tracker.promise.resolve(message)
      else
        Log.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in BinData
      # https://github.com/crystal-lang/crystal/issues/9116
      # https://github.com/crystal-lang/crystal/issues/9235
      Log.fatal { "compiler bug" }
      raise "should never select this case"
    end
  end
end
