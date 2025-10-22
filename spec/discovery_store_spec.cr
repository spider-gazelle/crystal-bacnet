require "./helper"
require "json"
require "file_utils"

module BACnet
  describe DiscoveryStore do
    describe DiscoveryStore::Device do
      it "should create a device with required fields" do
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        device.device_instance.should eq(2803_u32)
        device.vmac.should eq("22062a1b6dcb")
        device.vmac_hex.should eq("22062a1b6dcb")
        device.objects.should be_empty
        device.sub_devices.should be_empty
      end

      it "should create a device with all optional fields" do
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb",
          max_apdu_length: 1476_u64,
          segmentation_supported: "Both",
          vendor_id: 364_u64,
          network: 28031_u16,
          address: "01"
        )

        device.max_apdu_length.should eq(1476_u64)
        device.segmentation_supported.should eq("Both")
        device.vendor_id.should eq(364_u64)
        device.network.should eq(28031_u16)
        device.address.should eq("01")
      end

      it "should convert vmac hex to bytes" do
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        bytes = device.vmac_bytes
        bytes.should_not be_nil
        bytes.should eq("22062a1b6dcb".hexbytes)
        bytes.not_nil!.size.should eq(6)
      end

      it "should support BACnet/IP with IP address" do
        device = DiscoveryStore::Device.new(
          device_instance: 1001_u32,
          ip_address: "192.168.1.100"
        )

        device.device_instance.should eq(1001_u32)
        device.ip_address.should eq("192.168.1.100")
        device.vmac.should be_nil
        device.network_id.should eq("192.168.1.100")
      end

      it "should support BACnet/SC with VMAC" do
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        device.device_instance.should eq(2803_u32)
        device.vmac.should eq("22062a1b6dcb")
        device.ip_address.should be_nil
        device.network_id.should eq("22062a1b6dcb")
      end

      it "should track sub-device status" do
        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        sub_device = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb",
          parent_device_instance: 2803_u32
        )

        parent.sub_device?.should be_false
        sub_device.sub_device?.should be_true
      end

      it "should track parent status" do
        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        sub_device = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb"
        )

        parent.parent?.should be_false
        parent.sub_devices << sub_device
        parent.parent?.should be_true
      end

      it "should serialize to and from JSON" do
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb",
          max_apdu_length: 1476_u64,
          segmentation_supported: "Both",
          vendor_id: 364_u64
        )
        device.object_name = "BMS_L8_03"
        device.vendor_name = "Distech Controls, Inc."
        device.model_name = "ECY-S1000 Rev 1.0A"

        json = device.to_json
        parsed = DiscoveryStore::Device.from_json(json)

        parsed.device_instance.should eq(2803_u32)
        parsed.vmac.should eq("22062a1b6dcb")
        parsed.object_name.should eq("BMS_L8_03")
        parsed.vendor_name.should eq("Distech Controls, Inc.")
        parsed.model_name.should eq("ECY-S1000 Rev 1.0A")
        parsed.max_apdu_length.should eq(1476_u64)
        parsed.segmentation_supported.should eq("Both")
        parsed.vendor_id.should eq(364_u64)
      end
    end

    describe DiscoveryStore::ObjectReference do
      it "should create an object reference" do
        obj_ref = DiscoveryStore::ObjectReference.new(
          object_type: "AnalogInput",
          instance_number: 201_u32,
          object_name: "CH_L8_03_CHW_FLOW"
        )

        obj_ref.object_type.should eq("AnalogInput")
        obj_ref.instance_number.should eq(201_u32)
        obj_ref.object_name.should eq("CH_L8_03_CHW_FLOW")
      end

      it "should identify device objects" do
        device_ref = DiscoveryStore::ObjectReference.new(
          object_type: "Device",
          instance_number: 183101_u32
        )

        analog_ref = DiscoveryStore::ObjectReference.new(
          object_type: "AnalogInput",
          instance_number: 201_u32
        )

        device_ref.is_device?.should be_true
        analog_ref.is_device?.should be_false
      end

      it "should serialize to and from JSON" do
        obj_ref = DiscoveryStore::ObjectReference.new(
          object_type: "AnalogInput",
          instance_number: 201_u32,
          object_name: "CH_L8_03_CHW_FLOW"
        )

        json = obj_ref.to_json
        parsed = DiscoveryStore::ObjectReference.from_json(json)

        parsed.object_type.should eq("AnalogInput")
        parsed.instance_number.should eq(201_u32)
        parsed.object_name.should eq("CH_L8_03_CHW_FLOW")
      end
    end

    describe DiscoveryStore::Store do
      it "should create an empty store" do
        store = DiscoveryStore::Store.new
        store.size.should eq(0)
        store.top_level_count.should eq(0)
        store.all_devices.should be_empty
        store.top_level_devices.should be_empty
      end

      it "should add and retrieve devices" do
        store = DiscoveryStore::Store.new
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        store.add_device(device)
        store.size.should eq(1)
        store.has_device?(2803_u32).should be_true
        store.has_device?(9999_u32).should be_false

        retrieved = store.get_device(2803_u32)
        retrieved.should_not be_nil
        retrieved.try(&.device_instance).should eq(2803_u32)
      end

      it "should track top-level vs sub-devices" do
        store = DiscoveryStore::Store.new

        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        sub1 = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb"
        )

        sub2 = DiscoveryStore::Device.new(
          device_instance: 183102_u32,
          vmac: "22062a1b6dcb"
        )

        store.add_device(parent)
        store.add_device(sub1)
        store.add_device(sub2)

        store.size.should eq(3)
        store.top_level_count.should eq(3)

        # Mark sub-devices
        store.mark_as_sub_device(183101_u32, 2803_u32)
        store.mark_as_sub_device(183102_u32, 2803_u32)

        store.size.should eq(3)
        store.top_level_count.should eq(1)

        top_level = store.top_level_devices
        top_level.size.should eq(1)
        top_level[0].device_instance.should eq(2803_u32)

        all = store.all_devices
        all.size.should eq(3)
      end

      it "should get sub-devices of a parent" do
        store = DiscoveryStore::Store.new

        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        sub1 = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb",
          parent_device_instance: 2803_u32
        )

        sub2 = DiscoveryStore::Device.new(
          device_instance: 183102_u32,
          vmac: "22062a1b6dcb",
          parent_device_instance: 2803_u32
        )

        store.add_device(parent)
        store.add_device(sub1)
        store.add_device(sub2)

        subs = store.sub_devices_of(2803_u32)
        subs.size.should eq(2)
        subs.map(&.device_instance).should contain(183101_u32)
        subs.map(&.device_instance).should contain(183102_u32)
      end

      it "should clear all devices" do
        store = DiscoveryStore::Store.new
        device = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        store.add_device(device)
        store.size.should eq(1)

        store.clear
        store.size.should eq(0)
        store.all_devices.should be_empty
      end

      it "should serialize to and from JSON" do
        store = DiscoveryStore::Store.new

        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )
        parent.object_name = "BMS_L8_03"

        sub_device = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb",
          parent_device_instance: 2803_u32
        )
        sub_device.object_name = "Chiller 3"

        store.add_device(parent)
        store.add_device(sub_device)

        json = store.to_json
        parsed = DiscoveryStore::Store.from_json(json)

        parsed.size.should eq(2)
        parsed.has_device?(2803_u32).should be_true
        parsed.has_device?(183101_u32).should be_true

        parent_parsed = parsed.get_device(2803_u32)
        parent_parsed.should_not be_nil
        parent_parsed.try(&.object_name).should eq("BMS_L8_03")

        sub_parsed = parsed.get_device(183101_u32)
        sub_parsed.should_not be_nil
        sub_parsed.try(&.object_name).should eq("Chiller 3")
        sub_parsed.try(&.parent_device_instance).should eq(2803_u32)
      end

      it "should save and load from file" do
        temp_file = File.tempname("discovery_store", ".json")

        begin
          store = DiscoveryStore::Store.new

          device = DiscoveryStore::Device.new(
            device_instance: 2803_u32,
            vmac: "22062a1b6dcb"
          )
          device.object_name = "BMS_L8_03"

          store.add_device(device)
          store.save(temp_file)

          File.exists?(temp_file).should be_true

          loaded = DiscoveryStore::Store.load(temp_file)
          loaded.size.should eq(1)
          loaded.has_device?(2803_u32).should be_true

          device_loaded = loaded.get_device(2803_u32)
          device_loaded.should_not be_nil
          device_loaded.try(&.object_name).should eq("BMS_L8_03")
        ensure
          File.delete(temp_file) if File.exists?(temp_file)
        end
      end

      it "should handle nested sub-devices in JSON" do
        store = DiscoveryStore::Store.new

        parent = DiscoveryStore::Device.new(
          device_instance: 2803_u32,
          vmac: "22062a1b6dcb"
        )

        sub_device = DiscoveryStore::Device.new(
          device_instance: 183101_u32,
          vmac: "22062a1b6dcb"
        )
        sub_device.object_name = "Chiller 3"

        parent.sub_devices << sub_device
        store.add_device(parent)

        json = store.to_json
        parsed = DiscoveryStore::Store.from_json(json)

        parent_parsed = parsed.get_device(2803_u32)
        parent_parsed.should_not be_nil
        parent_parsed.try(&.sub_devices.size).should eq(1)
        parent_parsed.try(&.sub_devices[0].object_name).should eq("Chiller 3")
      end
    end
  end
end
