require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::ReadProperty
  extend self

  def build(message,
            object_id : ObjectIdentifier,
            property_id : PropertyType | PropertyIdentifier,
            index : Int? = nil,
            network : UInt16? = nil,
            address : String | Bytes? = nil)
    if property_id.is_a?(PropertyType)
      property_id = PropertyIdentifier.new(property_id)
    end

    net = message.network
    net.expecting_reply = true

    # Message requires routing
    if network && address
      net.destination.network = network
      net.destination_address = address
    end

    application = ConfirmedRequest.new
    application.service = ConfirmedService::ReadProperty
    application.max_size_indicator = 5_u8
    message.application = application

    objects = Array(Object | Objects).new(3).tap do |array|
      array << Object.new.set_value(object_id, context_specific: true, tag: 0)
      array << Object.new.set_value(property_id, context_specific: true, tag: 1)
    end

    if index
      objects << Object.new.set_value(index.to_u32, context_specific: true, tag: 2)
    end

    message.objects = objects
    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(ConfirmedRequest) ? app.service.read_property? : false
      raise ArgumentError.new "expected ReadProperty service, passed: #{message}"
    end

    net = message.network.not_nil!
    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    objects = message.objects
    {
      object_id: objects[0].to_object_id,
      property:  objects[1].to_property_id.property_type,
      index:     objects[2].try &.to_i,
      network:   network,
      address:   address,
    }
  end
end
