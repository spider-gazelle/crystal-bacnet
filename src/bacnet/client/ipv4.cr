require "../../bacnet"
require "promise"
require "socket"
require "log"

class BACnet::Client::IPv4
  Log = ::Log.for("bacnet.client")

  def initialize(
    @retries : Int32 = 3,
    @timeout : ::Time::Span = 5.seconds
  )
    @invoke_id = rand(0xFF).to_u8
    @in_flight = {} of UInt8 => Tracker
    @control_callbacks = [] of (BACnet::Message::IPv4, Socket::IPAddress) -> Nil
    @request_callbacks = [] of (BACnet::Message::IPv4, Socket::IPAddress) -> Nil
    @broadcast_callbacks = [] of (BACnet::Message::IPv4, Socket::IPAddress) -> Nil
  end

  @invoke_id : UInt8
  @mutex : Mutex = Mutex.new(:reentrant)

  protected def next_invoke_id
    @mutex.synchronize do
      next_id = @invoke_id &+ 1
      @invoke_id = next_id
    end
  end

  def new_message
    data_link = BACnet::Message::IPv4::BVLCI.new
    network = NPDU.new
    BACnet::Message::IPv4.new(data_link, network)
  end

  protected def configure_defaults(message)
    message.data_link.request_type = BACnet::Message::IPv4::Request::OriginalUnicastNPDU

    app = message.application
    case app
    when ConfirmedRequest
      app.invoke_id = next_invoke_id
    end

    message
  end

  {% begin %}
    {% expects_reply = %w(ReadProperty) %}
    {% for klass in %w(IAm IHave ReadProperty ComplexAck) %}
      def {{klass.underscore.id}}(address : Socket::IPAddress, *args, **opts)
        message = configure_defaults Client::Message::{{klass.id}}.build(new_message, *args, **opts)

        {% if expects_reply.includes?(klass) %}
          send_and_retry(Tracker.new(message.application.as(ConfirmedRequest).invoke_id.not_nil!, address, message))
        {% else %}
          @on_transmit.try &.call(message, address)
        {% end %}
      end

      def parse_{{klass.underscore.id}}(message : BACnet::Message::IPv4)
        Client::Message::{{klass.id}}.parse(message)
      end
    {% end %}
  {% end %}

  def who_is(*args, **opts)
    message = configure_defaults Client::Message::WhoIs.build(new_message, *args, **opts)
    @on_transmit.try &.call(message, Socket::IPAddress.new("255.255.255.255", 0xBAC0))
  end

  def on_transmit(&@on_transmit : (BACnet::Message::IPv4, Socket::IPAddress) -> Nil)
  end

  def on_control_info(&callback : (BACnet::Message::IPv4, Socket::IPAddress) -> Nil)
    @control_callbacks << callback
  end

  def on_request(&callback : (BACnet::Message::IPv4, Socket::IPAddress) -> Nil)
    @request_callbacks << callback
  end

  def on_broadcast(&callback : (BACnet::Message::IPv4, Socket::IPAddress) -> Nil)
    @broadcast_callbacks << callback
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def received(message : BACnet::Message::IPv4, address : Socket::IPAddress)
    Log.trace { "received #{message.data_link.request_type} message from #{address.inspect} - #{message.application.class}" }

    app = message.application
    case app
    in Nil
      spawn { @control_callbacks.each &.call(message, address) }
    in BACnet::ConfirmedRequest
      spawn { @request_callbacks.each &.call(message, address) }
    in BACnet::UnconfirmedRequest
      spawn { @broadcast_callbacks.each &.call(message, address) }
    in BACnet::ErrorResponse, BACnet::AbortCode, BACnet::RejectResponse
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        if app.is_a?(ErrorResponse)
          klass = ErrorClass.from_value message.objects[0].to_u64
          code = ErrorCode.from_value message.objects[1].to_u64

          error_message = "request failed with #{app.class} - #{klass}: #{code}"
          Log.trace { error_message }

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
        Log.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in BACnet::ComplexAck, BACnet::SimpleAck, BACnet::SegmentAck
      # TODO:: handle segmented responses
      if tracker = @mutex.synchronize { @in_flight.delete(app.invoke_id) }
        tracker.promise.resolve(message)
      else
        Log.debug { "unexpected request ID received #{app.invoke_id}" }
      end
    in BinData
      # https://github.com/crystal-lang/crystal/issues/9116
      # https://github.com/crystal-lang/crystal/issues/9235
      Log.fatal { "compiler bug" }
      raise "should never select this case"
    end
  end

  protected def send_and_retry(tracker : Tracker)
    promise = Promise.new(BACnet::Message::IPv4, @timeout)
    tracker.promise.then { |message| promise.resolve(message) }
    tracker.promise.catch { |error| promise.reject(error); raise error }
    promise.catch do |error|
      case error
      when Promise::Timeout
        Log.debug { "timeout sending message to #{tracker.address.inspect}" }
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
    @on_transmit.try &.call(tracker.request, tracker.address)
    tracker.promise
  end

  class Tracker
    def initialize(@request_id, @address, @request)
      @promise = Promise.new(BACnet::Message::IPv4)
    end

    property request_id : UInt8
    property promise : Promise::DeferredPromise(BACnet::Message::IPv4)
    property address : Socket::IPAddress
    property request : BACnet::Message::IPv4
    property attempt : Int32 = 0
  end
end
