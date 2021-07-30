require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::WhoIs
  extend self

  MAX_INSTANCE = 0x3FFFFF_u32

  def build(message,
            low_limit : Int = 0,
            high_limit : Int = MAX_INSTANCE,
            network : UInt16? = 0xFFFF_u16)

    net = message.network
    if net
      net.destination_specifier = true
      net.destination.network = network
    end

    application = UnconfirmedRequest.new
    application.service = UnconfirmedService::WhoIs
    message.application = application

    low_limit = 0 if low_limit < 0
    high_limit = MAX_INSTANCE if high_limit > MAX_INSTANCE

    message.objects = Array(Object | Objects).new(2).tap do |array|
      array << Object.new.set_value(low_limit.to_u32, context_specific: true, tag: 0)
      array << Object.new.set_value(high_limit.to_u32, context_specific: true, tag: 1)
    end

    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(UnconfirmedRequest) ? app.service.who_is? : false
      raise ArgumentError.new "expected WhoIs service, passed: #{message}"
    end

    low_limit = 0_u32
    high_limit = MAX_INSTANCE_u32

    objects = message.objects.map(&.as(Object))
    objects.each do |object|
      low_limit = object.to_u32 if object.tag == 0_u8
      high_limit = object.to_u32 if object.tag == 1_u8
    end

    net = message.network.not_nil!
    if net.destination_specifier
      destination_network = net.destination.network
      destination_address = net.destination_address
    end

    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    {
      low_limit:           low_limit,
      high_limit:          high_limit,
      network:             network,
      address:             address,
      destination_network: destination_network,
      destination_address: destination_address,
    }
  end
end
