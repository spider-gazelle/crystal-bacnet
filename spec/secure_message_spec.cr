require "./spec_helper"

module BACnet
  describe Message::Secure do
    it "should parse a Encapsulated-NPDU message" do
      bytes = "0107B5EC927BF71A96A2BF0007022BBAC5ECC0993F00030309390101040000010C0C000000051955".hexbytes
      me = IO::Memory.new(bytes).read_bytes(Message::Secure)
      me.data_link.request_type.should eq(Message::Secure::Request::EncapsulatedNPDU)
      me.data_link.destination_specifier.should eq(true)
      me.data_link.destination_options_present.should eq(true)
      me.data_link.data_options_present.should eq(true)

      me.data_link.message_id.should eq(0xB5EC)

      me.data_link.destination_options.size.should eq(2)
      dest = me.data_link.destination_options[0]
      dest.header_type.proprietary?.should eq(true)
      dest.proprietary.vendor_id.should eq(555)
      dest.proprietary.type.should eq(0xba)

      dest = me.data_link.destination_options[1]
      dest.header_type.proprietary?.should eq(true)
      dest.proprietary.vendor_id.should eq(777)
      dest.proprietary.type.should eq(0x39)

      me.data_link.data_options.size.should eq(1)
      opt = me.data_link.data_options[0]
      opt.header_type.secure_path?.should eq(true)
      opt.header_data.should eq(false)

      app = me.application
      case app
      when ConfirmedRequest
        app.service.should eq(ConfirmedService::ReadProperty)
      else
        raise "unexpected message type: #{app.inspect}"
      end

      me.to_slice.should eq(bytes)
    end

    it "should parse a BVLC-Result message" do
      bytes = "0009B5EC927BF71A96A2010101BF00070111556E6DC3B6676C696368657220436F646521".hexbytes
      me = IO::Memory.new(bytes).read_bytes(Message::Secure)
      me.data_link.request_type.should eq(Message::Secure::Request::BVCLResult)
      me.data_link.source_specifier.should eq(true)
      me.data_link.destination_options_present.should eq(false)
      me.data_link.data_options_present.should eq(true)

      me.data_link.message_id.should eq(0xB5EC)
      me.data_link.source_vmac.hexstring.should eq("927bf71a96a2")

      me.data_link.destination_options.size.should eq(0)
      me.data_link.data_options.size.should eq(1)
      opt = me.data_link.data_options[0]
      opt.header_type.secure_path?.should eq(true)
      opt.header_data.should eq(false)

      me.to_slice.should eq(bytes)
    end
  end
end
