require "../object"

module BACnet
  class BitString < BinData
    endian :big

    field ignore : UInt8
    remaining_bytes :bitdata

    def to_s(io)
      final = size - 1
      io << "["
      size.times do |index|
        self[index].to_s(io)
        io << ", " unless index == final
      end
      io << "]"
    end

    def size
      bitdata.size * 8 - ignore
    end

    def [](index : Int) : Bool
      if index >= size
        raise IndexError.new("Index #{index} out of bounds")
      else
        length = bitdata.size
        byte_index = length // 8

        # bit look up is done from the least significant
        bit_index = 7 - (length % 8)
        bitdata[byte_index].bit(bit_index) > 0
      end
    end

    def []?(index : Int) : Bool
      if index >= size
        false
      else
        length = bitdata.size
        byte_index = length // 8

        # bit look up is done from the least significant
        bit_index = 7 - (length % 8)
        bitdata[byte_index].bit(bit_index) > 0
      end
    end

    def []=(index : Int, state : Bool)
      if index >= size
        raise IndexError.new("Index #{index} out of bounds")
      else
        length = bitdata.size
        byte_index = length // 8
        bit_index = 7 - (length % 8)
        byte = bitdata[byte_index]

        if state
          bitdata[byte_index] = byte | (1_u8 << bit_index)
        else
          bitdata[byte_index] = byte & ~(1_u8 << bit_index)
        end

        state
      end
    end
  end
end
