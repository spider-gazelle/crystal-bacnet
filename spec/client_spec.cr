require "./spec_helper"

module BACnet
  describe BACnet::Client do
    it "should work with IPv4" do
      client = BACnet::Client::IPv4.new
      client.on_transmit do |_, address|
        if address.address == Socket::IPAddress::BROADCAST
          # Broadcast this message, might need to be a unicast to a BBMD
        else
          # server.send message, to: address
        end
      end
    end

    it "should work with SecureConnect" do
      client = BACnet::Client::SecureConnect.new
      client.on_transmit do |_|
        # server.send message
      end
      client.connect!
      client.on_control_info do |message|
        if message.data_link.request_type.connect_accept?
        end
      end
    end
  end
end
