module BACnet
  # NOTE:: for request structures see page 646 of the ANSI/ASHRAE Standard 135-2012

  class ConfirmedRequest < BinData
    endian :big

    bit_field do
      enum_bits 4, message_type : MessageType = MessageType::ConfirmedRequest

      # APDU flags
      bool segmented_request
      bool more_segments_follow
      bool segmented_response_accepted
      bool ignore1

      # Max Length
      bool :ignore2
      bits 3, :max_response_segments_indicator # 0=Int(MAX),1=2,2=4,3=8,4=16,5=32,6=64,7=Int(MAX)
      bits 4, :max_size_indicator              # 0=50, 1=128, 2=206, 3=480, 4=1024, 5=1476
    end

    # 0 == unspecified, 7 == greater than 64
    SEGMENTS_SUPPORTED = {128, 2, 4, 8, 16, 32, 64, 128}

    def max_segments
      SEGMENTS_SUPPORTED[max_response_segments_indicator]
    end

    MAX_SIZE = {50, 128, 206, 480, 1024, 1476, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

    def max_size
      MAX_SIZE[max_size_indicator]
    end

    uint8 :invoke_id

    group :segment, onlyif: ->{ segmented_request } do
      uint8 :sequence_number
      uint8 :window_size
    end

    enum_field UInt8, service : ConfirmedService = ConfirmedService::AcknowledgeAlarm
  end
end
