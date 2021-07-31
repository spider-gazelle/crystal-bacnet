require "socket"
require "../src/bacnet"

::Log.setup("*", :trace)

# ======================
# Create transport layer
# ======================
server = UDPSocket.new
server.bind "0.0.0.0", 0xBAC0
remote_address = Socket::IPAddress.new("192.168.86.25", 0xBAC0)

# ======================
# Hook up the client to the transport
# ======================
client = BACnet::Client::IPv4.new

client.on_transmit do |message, address|
  if address.address == Socket::IPAddress::BROADCAST
    server.send message, to: remote_address
  else
    server.send message, to: address
  end
end

spawn do
  # Feed data to the client
  loop do
    break if server.closed?
    bytes, client_addr = server.receive

    message = IO::Memory.new(bytes).read_bytes(BACnet::Message::IPv4)
    client.received message, client_addr
  end
end

# ======================
# Collect device information
# ======================
registry = BACnet::Client::DeviceRegistry.new(client)
registry.on_new_device do |device|
  puts "FOUND NEW DEVICE: #{device.vendor_name} #{device.name} #{device.model_name}"
end

# send a who_is out onto the network
client.who_is

# ======================
# Wait for ctrl-c before exiting
# ======================
channel = Channel(Nil).new(1)

terminate = Proc(Signal, Nil).new do |signal|
  puts " > terminating gracefully"
  channel.send(nil)
  signal.ignore
end

# Detect ctr-c to shutdown gracefully
Signal::INT.trap &terminate
# Docker containers use the term signal
Signal::TERM.trap &terminate

channel.receive

# Print the list of discovered devices and their object values
pp! registry
