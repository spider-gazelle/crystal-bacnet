require "./spec_helper"

# ObjectIdentifier Serialization Tests
#
# These tests ensure that ObjectIdentifier instances serialize correctly to BACnet
# wire format and can be deserialized back to the correct object type.
#
# CRITICAL BUG PREVENTION:
# These tests specifically guard against a bug where the bit_field default value
# factory `value: -> { ObjectType::Device.to_u16 }` was being used during
# serialization, causing ALL ObjectIdentifiers to serialize as Device type (8)
# regardless of their actual type in memory.
#
# This bug caused:
# - All non-device object queries to fail with "UnknownObject" errors
# - Sub-device objects to be unreachable
# - Device properties worked (they were already type 8)
# - ObjectList would report objects existed, but querying them would fail
#
# The fix was to remove the default value factory from the bit_field declaration
# and set the default value in the initialize method instead.
#
# BACnet ObjectIdentifier encoding format:
# - 32 bits total
# - Upper 10 bits: Object Type (0-1023)
# - Lower 22 bits: Instance Number (0-4194303)
#
module BACnet
  describe ObjectIdentifier do
    describe "serialization" do
      it "should correctly serialize Device object type" do
        # Device:2803
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::Device,
          instance_number: 2803
        )

        obj_id.object_value.should eq(8_u16)
        obj_id.instance_number.should eq(2803_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::Device)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (8 << 22) | 2803 = 0x02000AF3
        bytes.hexstring.should eq("02000af3")

        # Round-trip: deserialize and verify
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(8_u16)
        parsed.instance_number.should eq(2803_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::Device)
      end

      it "should correctly serialize File object type" do
        # File:1 - This was the bug case!
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::File,
          instance_number: 1
        )

        obj_id.object_value.should eq(10_u16)
        obj_id.instance_number.should eq(1_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::File)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (10 << 22) | 1 = 0x02800001
        bytes.hexstring.should eq("02800001")

        # Round-trip: deserialize and verify it's still File, not Device!
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(10_u16)
        parsed.instance_number.should eq(1_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::File)
      end

      it "should correctly serialize AnalogValue object type" do
        # AnalogValue:6
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::AnalogValue,
          instance_number: 6
        )

        obj_id.object_value.should eq(2_u16)
        obj_id.instance_number.should eq(6_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::AnalogValue)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (2 << 22) | 6 = 0x00800006
        bytes.hexstring.should eq("00800006")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(2_u16)
        parsed.instance_number.should eq(6_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::AnalogValue)
      end

      it "should correctly serialize BinaryValue object type" do
        # BinaryValue:5
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::BinaryValue,
          instance_number: 5
        )

        obj_id.object_value.should eq(5_u16)
        obj_id.instance_number.should eq(5_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::BinaryValue)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (5 << 22) | 5 = 0x01400005
        bytes.hexstring.should eq("01400005")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(5_u16)
        parsed.instance_number.should eq(5_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::BinaryValue)
      end

      it "should correctly serialize AnalogInput object type" do
        # AnalogInput:201
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::AnalogInput,
          instance_number: 201
        )

        obj_id.object_value.should eq(0_u16)
        obj_id.instance_number.should eq(201_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::AnalogInput)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (0 << 22) | 201 = 0x000000C9
        bytes.hexstring.should eq("000000c9")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(0_u16)
        parsed.instance_number.should eq(201_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::AnalogInput)
      end

      it "should correctly serialize NetworkPort object type" do
        # NetworkPort:2
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::NetworkPort,
          instance_number: 2
        )

        obj_id.object_value.should eq(56_u16)
        obj_id.instance_number.should eq(2_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::NetworkPort)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (56 << 22) | 2 = 0x0E000002
        bytes.hexstring.should eq("0e000002")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(56_u16)
        parsed.instance_number.should eq(2_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::NetworkPort)
      end

      it "should correctly serialize Program object type" do
        # Program:1
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::Program,
          instance_number: 1
        )

        obj_id.object_value.should eq(16_u16)
        obj_id.instance_number.should eq(1_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::Program)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (16 << 22) | 1 = 0x04000001
        bytes.hexstring.should eq("04000001")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(16_u16)
        parsed.instance_number.should eq(1_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::Program)
      end

      it "should handle maximum instance number" do
        # Maximum instance number is 22 bits: 4194303
        obj_id = ObjectIdentifier.new(
          object_type: ObjectIdentifier::ObjectType::AnalogOutput,
          instance_number: 4194303
        )

        obj_id.object_value.should eq(1_u16)
        obj_id.instance_number.should eq(4194303_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::AnalogOutput)

        # Serialize to bytes
        io = IO::Memory.new
        io.write_bytes obj_id
        bytes = io.to_slice

        # Expected: (1 << 22) | 4194303 = 0x007FFFFF
        bytes.hexstring.should eq("007fffff")

        # Round-trip test
        io2 = IO::Memory.new(bytes)
        parsed = io2.read_bytes(ObjectIdentifier)
        parsed.object_value.should eq(1_u16)
        parsed.instance_number.should eq(4194303_u32)
        parsed.object_type.should eq(ObjectIdentifier::ObjectType::AnalogOutput)
      end

      it "should ensure different object types serialize to different bytes" do
        # Create multiple objects with same instance number but different types
        device = ObjectIdentifier.new(ObjectIdentifier::ObjectType::Device, 100)
        file = ObjectIdentifier.new(ObjectIdentifier::ObjectType::File, 100)
        analog = ObjectIdentifier.new(ObjectIdentifier::ObjectType::AnalogValue, 100)

        device_bytes = IO::Memory.new.tap(&.write_bytes(device)).to_slice
        file_bytes = IO::Memory.new.tap(&.write_bytes(file)).to_slice
        analog_bytes = IO::Memory.new.tap(&.write_bytes(analog)).to_slice

        # All three should have different serialized bytes
        device_bytes.should_not eq(file_bytes)
        device_bytes.should_not eq(analog_bytes)
        file_bytes.should_not eq(analog_bytes)

        # Verify they all have instance 100
        device.instance_number.should eq(100_u32)
        file.instance_number.should eq(100_u32)
        analog.instance_number.should eq(100_u32)

        # But different object types
        device.object_type.should eq(ObjectIdentifier::ObjectType::Device)
        file.object_type.should eq(ObjectIdentifier::ObjectType::File)
        analog.object_type.should eq(ObjectIdentifier::ObjectType::AnalogValue)
      end

      it "should NOT serialize all objects as Device type (regression test for critical bug)" do
        # This test specifically guards against the bug where bit_field default value
        # factory caused all ObjectIdentifiers to serialize as Device type

        # Create a File object
        file = ObjectIdentifier.new(ObjectIdentifier::ObjectType::File, 1)
        file_bytes = IO::Memory.new.tap(&.write_bytes(file)).to_slice

        # Create a Device object with same instance
        device = ObjectIdentifier.new(ObjectIdentifier::ObjectType::Device, 1)
        device_bytes = IO::Memory.new.tap(&.write_bytes(device)).to_slice

        # File:1 should serialize as 0x02800001 (type=10, instance=1)
        # Device:1 should serialize as 0x02000001 (type=8, instance=1)
        # These MUST be different!
        file_bytes.hexstring.should eq("02800001")
        device_bytes.hexstring.should eq("02000001")
        file_bytes.should_not eq(device_bytes)

        # When deserialized, File object MUST remain File, not become Device
        parsed_file = IO::Memory.new(file_bytes).read_bytes(ObjectIdentifier)
        parsed_file.object_type.should eq(ObjectIdentifier::ObjectType::File)
        parsed_file.object_type.should_not eq(ObjectIdentifier::ObjectType::Device)
        parsed_file.object_value.should eq(10_u16)    # File type = 10
        parsed_file.object_value.should_not eq(8_u16) # Device type = 8
      end
    end

    describe "default initialization" do
      it "should initialize with Device type by default" do
        obj_id = ObjectIdentifier.new
        obj_id.object_value.should eq(8_u16)
        obj_id.instance_number.should eq(0_u32)
        obj_id.object_type.should eq(ObjectIdentifier::ObjectType::Device)
      end
    end
  end
end
