require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::ComplexAck
  extend self

  def build(message,
            invoke_id : Int,
            service : ConfirmedService,
            object_id : ObjectIdentifier,
            property_id : PropertyType | PropertyIdentifier,
            objects : Array(Object | Objects),
            index : Int? = nil,
            network : UInt16? = nil,
            address : String | Bytes? = nil)
    application = BACnet::ComplexAck.new
    application.invoke_id = invoke_id.to_u8
    application.service = service
    message.application = application

    if property_id.is_a?(PropertyType)
      property_id = PropertyIdentifier.new(property_id)
    end

    # Message requires routing
    if network && address
      net = message.network
      net.destination.network = network
      net.destination_address = address
    end

    data = Array(Object | Objects).new(4)
    data << Object.new.set_value(object_id, context_specific: true, tag: 0)
    data << Object.new.set_value(property_id, context_specific: true, tag: 1)
    if index
      data << Object.new.set_value(index.to_u16, context_specific: true, tag: 2)
    end
    data << Objects.new(context_specific: true, tag: 3, objects: objects)

    message.objects = data
    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(BACnet::ComplexAck) ? app.service.read_property? : false
      raise ArgumentError.new "expected ComplexAck service, passed: #{message}"
    end

    app = message.application.not_nil!.as(BACnet::ComplexAck)
    invoke_id = app.invoke_id
    service = app.service
    objects = message.objects

    net = message.network.not_nil!
    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    {
      invoke_id: invoke_id,
      service:   service,
      object_id: objects[0].to_object_id,
      property:  objects[1].to_property_id.property_type,
      index:     objects.size > 3 ? objects[2].to_i : nil,
      objects:   objects[-1].objects,
      network:   network,
      address:   address,
    }
  end
end
