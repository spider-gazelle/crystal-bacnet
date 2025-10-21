require "../src/bacnet"
require "promise"
require "http"
require "uuid"
require "set"

::Log.setup("*", :trace)

class SecureConnectTest
  def initialize(
    @host = "138.80.128.217",
    @path = "/hub",
    @private_key_file = "./private.key",
    @client_cert_file = "./client.pem",
    @uuid : UUID = UUID.v4,
    @timeout : ::Time::Span = 10.seconds,
  )
    tls = OpenSSL::SSL::Context::Client.insecure
    tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    tls.private_key = private_key_file
    tls.certificate_chain = client_cert_file
    @tls = tls

    @vmac = BACnet::Client::SecureConnect.generate_vmac
    @message_id = rand(0xFFFF).to_u16

    spawn do
      (0_u8...UInt8::MAX).each do |id|
        return_invoke_id(id)
      end
    end
  end

  getter host : String
  getter path : String
  getter private_key_file : String
  getter client_cert_file : String
  getter tls : OpenSSL::SSL::Context::Client
  getter uuid : UUID
  getter vmac : Bytes

  @invoke_id : Channel(UInt8) = Channel(UInt8).new(255)
  @message_id : UInt16
  @mutex : Mutex = Mutex.new(:reentrant)
  getter! writer : Channel(BACnet::Message::Secure)

  protected def return_invoke_id(id : UInt8)
    @invoke_id.send(id)
  end

  protected def next_invoke_id : UInt8
    @invoke_id.receive
  end

  protected def next_message_id : UInt16
    @mutex.synchronize do
      next_id = @message_id &+ 1
      @message_id = next_id
    end
  end

  def connect!
    data_link = BACnet::Message::Secure::BVLCI.new
    data_link.request_type = BACnet::Message::Secure::Request::ConnectRequest
    data_link.message_id = next_message_id
    data_link.connect_details.vmac = @vmac
    data_link.connect_details.device_uuid = @uuid.bytes.to_slice
    data_link.connect_details.max_bvlc_length = 65535_u16 # maximum BVLC size
    data_link.connect_details.max_npdu_length = 61327_u16 # maximum BVLC size (65535) minus the 16-byte BVLC header and minus 4192 bytes reserved for data options
    message = BACnet::Message::Secure.new(data_link)

    Log.debug { "--> sending Connect Request" }
    writer.send(message)
  end

  def new_message
    data_link = BACnet::Message::Secure::BVLCI.new
    network = BACnet::NPDU.new
    BACnet::Message::Secure.new(data_link, network)
  end

  def configure_defaults(message)
    data_link = message.data_link
    data_link.request_type = BACnet::Message::Secure::Request::EncapsulatedNPDU
    data_link.source_specifier = true
    data_link.source_vmac = @vmac
    data_link.message_id = next_message_id

    app = message.application
    case app
    when BACnet::ConfirmedRequest
      app.invoke_id = next_invoke_id
    end

    message
  end

  def who_is!
    message = configure_defaults(BACnet::Client::Message::WhoIs.build(new_message))
    data_link = message.data_link
    data_link.destination_specifier = true
    data_link.destination_vmac = BACnet::Message::Secure::BVLCI::BROADCAST_VMAC

    Log.debug { "--> sending WhoIs broadcast" }
    writer.send(message)
  end

  def heartbeat!
    data_link = BACnet::Message::Secure::BVLCI.new
    data_link.request_type = BACnet::Message::Secure::Request::HeartbeatRequest
    data_link.message_id = next_message_id
    message = BACnet::Message::Secure.new(data_link)

    Log.debug { "--> sending Heartbeat" }
    writer.send(message)
  end

  def heartbeat_ack!(message : BACnet::Message::Secure)
    raise ArgumentError.new("expected heartbeat request, not #{message.data_link.request_type}") unless message.data_link.request_type.heartbeat_request?
    message.data_link.request_type = BACnet::Message::Secure::Request::HeartbeatACK
    writer.send(message)
  end

  protected def heartbeat_loop
    loop do
      sleep 60.seconds
      break if writer.closed?
      heartbeat!
    end
  end

  def read_property(
    link_address : Bytes,
    object_id : BACnet::ObjectIdentifier,
    property_id : BACnet::PropertyIdentifier::PropertyType | BACnet::PropertyIdentifier,
    index : Int? = nil,
    network : UInt16? = nil,
    address : String | Bytes? = nil,
  )
    message = configure_defaults(BACnet::Client::Message::ReadProperty.build(
      new_message, object_id,
      property_id, index, network, address
    ))
    message.data_link.destination_address = link_address
    response = track_confirmed_request(message).get
    details = BACnet::Client::Message::ComplexAck.parse(response)
    # {
    #  invoke_id: invoke_id,
    #  service:   service,
    #  object_id: objects[0].to_object_id,
    #  property:  objects[1].to_property_id.property_type,
    #  index:     objects.size > 3 ? objects[2].to_i : nil,
    #  objects:   objects[-1].objects,
    #  network:   network,
    #  address:   address }
    details
  end

  @tracker : Hash(UInt8, Promise::DeferredPromise(BACnet::Message::Secure)) = {} of UInt8 => Promise::DeferredPromise(BACnet::Message::Secure)

  def track_confirmed_request(message : BACnet::Message::Secure) : Promise::DeferredPromise(BACnet::Message::Secure)
    promise = Promise.new(BACnet::Message::Secure, @timeout)
    invoke_id = message.application.as(BACnet::ConfirmedRequest).invoke_id
    promise.catch do |error|
      case error
      when Promise::Timeout
        BACnet.logger.error { "timeout sending message: #{invoke_id}" }
        return_invoke_id(invoke_id)
      end
      raise error
    end
    @tracker[invoke_id] = promise
    writer.send(message)
    promise
  end

  protected def on_connect
    # the client is expected to maintain the connection, not the server
    spawn { heartbeat_loop }

    # perform a who-is to kick off discovery
    who_is!

    # wait for the responses to be processed
    sleep 30.seconds

    # inspect the data we've collected
  end

  protected def process_i_am(message : BACnet::Message::Secure)
    remote_address = message.data_link.source_vmac
    details = BACnet::Client::Message::IAm.parse(message)
    # {object_id:              objects[0].to_object_id,
    #  max_adpu_length:        objects[1].to_u64,
    #  segmentation_supported: SegmentationSupport.new(objects[2].to_i),
    #  vendor_id:              objects[3].to_u64,
    #  network:                network,
    #  address:                address }

    # Grab the details of the device
    Log.info { "received IAm message #{details}" }
    inspect_device(remote_address, details[:object_id], details[:network], details[:address])
  end

  protected def process_i_have(message : BACnet::Message::Secure)
    remote_address = message.data_link.source_vmac
    details = BACnet::Client::Message::IHave.parse(message)
    # {device_id:   objects[0].to_object_id,
    #  object_id:   objects[1].to_object_id,
    #  object_name: objects[2].value.as(String),
    #  network:     network,
    #  address:     address }

    # Grab the details of the device
    Log.info { "received IHave message #{details}" }
    inspect_device(remote_address, details[:object_id], details[:network], details[:address])
  end

  @inspected : Set(UInt64) = Set(UInt64).new

  protected def inspect_device(link_address, object_id, network, address)
    # don't inspect a device twice
    device_id = object_id.instance_number
    return if @inspected.includes?(device_id)
    @inspected << device_id

    device_name = read_property(link_address, object_id, :object_name, nil, network, address)[:objects][0].value.as(String) rescue nil
    vendor_name = read_property(link_address, object_id, :vendor_name, nil, network, address)[:objects][0].value.as(String) rescue nil
    model_name = read_property(link_address, object_id, :model_name, nil, network, address)[:objects][0].value.as(String) rescue nil
    max_properties = begin
      read_property(link_address, object_id, :object_list, 0, network, address)[:objects][0].to_u64
    rescue error
      Log.warn(exception: error) { "error reading object list size" }
      0_u64
    end

    # Grab the object details of all the properties
    # Index 0 == max index
    # Index 1 == device info
    # Index 2..max == object info
    failed = 0
    objects = [] of BACnet::ObjectIdentifier
    (2..max_properties).each do |index|
      prop = read_property(link_address, object_id, :object_list, index, network, address) rescue nil
      unless prop
        # Some devices specify more objects than actually exist
        # so we want to exit early
        failed += 1
        break if failed > 2
        next
      end

      objects << prop[:objects][0].to_object_id
    end

    # inspect each objects details
    objects.each do |obj|
      type = obj.object_type
      case type
      in BACnet::ObjectIdentifier::ObjectType
        if type.device?
          Log.info { " - found gateway device: #{obj.inspect}" }
          # inspect_device()
        else
          inspect_object(link_address, type, obj, nil, network, address)
        end
      in UInt16
        Log.info { "unknown object type found: #{type} in #{device_name} (#{model_name})" }
      end
    end

    Log.info { "inspected new device #{vendor_name} - #{device_name} (#{model_name}) with #{objects.size} objects" }
  end

  alias ObjectType = BACnet::ObjectIdentifier::ObjectType

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

  def inspect_object(
    link_address : Bytes,
    object_type : ObjectType,
    property_id : BACnet::ObjectIdentifier,
    index : Int? = nil,
    network : UInt16? = nil,
    address : String | Bytes? = nil,
  )
    name = read_property(link_address, property_id, :object_name, index, network, address)

    # Not all objects have a unit
    if OBJECTS_WITH_UNITS.includes? object_type
      unit = read_property(link_address, property_id, :units, index, network, address)
      puts "READ UNITS: #{unit.inspect}"
    end

    # Not all objects have a value
    if OBJECTS_WITH_VALUES.includes? object_type
      value = read_property(link_address, property_id, :present_value, index, network, address)
    end

    Log.info { "-- DATAPOINT #{object_type}: #{name}: #{value} (#{unit})" }
  rescue error
    Log.error(exception: error) { "-- ERR reading DATAPOINT #{object_type}" }
  end

  def run!
    @writer = writer = Channel(BACnet::Message::Secure).new(5)

    ws = HTTP::WebSocket.new(@host, @path, tls: tls, headers: HTTP::Headers{
      # NOTE:: use dc.bsc.bacnet.org for direct node to node connections
      "Sec-WebSocket-Protocol" => "hub.bsc.bacnet.org",
      "Host"                   => @host,
    })

    ws.on_binary do |bytes|
      # incoming messages
      message = IO::Memory.new(bytes).read_bytes(::BACnet::Message::Secure)
      # Log.debug { "received #{message.data_link.request_type} message: #{message.application.class}" }

      spawn { process_message(message) }
    end

    # close the websocket on interrupt
    Process.on_terminate do
      writer.close
      ws.close
    end

    # start processing data
    connect!
    spawn do
      # wait for other things to send
      while message = writer.receive?
        io = IO::Memory.new
        io.write_bytes message
        ws.send(io.to_slice)
      end

      Log.warn { "! write loop exited" }
    end

    begin
      ws.run
    ensure
      # shutsdown the writer fiber when the websocket closes
      writer.close
    end
  end

  def process_message(message)
    app = message.application
    case app
    in Nil
      case message.data_link.request_type
      when .heartbeat_request?
        heartbeat_ack!(message)
      when .heartbeat_ack?
        Log.debug { "<-- heartbeat acknowledged" }
      when .connect_accept?
        Log.debug { "running on connect callback" }
        on_connect
      else
        Log.info { "unhandled message: #{message.inspect}" }
      end
    in BACnet::ConfirmedRequest
      # handle requests coming being sent to us
    in BACnet::UnconfirmedRequest
      case app.service
      when .i_am?
        process_i_am(message)
      when .i_have?
        process_i_have(message)
      end
    in BACnet::ErrorResponse, BACnet::AbortCode, BACnet::RejectResponse
      if promise = @tracker.delete(app.invoke_id)
        return_invoke_id(app.invoke_id)
        if app.is_a?(BACnet::ErrorResponse)
          klass = BACnet::ErrorClass.new message.objects[0].to_i
          code = BACnet::ErrorCode.new message.objects[1].to_i
          error_message = "request failed with #{app.class} - #{klass}: #{code}"

          error = case code
                  when .unknown_property?
                    BACnet::UnknownPropertyError.new(error_message)
                  else
                    BACnet::Error.new(error_message)
                  end

          promise.reject(error)
        else
          promise.reject(BACnet::Error.new("request failed with #{app.class} - #{app.reason}"))
        end
      else
        Log.debug { "unexpected request ID received #{app.invoke_id}\nmessage: #{message.inspect}" }
      end
    in BACnet::ComplexAck, BACnet::SimpleAck, BACnet::SegmentAck
      if promise = @tracker.delete(app.invoke_id)
        return_invoke_id(app.invoke_id)
        promise.resolve(message)
      else
        Log.debug { "unexpected request ID received #{app.invoke_id}\nmessage: #{message.inspect}" }
      end
    in BinData
      # https://github.com/crystal-lang/crystal/issues/9116
      # https://github.com/crystal-lang/crystal/issues/9235
    end
  end
end

test = SecureConnectTest.new(uuid: UUID.new("04fba096-6ac2-4f2d-b96c-396d1698566f"))
test.run!
