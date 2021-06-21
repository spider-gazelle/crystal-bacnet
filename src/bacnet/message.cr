require "../bacnet"

class BACnet::Message
  def initialize(@network = nil, @application = nil, @objects = [] of Object | Objects)
  end

  alias AppLayer = Nil | ConfirmedRequest | UnconfirmedRequest | SimpleAck | ComplexAck | SegmentAck | ErrorResponse | RejectResponse | AbortResponse

  property network : NPDU?
  property application : AppLayer?
  property objects : Array(Object | Objects)

  def self.from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Message
    network = io.read_bytes(NPDU)
    if network.network_layer_message
      self.new(network)
    else
      # Work out what type of Application request is in the message
      apdu = io.read_bytes(APDUIndicator)
      io.pos -= 1

      # Parse the applicaion layer
      application = case apdu.message_type
                    when .confirmed_request?
                      io.read_bytes(ConfirmedRequest)
                    when .unconfirmed_request?
                      io.read_bytes(UnconfirmedRequest)
                    when .simple_ack?
                      io.read_bytes(SimpleAck)
                    when .complex_ack?
                      io.read_bytes(ComplexAck)
                    when .segment_ack?
                      io.read_bytes(SegmentAck)
                    when .error?
                      io.read_bytes(ErrorResponse)
                    when .reject?
                      io.read_bytes(RejectResponse)
                    when .abort?
                      io.read_bytes(AbortResponse)
                    end

      objects = [] of Object
      loop do
        break unless io.pos < io.size
        objects << io.read_bytes(Object)
      end
      self.new(network, application, Objects.parse_object_list(objects))
    end
  end

  def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
    # this will always be big endian, just need to match the interface
    # ameba:disable Lint/ShadowedArgument
    format = IO::ByteFormat::BigEndian
    if network = @network
      io.write_bytes(network, format)
      if app = @application
        io.write_bytes(app, format)
        objects.each { |object| io.write_bytes(object, format) }
      end
    end
  end

  def to_slice
    io = IO::Memory.new
    io.write_bytes self
    io.to_slice
  end
end
