require "../../../bacnet"
require "../../message"

module BACnet::Client::Message::IAm
  extend self

  def build(message,
            object_id : ObjectIdentifier,
            max_adpu_length : Int,
            segmentation_supported : SegmentationSupport,
            vendor_id : Int,
            network : UInt16? = nil,
            address : String | Bytes? = nil)
    application = UnconfirmedRequest.new
    application.service = UnconfirmedService::IAm
    message.application = application

    # Message requires routing
    if network && address
      net = message.network
      net.destination.network = network
      net.destination_address = address
    end

    message.objects = Array(Object | Objects).new(4).tap do |array|
      array << Object.new.set_value(object_id, context_specific: true, tag: 0)
      array << Object.new.set_value(max_adpu_length.to_u32, context_specific: true, tag: 1)
      array << Object.new.set_value(segmentation_supported, context_specific: true, tag: 2)
      array << Object.new.set_value(vendor_id.to_u32, context_specific: true, tag: 3)
    end

    message
  end

  def parse(message)
    app = message.application
    unless app.is_a?(UnconfirmedRequest) ? app.service.i_am? : false
      raise ArgumentError.new "expected IAm service, passed: #{message}"
    end

    objects = message.objects

    net = message.network.not_nil!
    if net.source_specifier
      network = net.source.network
      address = net.source_address
    end

    {
      object_id:              objects[0].to_object_id,
      max_adpu_length:        objects[1].to_u64,
      segmentation_supported: SegmentationSupport.from_value(objects[2].to_u64),
      vendor_id:              objects[3].to_u64,
      network:                network,
      address:                address,
    }
  end
end
