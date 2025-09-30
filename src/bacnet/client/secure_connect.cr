require "../../bacnet"
require "promise"
require "uuid"
require "log"

class BACnet::Client::SecureConnect
  def initialize(
    @retries : Int32 = 3,
    @timeout : ::Time::Span = 5.seconds,
    @uuid : UUID = UUID.v4,
    @vmac : Bytes = SecureConnect.generate_vmac,
  )
    @invoke_id = rand(0xFF).to_u8
    @message_id = rand(0xFFFF).to_u16
    @in_flight = {} of UInt8 => Tracker
    @control_callbacks = [] of (BACnet::Message::Secure) -> Nil
    @request_callbacks = [] of (BACnet::Message::Secure) -> Nil
    @broadcast_callbacks = [] of (BACnet::Message::Base, Socket::IPAddress | Bytes?) -> Nil
  end

  @invoke_id : UInt8
  @message_id : UInt16
  @mutex : Mutex = Mutex.new(:reentrant)

  getter uuid : UUID
  getter vmac : Bytes

  protected def next_invoke_id : UInt8
    @mutex.synchronize do
      next_id = @invoke_id &+ 1
      @invoke_id = next_id
    end
  end

  protected def next_message_id : UInt16
    @mutex.synchronize do
      next_id = @message_id &+ 1
      @message_id = next_id
    end
  end

  def connect!
    data_link = BACnet::Message::Secure::BVLCI.new
    data_link.request_type = BACnet::Message::Secure::Request::ConnectRequest
    data_link.message_id = next_message_id
    data_link.connect_details.vmac = @vmac
    data_link.connect_details.device_uuid = @uuid.bytes.to_slice
    data_link.connect_details.max_bvlc_length = 65535_u16 # maximum BVLC size
    data_link.connect_details.max_npdu_length = 61327_u16 # maximum BVLC size (65535) minus the 16-byte BVLC header and minus 4192 bytes reserved for data options

    # TODO:: create a promise and parse the Connect Accept request
    message = BACnet::Message::Secure.new(data_link)
    @on_transmit.try(&.call(message))
  end

  def heartbeat!
    data_link = BACnet::Message::Secure::BVLCI.new
    data_link.request_type = BACnet::Message::Secure::Request::HeartbeatRequest
    data_link.message_id = next_message_id

    message = BACnet::Message::Secure.new(data_link)
    @on_transmit.try(&.call(message))
  end

  def heartbeat_ack!(message : BACnet::Message::Secure)
    raise ArgumentError.new("expected heartbeat request, not #{message.data_link.request_type}") unless message.data_link.request_type.heartbeat_request?
    message.data_link.request_type = BACnet::Message::Secure::Request::HeartbeatACK
    @on_transmit.try(&.call(message))
  end

  def new_message
    data_link = BACnet::Message::Secure::BVLCI.new
    network = NPDU.new
    BACnet::Message::Secure.new(data_link, network)
  end

  protected def configure_defaults(message)
    data_link = message.data_link
    data_link.request_type = BACnet::Message::Secure::Request::EncapsulatedNPDU
    data_link.source_specifier = true
    data_link.source_vmac = @vmac
    data_link.message_id = next_message_id

    app = message.application
    case app
    when ConfirmedRequest
      app.invoke_id = next_invoke_id
    end

    message
  end

  def self.generate_vmac : Bytes
    vmac = Bytes.new(6)
    Random::Secure.random_bytes(vmac)

    # Ensure not all 0s or all FFs
    if vmac.all?(&.zero?) || vmac.all? { |b| b == 0xFF_u8 }
      return generate_vmac
    end

    vmac
  end

  def self.generate_uuid_bytes : Bytes
    uuid = UUID.v4
    uuid.bytes.to_slice # 16-byte representation
  end

  {% begin %}
    {% expects_reply = %w(WriteProperty ReadProperty) %}
    {% for klass in %w(IAm IHave WriteProperty ReadProperty ComplexAck) %}
      def {{klass.underscore.id}}(*args, link_address : Socket::IPAddress | Bytes? = nil, **opts)
        raise ArgumentError.new("link_address should be VMAC bytes") unless link_address.is_a?(Bytes)
        message = configure_defaults Client::Message::{{klass.id}}.build(new_message, *args, **opts)
        message.data_link.destination_address = link_address

        {% if expects_reply.includes?(klass) %}
          send_and_retry(Tracker.new(message.application.as(ConfirmedRequest).invoke_id.not_nil!, message))
        {% else %}
          @on_transmit.try &.call(message)
        {% end %}
      end

      def parse_{{klass.underscore.id}}(message : BACnet::Message::Base)
        Client::Message::{{klass.id}}.parse(message)
      end
    {% end %}
  {% end %}

  def who_is(*args, **opts)
    message = configure_defaults Client::Message::WhoIs.build(new_message, *args, **opts)
    data_link = message.data_link
    data_link.destination_specifier = true
    data_link.destination_vmac = BACnet::Message::Secure::BVLCI::BROADCAST_VMAC

    @on_transmit.try &.call(message)
  end

  def on_transmit(&@on_transmit : (BACnet::Message::Secure) -> Nil)
  end

  def on_control_info(&callback : (BACnet::Message::Secure) -> Nil)
    @control_callbacks << callback
  end

  def on_request(&callback : (BACnet::Message::Secure) -> Nil)
    @request_callbacks << callback
  end

  def on_broadcast(&callback : (BACnet::Message::Base, Socket::IPAddress | Bytes?) -> Nil)
    @broadcast_callbacks << callback
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def received(message : BACnet::Message::Secure)
    BACnet.logger.debug { "received #{message.data_link.request_type} message: #{message.application.class}" }

    app = message.application
    case app
    in Nil
      case message.data_link.request_type
      when .heartbeat_request?
        heartbeat_ack!(message)
      else
        spawn { @control_callbacks.each &.call(message) }
      end
    in BACnet::ConfirmedRequest
      spawn { @request_callbacks.each &.call(message) }
    in BACnet::UnconfirmedRequest
      spawn { @broadcast_callbacks.each &.call(message, message.data_link.source_vmac) }
    in BACnet::ErrorResponse, BACnet::AbortCode, BACnet::RejectResponse
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        if app.is_a?(ErrorResponse)
          klass = ErrorClass.new message.objects[0].to_i
          code = ErrorCode.new message.objects[1].to_i

          error_message = "request failed with #{app.class} - #{klass}: #{code}"
          BACnet.logger.warn { error_message }

          error = case code
                  when ErrorCode::UnknownProperty
                    UnknownPropertyError.new(error_message)
                  else
                    Error.new(error_message)
                  end
          tracker.promise.reject(error)
        else
          tracker.promise.reject(Error.new("request failed with #{app.class} - #{app.reason}"))
        end
      else
        BACnet.logger.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in BACnet::ComplexAck, BACnet::SimpleAck, BACnet::SegmentAck
      # TODO:: handle segmented responses
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        tracker.promise.resolve(message)
      else
        BACnet.logger.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in BinData
      # https://github.com/crystal-lang/crystal/issues/9116
      # https://github.com/crystal-lang/crystal/issues/9235
      BACnet.logger.fatal { "compiler bug" }
      raise "should never select this case"
    end
  end

  protected def send_and_retry(tracker : Tracker)
    promise = Promise.new(BACnet::Message::Secure, @timeout)
    tracker.promise.then { |message| promise.resolve(message) }
    tracker.promise.catch { |error| promise.reject(error); raise error }
    promise.catch do |error|
      case error
      when Promise::Timeout
        BACnet.logger.debug { "timeout sending message #{tracker.request_id}" }
        tracker.attempt += 1
        if tracker.attempt <= @retries
          send_and_retry(tracker)
        else
          @mutex.synchronize { @in_flight.delete(tracker.request_id) }
          tracker.promise.reject(error)
          error
        end
      else # propagate the error (this shouldn't happen)
        raise error
      end
    end

    @mutex.synchronize { @in_flight[tracker.request_id] = tracker }
    @on_transmit.try &.call(tracker.request)
    tracker.promise
  end

  class Tracker
    def initialize(@request_id, @request)
      @promise = Promise.new(BACnet::Message::Secure)
    end

    property request_id : UInt8
    property promise : Promise::DeferredPromise(BACnet::Message::Secure)
    property request : BACnet::Message::Secure
    property attempt : Int32 = 0
  end
end
