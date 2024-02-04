module BACnet
  class SimpleAck < BinData
    endian :big

    bit_field do
      bits 4, message_type : MessageType = MessageType::SimpleACK
      bits 4, :flags
    end

    field invoke_id : UInt8
    field service : ConfirmedService = ConfirmedService::AcknowledgeAlarm
  end
end
