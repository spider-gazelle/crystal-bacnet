module BACnet
  # NOTE:: for request structures see page 650 ANSI/ASHRAE Standard 135-2012

  class UnconfirmedRequest < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::UnconfirmedRequest
      bits 4, :flags
    end

    enum_field UInt8, service : UnconfirmedService = UnconfirmedService::IAm
  end
end
