module BACnet
  # Contains the result of a request
  class ComplexAck < BinData
    endian :big

    bit_field do
      bits 4, message_type : MessageType = MessageType::ComplexACK

      # APDU flags
      bool segmented_message
      bool more_segments_follow
      bits 2, :ignore
    end

    field invoke_id : UInt8

    group :segment, onlyif: ->{ segmented_message } do
      field sequence_number : UInt8
      field window_size : UInt8
    end

    field service : ConfirmedService = ConfirmedService::AcknowledgeAlarm
  end
end
