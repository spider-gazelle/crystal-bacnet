require "../src/bacnet"
require "http"
require "uuid"
require "option_parser"

::Log.setup("*", :info)

# Device details example: inspects a specific device and lists its properties
#
# Usage: crystal run example/2_device_details.cr -- --device-id 1001 --vmac 010203040506
#
# Required arguments:
#   --device-id <id>       Device instance ID
#   --vmac <hex>           Virtual MAC address (hex string)
#
# Optional environment variables:
#   BACNET_HOST=138.80.128.217
#   BACNET_PATH=/hub
#   BACNET_UUID=04fba096-6ac2-4f2d-b96c-396d1698566f
#   BACNET_PRIVATE_KEY=./private.key
#   BACNET_CLIENT_CERT=./client.pem

class DeviceDetailsExample
  def initialize(
    @device_id : UInt32,
    @target_vmac : Bytes,
    @host : String = ENV.fetch("BACNET_HOST", "138.80.128.217"),
    @path : String = ENV.fetch("BACNET_PATH", "/hub"),
    @private_key_file : String = ENV.fetch("BACNET_PRIVATE_KEY", "./private.key"),
    @client_cert_file : String = ENV.fetch("BACNET_CLIENT_CERT", "./client.pem"),
    @uuid : UUID = UUID.new(ENV.fetch("BACNET_UUID", "04fba096-6ac2-4f2d-b96c-396d1698566f")),
    @timeout : Time::Span = 30.seconds,
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
  getter device_id : UInt32
  getter target_vmac : Bytes

  @complete : Channel(Nil) = Channel(Nil).new
  @connected : Channel(Nil)

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

    # Wait for connection and then query the device
    spawn do
      @connected.receive?
      Log.info { "Connected! Querying device [#{@device_id}]..." }
      begin
        inspect_device
      rescue error
        Log.error(exception: error) { "Failed to inspect device" }
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

  protected def inspect_device
    object_id = BACnet::ObjectIdentifier.new(
      object_type: BACnet::ObjectIdentifier::ObjectType::Device,
      instance_number: @device_id
    )

    # Read device properties
    name = read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName)
    vendor_name = read_property(object_id, BACnet::PropertyIdentifier::PropertyType::VendorName)
    model_name = read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ModelName)
    description = read_property(object_id, BACnet::PropertyIdentifier::PropertyType::Description)

    # Read object list size
    max_properties = begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, nil, nil, link_address: @target_vmac).get
      client.parse_complex_ack(result)[:objects][0].to_u64
    rescue error
      Log.warn(exception: error) { "Failed to read object list size" }
      0_u64
    end

    # Read all objects
    objects = [] of Tuple(BACnet::ObjectIdentifier, String)
    sub_devices = [] of Tuple(BACnet::ObjectIdentifier, String)
    failed = 0

    Log.info { "Reading #{max_properties} objects..." }

    (2..max_properties).each do |index|
      begin
        result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, nil, nil, link_address: @target_vmac).get
        obj_id = client.parse_complex_ack(result)[:objects][0].to_object_id

        # Get object name
        obj_name = begin
          name_result = client.read_property(obj_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, nil, nil, link_address: @target_vmac).get
          client.parse_complex_ack(name_result)[:objects][0].value.as(String)
        rescue
          "(unnamed)"
        end

        obj_type = obj_id.object_type
        if obj_type && obj_type.device?
          sub_devices << {obj_id, obj_name}
        else
          objects << {obj_id, obj_name}
        end
      rescue error
        Log.debug(exception: error) { "Failed to read object at index #{index}" }
        failed += 1
        break if failed > 2
      end
    end

    # Print results
    print_device_info(name, vendor_name, model_name, description, objects, sub_devices)
  end

  protected def read_property(object_id : BACnet::ObjectIdentifier, property : BACnet::PropertyIdentifier::PropertyType) : String
    result = client.read_property(object_id, property, nil, nil, nil, link_address: @target_vmac).get
    client.parse_complex_ack(result)[:objects][0].value.as(String)
  rescue error
    Log.warn(exception: error) { "Failed to read #{property}" }
    "(unknown)"
  end

  protected def print_device_info(
    name : String,
    vendor : String,
    model : String,
    description : String,
    objects : Array(Tuple(BACnet::ObjectIdentifier, String)),
    sub_devices : Array(Tuple(BACnet::ObjectIdentifier, String)),
  )
    puts "\n" + "="*80
    puts "BACnet Device Details"
    puts "="*80
    puts "Device Instance: #{@device_id}"
    puts "VMAC: #{@target_vmac.hexstring}"
    puts "Object Name: #{name}"
    puts "Vendor Name: #{vendor}"
    puts "Model Name: #{model}"
    puts "Description: #{description}" unless description == "(unknown)"
    puts ""

    if sub_devices.any?
      puts "Sub-Devices (#{sub_devices.size}):"
      sub_devices.each do |(obj_id, obj_name)|
        puts "  [#{obj_id.instance_number}] #{obj_name}"
      end
      puts ""
    end

    puts "Objects (#{objects.size}):"
    objects.group_by { |(obj_id, _)| obj_id.object_type }.each do |type, objs|
      puts "  #{type} (#{objs.size}):"
      objs.each do |(obj_id, obj_name)|
        puts "    [#{obj_id.instance_number}] #{obj_name}"
      end
    end

    puts "="*80
  end
end

# Parse command line arguments
device_id : UInt32? = nil
vmac_hex : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run example/2_device_details.cr -- [options]"

  parser.on("--device-id ID", "Device instance ID (required)") do |id|
    device_id = id.to_u32
  end

  parser.on("--vmac VMAC", "Virtual MAC address in hex (required)") do |vmac|
    vmac_hex = vmac
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

unless device_id && vmac_hex
  puts "Error: Both --device-id and --vmac are required"
  puts "Usage: crystal run example/2_device_details.cr -- --device-id <id> --vmac <hex>"
  exit 1
end

# Convert hex string to bytes
vmac_bytes = vmac_hex.not_nil!.gsub(/[:\s-]/, "").hexbytes

example = DeviceDetailsExample.new(device_id.not_nil!, vmac_bytes)
example.run!
