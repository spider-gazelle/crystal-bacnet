require "../../bacnet"
require "../services/*"
require "../message"
require "../object"

class BACnet::Message::Secure
  enum Request : UInt8
    BVCLResult                =    0
    EncapsulatedNPDU          =    1
    AddressResolution         =    2
    AddressResolutionACK      =    3
    Advertisement             =    4
    AdvertisementSolicitation =    5
    ConnectRequest            =    6
    ConnectAccept             =    7
    DisconnectRequest         =    8
    DisconnectACK             =    9
    HeartbeatRequest          = 0x0a
    HeartbeatACK              = 0x0b
    ProprietaryMessage        = 0x0c
  end

  def initialize(@data_link : Secure::BVLCI, network = nil, application = nil, objects : Array(Object | Objects) = [] of Object | Objects)
    @message = Message.new(network, application, objects)
  end

  def initialize(@data_link : Secure::BVLCI, @message : Message)
  end

  property data_link : Secure::BVLCI
  property message : Message

  forward_missing_to @message

  def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Secure
    # Parse only the bytes that make up the message
    data_link = io.read_bytes(Secure::BVLCI)
    return self.new(data_link) unless data_link.request_type.encapsulated_npdu?

    message = Message.from_io(io, format)
    self.new(data_link, message)
  end

  def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
    # this will always be big endian, just need to match the interface
    # ameba:disable Lint/ShadowedArgument
    format = IO::ByteFormat::BigEndian
    io.write_bytes(@data_link, format)
    io.write_bytes(@message, format)
  end

  def to_slice
    io = IO::Memory.new
    io.write_bytes self
    io.to_slice
  end
end

require "./secure_bvlci"
