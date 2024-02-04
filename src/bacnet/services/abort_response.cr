module BACnet
  enum AbortCode : UInt8
    Other                         =  0
    BufferOverflow                =  1
    InvalidApduInThisState        =  2
    PreemptedByHigherPriorityTask =  3
    SegmentationNotSupported      =  4
    SecurityError                 =  5
    InsufficientSecurity          =  6
    WindowSizeOutOfRange          =  7
    ApplicationExceededReplyTime  =  8
    OutOfResources                =  9
    TsmTimeout                    = 10
    ApduTooLong                   = 11
  end

  class AbortResponse < BinData
    endian :big

    bit_field do
      bits 4, message_type : MessageType = MessageType::Abort
      bits 3, :flags
      bool from_server
    end

    field invoke_id : UInt8
    field reason : AbortCode = AbortCode::Other
  end
end
