require "socket"
require "../src/bacnet"

::Log.setup("*", :info)

# BACnet/IP Discovery Example
# Discovers BACnet devices on a local IP network using UDP broadcast
#
# Usage: crystal run example/bacnet_ip_discovery.cr
#
# Configuration:
#   BACNET_BIND_PORT - UDP port to bind to (default: 0xBAC0 / 47808)
#   BACNET_REMOTE_IP - Target IP address for discovery (default: 192.168.86.25)

class BACnetIPDiscovery
  def initialize(
    @bind_port : Int32 = ENV.fetch("BACNET_BIND_PORT", "47808").to_i,
    @remote_ip : String = ENV.fetch("BACNET_REMOTE_IP", "192.168.86.25"),
    @timeout : Time::Span = 30.seconds,
  )
    @store = BACnet::DiscoveryStore::Store.new
    @last_response = Time.utc
    @discovery_complete = Channel(Nil).new
    @pending_queries = Atomic(Int32).new(0)
  end

  getter store : BACnet::DiscoveryStore::Store

  @server : UDPSocket?
  @client : BACnet::Client::IPv4?
  @remote_address : Socket::IPAddress?
  @last_response : Time
  @discovery_complete : Channel(Nil)
  @pending_queries : Atomic(Int32)

  def run!
    # Create transport layer
    @server = server = UDPSocket.new
    server.bind "0.0.0.0", @bind_port
    @remote_address = remote_address = Socket::IPAddress.new(@remote_ip, @bind_port)

    Log.info { "Bound to UDP port #{@bind_port}" }

    # Create client
    @client = client = BACnet::Client::IPv4.new

    # Hook up client to transport
    client.on_transmit do |message, address|
      if address.address == Socket::IPAddress::BROADCAST
        server.send message, to: remote_address
      else
        server.send message, to: address
      end
    end

    # Feed data to the client
    spawn do
      loop do
        break if server.closed?
        bytes, client_addr = server.receive

        message = IO::Memory.new(bytes).read_bytes(BACnet::Message::IPv4)
        spawn { process_message(message, client_addr) }
      end
    end

    # Send WhoIs broadcast
    Log.info { "Sending WhoIs broadcast to #{@remote_ip}..." }
    client.who_is
    @last_response = Time.utc

    # Monitor for discovery completion
    spawn { monitor_discovery_timeout }

    # Wait for discovery to complete
    spawn do
      @discovery_complete.receive?

      # Wait for all pending device queries to complete
      pending = @pending_queries.get
      if pending > 0
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
          Log.info { "All device queries complete, displaying results..." }
        end
      end

      print_discovered_devices
      server.close
    end

    # Wait for signal or timeout
    channel = Channel(Nil).new(1)

    terminate = Proc(Signal, Nil).new do |signal|
      Log.info { "Terminating gracefully" }
      @discovery_complete.close
      channel.send(nil)
      signal.ignore
    end

    Signal::INT.trap &terminate
    Signal::TERM.trap &terminate

    # Overall timeout
    spawn do
      sleep @timeout + 25.seconds # Account for query completion time
      Log.warn { "Overall timeout reached" }
      @discovery_complete.try &.close
      channel.send(nil)
    end

    channel.receive
  end

  protected def process_message(message : BACnet::Message::IPv4, address : Socket::IPAddress)
    apdu = message.application
    case apdu
    when BACnet::UnconfirmedRequest
      @last_response = Time.utc
      case apdu.service
      when .i_am?
        process_i_am(message, address)
      else
        Log.debug { "Received unconfirmed request: #{apdu.service}" }
      end
    when BACnet::ConfirmedRequest, BACnet::ErrorResponse, BACnet::AbortResponse,
         BACnet::RejectResponse, BACnet::ComplexAck, BACnet::SimpleAck,
         BACnet::SegmentAck
      # Pass to client for handling
      @client.try(&.received(message, address))
    end
  end

  protected def process_i_am(message : BACnet::Message::IPv4, address : Socket::IPAddress)
    client = @client
    return unless client

    details = client.parse_i_am(message)
    device_instance = details[:object_id].instance_number
    ip_address = address.address

    Log.info { "Discovered device [#{device_instance}] from #{ip_address}" }

    # Don't re-process devices we've already seen
    return if store.has_device?(device_instance)

    device = BACnet::DiscoveryStore::Device.new(
      device_instance: device_instance,
      ip_address: ip_address,
      max_apdu_length: details[:max_adpu_length],
      segmentation_supported: details[:segmentation_supported].to_s,
      vendor_id: details[:vendor_id]
    )

    store.add_device(device)

    # Query device details in background
    @pending_queries.add(1)
    spawn do
      begin
        query_device_details(device, address)
      ensure
        @pending_queries.sub(1)
      end
    end
  end

  protected def query_device_details(device : BACnet::DiscoveryStore::Device, address : Socket::IPAddress)
    client = @client
    return unless client

    Log.info { "Querying details for device [#{device.device_instance}]" }

    object_id = BACnet::ObjectIdentifier.new(
      object_type: BACnet::ObjectIdentifier::ObjectType::Device,
      instance_number: device.device_instance
    )

    # Query device name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectName, link_address: address).get
      device.object_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read object_name for device [#{device.device_instance}]" }
    end

    # Query vendor name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::VendorName, link_address: address).get
      device.vendor_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read vendor_name for device [#{device.device_instance}]" }
    end

    # Query model name
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ModelName, link_address: address).get
      device.model_name = client.parse_complex_ack(result)[:objects][0].value.as(String)
    rescue error
      Log.debug(exception: error) { "Failed to read model_name for device [#{device.device_instance}]" }
    end

    # Query object list size
    begin
      result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, 0, link_address: address).get
      obj_list_item = client.parse_complex_ack(result)[:objects][0]

      # Check if the device incorrectly returned a string instead of an integer
      if obj_list_item.tag == 7
        string_value = obj_list_item.to_encoded_string
        Log.warn { "Device [#{device.device_instance}] returned string '#{string_value}' for ObjectList[0] instead of count" }
        return
      end

      max_objects = obj_list_item.to_u64

      # Sanity check
      if max_objects > 10_000
        Log.warn { "Device [#{device.device_instance}] reports #{max_objects} objects - unreasonably large, skipping object scan" }
        return
      end

      Log.debug { "Scanning #{max_objects} objects on device [#{device.device_instance}]" }

      # Read object list
      failed = 0
      (2..max_objects).each do |index|
        begin
          result = client.read_property(object_id, BACnet::PropertyIdentifier::PropertyType::ObjectList, index, link_address: address).get
          obj_id = client.parse_complex_ack(result)[:objects][0].to_object_id

          obj_type = obj_id.object_type
          if obj_type
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
    puts "BACnet/IP Device Discovery Results"
    puts "="*80
    puts "Network: #{@remote_ip}:#{@bind_port}"
    puts ""

    devices = store.all_devices

    if devices.empty?
      puts "  No devices discovered"
      return
    end

    devices.sort_by!(&.device_instance).each do |device|
      name = device.object_name.empty? ? "(unnamed)" : device.object_name

      puts "  Device [#{device.device_instance}] - #{name}"
      puts "    IP Address: #{device.ip_address}"
      puts "    Vendor: #{device.vendor_name}" unless device.vendor_name.empty?
      puts "    Model: #{device.model_name}" unless device.model_name.empty?
      puts "    Objects: #{device.objects.size}"
      puts ""
    end

    puts "Total devices discovered: #{store.size}"
    puts "="*80
  end
end

example = BACnetIPDiscovery.new
example.run!
