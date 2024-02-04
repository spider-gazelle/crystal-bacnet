module BACnet
  class ErrorResponse < BinData
    endian :big

    bit_field do
      bits 4, message_type : MessageType = MessageType::Error
      bits 4, :flags
    end

    field invoke_id : UInt8
    field service : ConfirmedService = ConfirmedService::AcknowledgeAlarm

    # error_class_data, error_code_data are passed as BACnet objects
    def error_details(objects)
      klass = ErrorClass.new message.objects[0].to_i
      code = ErrorCode.new message.objects[1].to_i
      {klass, code}
    end
  end

  enum ErrorClass
    Device        = 0
    Object        = 1
    Property      = 2
    Resources     = 3
    Security      = 4
    Services      = 5
    VT            = 6
    Communication = 7
  end

  enum ErrorCode
    Other                              =   0
    ConfigurationInProgress            =   2
    DeviceBusy                         =   3
    DynamicCreationNotSupported        =   4
    FileAccessDenied                   =   5
    InconsistentParameters             =   7
    InconsistentSelectionCriterion     =   8
    InvalidDataType                    =   9
    InvalidFileAccessMethod            =  10
    InvalidFileStartPosition           =  11
    InvalidParameterDataType           =  13
    InvalidTimeStamp                   =  14
    MissingRequiredParameter           =  16
    NoObjectsOfSpecifiedType           =  17
    NoSpaceForObject                   =  18
    NoSpaceToAddListElement            =  19
    NoSpaceToWriteProperty             =  20
    NoVtSessionsAvailable              =  21
    PropertyIsNotAlist                 =  22
    ObjectDeletionNotPermitted         =  23
    ObjectIdentifierAlreadyExists      =  24
    OperationalProblem                 =  25
    PasswordFailure                    =  26
    ReadAccessDenied                   =  27
    ServiceRequestDenied               =  29
    Timeout                            =  30
    UnknownObject                      =  31
    UnknownProperty                    =  32
    UnknownVtClass                     =  34
    UnknownVtSession                   =  35
    UnsupportedObjectType              =  36
    ValueOutOfRange                    =  37
    VtSessionAlreadyClosed             =  38
    VtSessionTerminationFailure        =  39
    WriteAccessDenied                  =  40
    CharacterSetNotSupported           =  41
    InvalidArrayIndex                  =  42
    CovSubscriptionFailed              =  43
    NotCovProperty                     =  44
    OptionalFunctionalityNotSupported  =  45
    InvalidConfigurationData           =  46
    DatatypeNotSupported               =  47
    DuplicateName                      =  48
    DuplicateObjectId                  =  49
    PropertyIsNotAnArray               =  50
    AbortBufferOverflow                =  51
    AbortInvalidApduInThisState        =  52
    AbortPreemptedByHigherPriorityTask =  53
    AbortSegmentationNotSupported      =  54
    AbortProprietary                   =  55
    AbortOther                         =  56
    InvalidTag                         =  57
    NetworkDown                        =  58
    RejectBufferOverflow               =  59
    RejectInconsistentParameters       =  60
    RejectInvalidParameterDataType     =  61
    RejectInvalidTag                   =  62
    RejectMissingRequiredParameter     =  63
    RejectParameterOutOfRange          =  64
    RejectTooManyArguments             =  65
    RejectUndefinedEnumeration         =  66
    RejectUnrecognizedService          =  67
    RejectProprietary                  =  68
    RejectOther                        =  69
    UnknownDevice                      =  70
    UnknownRoute                       =  71
    ValueNotInitialized                =  72
    InvalidEventState                  =  73
    NoAlarmConfigured                  =  74
    LogBufferFull                      =  75
    LoggedValuePurged                  =  76
    NoPropertySpecified                =  77
    NotConfiguredForTriggeredLogging   =  78
    UnknownSubscription                =  79
    ParameterOutOfRange                =  80
    ListElementNotFound                =  81
    Busy                               =  82
    CommunicationDisabled              =  83
    Success                            =  84
    AccessDenied                       =  85
    BadDestinationAddress              =  86
    BadDestinationDeviceId             =  87
    BadSignature                       =  88
    BadSourceAddress                   =  89
    BadTimestamp                       =  90
    CannotUseKey                       =  91
    CannotVerifyMessageId              =  92
    CorrectKeyRevision                 =  93
    DestinationDeviceIdRequired        =  94
    DuplicateMessage                   =  95
    EncryptionNotConfigured            =  96
    EncryptionRequired                 =  97
    IncorrectKey                       =  98
    InvalidKeyData                     =  99
    KeyUpdateInProgress                = 100
    MalformedMessage                   = 101
    NotKeyServer                       = 102
    SecurityNotConfigured              = 103
    SourceSecurityRequired             = 104
    TooManyKeys                        = 105
    UnknownAuthenticationType          = 106
    UnknownKey                         = 107
    UnknownKeyRevision                 = 108
    UnknownSourceMessage               = 109
    NotRouterToDnet                    = 110
    RouterBusy                         = 111
    UnknownNetworkMessage              = 112
    MessageTooLong                     = 113
    SecurityError                      = 114
    AddressingError                    = 115
    WriteBdtFailed                     = 116
    ReadBdtFailed                      = 117
    RegisterForeignDeviceFailed        = 118
    ReadFdtFailed                      = 119
    DeleteFdtEntryFailed               = 120
    DistributeBroadcastFailed          = 121
    UnknownFileSize                    = 122
    AbortApduTooLong                   = 123
    AbortApplicationExceededReplyTime  = 124
    AbortOutOfResources                = 125
    AbortTsmTimeout                    = 126
    AbortWindowSizeOutOfRange          = 127
    FileFull                           = 128
    InconsistentConfiguration          = 129
    InconsistentObjectType             = 130
    InternalError                      = 131
    NotConfigured                      = 132
    OutOfMemory                        = 133
    ValueTooLong                       = 134
    AbortInsufficientSecurity          = 135
    AbortSecurityError                 = 136
    DuplicateEntry                     = 137
    InvalidValueInThisState            = 138
  end
end
