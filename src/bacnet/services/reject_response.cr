module BACnet
  enum RejectCode
    Other                    = 0
    BufferOverflow           = 1
    InconsistentParameters   = 2
    InvalidParameterDataType = 3
    InvalidTag               = 4
    MissingRequiredParameter = 5
    ParameterOutOfRange      = 6
    TooManyArguments         = 7
    UndefinedEnumeration     = 8
    UnrecognizedService      = 9
  end

  class RejectResponse < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::Reject
      bits 4, :flags
    end

    uint8 :invoke_id
    enum_field UInt8, reason : RejectCode = RejectCode::Other
  end
end
