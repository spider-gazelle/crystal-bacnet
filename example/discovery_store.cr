require "../src/bacnet"

# Simple store for tracking discovered BACnet devices during discovery
# Uses official BACnet terminology
module DiscoveryStore
  # Represents a discovered BACnet device
  class Device
    def initialize(
      @device_instance : UInt32,
      @vmac : Bytes,
      @max_apdu_length : UInt64? = nil,
      @segmentation_supported : BACnet::SegmentationSupport? = nil,
      @vendor_id : UInt64? = nil,
    )
      @objects = [] of ObjectReference
      @sub_devices = [] of Device
    end

    property device_instance : UInt32
    property vmac : Bytes
    property max_apdu_length : UInt64?
    property segmentation_supported : BACnet::SegmentationSupport?
    property vendor_id : UInt64?

    # Standard BACnet device properties
    property object_name : String = ""
    property vendor_name : String = ""
    property model_name : String = ""
    property description : String = ""

    # Objects exposed by this device
    property objects : Array(ObjectReference)

    # Sub-devices (for gateway devices)
    property sub_devices : Array(Device)

    def vmac_hex : String
      @vmac.hexstring
    end
  end

  # Reference to a BACnet object within a device
  class ObjectReference
    def initialize(@object_identifier : BACnet::ObjectIdentifier, @object_name : String = "")
    end

    property object_identifier : BACnet::ObjectIdentifier
    property object_name : String

    def object_type
      @object_identifier.object_type
    end

    def instance_number
      @object_identifier.instance_number
    end

    def is_device?
      obj_type = object_type
      obj_type && obj_type.device?
    end
  end

  # Store for managing discovered devices during discovery
  class Store
    def initialize
      @devices = {} of UInt32 => Device
      @mutex = Mutex.new(:reentrant)
    end

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

    # Get all devices
    def all_devices : Array(Device)
      @mutex.synchronize do
        @devices.values
      end
    end

    # Clear all devices
    def clear
      @mutex.synchronize do
        @devices.clear
      end
    end

    # Count of devices
    def size : Int32
      @mutex.synchronize do
        @devices.size
      end
    end
  end
end
