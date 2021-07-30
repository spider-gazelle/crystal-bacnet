require "../bacnet"
require "./objects/*"

class BACnet::Object < BinData
  endian :big

  bit_field do
    bits 4, :short_tag
    bool :context_specific
    # if context specific then the length will be set to 6
    bits 3, :uint3_length
  end

  uint8 :ext_tag, onlyif: ->{ short_tag == 0x0F_u8 }

  uint8 :uint8_length, onlyif: ->{ uint3_length == 5_u8 }
  uint16 :uint16_length, onlyif: ->{ uint3_length == 5_u8 && uint8_length == 254_u8 }
  uint32 :uint32_length, onlyif: ->{ uint3_length == 5_u8 && uint8_length == 255_u8 }

  bytes :data, length: ->{ length }

  def tag
    if short_tag == 0x0F_u8
      ext_tag
    else
      short_tag
    end
  end

  def tag=(value : Int)
    value = value.to_u8
    if value >= 0x0F_u8
      self.short_tag = 0x0F_u8
      self.ext_tag = value
    else
      self.short_tag = value
    end
  end

  def length
    # uint3_length of 6 or 7 with context specific means open or close tags
    return 0 if uint3_length > 5_u8
    # uint3_length == 5 means use extended length
    return uint3_length if uint3_length < 5_u8
    # uint8_length > 254 means use extended extended length
    return uint8_length if uint8_length < 254_u8
    return uint16_length if uint8_length == 254_u8
    uint32_length
  end

  def length=(size : Int)
    if size < 5
      self.uint3_length = size.to_u8
    elsif size < 254
      self.uint3_length = 5_u8
      self.uint8_length = size.to_u8
    elsif size < 65536
      self.uint3_length = 5_u8
      self.uint8_length = 254_u8
      self.uint16_length = size.to_u16
    else
      self.uint3_length = 5_u8
      self.uint8_length = 255_u8
      self.uint32_length = size.to_u32
    end
  end

  def opening?
    context_specific && uint3_length == 6
  end

  def closing?
    context_specific && uint3_length == 7
  end

  STRING_ENCODING = {
    0_u8 => "UTF-8",
    1_u8 => "UTF-16BE",
    # https://en.wikipedia.org/wiki/JIS_X_0213
    2_u8 => "EUC-JISX0213",
    3_u8 => "UCS-4BE",
    4_u8 => "UCS-2BE",
    5_u8 => "ISO8859-1",
  }

  # ameba:disable Metrics/CyclomaticComplexity
  def value
    raise Error.new("context specific flag set, not primitive data") if context_specific

    case tag
    when 0
      nil
    when 1
      to_bool
    when 2, 9
      # UnsignedInt, Enum response
      to_u64
    when 3
      # SignedInt
      to_i64
    when 4
      # single-precision floating-point
      to_f32
    when 5
      # Double-precision floating-point
      to_f64
    when 6
      # OctetString
      to_string
    when 7
      # CharString
      to_encoded_string
    when 8
      # bit string (array of bools)
      to_bit_string
    when 10
      # date
      to_date
    when 11
      # Time
      to_time
    when 12
      to_object_id
    else
      raise Error.new("unknown object: #{tag}")
    end
  end

  def inspect(io : IO) : Nil
    super(io)

    if !context_specific && tag < 13
      io << "\b #value="
      value.inspect(io)
      io << ">"
    end
  end

  def is_null?
    !context_specific && tag == 0_u8
  end

  def to_u64
    val = 0_u64
    len = data.bytesize - 1
    data.each_with_index do |byte, index|
      val |= ((byte & 0xff).to_u64 << ((len - index) * 8))
    end
    val
  end

  def to_i64
    negative = (self.data[0] & 0b10000000) > 0
    val = 0_i64
    len = data.size - 1

    if negative
      data.each_with_index do |byte, index|
        # Invert each byte
        val |= ((~byte & 0xff).to_i64 << ((len - index) * 8))
      end

      # Complete the 2's compliment conversion
      -(val + 1)
    else
      data.each_with_index do |byte, index|
        val |= ((byte & 0xff).to_i64 << ((len - index) * 8))
      end
      val
    end
  end

  {% begin %}
    {% for name in %w(to_u32 to_u16 to_u8) %}
      def {{name.id}}; to_u64.{{name.id}}; end
    {% end %}

    {% for name in %w(to_i to_i32 to_i16 to_i8) %}
      def {{name.id}}; to_i64.{{name.id}}; end
    {% end %}
  {% end %}

  def to_bool
    # Boolean
    self.uint3_length == 1_u8
  end

  def to_f32
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(Float32, IO::ByteFormat::BigEndian)
  end

  def to_f64
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(Float64, IO::ByteFormat::BigEndian)
  end

  def to_string
    String.new(data)
  end

  def to_encoded_string
    encoding = STRING_ENCODING[data[0]]?
    if encoding
      String.new(data[1..-1], encoding)
    else # hope for the best?
      String.new(data[1..-1])
    end
  end

  def to_bit_string
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(BACnet::BitString, IO::ByteFormat::BigEndian)
  end

  def to_date
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(BACnet::Date, IO::ByteFormat::BigEndian)
  end

  def to_time
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(BACnet::Time, IO::ByteFormat::BigEndian)
  end

  def to_object_id
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(BACnet::ObjectIdentifier, IO::ByteFormat::BigEndian)
  end

  def to_property_id
    io = IO::Memory.new(data, writeable: false)
    io.read_bytes(BACnet::PropertyIdentifier, IO::ByteFormat::BigEndian)
  end

  def set_value(value, context_specific : Bool = false, tag : Int? = nil)
    self.value = value
    self.context_specific = context_specific
    if tag
      self.tag = tag
    end
    self
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def value=(var)
    self.context_specific = false

    case var
    when Nil
      self.short_tag = 0_u8
      self.uint3_length = 0_u8
    when Bool
      self.short_tag = 1_u8
      self.uint3_length = var ? 1_u8 : 0_u8
    when Int, Enum
      raw = var.is_a?(Enum) ? var.to_i64 : var
      if raw >= 0
        io = IO::Memory.new(8)
        io.write_bytes(var.to_u64, IO::ByteFormat::BigEndian)
        bytes = io.to_slice
        index = 0
        bytes.each_with_index do |byte, i|
          index = i
          break if byte > 0_u8
        end
      else # negative
        io = IO::Memory.new(8)
        io.write_bytes(raw, IO::ByteFormat::BigEndian)
        bytes = io.to_slice
        index = 0
        bytes.each_with_index do |byte, i|
          if byte < 0xFF_u8
            index == i if (byte & 0b1000_0000_u8) > 0
            break
          end
          index = i
        end
      end

      self.data = bytes[index..-1]

      case var
      when Enum
        self.short_tag = 9_u8
      when Int8, Int16, Int32, Int64, Int128
        self.short_tag = 3_u8
      else
        self.short_tag = 2_u8
      end
      self.length = self.data.size
    when Float32
      io = IO::Memory.new(4)
      io.write_bytes(var, IO::ByteFormat::BigEndian)
      self.data = io.to_slice
      self.length = self.data.size
      self.short_tag = 4_u8
    when Float64
      io = IO::Memory.new(8)
      io.write_bytes(var, IO::ByteFormat::BigEndian)
      self.data = io.to_slice
      self.length = self.data.size
      self.short_tag = 5_u8
    when String
      self.data = var.to_slice
      self.length = self.data.size
      self.short_tag = 6_u8
    else
      # NOTE:: this requires manual tagging of the data type
      if var.responds_to?(:to_slice)
        self.data = var.to_slice
      else
        io = IO::Memory.write_bytes(var, IO::ByteFormat::BigEndian)
        self.data = io.to_slice
      end
      self.length = self.data.size
    end

    var
  end

  def objects : Array(Object | Objects)
    raise Error.new("objects called on object, context_specific: #{context_specific}, tag: #{tag}")
  end
end
