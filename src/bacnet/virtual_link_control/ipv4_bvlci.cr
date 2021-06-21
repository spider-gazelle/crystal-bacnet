require "../../bacnet"

module BACnet
  # Header
  enum RequestTypeIP4
    BVCLResult                        =    0
    WriteBroadcastDistributionTable   =    1
    ReadBroadcastDistributionTable    =    2
    ReadBroadcastDistributionTableAck =    3
    ForwardedNPDU                     =    4
    RegisterForeignDevice             =    5
    ReadForeignDeviceTable            =    6
    ReadForeignDeviceTableAck         =    7
    DeleteForeignDeviceTableEntry     =    8
    DistributeBroadcastToNetwork      =    9
    OriginalUnicastNPDU               = 0x0a
    OriginalBroadcastNPDU             = 0x0b
    # Clause 24
    SecureBVLL = 0x0c
  end

  # BACnet Virtual Link Control Interface
  class IP4BVLCI < BinData
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
    enum_field UInt8, request_type : RequestTypeIP4 = RequestTypeIP4::BVCLResult
    uint16 :request_length

    array bdt_entries : BDTEntry, length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      {
        RequestTypeIP4::ReadBroadcastDistributionTableAck,
        RequestTypeIP4::WriteBroadcastDistributionTable,
      }.includes? request_type
    }

    array fdt_entries : FDTEntry, length: ->{ (request_length - 4) / 10 }, onlyif: ->{
      request_type.read_foreign_device_table_ack?
    }

    # B/IP Address http://www.bacnet.org/Tutorial/BACnetIP/sld014.html
    group(:address, onlyif: ->{
      {
        RequestTypeIP4::ForwardedNPDU,
        RequestTypeIP4::DeleteForeignDeviceTableEntry,
      }.includes? request_type
    }) do
      uint32 :ip
      uint16 :port
    end

    uint16 :register_ttl, onlyif: ->{ request_type.register_foreign_device? }

    enum ResultCode
      Success                            =    0
      WriteBroadcastDistributionTableNAK = 0x10
      ReadBroadcastDistributionTableNAK  = 0x20
      RegisterForeignDeviceNAK           = 0x30
      ReadForeignDeviceTableNAK          = 0x40
      DeleteForeignDeviceTableEntryNAK   = 0x50
      DistributeBroadcastToNetworkNAK    = 0x60
    end

    enum_field UInt16, result_code : ResultCode = ResultCode::Success, onlyif: ->{ request_type.bvcl_result? }
  end
end
