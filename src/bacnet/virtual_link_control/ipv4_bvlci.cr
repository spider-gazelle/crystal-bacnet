require "../../bacnet"
require "./ipv4_message"
require "socket"

module BACnet
  # BACnet Virtual Link Control Interface
  class Message::IPv4::BVLCI < BinData
    endian :big

    class BDTEntry < BinData
      endian :big

      # six octets consisting of the four-octet IP address followed by
      # a two-octet UDP port number shall function analogously to the MAC address
      field ip : UInt32
      field port : UInt16

      field broadcast_distribution_mask : UInt32
    end

    class FDTEntry < BinData
      endian :big

      field ip : UInt32
      field port : UInt16

      field registered_ttl : UInt16
      field remaining_ttl : UInt16
    end

    # ref: http://www.bacnet.org/Tutorial/BACnetIP/sld005.html

    field protocol : UInt8, value: ->{ 0x81_u8 } # 0x81 == BACnet/IP
    field request_type : Request = Request::BVCLResult
    field request_length : UInt16

    field bdt_entries : Array(BDTEntry), length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      {
        Request::ReadBroadcastDistributionTableAck,
        Request::WriteBroadcastDistributionTable,
      }.includes? request_type
    }

    field fdt_entries : Array(FDTEntry), length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      request_type.read_foreign_device_table_ack?
    }

    # B/IP Address http://www.bacnet.org/Tutorial/BACnetIP/sld014.html
    group(:address, onlyif: ->{
      {
        Request::ForwardedNPDU,
        Request::DeleteForeignDeviceTableEntry,
      }.includes? request_type
    }) do
      field ip1 : UInt8
      field ip2 : UInt8
      field ip3 : UInt8
      field ip4 : UInt8
      field port : UInt16
    end

    field register_ttl : UInt16, onlyif: ->{ request_type.register_foreign_device? }

    field result_code : Result = Result::Success, onlyif: ->{ request_type.bvcl_result? }

    def forwarded_address
      Socket::IPAddress.new("#{address.ip1}.#{address.ip2}.#{address.ip3}.#{address.ip4}", address.port.to_i)
    end
  end
end
