require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::IHave
  extend self

  def build(message,
            device_id : ObjectIdentifier,
            object_id : ObjectIdentifier,
            object_name : String,
            network : UInt16? = nil,
            address : String | Bytes? = nil)
    application = UnconfirmedRequest.new
    application.service = UnconfirmedService::IHave
    message.application = application

    # Message requires routing
    if network && address
      net = message.network
      net.destination.network = network
      net.destination_address = address
    end

    message.objects = Array(Object | Objects).new(3).tap do |array|
      array << Object.new.set_value(device_id, context_specific: true, tag: 0)
      array << Object.new.set_value(object_id, context_specific: true, tag: 1)
      array << Object.new.set_value(object_name, context_specific: true, tag: 2)
    end

    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(UnconfirmedRequest) ? app.service.i_have? : false
      raise ArgumentError.new "expected IHave service, passed: #{message}"
    end

    objects = message.objects

    net = message.network.not_nil!
    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    {
      device_id:   objects[0].to_object_id,
      object_id:   objects[1].to_object_id,
      object_name: objects[2].value.as(String),
      network:     network,
      address:     address,
    }
  end
end
