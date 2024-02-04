require "../bacnet"

class BACnet::NPDU < BinData
  endian :big

  # NPCI
  field version : UInt8, value: ->{ 1_u8 }
  bit_field do
    # true == network layer message, message type field is present
    bool network_layer_message
    bits 1, :reserved_1
    # Contains a destination address
    bool destination_specifier
    bits 1, :reserved_2
    # Contains a source address
    bool source_specifier
    bool expecting_reply
    bits 2, priority : Priority = Priority::Normal
  end

  group :destination, onlyif: ->{ destination_specifier } do
    field network : UInt16
    field address_length : UInt8, value: ->{ address.size }
    field address : Bytes, length: ->{ address_length }
  end

  group :source, onlyif: ->{ source_specifier } do
    field network : UInt16
    field address_length : UInt8, value: ->{ address.size }
    field address : Bytes, length: ->{ address_length }
  end

  field hop_count : UInt8, onlyif: ->{ destination_specifier }

  # Network layer message
  enum NetworkMessage
    WhoIs               = 0
    IAm                 = 1
    ICountBe            = 2
    RejectMessage       = 3
    RouterBusy          = 4
    RouterAvailable     = 5
    InitRoutingTable    = 6
    InitRoutingTableAck = 7
    ConnectNetwork      = 8
    DisconnectNetwork   = 9
  end

  field network_message_type : UInt8, onlyif: ->{ network_layer_message }
  field vendor_id : UInt16, onlyif: ->{ network_layer_message && (network_message_type >= 0x80_u8) }

  # When network message type is a RejectMessage
  enum RejectReson
    Other          = 0
    RouteNotFound  = 1
    RouterBusy     = 2
    UnknownMessage = 3
    MessageTooLong = 4
  end

  # TODO:: there are a bunch of bytes associated with a network message
  # 0x00 == WHO IS (array of 2 byte dnets)
  # 0x01 == I AM (??)
  # 0x02 == I could be a router (2 byte dnet, 1 byte performance index)
  # 0x03 == Reject Message (1 byte reason, 2 byte dnet)
  # 0x04 == Router Busy to (array of 2 byte dnets)
  # 0x05 == Router Available to (array of 2 byte dnets)
  # 0x08 == Establish Connection (2 byte dnet, 1 byte termination time value)

  def destination_address
    return nil unless destination_specifier
    read_mac destination
  end

  def destination_address=(address : String | Bytes?)
    case address
    in String
      assign_mac(destination, address)
      self.destination_specifier = true
      self.hop_count = 254_u8
    in Bytes
      self.destination.address = address
      self.destination_specifier = true
      self.hop_count = 254_u8
    in Nil
      assign_mac(destination, "")
      self.destination_specifier = false
    end

    address
  end

  def destination_broadcast?
    destination_specifier && destination.address_length == 0_u8
  end

  enum BroadcastType
    Remote
    Global
  end

  def broadcast!(send_to : BroadcastType = BroadcastType::Global)
    if send_to.global?
      destination.address = Bytes[0xff, 0xff]
    else
      destination.address = Bytes.new(0)
    end
  end

  def source_address
    return nil unless source_specifier
    read_mac source
  end

  def source_address=(address : String | Bytes?)
    case address
    in String
      assign_mac(source, address)
      self.source_specifier = true
    in Bytes
      self.source.address = address
      self.source_specifier = true
    in Nil
      assign_mac(source, "")
      self.source_specifier = false
    end

    address
  end

  def read_mac(group)
    group.address.hexstring
  end

  def assign_mac(group, address : String)
    group.address = address.hexbytes
  end

  def expecting_reply?
    expecting_reply
  end
end
