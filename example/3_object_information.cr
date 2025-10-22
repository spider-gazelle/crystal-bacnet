require "../src/bacnet"
require "http"
require "uuid"
require "option_parser"

::Log.setup("*", :info)

# Object information example: reads all properties of a specific object
#
# Usage: crystal run example/3_object_information.cr -- --device-id 1001 --vmac 010203040506 --object-type AnalogInput --object-instance 1
#
# Required arguments:
#   --device-id <id>           Device instance ID
#   --vmac <hex>               Virtual MAC address (hex string)
#   --object-type <type>       Object type (e.g., AnalogInput, BinaryOutput, etc.)
#   --object-instance <num>    Object instance number
#
# Optional environment variables:
#   BACNET_HOST=138.80.128.217
#   BACNET_PATH=/hub
#   BACNET_UUID=04fba096-6ac2-4f2d-b96c-396d1698566f
#   BACNET_PRIVATE_KEY=./private.key
#   BACNET_CLIENT_CERT=./client.pem

class ObjectInformationExample
  def initialize(
    @device_id : UInt32,
    @target_vmac : Bytes,
    @object_type : BACnet::ObjectIdentifier::ObjectType,
    @object_instance : UInt32,
    @host : String = ENV.fetch("BACNET_HOST", "138.80.128.217"),
    @path : String = ENV.fetch("BACNET_PATH", "/hub"),
    @private_key_file : String = ENV.fetch("BACNET_PRIVATE_KEY", "./private.key"),
    @client_cert_file : String = ENV.fetch("BACNET_CLIENT_CERT", "./client.pem"),
    @uuid : UUID = UUID.new(ENV.fetch("BACNET_UUID", "04fba096-6ac2-4f2d-b96c-396d1698566f")),
    @timeout : Time::Span = 20.seconds,
  )
    tls = OpenSSL::SSL::Context::Client.insecure
    tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    tls.private_key = @private_key_file
    tls.certificate_chain = @client_cert_file
    @tls = tls

    @client = BACnet::Client::SecureConnect.new(uuid: @uuid, timeout: 10.seconds)
    @connected = Channel(Nil).new
  end

  getter client : BACnet::Client::SecureConnect
  getter host : String
  getter path : String
  getter tls : OpenSSL::SSL::Context::Client

  @complete : Channel(Nil) = Channel(Nil).new
  @connected : Channel(Nil)

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

  def run!
    ws = HTTP::WebSocket.new(@host, @path, tls: @tls, headers: HTTP::Headers{
      "Sec-WebSocket-Protocol" => "hub.bsc.bacnet.org",
      "Host"                   => @host,
    })

    ws.on_binary do |bytes|
      message = IO::Memory.new(bytes).read_bytes(::BACnet::Message::Secure)
      spawn { process_message(message) }
    end

    client.on_transmit do |message|
      io = IO::Memory.new
      io.write_bytes message
      ws.send(io.to_slice)
    end

    # close the websocket on interrupt
    Process.on_terminate do
      @complete.close
      @connected.close
      ws.close
    end

    # start the connection
    Log.info { "Connecting to wss://#{@host}#{@path}..." }
    client.connect!

    # Wait for connection and then query the object
    spawn do
      @connected.receive?
      Log.info { "Connected! Querying object #{@object_type}[#{@object_instance}] on device [#{@device_id}]..." }
      begin
        inspect_object
      rescue error
        Log.error(exception: error) { "Failed to inspect object" }
      ensure
        @complete.try &.close
        ws.close
      end
    end

    # Set a timeout for the entire operation
    spawn do
      sleep @timeout
      Log.warn { "Operation timed out after #{@timeout}" }
      @complete.try &.close
      @connected.try &.close
      ws.close
    end

    begin
      ws.run
    rescue error
      Log.error(exception: error) { "WebSocket error" }
    end
  end

  protected def process_message(message : BACnet::Message::Secure)
    app = message.application
    case app
    in Nil
      case message.data_link.request_type
      when .connect_accept?
        Log.debug { "Received connect accept" }
        @connected.try &.send(nil)
      when .heartbeat_request?
        client.heartbeat_ack!(message)
      else
        Log.debug { "Received control message: #{message.data_link.request_type}" }
      end
    in BACnet::ConfirmedRequest, BACnet::UnconfirmedRequest, BACnet::ErrorResponse,
       BACnet::AbortCode, BACnet::RejectResponse, BACnet::ComplexAck, BACnet::SimpleAck,
       BACnet::SegmentAck
      # Pass to client for handling confirmed requests/responses
      client.received(message)
    in BinData
      # Compiler bug workaround - ignore these messages
      Log.debug { "Ignoring BinData message (compiler bug workaround)" }
    end
  end

  protected def inspect_object
    object_id = BACnet::ObjectIdentifier.new(
      object_type: @object_type,
      instance_number: @object_instance
    )

    # Read basic properties
    name = read_property_string(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName)
    description = read_property_string(object_id, BACnet::PropertyIdentifier::PropertyType::Description)

    # Read value if applicable
    value = if OBJECTS_WITH_VALUES.includes?(@object_type)
              read_property_value(object_id, BACnet::PropertyIdentifier::PropertyType::PresentValue)
            end

    # Read units if applicable
    unit = if OBJECTS_WITH_UNITS.includes?(@object_type)
             read_property_unit(object_id, BACnet::PropertyIdentifier::PropertyType::Units)
           end

    # Read additional common properties
    out_of_service = read_property_value(object_id, BACnet::PropertyIdentifier::PropertyType::OutOfService)
    status_flags = read_property_value(object_id, BACnet::PropertyIdentifier::PropertyType::StatusFlags)

    # Print results
    print_object_info(
      object_id: object_id,
      name: name,
      description: description,
      value: value,
      unit: unit,
      out_of_service: out_of_service,
      status_flags: status_flags
    )
  end

  protected def read_property_string(object_id : BACnet::ObjectIdentifier, property : BACnet::PropertyIdentifier::PropertyType) : String
    result = client.read_property(object_id, property, nil, nil, nil, link_address: @target_vmac).get
    client.parse_complex_ack(result)[:objects][0].value.as(String)
  rescue error
    Log.debug(exception: error) { "Failed to read #{property}" }
    "(unknown)"
  end

  protected def read_property_value(object_id : BACnet::ObjectIdentifier, property : BACnet::PropertyIdentifier::PropertyType) : BACnet::Object?
    result = client.read_property(object_id, property, nil, nil, nil, link_address: @target_vmac).get
    client.parse_complex_ack(result)[:objects][0]?.try(&.as(BACnet::Object))
  rescue error
    Log.debug(exception: error) { "Failed to read #{property}" }
    nil
  end

  protected def read_property_unit(object_id : BACnet::ObjectIdentifier, property : BACnet::PropertyIdentifier::PropertyType) : BACnet::Unit?
    result = client.read_property(object_id, property, nil, nil, nil, link_address: @target_vmac).get
    unit_value = client.parse_complex_ack(result)[:objects][0].to_i
    BACnet::Unit.new(unit_value)
  rescue error
    Log.debug(exception: error) { "Failed to read #{property}" }
    nil
  end

  protected def print_object_info(
    object_id : BACnet::ObjectIdentifier,
    name : String,
    description : String,
    value : BACnet::Object?,
    unit : BACnet::Unit?,
    out_of_service : BACnet::Object?,
    status_flags : BACnet::Object?,
  )
    puts "\n" + "="*80
    puts "BACnet Object Information"
    puts "="*80
    puts "Device Instance: #{@device_id}"
    puts "VMAC: #{@target_vmac.hexstring}"
    puts ""
    puts "Object Type: #{object_id.object_type}"
    puts "Object Instance: #{object_id.instance_number}"
    puts "Object Name: #{name}"
    puts "Description: #{description}" unless description == "(unknown)"
    puts ""

    if value
      value_str = format_value(value)
      puts "Present Value: #{value_str}"
      puts "Units: #{unit}" if unit
    end

    if out_of_service
      puts "Out of Service: #{format_value(out_of_service)}"
    end

    if status_flags
      puts "Status Flags: #{format_value(status_flags)}"
    end

    puts "="*80
  end

  protected def format_value(obj : BACnet::Object) : String
    return "(null)" if obj.is_null?

    case obj.tag
    when 1 # Boolean
      obj.to_bool.to_s
    when 2, 9 # UnsignedInt, Enum
      obj.to_u64.to_s
    when 3 # SignedInt
      obj.to_i64.to_s
    when 4 # Float32
      obj.to_f32.to_s
    when 5 # Float64
      obj.to_f64.to_s
    when 6 # OctetString
      obj.to_string
    when 7 # CharString
      obj.to_encoded_string
    when 8 # BitString
      bits = obj.to_bit_string
      (0...bits.size).compact_map { |i| bits[i] ? "#{i}" : nil }.join(", ")
    when 10 # Date
      obj.to_date.to_s
    when 11 # Time
      obj.to_time.to_s
    when 12 # ObjectIdentifier
      oid = obj.to_object_id
      "#{oid.object_type}:#{oid.instance_number}"
    else
      obj.value.to_s
    end
  rescue
    obj.inspect
  end
