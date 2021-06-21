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

  def self.who_is
    data_link = IP4BVLCI.new
    data_link.request_type = RequestTypeIP4::OriginalBroadcastNPDU

    # broadcast
    network = NPDU.new
    network.destination_specifier = true
    network.destination.address = 0xFFFF_u16
    network.hop_count = 255_u8

    request = UnconfirmedRequest.new
    request.service = UnconfirmedService::WhoIs

    IP4Message.new(data_link, network, request)
  end

  @@invoke_id = 0_u8

  def self.next_invoke_id
    next_id = @@invoke_id &+ 1
    @@invoke_id = next_id
  end

  # Index 0 == max index
  # Index 1 == device info
  # Index 2..max == object info
  def self.read_property(
    object_type : ObjectIdentifier::ObjectType,
    instance : UInt32,
    property : PropertyIdentifier::PropertyType,
    index : Int
  )
    data_link = IP4BVLCI.new
    data_link.request_type = RequestTypeIP4::OriginalUnicastNPDU

    network = NPDU.new
    network.expecting_reply = true

    request = ConfirmedRequest.new
    request.max_size_indicator = 5_u8
    request.invoke_id = next_invoke_id
    request.service = ConfirmedService::ReadProperty

    object_id = ObjectIdentifier.new
    object_id.object_type = object_type
    object_id.instance_number = instance
    object = Object.new.set_value(object_id)
    object.context_specific = true
    object.short_tag = 0_u8

    property_id = PropertyIdentifier.new
    property_id.property_type = property
    property_obj = Object.new.set_value(property_id)
    property_obj.context_specific = true
    property_obj.short_tag = 1_u8

    index_obj = Object.new.set_value(index.to_u32)
    index_obj.context_specific = true
    index_obj.short_tag = 2_u8

    IP4Message.new(data_link, network, request, [object, property_obj, index_obj])
  end

  def self.parse_i_am(objects)
    obj_id = objects[0].value.as(BACnet::ObjectIdentifier)
    {
      object_type: obj_id.object_type,
      object_instance: obj_id.instance_number,
      max_adpu_length: objects[1].to_u64,
      segmentation_supported: SegmentationSupport.from_value(objects[2].to_u64),
      vendor_id: objects[3].to_u64,
    }
  end

  def self.read_complex_ack(objects)
    obj_id = objects[0].to_object_id
    {
      object_type: obj_id.object_type,
      object_instance: obj_id.instance_number,
      property: objects[1].to_property_id.property_type,
      index: objects[2].to_u64,
      data: objects[3].objects,
    }
  end
end

require "./bacnet/*"
require "./bacnet/**"
