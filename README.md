# BACnet Support for Crystal Lang

[![CI](https://github.com/spider-gazelle/crystal-bacnet/actions/workflows/ci.yml/badge.svg)](https://github.com/spider-gazelle/crystal-bacnet/actions/workflows/ci.yml)

it supports

* the IPv4 data link layer (BACnet/IP)
* the websocket data link layer (BACnet/SC)

## Installation

Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bacnet:
       github: spider-gazelle/crystal-bacnet
   ```

## Usage

```crystal

require "bacnet"
require "socket"

# ======================
# Create transport layer
# ======================
server = UDPSocket.new
server.bind "0.0.0.0", 0xBAC0

# ======================
# Hook up the client to the transport
# ======================
client = BACnet::Client::IPv4.new

client.on_transmit do |message, address|
  if address.address == Socket::IPAddress::BROADCAST
    # Broadcast this message, might need to be a unicast to a BBMD
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

# broadcast a who_is out onto the network
client.who_is

```
