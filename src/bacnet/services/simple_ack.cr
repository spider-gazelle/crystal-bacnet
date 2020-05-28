module BACnet
  class SimpleAck < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::SimpleACK
      bits 4, :flags
    end

    uint8 :invoke_id
    enum_field UInt8, service : ConfirmedService = ConfirmedService::AcknowledgeAlarm
  end
end
