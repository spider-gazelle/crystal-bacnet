require "./helper"

module BACnet
  describe Message::IPv4 do
    it "should parse a who is request" do
      bytes = "810b000c0120ffff00ff1008".hexbytes

      me = IO::Memory.new(bytes).read_bytes(Message::IPv4)
      net = me.network.not_nil!
      net.destination.address.should eq(65535)
      net.destination.mac_address_length.should eq(0)
      net.destination_broadcast?.should be_true
      net.hop_count.should eq(255)

      app = me.application
      case app
      when UnconfirmedRequest
        app.service.should eq(UnconfirmedService::WhoIs)
      else
        raise "unexpected message type"
      end

      me.objects.should eq([] of Object)
    end

    it "should parse a i am request" do
      bytes = "810b00190120ffff00ff1000c4023fffff2201e09103220104".hexbytes

      me = IO::Memory.new(bytes).read_bytes(Message::IPv4)
      me.data_link.request_type.should eq(Message::IPv4::Request::OriginalBroadcastNPDU)

      net = me.network.not_nil!
      net.destination.address.should eq(65535)
      net.destination.mac_address_length.should eq(0)
      net.destination_broadcast?.should be_true
      net.hop_count.should eq(255)

      app = me.application
      case app
      when UnconfirmedRequest
        app.service.should eq(UnconfirmedService::IAm)
      else
        raise "unexpected message type"
      end

      me.objects.size.should eq(4)
      object_id = me.objects[0].value.as(ObjectIdentifier)
      object_id.object_type.should eq(ObjectIdentifier::ObjectType::Device)
      object_id.instance_number.should eq(4194303)

      max_len = me.objects[1].value.as(UInt64)
      max_len.should eq(480_u64)

      segment_support = me.objects[2].value.as(UInt64)
      segment_support.should eq(3_u64)

      vendor_id = me.objects[3].value.as(UInt64)
      vendor_id.should eq(260_u64)

      me.to_slice.should eq(bytes)
    end

    it "should parse a confirmed request" do
      bytes = "810a0016012465910172ff00030a0c0c02015062191c".hexbytes
      me = IO::Memory.new(bytes).read_bytes(Message::IPv4)
      me.data_link.request_type.should eq(Message::IPv4::Request::OriginalUnicastNPDU)

      net = me.network.not_nil!
      net.expecting_reply?.should eq(true)
      net.destination.address.should eq(26001)
      net.destination_mac.should eq("72")
      net.hop_count.should eq(255)

      app = me.application
      case app
      when ConfirmedRequest
        app.service.should eq(ConfirmedService::ReadProperty)
        app.max_size.should eq(480)
        app.invoke_id.should eq(10)
      else
        raise "unexpected message type"
      end

      me.objects.size.should eq(2)
      object_id = me.objects[0].to_object_id
      prop_id = me.objects[1].to_property_id

      object_id.object_type.should eq(ObjectIdentifier::ObjectType::Device)
      object_id.instance_number.should eq(86114)
      prop_id.property_type.should eq(PropertyIdentifier::PropertyType::Description)

      me.to_slice.should eq(bytes)
    end

    it "should parse a complex ack" do
      bytes = "810a0029010865910172300a0c0c02015062191c3e75110041546d656761313638204465766963653f".hexbytes
      me = IO::Memory.new(bytes).read_bytes(Message::IPv4)
      me.data_link.request_type.should eq(Message::IPv4::Request::OriginalUnicastNPDU)

      net = me.network.not_nil!
      net.expecting_reply?.should eq(false)
      net.source.address.should eq(26001)
      net.source_mac.should eq("72")

      app = me.application
      case app
      when ComplexAck
        app.service.should eq(ConfirmedService::ReadProperty)
        app.invoke_id.should eq(10)
      else
        raise "unexpected message type"
      end

      me.objects.size.should eq(3)
      object_id = me.objects[0].to_object_id
      prop_id = me.objects[1].to_property_id

      object_id.object_type.should eq(ObjectIdentifier::ObjectType::Device)
      object_id.instance_number.should eq(86114)
      prop_id.property_type.should eq(PropertyIdentifier::PropertyType::Description)

      desc = me.objects[2].objects.first.to_encoded_string
      desc.should eq("ATmega168 Device")

      me.to_slice.should eq(bytes)
    end

    it "should parse a complex i-am message" do
      bvcl = "810b0017"
      npdu = "0120ffff00ff"
      apdu = "1000"
      objects = "c40200006f21329103212a"
      bytes = bvcl + npdu + apdu + objects
      IO::Memory.new(bytes.hexbytes).read_bytes(Message::IPv4)
    end
  end
end
