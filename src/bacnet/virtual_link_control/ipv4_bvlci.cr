require "../../bacnet"
require "./ipv4_message"

module BACnet
  # BACnet Virtual Link Control Interface
  class Message::IPv4::BVLCI < BinData
    endian :big

    class BDTEntry < BinData
      endian :big

      # six octets consisting of the four-octet IP address followed by
      # a two-octet UDP port number shall function analogously to the MAC address
      uint32 :ip
      uint16 :port

      uint32 :broadcast_distribution_mask
    end

    class FDTEntry < BinData
      endian :big

      uint32 :ip
      uint16 :port

      uint16 :registered_ttl
      uint16 :remaining_ttl
    end

    # ref: http://www.bacnet.org/Tutorial/BACnetIP/sld005.html

    uint8 :protocol, value: ->{ 0x81_u8 } # 0x81 == BACnet/IP
    enum_field UInt8, request_type : Request = Request::BVCLResult
    uint16 :request_length

    array bdt_entries : BDTEntry, length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      {
        Request::ReadBroadcastDistributionTableAck,
        Request::WriteBroadcastDistributionTable,
      }.includes? request_type
    }

    array fdt_entries : FDTEntry, length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      request_type.read_foreign_device_table_ack?
    }

    # B/IP Address http://www.bacnet.org/Tutorial/BACnetIP/sld014.html
    group(:address, onlyif: ->{
      {
        Request::ForwardedNPDU,
        Request::DeleteForeignDeviceTableEntry,
      }.includes? request_type
    }) do
      uint32 :ip
      uint16 :port
    end

    uint16 :register_ttl, onlyif: ->{ request_type.register_foreign_device? }

    enum_field UInt16, result_code : Result = Result::Success, onlyif: ->{ request_type.bvcl_result? }
  end
end
