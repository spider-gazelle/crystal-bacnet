module BACnet
  # Sent after receiving any segment of a segmented request
  # Also after receiving any segment of a segmented response
  class SegmentAck < BinData
    endian :big

    bit_field do
      bits 4, message_type : MessageType = MessageType::SegmentACK

      # APDU flags
      bits 2, :ignore
      bool negative_ack
      bool from_server
    end

    field invoke_id : UInt8

    group :segment do
      field sequence_number : UInt8
      field window_size : UInt8
    end
  end
end
