require "json"
require "../bacnet"

# Store for tracking discovered BACnet devices during discovery
# Uses official BACnet terminology
module BACnet
  module DiscoveryStore
    # Represents a discovered BACnet device
    # Supports both BACnet/SC (using VMAC) and BACnet/IP (using IP address)
    class Device
      include JSON::Serializable

      def initialize(
        @device_instance : UInt32,
        @vmac : String? = nil,
        @ip_address : String? = nil,
        @max_apdu_length : UInt64? = nil,
        @segmentation_supported : String? = nil,
        @vendor_id : UInt64? = nil,
        @network : UInt16? = nil,
        @address : String? = nil,
        @parent_device_instance : UInt32? = nil,
      )
        @objects = [] of ObjectReference
        @sub_devices = [] of Device
      end

      property device_instance : UInt32
      property vmac : String?
      property ip_address : String?
      property max_apdu_length : UInt64?
      property segmentation_supported : String?
      property vendor_id : UInt64?
      property network : UInt16?
      property address : String?
      property parent_device_instance : UInt32?

      # Standard BACnet device properties
      property object_name : String = ""
      property vendor_name : String = ""
      property model_name : String = ""
      property description : String = ""

      # Objects exposed by this device
      property objects : Array(ObjectReference) = [] of ObjectReference

      # Sub-devices (for gateway devices)
      property sub_devices : Array(Device) = [] of Device

      # BACnet/SC specific methods (VMAC)
      def vmac_hex : String?
        @vmac
      end

      def vmac_bytes : Bytes?
        @vmac.try(&.hexbytes)
      end

      # Check if this device is a sub-device
      def sub_device? : Bool
        !@parent_device_instance.nil?
      end

      # Check if this device is a parent (has sub-devices)
      def parent? : Bool
        !@sub_devices.empty?
      end

      # Returns the network identifier for this device
      # For BACnet/SC this is the VMAC, for BACnet/IP this is the IP address
      def network_id : String
        @vmac || @ip_address || ""
      end
    end

    # Reference to a BACnet object within a device
    class ObjectReference
      include JSON::Serializable

      def initialize(
        @object_type : String,
        @instance_number : UInt32,
        @object_name : String = "",
      )
      end

      property object_type : String
      property instance_number : UInt32
      property object_name : String

      def is_device? : Bool
        @object_type == "Device"
      end
    end

    # Store for managing discovered devices during discovery
    class Store
      include JSON::Serializable

      @[JSON::Field(ignore: true)]
      @mutex : Mutex = Mutex.new(:reentrant)

      def initialize
        @devices = {} of UInt32 => Device
      end

      property devices : Hash(UInt32, Device)

      # Add or update a device
      def add_device(device : Device)
        @mutex.synchronize do
          @devices[device.device_instance] = device
        end
      end

      # Get a device by instance number
      def get_device(device_instance : UInt32) : Device?
        @mutex.synchronize do
          @devices[device_instance]?
        end
      end

      # Check if device exists
      def has_device?(device_instance : UInt32) : Bool
        @mutex.synchronize do
          @devices.has_key?(device_instance)
        end
      end

      # Get all devices (including sub-devices as top-level)
      def all_devices : Array(Device)
        @mutex.synchronize do
          @devices.values
        end
      end

      # Get only top-level devices (not sub-devices)
      def top_level_devices : Array(Device)
        @mutex.synchronize do
          @devices.values.reject(&.sub_device?)
        end
      end

      # Mark a device as a sub-device of a parent
      def mark_as_sub_device(device_instance : UInt32, parent_instance : UInt32)
        @mutex.synchronize do
          if device = @devices[device_instance]?
            device.parent_device_instance = parent_instance
          end
        end
      end

      # Get all sub-devices of a parent
      def sub_devices_of(parent_instance : UInt32) : Array(Device)
        @mutex.synchronize do
          @devices.values.select { |d| d.parent_device_instance == parent_instance }
        end
      end

      # Clear all devices
      def clear
        @mutex.synchronize do
          @devices.clear
        end
      end

      # Count of all devices (including sub-devices)
      def size : Int32
        @mutex.synchronize do
          @devices.size
        end
      end

      # Count of top-level devices only
      def top_level_count : Int32
        @mutex.synchronize do
          @devices.values.count { |d| !d.sub_device? }
        end
      end

      # Serialize to JSON
      def to_json(json : JSON::Builder)
        @mutex.synchronize do
          json.object do
            json.field "devices", @devices
          end
        end
      end

      # Deserialize from JSON
      def self.from_json(json : String | IO) : Store
        store = Store.allocate
        store.initialize
        pull = JSON::PullParser.new(json)
        pull.read_object do |key|
          case key
          when "devices"
            pull.read_object do |_device_id|
              device = Device.from_json(pull.read_raw)
              store.add_device(device)
            end
          end
        end
        store
      end

      # Save to file
      def save(path : String)
        File.write(path, to_json)
      end

      # Load from file
      def self.load(path : String) : Store
        from_json(File.read(path))
      end
    end
  end
end