end

# Parse command line arguments
device_id : UInt32? = nil
vmac_hex : String? = nil
object_type_str : String? = nil
object_instance : UInt32? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run example/3_object_information.cr -- [options]"

  parser.on("--device-id ID", "Device instance ID (required)") do |id|
    device_id = id.to_u32
  end

  parser.on("--vmac VMAC", "Virtual MAC address in hex (required)") do |vmac|
    vmac_hex = vmac
  end

  parser.on("--object-type TYPE", "Object type (required, e.g., AnalogInput)") do |type|
    object_type_str = type
  end

  parser.on("--object-instance NUM", "Object instance number (required)") do |instance|
    object_instance = instance.to_u32
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    puts "\nAvailable object types:"
    puts "  AnalogInput, AnalogOutput, AnalogValue"
    puts "  BinaryInput, BinaryOutput, BinaryValue"
    puts "  MultiStateInput, MultiStateOutput, MultiStateValue"
    puts "  Device, TrendLog, Schedule, Calendar"
    puts "  ... and many more (see BACnet::ObjectIdentifier::ObjectType)"
    exit 0
  end
end

unless device_id && vmac_hex && object_type_str && object_instance
  puts "Error: All options are required"
  puts "Usage: crystal run example/3_object_information.cr -- --device-id <id> --vmac <hex> --object-type <type> --object-instance <num>"
  exit 1
end

# Parse object type
object_type = BACnet::ObjectIdentifier::ObjectType.parse?(object_type_str.not_nil!)
unless object_type
  puts "Error: Invalid object type '#{object_type_str}'"
  puts "Run with --help to see available object types"
  exit 1
end

# Convert hex string to bytes
vmac_bytes = vmac_hex.not_nil!.gsub(/[:\s-]/, "").hexbytes

example = ObjectInformationExample.new(
  device_id.not_nil!,
  vmac_bytes,
  object_type,
  object_instance.not_nil!
)
example.run!
