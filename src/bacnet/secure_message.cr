require "../bacnet"
require "./secure_bvlci"
require "./services/*"
require "./object"

module BACnet
  class SecureMessage
    def initialize(@data_link, @network = nil, @application = nil, @objects = [] of Object)
    end

    alias AppLayer = Nil | ConfirmedRequest | UnconfirmedRequest | SimpleAck | ComplexAck | SegmentAck | ErrorResponse | RejectResponse | AbortResponse

    property data_link : SecureBVLCI
    property network : NPDU?
    property application : AppLayer?
    property objects : Array(Object)

    def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : SecureMessage
      # Parse only the bytes that make up the message
      data_link = io.read_bytes(SecureBVLCI)
      return self.new(data_link) unless data_link.request_type.encapsulated_npdu?

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
      if network = @network
        wrote += io.write_bytes(network, format)
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
