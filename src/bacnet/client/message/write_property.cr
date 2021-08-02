require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::WriteProperty
  extend self

  def build(message,
            object_id : ObjectIdentifier,
            property_id : PropertyIdentifier::PropertyType | PropertyIdentifier,
            objects : Array(Object | Objects) | Array(Object) | Array(Objects) | Object | Objects,
            index : Int? = nil,
            priority : Int? = nil,
            network : UInt16? = nil,
            address : String | Bytes? = nil)
    if property_id.is_a?(PropertyIdentifier::PropertyType)
      property_id = PropertyIdentifier.new(property_id)
    end

    unless objects.is_a?(Array)
      objects = [objects]
    end
    objects = Array(Object | Objects).new(objects.size).tap do |array|
      objects.each { |object| array << object }
    end

    net = message.network.not_nil!
    net.expecting_reply = true

    # Message requires routing
    if network && address
      net.destination.network = network
      net.destination_address = address
    end

    application = ConfirmedRequest.new
    application.service = ConfirmedService::WriteProperty
    application.max_size_indicator = 5_u8
    message.application = application

    objects = Array(Object | Objects).new(5).tap do |array|
      array << Object.new.set_value(object_id, context_specific: true, tag: 0)
      array << Object.new.set_value(property_id, context_specific: true, tag: 1)

      if index
        array << Object.new.set_value(index.to_u32, context_specific: true, tag: 2)
      end

      array << Objects.new(context_specific: true, tag: 3, objects: objects)

      if priority
        priority = 16 if priority > 16
        priority = 1 if priority < 1
        array << Object.new.set_value(priority.to_u32, context_specific: true, tag: 4)
      end
    end

    message.objects = objects
    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(ConfirmedRequest) ? app.service.write_property? : false
      raise ArgumentError.new "expected WriteProperty service, passed: #{message}"
    end

    net = message.network.not_nil!
    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    objects = message.objects

    obj_id = objects[0].to_object_id
    prop_id = objects[1].to_property_id.property_type

    index = 2
    tag = 2

    # Extract index
    if (object = objects[index]?) && object.tag == tag
      the_index = object.to_i
      index += 1
    end
    tag += 1

    # Extract new value
    new_value = objects[index].objects
    index += 1
    tag += 1

    # Extract priority
    if (object = objects[index]?) && object.tag == tag
      priority = object.to_i
    end
    {
      object_id: obj_id,
      property:  prop_id,
      index:     the_index,
      objects:   new_value,
      priority:  priority,
      network:   network,
      address:   address,
    }
  end
end
