require "../src/bacnet"
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
    @store = BACnet::DiscoveryStore::Store.new
    @last_response = Time.utc
    @connected = Channel(Nil).new
  end

  getter client : BACnet::Client::SecureConnect
  getter store : BACnet::DiscoveryStore::Store
  getter host : String
  getter path : String
  getter tls : OpenSSL::SSL::Context::Client

  @last_response : Time
  @discovery_complete : Channel(Nil) = Channel(Nil).new
  @connected : Channel(Nil)
  @pending_queries : Atomic(Int32) = Atomic.new(0)

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

      # Wait for all pending device queries to complete
      pending = @pending_queries.get
      Log.info { "Discovery timeout reached, waiting for #{pending} device queries to complete..." }

      # Wait up to 20 seconds for queries to complete
      timeout_at = Time.utc + 20.seconds
      loop do
        break if @pending_queries.get == 0
        break if Time.utc > timeout_at

        if @pending_queries.get != pending
          pending = @pending_queries.get
          Log.info { "#{pending} queries still pending..." }
        end

        sleep 0.5.seconds
      end

      final_pending = @pending_queries.get
      if final_pending > 0
        Log.warn { "Timed out waiting for #{final_pending} device queries, displaying results anyway..." }
      else
        Log.info { "All device queries complete, discovering hierarchy..." }
      end

      # Discover parent-child relationships by grouping devices with same VMAC
      discover_device_hierarchy

      Log.info { "Displaying results..." }
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

    device = BACnet::DiscoveryStore::Device.new(
      device_instance: device_instance,
      vmac: vmac.hexstring,
      max_apdu_length: details[:max_adpu_length],
      segmentation_supported: details[:segmentation_supported].to_s,
      vendor_id: details[:vendor_id]
    )

    store.add_device(device)

    # Query device details in background
    @pending_queries.add(1)
    spawn do
      begin
        query_device_details(device)
      ensure
        @pending_queries.sub(1)
      end
    end
  end

  protected def process_i_have(message : BACnet::Message::Secure)
    vmac = message.data_link.source_vmac
    return unless vmac

    details = client.parse_i_have(message)
    device_instance = details[:device_id].instance_number

    Log.debug { "Received IHave for device [#{device_instance}]" }
  end

  protected def query_device_details(device : BACnet::DiscoveryStore::Device)
    Log.info { "Querying details for device [#{device.device_instance}]" }

    object_id = BACnet::ObjectIdentifier.new(
      object_type: BACnet::ObjectIdentifier::ObjectType::Device,
      instance_number: device.device_instance
    )

    # Query device name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, nil, nil, link_address: device.vmac_bytes.not_nil!).get
      device.object_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read object_name for device [#{device.device_instance}]" }
    end

    # Query vendor name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::VendorName, nil, nil, nil, link_address: device.vmac_bytes.not_nil!).get
      device.vendor_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read vendor_name for device [#{device.device_instance}]" }
    end

    # Query model name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ModelName, nil, nil, nil, link_address: device.vmac_bytes.not_nil!).get
      device.model_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read model_name for device [#{device.device_instance}]" }
    end

    # Query object list to find sub-devices
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, nil, nil, link_address: device.vmac_bytes.not_nil!).get
      obj_list_item = client.parse_complex_ack(result)[:objects][0]

      # Check if the device incorrectly returned a string instead of an integer
      # Tag 7 = CharacterString, Tag 2 = UnsignedInteger
      if obj_list_item.tag == 7
        string_value = obj_list_item.to_encoded_string
        Log.warn { "Device [#{device.device_instance}] returned string '#{string_value}' for ObjectList[0] instead of count" }

        # Try to parse the string as a number
        if parsed_count = string_value.to_u64?
          Log.info { "Successfully parsed object count #{parsed_count} from string for device [#{device.device_instance}]" }
          max_objects = parsed_count
        else
          Log.warn { "Unable to parse object count from string '#{string_value}' for device [#{device.device_instance}], skipping object scan" }
          return
        end
      else
        max_objects = obj_list_item.to_u64
      end

      # Sanity check - if the count is unreasonably large, skip scanning
      if max_objects > 10_000
        Log.warn { "Device [#{device.device_instance}] reports #{max_objects} objects - unreasonably large, skipping object scan" }
        return
      end

      Log.debug { "Scanning #{max_objects} objects on device [#{device.device_instance}] for sub-devices" }

      # Scan for sub-devices (Device objects in the object list)
      failed = 0
      (2..max_objects).each do |index|
        begin
          result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, nil, nil, link_address: device.vmac_bytes.not_nil!).get
          obj_id = client.parse_complex_ack(result)[:objects][0].to_object_id

          # If this is a device object, it's a sub-device
          obj_type = obj_id.object_type

          if obj_type && obj_type.device?
            Log.debug { "Found Device object [#{obj_id.instance_number}] in ObjectList of device [#{device.device_instance}]" }
            # Check if this device already exists in the store (from IAm message)
            sub_device = store.get_device(obj_id.instance_number)

            if sub_device
              # Device already discovered via IAm, just update it
              sub_device.parent_device_instance = device.device_instance
              Log.info { "Marking existing device [#{obj_id.instance_number}] as sub-device of [#{device.device_instance}]" }
            else
              # Device not yet discovered, create new entry
              sub_device = BACnet::DiscoveryStore::Device.new(
                device_instance: obj_id.instance_number,
                vmac: device.vmac,
                parent_device_instance: device.device_instance
              )
              store.add_device(sub_device)

              # Query the sub-device name
              begin
                result = client.read_property(obj_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, nil, nil, nil, link_address: device.vmac_bytes.not_nil!).get
                sub_device.object_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
              rescue error
                Log.debug(exception: error) { "Failed to read sub-device name for [#{obj_id.instance_number}]" }
              end

              Log.debug { "Found new sub-device [#{obj_id.instance_number}] under device [#{device.device_instance}]" }
            end

            # Add to parent's sub_devices array
            device.sub_devices << sub_device
          else
            obj_type_str = obj_type.to_s
            device.objects << BACnet::DiscoveryStore::ObjectReference.new(obj_type_str, obj_id.instance_number)
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

  # Discover parent-child relationships by grouping devices with the same network identifier
  # For BACnet/SC: Devices sharing a VMAC are part of a gateway hierarchy
  # For BACnet/IP: Devices on the same network can be grouped by IP address
  # The device with the lowest instance number is the parent (gateway) and others are sub-devices
  protected def discover_device_hierarchy
    # Group devices by network identifier (VMAC for BACnet/SC, IP for BACnet/IP)
    devices_by_network = {} of String => Array(BACnet::DiscoveryStore::Device)

    store.all_devices.each do |device|
      network_id = device.network_id
      next if network_id.empty?

      devices_by_network[network_id] ||= [] of BACnet::DiscoveryStore::Device
      devices_by_network[network_id] << device
    end

    # Process each network group
    devices_by_network.each do |network_id, devices|
      # Skip if only one device on this network
      next if devices.size <= 1

      # Sort by instance number to find parent (lowest instance)
      devices.sort_by!(&.device_instance)
      parent = devices.first
      sub_devices = devices[1..]

      Log.info { "Discovered device hierarchy on network #{network_id}: parent [#{parent.device_instance}] with #{sub_devices.size} sub-devices" }

      # Mark sub-devices and add to parent
      sub_devices.each do |sub_device|
        sub_device.parent_device_instance = parent.device_instance
        parent.sub_devices << sub_device
        Log.debug { "  └─ Sub-device [#{sub_device.device_instance}] #{sub_device.object_name.empty? ? "(unnamed)" : sub_device.object_name}" }
      end
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

    devices = store.top_level_devices

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

    puts "Total devices discovered: #{store.size}"
    puts "="*80
  end
end

example = DiscoveryExample.new
example.run!
