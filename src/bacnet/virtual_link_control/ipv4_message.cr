require "../../bacnet"
require "../services/*"
require "../message"
require "../object"

class BACnet::Message::IPv4
  # Header
  enum Request : UInt8
    BVCLResult                        =    0
    WriteBroadcastDistributionTable   =    1
    ReadBroadcastDistributionTable    =    2
    ReadBroadcastDistributionTableAck =    3
    ForwardedNPDU                     =    4
    RegisterForeignDevice             =    5
    ReadForeignDeviceTable            =    6
    ReadForeignDeviceTableAck         =    7
    DeleteForeignDeviceTableEntry     =    8
    DistributeBroadcastToNetwork      =    9
    OriginalUnicastNPDU               = 0x0a
    OriginalBroadcastNPDU             = 0x0b
    # Clause 24
    SecureBVLL = 0x0c
  end

  enum Result : UInt16
    Success                            =    0
    WriteBroadcastDistributionTableNAK = 0x10
    ReadBroadcastDistributionTableNAK  = 0x20
    RegisterForeignDeviceNAK           = 0x30
    ReadForeignDeviceTableNAK          = 0x40
    DeleteForeignDeviceTableEntryNAK   = 0x50
    DistributeBroadcastToNetworkNAK    = 0x60
  end

  def initialize(@data_link : IPv4::BVLCI, network = nil, application = nil, objects : Array(Object | Objects) = [] of Object | Objects)
    @message = Message.new(network, application, objects)
  end

  def initialize(@data_link : IPv4::BVLCI, @message : Message)
  end

  property data_link : IPv4::BVLCI
  property message : Message

  forward_missing_to @message

  def self.hint(io : IO) : DataLinkIndicator
    bytes = io.peek
    raise Error.new("not enough data") if bytes.size < 4

    data = IO::Memory.new(bytes, writeable: false)
    data.read_bytes(DataLinkIndicator)
  end

  def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : IPv4
    # Get message length
    indicator = hint(io)
    raise Error.new("only supports IPv4 datalink") unless indicator.is_ipv4?

    # Read the entire message into memory
    bytes = Bytes.new(indicator.request_length)
    io.read_fully(bytes)
    io = IO::Memory.new(bytes, writeable: false)

    # Parse only the bytes that make up the message
    data_link = io.read_bytes(IPv4::BVLCI)
    return self.new(data_link) unless data_link.request_type.forwarded_npdu? || data_link.request_type.original_unicast_npdu? || data_link.request_type.original_broadcast_npdu?

    message = Message.from_io(io, format)
    self.new(data_link, message)
  end

  def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
    io.write to_slice
  end

  def to_slice
    io = IO::Memory.new
    format = IO::ByteFormat::BigEndian
    io.write_bytes(@data_link, format)
    io.write_bytes(@message, format)

    # write the message length
    io.pos = 2
    io.write_bytes(io.size.to_u16, IO::ByteFormat::BigEndian)
    io.to_slice
  end
end

require "./ipv4_bvlci"
