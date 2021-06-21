require "../../bacnet"
require "./secure_bvlci"
require "../services/*"
require "../message"
require "../object"

class BACnet::Message::Secure
  def initialize(@data_link : SecureBVLCI, network = nil, application = nil, objects = [] of Object | Objects)
    @message = Message.new(network, application, objects)
  end

  def initialize(@data_link : SecureBVLCI, @message : Message)
  end

  property data_link : SecureBVLCI
  property message : Message

  forward_missing_to @message

  def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Secure
    # Parse only the bytes that make up the message
    data_link = io.read_bytes(SecureBVLCI)
    return self.new(data_link) unless data_link.request_type.encapsulated_npdu?

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
