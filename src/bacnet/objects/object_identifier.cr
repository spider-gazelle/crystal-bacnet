require "../object"

module BACnet
  class ObjectIdentifier < BinData
    endian :big

    bit_field do
      enum_bits 10, object_type : ObjectType = ObjectType::Device
      bits 22, :instance_number
    end

    def inspect(io : IO) : Nil
      super(io)

      io << "\b #type="
      object_type.to_s(io)
      io << ">"
    end

    enum ObjectType
      AnalogInput = 0
      AnalogOutput = 1
      AnalogValue = 2
      BinaryInput = 3
      BinaryOutput = 4
      BinaryValue = 5
      Calendar = 6
      Command = 7
      Device = 8
      EventEnrollment = 9
      File = 10
      Group = 11
      Loop = 12
      MultiStateInput = 13
      MultiStateOutput = 14
      NotificationClass = 15
      Program = 16
      Schedule = 17
      Averaging = 18
      MultiStateValue = 19
      TrendLog = 20
      LifeSafetyPoint = 21
      LifeSafetyZone = 22
      Accumulator = 23
      PulseConverter = 24
      EventLog = 25
      GlobalGroup = 26
      TrendLogMultiple = 27
      LoadControl = 28
      StructuredView = 29
      AccessDoor = 30
      Timer = 31
      AccessCredential = 32
      AccessPoint = 33
      AccessRights = 34
      AccessUser = 35
      AccessZone = 36
      CredentialDataInput = 37
      NetworkSecurity = 38
      BitstringValue = 39
      CharacterStringValue = 40
      DatePatternValue = 41
      DateValue = 42
      DatetimePatternValue = 43
      DatetimeValue = 44
      IntegerValue = 45
      LargeAnalogValue = 46
      OctetstringValue = 47
      PositiveIntegerValue = 48
      TimePatternValue = 49
      TimeValue = 50
      NotificationForwarder = 51
      AlertEnrollment = 52
      Channel = 53
      LightingOutput = 54
      BinaryLightingOutput = 55
      NetworkPort = 56
      ElevatorGroup = 57
      Escalator = 58
      Lift = 59
    end
  end
end
