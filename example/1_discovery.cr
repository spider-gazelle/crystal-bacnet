require "../src/bacnet"
require "./discovery_store"
require "http"
require "uuid"

::Log.setup("*", :info)

# Discovery example: performs WhoIs and lists discovered devices
# Terminates after 5 seconds of no new UnconfirmedRequest messages
#
# Usage: crystal run example/1_discovery.cr
#
# Optional environment variables:
#   BACNET_HOST=138.80.128.217
#   BACNET_PATH=/hub
#   BACNET_UUID=04fba096-6ac2-4f2d-b96c-396d1698566f
#   BACNET_PRIVATE_KEY=./private.key
#   BACNET_CLIENT_CERT=./client.pem

class DiscoveryExample
  def initialize(
    @host : String = ENV.fetch("BACNET_HOST", "138.80.128.217"),
    @path : String = ENV.fetch("BACNET_PATH", "/hub"),
    @private_key_file : String = ENV.fetch("BACNET_PRIVATE_KEY", "./private.key"),
    @client_cert_file : String = ENV.fetch("BACNET_CLIENT_CERT", "./client.pem"),
    @uuid : UUID = UUID.new(ENV.fetch("BACNET_UUID", "04fba096-6ac2-4f2d-b96c-396d1698566f")),
  )
    tls = OpenSSL::SSL::Context::Client.insecure
    tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    tls.private_key = @private_key_file
    tls.certificate_chain = @client_cert_file
    @tls = tls

    @client = BACnet::Client::SecureConnect.new(uuid: @uuid)
    @store = DiscoveryStore::Store.new
    @last_response = Time.utc
    @connected = Channel(Nil).new
  end

  getter client : BACnet::Client::SecureConnect
  getter store : DiscoveryStore::Store
  getter host : String
  getter path : String
  getter tls : OpenSSL::SSL::Context::Client

  @last_response : Time
  @discovery_complete : Channel(Nil) = Channel(Nil).new
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

    # close the websocket on interrupt or discovery completion
    Process.on_terminate do
      @discovery_complete.close
      @connected.close
      ws.close
    end

    # start the connection
    Log.info { "Connecting to wss://#{@host}#{@path}..." }
    client.connect!

    # Wait for connection to be established
    spawn do
      @connected.receive?
      Log.info { "Connected! Sending WhoIs broadcast..." }
      client.who_is
      @last_response = Time.utc

      # Monitor for discovery completion (5 seconds of no new responses)
      monitor_discovery_timeout
    end

    # Wait for discovery to complete
    spawn do
      @discovery_complete.receive?
      print_discovered_devices
      ws.close
    end

    begin
      ws.run
    rescue error
      Log.error(exception: error) { "WebSocket error" }
    end
  end

  protected def process_message(message : BACnet::Message::Secure)
    # Handle control messages
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
    in BACnet::UnconfirmedRequest
      @last_response = Time.utc
      case app.service
      when .i_am?
        process_i_am(message)
      when .i_have?
        process_i_have(message)
      else
        Log.debug { "Received unconfirmed request: #{app.service}" }
      end
    in BACnet::ConfirmedRequest, BACnet::ErrorResponse, BACnet::AbortCode, BACnet::RejectResponse,
       BACnet::ComplexAck, BACnet::SimpleAck, BACnet::SegmentAck
      # Pass to client for handling
      client.received(message)
    in BinData
      # Compiler bug workaround - ignore these messages
      Log.debug { "Ignoring BinData message (compiler bug workaround)" }
    end
  end

  protected def process_i_am(message : BACnet::Message::Secure)
    vmac = message.data_link.source_vmac
    return unless vmac

    details = client.parse_i_am(message)
    device_instance = details[:object_id].instance_number

    Log.info { "Discovered device [#{device_instance}] from #{vmac.hexstring}" }

    # Don't re-process devices we've already seen
    return if store.has_device?(device_instance)

    device = DiscoveryStore::Device.new(
      device_instance: device_instance,
      vmac: vmac,
      max_apdu_length: details[:max_adpu_length],
      segmentation_supported: details[:segmentation_supported],
      vendor_id: details[:vendor_id]
    )

    store.add_device(device)

    # Query device details in background
    spawn { query_device_details(device) }
  end

  protected def process_i_have(message : BACnet::Message::Secure)
    vmac = message.data_link.source_vmac
    return unless vmac

    details = client.parse_i_have(message)
    device_instance = details[:device_id].instance_number

    Log.debug { "Received IHave for device [#{device_instance}]" }
  end

  protected def query_device_details(device : DiscoveryStore::Device)
    object_id = BACnet::ObjectIdentifier.new(
      object_type: BACnet::ObjectIdentifier::ObjectType::Device,
      instance_number: device.device_instance
    )

    # Query device name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, nil, nil, link_address: device.vmac).get
      device.object_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read object_name for device [#{device.device_instance}]" }
    end

    # Query vendor name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::VendorName, nil, nil, nil, link_address: device.vmac).get
      device.vendor_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read vendor_name for device [#{device.device_instance}]" }
    end

    # Query model name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ModelName, nil, nil, nil, link_address: device.vmac).get
      device.model_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read model_name for device [#{device.device_instance}]" }
    end

    # Query object list to find sub-devices
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, nil, nil, link_address: device.vmac).get
      max_objects = client.parse_complex_ack(result)[:objects][0].to_u64

      # Scan for sub-devices (Device objects in the object list)
      failed = 0
      (2..max_objects).each do |index|
        begin
          result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, nil, nil, link_address: device.vmac).get
          obj_id = client.parse_complex_ack(result)[:objects][0].to_object_id

          # If this is a device object, it's a sub-device
          obj_type = obj_id.object_type
          if obj_type && obj_type.device?
            # Query the sub-device name
            sub_device_name = begin
              result = client.read_property(obj_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, nil, nil, link_address: device.vmac).get
              client.parse_complex_ack(result)[:objects][0].value.as(String)
            rescue
              ""
            end

            sub_device = DiscoveryStore::Device.new(
              device_instance: obj_id.instance_number,
              vmac: device.vmac
            )
            sub_device.object_name = sub_device_name
            device.sub_devices << sub_device

            Log.debug { "Found sub-device [#{obj_id.instance_number}] under device [#{device.device_instance}]" }
          else
            device.objects << DiscoveryStore::ObjectReference.new(obj_id)
          end
        rescue error
          Log.trace(exception: error) { "Failed to read object at index #{index}" }
          failed += 1
          break if failed > 2
        end
      end
    rescue error
      Log.debug(exception: error) { "Failed to read object_list for device [#{device.device_instance}]" }
    end
  end

  protected def monitor_discovery_timeout
    loop do
      sleep 1.second

      # Check if 5 seconds have passed since last response
      if (Time.utc - @last_response) > 5.seconds
        Log.info { "Discovery complete (no new devices for 5 seconds)" }
        @discovery_complete.try &.close
        break
      end
    end
  end

  protected def print_discovered_devices
    puts "\n" + "="*80
    puts "BACnet Device Discovery Results"
    puts "="*80
    puts "Secure Connect: wss://#{@host}#{@path}"
    puts ""

    devices = store.all_devices

    if devices.empty?
      puts "  No devices discovered"
      return
    end

    devices.sort_by!(&.device_instance).each do |device|
      name = device.object_name.empty? ? "(unnamed)" : device.object_name

      puts "  Device [#{device.device_instance}] - #{name}"
      puts "    VMAC: #{device.vmac_hex}"
      puts "    Vendor: #{device.vendor_name}" unless device.vendor_name.empty?
      puts "    Model: #{device.model_name}" unless device.model_name.empty?
      puts "    Objects: #{device.objects.size}"

      # Show sub-devices
      unless device.sub_devices.empty?
        puts "    Sub-devices:"
        device.sub_devices.each do |sub|
          sub_name = sub.object_name.empty? ? "(unnamed)" : sub.object_name
          puts "      [#{sub.device_instance}] #{sub_name}"
        end
      end

      puts ""
    end

    puts "Total devices discovered: #{devices.size}"
    puts "="*80
  end
end

example = DiscoveryExample.new
example.run!
