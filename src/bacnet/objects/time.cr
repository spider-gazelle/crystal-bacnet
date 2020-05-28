require "../object"

module BACnet
  class Time < BinData
    endian :big

    UNSPECIFIED = 255_u8

    uint8 :hour_raw
    uint8 :minute_raw
    uint8 :second_raw
    uint8 :hundredth_raw

    property timezone : ::Time::Location = ::Time::Location::UTC

    def hour(default : ::Time)
      hour_raw == UNSPECIFIED ? default.hour : hour_raw.to_i
    end

    def minute(default : ::Time)
      minute_raw == UNSPECIFIED ? default.minute : minute_raw.to_i
    end

    def second(default : ::Time)
      second_raw == UNSPECIFIED ? default.second : second_raw.to_i
    end

    def nanosecond(default : ::Time)
      if hundredth_raw == UNSPECIFIED
        default.nanosecond
      else
        hundredth_raw.to_i * 10000000
      end
    end

    def value(date = ::Time.local(@timezone))
      ::Time.local(date.year, date.month, date.day, hour(date), minute(date), second(date), nanosecond: nanosecond(date), location: @timezone)
    end
  end
end
