module BACnet
  # Contains the result of a request
  class ComplexAck < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::ComplexACK

      # APDU flags
      bool segmented_message
      bool more_segments_follow
      bits 2, :ignore
    end

    uint8 :invoke_id

    group :segment, onlyif: ->{ segmented_message } do
      uint8 :sequence_number
      uint8 :window_size
    end

    enum_field UInt8, service : ConfirmedService = ConfirmedService::AcknowledgeAlarm
  end
end
