require "../../bacnet"
require "./ipv4_bvlci"
require "../services/*"
require "../message"
require "../object"

class BACnet::Message::IPv4
  def initialize(@data_link : IP4BVLCI, network = nil, application = nil, objects = [] of Object | Objects)
    @message = Message.new(network, application, objects)
  end

  def initialize(@data_link : IP4BVLCI, @message : Message)
  end

  property data_link : IP4BVLCI
  property message : Message

  forward_missing_to @message

  def self.hint(io : IO) : DataLinkIndicator
    bytes = io.peek
    raise Error.new("not enough data") if bytes.size < 4

    data = IO::Memory.new(bytes, writeable: false)
    data.read_bytes(DataLinkIndicator)
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : IPv4
    # Get message length
    indicator = hint(io)
    raise Error.new("only supports IPv4 datalink") unless indicator.is_ipv4?

    # Read the entire message into memory
    bytes = Bytes.new(indicator.request_length)
    io.read_fully(bytes)
    io = IO::Memory.new(bytes, writeable: false)

    # Parse only the bytes that make up the message
    data_link = io.read_bytes(IP4BVLCI)
    return self.new(data_link) unless data_link.request_type.forwarded_npdu? || data_link.request_type.original_unicast_npdu? || data_link.request_type.original_broadcast_npdu?

    message = Message.from_io(io, format)
    self.new(data_link, message)
  end

  def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
    # this will always be big endian, just need to match the interface
    # ameba:disable Lint/ShadowedArgument
    format = IO::ByteFormat::BigEndian
    wrote = io.write_bytes(@data_link, format)
    wrote += io.write_bytes(@message, format)
    wrote
  end

  def to_slice
    io = IO::Memory.new
    io.write_bytes self
    io.to_slice
  end
end
