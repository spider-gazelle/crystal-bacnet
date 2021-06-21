require "../../bacnet"

module BACnet
  enum RequestTypeSecure
    BVCLResult                =    0
    EncapsulatedNPDU          =    1
    AddressResolution         =    2
    AddressResolutionACK      =    3
    Advertisement             =    4
    AdvertisementSolicitation =    5
    ConnectRequest            =    6
    ConnectAccept             =    7
    DisconnectRequest         =    8
    DisconnectACK             =    9
    HeartbeatRequest          = 0x0a
    HeartbeatACK              = 0x0b
    ProprietaryMessage        = 0x0c
  end

  class SecureBVLCI < BinData
    endian :big

    enum HeaderType
      # SecurePath presence means this packet has only been on secure mediums
      SecurePath  =  1
      Proprietary = 31
    end

    class Header < BinData
      endian :big

      bit_field do
        bool more_headers
        bool must_understand
        bool header_data

        enum_bits 5, header_type : HeaderType = HeaderType::SecurePath
      end

      uint16 :data_length, value: ->{ header_type.proprietary? ? (proprietary.data.size + 3) : data.size }, onlyif: ->{ header_data }
      bytes :data, length: ->{ data_length }, onlyif: ->{ header_data && !header_type.proprietary? }

      group :proprietary, onlyif: ->{ header_data && header_type.proprietary? } do
        uint16 :vendor_id
        uint8 :type
        bytes :data, length: ->{ parent.data_length - 3 }
      end
    end

    # NOTE:: a UUID constant needs to be generated

    enum_field UInt8, request_type : RequestTypeSecure = RequestTypeSecure::BVCLResult
    bit_field do
      # true == network layer message, message type field is present
      bits 4, :reserved
      # Contains a destination address
      bool source_specifier
      bool destination_specifier
      bool destination_options_present
      bool data_options_present
    end
    uint16 :message_id

    # Broadcast VMAC is 0xFFFFFFFFFFFF
    bytes :source_vmac, onlyif: ->{ source_specifier }, length: ->{ 6 }
    bytes :destination_vmac, onlyif: ->{ destination_specifier }, length: ->{ 6 }

    # Destination Options
    variable_array destination_options : Header, onlyif: ->{ destination_options_present }, read_next: ->{
      destination_options.empty? || destination_options[-1].more_headers
    }

    # Data Options
    variable_array data_options : Header, onlyif: ->{ data_options_present }, read_next: ->{
      data_options.empty? || data_options[-1].more_headers
    }

    # Payloads:
    group :result, onlyif: ->{ request_type.bvcl_result? } do
      uint8 :bvlc_function
      uint8 :result_code

      # possibly result_code == 0x01
      group :error, onlyif: ->{ result_code > 0 } do
        uint8 :header_marker
        uint16 :class
        uint16 :code

        remaining_bytes :message_bytes

        def message
          String.new(message_bytes)
        end
      end
    end

    remaining_bytes :websocket_urls_data, onlyif: ->{ request_type.address_resolution_ack? }

    def websocket_urls
      String.new(websocket_urls_data).split(" ")
    end

    group :advertisement, onlyif: ->{ request_type.advertisement? } do
      # 0 == No hub connection, 1 == Connected to primary hub, 2 == Connected to failover hub
      uint8 :hub_connection_status
      # 0 == does not support, 1 == The node supports accepting direct connections
      uint8 :accept_direct_connection
      uint16 :max_bvlc_length
      uint16 :max_npdu_length
    end

    group :connect_details, onlyif: ->{ request_type.connect_request? || request_type.connect_accept? } do
      bytes :vmac, length: ->{ 6 }
      bytes :device_uuid, length: ->{ 16 }
      uint16 :max_bvlc_length
      uint16 :max_npdu_length
    end

    group :proprietary, onlyif: ->{ request_type.proprietary_message? } do
      uint16 :vendor_id
      uint8 :type
      remaining_bytes :data
    end
  end
end
