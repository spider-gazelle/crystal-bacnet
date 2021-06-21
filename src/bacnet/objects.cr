require "../bacnet"
require "./objects/*"

# needs to quack like an Object
class BACnet::Objects
  def initialize(@context_specific, @short_tag, @objects)
  end

  getter context_specific : Bool
  getter short_tag : UInt8
  getter objects : Array(Object | Objects)

  def tag
    short_tag
  end

  def opening?
    false
  end

  def closing?
    false
  end

  def is_null?
    false
  end

  {% for name in %w(value to_u64 to_i64 to_bool to_f32 to_f64 to_string to_encoded_string to_bit_string to_date to_time to_object_id to_property_id) %}
    def {{name.id}}
      raise Error.new("#{ {{name}} } called on objects list, context_specific: #{context_specific}, tag: #{tag}")
    end
  {% end %}

  def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::BigEndian)
    # this will always be big endian, just need to match the interface
    # ameba:disable Lint/ShadowedArgument
    format = IO::ByteFormat::BigEndian

    # open nested set
    obj = Object.new
    obj.context_specific = context_specific
    obj.short_tag = short_tag
    obj.uint3_length = 6 # opening tag indicator
    io.write_bytes(obj, format)

    # write the objects
    objects.each { |object| io.write_bytes(object, format) }

    # write the close nested set
    obj.uint3_length = 7 # closing tag indicator
    io.write_bytes(obj, format)
  end

  def to_slice
    io = IO::Memory.new
    io.write_bytes self
    io.to_slice
  end

  # this groups all the nested objects for simplified processing
  def self.parse_object_list(objects : Array(Object)) : Array(Object | Objects)
    objs = [] of Object | Objects
    subset = [] of Object
    parsing_subset = false
    subset_id = 0_u8

    objects.each do |obj|
      if parsing_subset
        if obj.closing? && obj.short_tag == subset_id
          objs << Objects.new(obj.context_specific, subset_id, parse_object_list(subset))
          parsing_subset = false
        else
          subset << obj
        end
      elsif obj.opening?
        parsing_subset = true
        subset_id = obj.short_tag
      else
        objs << obj
      end
    end

    # Context specific objects should be sorted by index
    if (first = objs.first?) && first.context_specific
      objs.sort { |a, b| a.short_tag <=> b.short_tag }
    else
      objs
    end
  end
end
