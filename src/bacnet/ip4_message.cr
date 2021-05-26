require "../bacnet"
require "./services/*"
require "./object"

module BACnet
  class IP4Message
    def initialize(@data_link, @network = nil, @application = nil, @objects = [] of Object)
    end

    alias AppLayer = Nil | ConfirmedRequest | UnconfirmedRequest | SimpleAck | ComplexAck | SegmentAck | ErrorResponse | RejectResponse | AbortResponse

    property data_link : IP4BVLCI
    property network : NPDU?
    property application : AppLayer?
    property objects : Array(Object)

    def self.hint(io : IO) : DataLinkIndicator
      bytes = io.peek
      raise Error.new("not enough data") if bytes.size < 4

      data = IO::Memory.new(bytes, writeable: false)
      data.read_bytes(DataLinkIndicator)
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : IP4Message
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

      network = io.read_bytes(NPDU)
      if network.network_layer_message
        self.new(data_link, network)
      else
        # Work out what type of Application request is in the message
        apdu = io.read_bytes(APDUIndicator)
        io.pos -= 1

        # Parse the applicaion layer
        application = case apdu.message_type
                      when MessageType::ConfirmedRequest
                        io.read_bytes(ConfirmedRequest)
                      when MessageType::UnconfirmedRequest
                        io.read_bytes(UnconfirmedRequest)
                      when MessageType::SimpleACK
                        io.read_bytes(SimpleAck)
                      when MessageType::ComplexACK
                        io.read_bytes(ComplexAck)
                      when MessageType::SegmentACK
                        io.read_bytes(SegmentAck)
                      when MessageType::Error
                        io.read_bytes(ErrorResponse)
                      when MessageType::Reject
                        io.read_bytes(RejectResponse)
                      when MessageType::Abort
                        io.read_bytes(AbortResponse)
                      end

        objects = [] of Object
        loop do
          break unless io.pos < io.size
          objects << io.read_bytes(Object)
        end
        self.new(data_link, network, application, objects)
      end
    end

    def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Int64
      # this will always be big endian, just need to match the interface
      # ameba:disable Lint/ShadowedArgument
      format = IO::ByteFormat::BigEndian
      wrote = io.write_bytes(@data_link, format)
      if net = @network
        wrote += io.write_bytes(net, format)
        if app = @application
          wrote += io.write_bytes(app, format)
          objects.each { |object| wrote += io.write_bytes(object, format) }
        end
      end
      wrote
    end

    def to_slice
      io = IO::Memory.new
      io.write_bytes self
      io.to_slice
    end
  end
end
