require "../bacnet"

class BACnet::APDUIndicator < BinData
  endian :big

  bit_field do
    bits 4, message_type : MessageType = MessageType::ConfirmedRequest
    bits 4, :flags
  end
end
