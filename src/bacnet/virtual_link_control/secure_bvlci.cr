require "../../bacnet"
require "./secure_message"

module BACnet
  class Message::Secure::BVLCI < BinData
    endian :big

    class Header < BinData
      endian :big

      enum Type
        # SecurePath presence means this packet has only been on secure mediums
        SecurePath  =  1
        Proprietary = 31
      end

      bit_field do
        bool more_headers
        bool must_understand
        bool header_data

        bits 5, header_type : Type = Type::SecurePath
      end

      field data_length : UInt16, value: -> { header_type.proprietary? ? (proprietary.data.size + 3) : data.size }, onlyif: -> { header_data }
      field data : Bytes, length: -> { data_length }, onlyif: -> { header_data && !header_type.proprietary? }

      group :proprietary, onlyif: -> { header_data && header_type.proprietary? } do
        field vendor_id : UInt16
        field type : UInt8
        field data : Bytes, length: -> { parent.data_length - 3 }
      end
    end

    # NOTE:: a UUID constant needs to be generated

    field request_type : Request = Request::BVCLResult
    bit_field do
      # true == network layer message, message type field is present
      bits 4, :reserved
      # Contains a destination address
      bool source_specifier
      bool destination_specifier
      bool destination_options_present
      bool data_options_present
    end
    field message_id : UInt16

    # Broadcast VMAC is 0xFFFFFFFFFFFF
    field source_vmac : Bytes, onlyif: -> { source_specifier }, length: -> { 6 }
    field destination_vmac : Bytes, onlyif: -> { destination_specifier }, length: -> { 6 }

    # Destination Options
    field destination_options : Array(Header), onlyif: -> { destination_options_present }, read_next: -> {
      destination_options.empty? || destination_options[-1].more_headers
    }

    # Data Options
    field data_options : Array(Header), onlyif: -> { data_options_present }, read_next: -> {
      data_options.empty? || data_options[-1].more_headers
    }

    # Payloads:
    group :result, onlyif: -> { request_type.bvcl_result? } do
      # BVLC function for which this is a result
      field bvlc_function : Request = Request::EncapsulatedNPDU
      field result_code : UInt8

      # possibly result_code == 0x01
      group :error, onlyif: -> { result_code > 0 } do
        field header_marker : UInt8
        field class : UInt16
        field code : UInt16

        remaining_bytes :message_bytes

        def message
          String.new(message_bytes)
        end
      end
    end

    remaining_bytes :websocket_urls_data, onlyif: -> { request_type.address_resolution_ack? }

    def websocket_urls
      String.new(websocket_urls_data).split(" ")
    end

    group :advertisement, onlyif: -> { request_type.advertisement? } do
      # 0 == No hub connection, 1 == Connected to primary hub, 2 == Connected to failover hub
      field hub_connection_status : UInt8
      # 0 == does not support, 1 == The node supports accepting direct connections
      field accept_direct_connection : UInt8
      field max_bvlc_length : UInt16
      field max_npdu_length : UInt16
    end

    group :connect_details, onlyif: -> { request_type.connect_request? || request_type.connect_accept? } do
      field vmac : Bytes, length: -> { 6 }
      field device_uuid : Bytes, length: -> { 16 }
      field max_bvlc_length : UInt16
      field max_npdu_length : UInt16
    end

    group :proprietary, onlyif: -> { request_type.proprietary_message? } do
      field vendor_id : UInt16
      field type : UInt8
      remaining_bytes :data
    end
  end
end
