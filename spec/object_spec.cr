require "./helper"

module BACnet
  describe NPDU do
    it "should support null values" do
      obj = Object.new
      obj.is_null?.should eq(true)
      obj.to_slice.should eq(Bytes[0x00])
    end

    it "should support boolean values" do
      obj = Object.new
      obj.value = false
      obj.value.should be_false
      obj.to_slice.should eq(Bytes[0x10])

      obj.value = true
      obj.value.should be_true
      obj.to_slice.should eq(Bytes[0x11])
    end

    it "should support unsigned integers" do
      obj = Object.new
      obj.value = 256_u16
      obj.short_tag.should eq(2_u8)
      obj.length.should eq(2)
      obj.value.should eq(256_u64)
      obj.to_slice.should eq(Bytes[0x22, 0x01, 0x00])
    end

    it "should support signed integers" do
      obj = Object.new
      obj.value = 256_i16
      obj.short_tag.should eq(3_u8)
      obj.length.should eq(2)
      obj.value.should eq(256_i64)
      obj.to_slice.should eq(Bytes[0x32, 0x01, 0x00])

      obj.value = -256_i16
      obj.short_tag.should eq(3_u8)
      obj.length.should eq(2)
      obj.value.should eq(-256_i64)
      obj.to_slice.should eq(Bytes[0x32, 0xFF, 0x00])
    end

    it "should support floating points" do
      obj = Object.new
      obj.value = 12.3_f32
      obj.short_tag.should eq(4_u8)
      obj.length.should eq(4)
      obj.value.should eq(12.3_f32)
      obj.to_slice.should eq(Bytes[0x44, 65, 68, 204, 205])
    end

    it "should support doubles" do
      obj = Object.new
      obj.value = 12.3_f64
      obj.short_tag.should eq(5_u8)
      obj.length.should eq(8)
      obj.value.should eq(12.3_f64)
      obj.to_slice.should eq(Bytes[0x55, 8, 64, 40, 153, 153, 153, 153, 153, 154])
    end

    it "should support strings" do
      obj = Object.new
      obj.value = "hello"
      obj.short_tag.should eq(6_u8)
      obj.length.should eq(5)
      obj.value.should eq("hello")
      obj.to_slice.should eq(Bytes[0x65, 5, 104, 101, 108, 108, 111])
    end

    it "should decode a time" do
      bytes = Bytes[0xA4, 0x5B, 0x01, 0x18, 0x05]
      io = IO::Memory.new(bytes)
      obj = io.read_bytes(Object)
      time_obj = obj.value.as(Date)
      time = time_obj.value
      time.year.should eq(1991)
      time.month.should eq(1)
      time.day.should eq(24)

      obj.value = time_obj
      obj.to_slice.should eq(bytes)
    end

    it "should decode an object identifier" do
      bytes = "c4023fffff".hexbytes
      io = IO::Memory.new(bytes)
      obj = io.read_bytes(Object)
      id = obj.value.as(ObjectIdentifier)
      id.object_type.should eq(8)
      id.instance_number.should eq(4194303)

      obj.value = id
      obj.to_slice.should eq(bytes)
    end
  end
end
