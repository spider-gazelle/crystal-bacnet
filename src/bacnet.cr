require "bindata"

module BACnet
  class Error < RuntimeError; end

  # http://kargs.net/BACnet/BACnet_IP_Details.pdf (page 14)
  enum RequestTypeIP6
    BVCLResult                    =    0
    OriginalUnicastNPDU           =    1
    OriginalBroadcastNPDU         =    2
    AddressResolution             =    3
    ForwardedAddressResolution    =    4
    AddressResolutionAck          =    5
    VirtualAddressResolution      =    6
    VirtualAddressResolutionAck   =    7
    ForwardedNPDU                 =    8
    RegisterForeignDevice         =    9
    DeleteForeignDeviceTableEntry = 0x0a
    SecureBVLL                    = 0x0b
    DistributeBroadcastToNetwork  = 0x0c
  end

  enum Priority
    Normal     = 0
    Urgent
    Critical
    LifeSafety
  end

  # APDU Message Type
  enum MessageType
    ConfirmedRequest   = 0
    UnconfirmedRequest
    SimpleACK
    ComplexACK
    SegmentACK
    Error
    Reject
    Abort
  end

  # ConfirmedRequest messages (NPDU description page 7)
  enum ConfirmedService
    # Alarm and Event Services
    AcknowledgeAlarm     = 0
    CovNotification      = 1
    EventNotification    = 2
    GetAlarmSummary      = 3
    GetEnrollmentSummary = 4
    SubscribeCov         = 5

    # File Access Services
    AtomicReadFile  = 6
    AtomicWriteFile = 7

    # Object Access Services
    AddListElement          =  8
    RemoveListElement       =  9
    CreateObject            = 10
    DeleteObject            = 11
    ReadProperty            = 12
    ReadPropertyConditional = 13
    ReadPropertyMuliple     = 14
    WriteProperty           = 15
    WritePropertyMultiple   = 16

    # Remote Device Management
    DeviceCommunicationControl = 17
    PrivateTransfer            = 18
    TextMessage                = 19
    ReinitializeDevice         = 20

    # Virtual Terminal
    VtOpen  = 21
    VtClose = 22
    VtData  = 23

    # Security Services
    Authenticate = 24
    RequestKey   = 25

    # Object Access Service
    ReadRange = 26

    # Alarm and Event Services
    LifeSafteyOperation  = 27
    SubscribeCovProperty = 28
    GetEvenInformation   = 29

    SubscribeCovPropertyMultiple     = 30
    ConfirmedCovNotificationMultiple = 31
  end

  # UnconfirmedRequest messages (NPDU description page 8)
  enum UnconfirmedService
    IAm                     =  0
    IHave                   =  1
    CovNotification         =  2
    EventNotification       =  3
    PrivateTransfer         =  4
    TextMessage             =  5
    TimeSync                =  6
    WhoHas                  =  7
    WhoIs                   =  8
    TimeSyncUTC             =  9
    WriteGroup              = 10
    CovNotificationMultiple = 11
  end

  enum SegmentationSupport
    Both         = 0
    Transmit
    Receive
    NotSupported
  end

  # ASN.1 message tags (NPDU description page 5)
  # enum ApplicationTags
  # end
end

require "./bacnet/*"
