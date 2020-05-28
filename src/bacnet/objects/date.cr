require "../object"

module BACnet
  class Date < BinData
    endian :big

    uint8 :year_raw
    uint8 :month_raw
    uint8 :day_raw
    uint8 :day_of_week # Monday == 1, Sunday == 7

    UNSPECIFIED       = 255_u8
    LAST_DAY_OF_MONTH =  32_u8

    property timezone : ::Time::Location = ::Time::Location::UTC

    def time_now
      ::Time.local(@timezone)
    end

    def year
      year_raw == UNSPECIFIED ? time_now.year : (year_raw.to_i + 1900)
    end

    def month
      month_raw == UNSPECIFIED ? time_now.month : month_raw.to_i
    end

    def day
      if day_raw == UNSPECIFIED
        time_now.day
      elsif day_raw >= LAST_DAY_OF_MONTH
        now = time_now
        ::Time.days_in_month(now.year, now.month)
      else
        day_raw.to_i
      end
    end

    def value
      if day_raw == UNSPECIFIED && day_of_week != UNSPECIFIED
        ::Time.week_date(year, time_now.calendar_week[1], day_of_week.to_i, location: @timezone)
      else
        ::Time.local(year, month, day, location: @timezone)
      end
    end
  end
end
