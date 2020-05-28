module BACnet
  # Sent after receiving any segment of a segmented request
  # Also after receiving any segment of a segmented response
  class SegmentAck < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::SegmentACK

      # APDU flags
      bits 2, :ignore
      bool negative_ack
      bool from_server
    end

    uint8 :invoke_id

    group :segment do
      uint8 :sequence_number
      uint8 :window_size
    end
  end
end
