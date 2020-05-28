require "../bacnet"

module BACnet
  # Used to tokenise the IP data stream and differentiate between packet types
  class DataLinkIndicator < BinData
    endian :big

    # There are a few different types of BVLCI
    # http://www.bacnet.org/Tutorial/BACnetIP/sld005.html
    # http://www.bacnet.org/Tutorial/BACnetIP/sld010.html
    # http://www.bacnet.org/Tutorial/BACnetIP/sld014.html

    # General datagram structure:
    # * BVLCI
    # * NPCI \
    #         - NPDU
    # * APDU /

    uint8 :protocol # 0x81 == BACnet/IP, 0x82 == BACnet/IP6
    uint8 :request_type
    uint16 :request_length

    def is_ipv4?
      protocol == 0x81_u8
    end

    def is_ipv6?
      protocol == 0x82_u8
    end
  end
end
