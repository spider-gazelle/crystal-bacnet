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

Currently this implements the code required to parse and generate BACnet messages.
It does not implement a client.

```crystal

require "bacnet"

message = io.read_bytes(BACnet::IP4Message)
message.data_link.request_type # => BACnet::RequestTypeIP4::OriginalUnicastNPDU

if network = message.network
  network.destination.address # => 26001
  network.expecting_reply? # => true
  network.hop_count # => 255

  app_layer = message.application
  case app_layer
  when BACnet::ConfirmedRequest
    app_layer.segmented_message
    app_layer.max_segments
  when BACnet::ComplexAck
  # ...
  end

  # Objects associated with the request
  message.objects # => [] of BACnet::Object

  # Helpers for primitive objects exist, constructed objects require request context
  message.objects.each do |object|
    puts object.value unless object.context_specific
  end
end

```
