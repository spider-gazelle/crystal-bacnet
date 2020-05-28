require "../bacnet"

module BACnet
  class APDUIndicator < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::ConfirmedRequest
      bits 4, :flags
    end
  end
end
