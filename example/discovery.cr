require "socket"
require "./client"

::Log.setup("*", :trace)

# Create server
server = UDPSocket.new
server.bind "0.0.0.0", 0xBAC0

client = BACnet::Client.new do |message, address|
  if address.address == Socket::IPAddress::BROADCAST
    server.send message, to: Socket::IPAddress.new("192.168.86.249", 0xBAC0)
  else
    server.send message, to: address
  end
end

client.who_is(Socket::IPAddress.new("192.168.86.249", 0xBAC0))

spawn do
  loop do
    break if server.closed?
    bytes, client_addr = server.receive

    message = IO::Memory.new(bytes).read_bytes(BACnet::Message::IPv4)
    # puts message.inspect
    client.received message, client_addr
  end
end

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

pp! client
