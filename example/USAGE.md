# BACnet/SC Example Scripts Usage Guide

This guide explains how to use the three example scripts for discovering and querying BACnet/SC devices over secure WebSocket connections.

## Prerequisites

### Required Files
You need the following certificate files for BACnet/SC authentication:
- `private.key` - Your client private key
- `client.pem` - Your client certificate

### Environment Variables (Optional)
The scripts use these environment variables with fallback defaults:

```bash
# BACnet/SC hub connection details
export BACNET_HOST="138.80.128.217"
export BACNET_PATH="/hub"

# Authentication
export BACNET_UUID="04fba096-6ac2-4f2d-b96c-396d1698566f"
export BACNET_PRIVATE_KEY="./private.key"
export BACNET_CLIENT_CERT="./client.pem"
```

you can generate a UUID like:

```crystal
require "uuid"

puts UUID.v4.to_s
```

If not set, the scripts will use the default values shown above.

## Script Overview

The three scripts form a progressive workflow:

1. **1_discovery.cr** - Discover all devices on the network
2. **2_device_details.cr** - Inspect a specific device and its objects
3. **3_object_information.cr** - Query properties of a specific object

---

## Script 1: Device Discovery

### Purpose
Performs a BACnet WhoIs broadcast and lists all discovered devices with their basic information.

### Usage

```bash
crystal run example/1_discovery.cr
```

### What It Does
1. Connects to the BACnet/SC hub via secure WebSocket
2. Sends a WhoIs broadcast message
3. Collects IAm responses for 5 seconds after the last response
4. Queries each device for name, vendor, model, and object count
5. Displays a hierarchical list of all devices

### Sample Output

```
================================================================================
BACnet Device Discovery
================================================================================

  Device [2001] - AHU_L2_01
    VMAC: 023f96a4807d
    Vendor: Distech Controls, Inc.
    Model: ECY-AHU Rev 1.0A
    Objects: 247

  Device [2803] - BMS_L8_03
    VMAC: 22062a1b6dcb
    Vendor: Distech Controls, Inc.
    Model: ECY-S1000 Rev 1.0A
    Objects: 109

    Sub-device [183101] - Chiller 3
      Objects: 123

    Sub-device [183102] - Chiller 4
      Objects: 98

Total devices discovered: 194
================================================================================
```

### Key Information to Extract

For the next script, you'll need:

1. **Device Instance** - The number in brackets `[2803]`
2. **VMAC** - The 6-byte hex identifier (e.g., `22062a1b6dcb`)

**Note:** Sub-devices share the same VMAC as their parent device.

### Understanding the Output

- **Top-level devices** - Directly accessible on the network
- **Sub-devices** (indented) - Devices behind a gateway, require routing
- **Object count** - Number of BACnet objects exposed by the device
- **(unnamed)** - Device didn't respond to name query (may require routing)

---

## Script 2: Device Details

### Purpose
Inspects a specific device and lists all its objects organized by type.

### Usage

```bash
crystal run example/2_device_details.cr -- --device-id <ID> --vmac <VMAC>
```

### Required Arguments

- `--device-id <ID>` - Device instance number from discovery output
- `--vmac <VMAC>` - Virtual MAC address (12 hex characters, no separators)

### Examples

#### Query a top-level device:
```bash
crystal run example/2_device_details.cr -- --device-id 2803 --vmac 22062a1b6dcb
```

#### Query a sub-device:
```bash
crystal run example/2_device_details.cr -- --device-id 183101 --vmac 22062a1b6dcb
```

**Note:** Sub-devices use their parent's VMAC but their own device ID.

### Sample Output

```
================================================================================
BACnet Device Details
================================================================================
Device Instance: 2803
VMAC: 22062a1b6dcb
Object Name: BMS_L8_03
Vendor Name: Distech Controls, Inc.
Model Name: ECY-S1000 Rev 1.0A

Sub-Devices (2):
  [183101] Chiller 3
  [183102] Chiller 4

Objects (109):
  AnalogInput (15):
    [201] CH_L8_03_CHW_FLOW
    [202] CH_L8_03_LVNG_CHW_TMP
    [203] CH_L8_03_ENT_CHW_TMP
    ...

  AnalogValue (42):
    [1] CH_L8_03_CHW_FLOW_SP
    [2] CHWP_L8_03_SPEED_SP
    ...

  BinaryValue (31):
    [1] CH_L8_03_SYS_LOCKOUT
    [2] CH_L8_03_SYS_AVAILABLE
    ...

  Device (2):
    [183101] Chiller 3
    [183102] Chiller 4
================================================================================
```

### Key Information to Extract

For the next script, you'll need:

1. **Device Instance** - From the header (e.g., `2803`)
2. **VMAC** - From the header (e.g., `22062a1b6dcb`)
3. **Object Type** - The category name (e.g., `AnalogInput`)
4. **Object Instance** - The number in brackets (e.g., `[201]`)

### Understanding the Output

- **Device metadata** - Name, vendor, model at the top
- **Sub-Devices** - Child devices that can be queried separately
- **Objects grouped by type** - All objects organized by BACnet object type
- **Object instance numbers** - Unique within the device for each object type
- **Object names** - Human-readable names assigned by the system integrator

### Common Object Types

- **AnalogInput** - Physical sensor readings (temperature, pressure, flow, etc.)
- **AnalogOutput** - Control outputs (valve positions, damper positions, etc.)
- **AnalogValue** - Virtual analog points (setpoints, calculated values)
- **BinaryInput** - Digital inputs (status, switches, alarms)
- **BinaryOutput** - Digital outputs (start/stop commands, enable/disable)
- **BinaryValue** - Virtual binary points (flags, modes)
- **MultiStateValue** - Multi-position values (modes, states)
- **Device** - Sub-devices (gateways, child controllers)

---

## Script 3: Object Information

### Purpose
Queries and displays detailed properties of a specific BACnet object.

### Usage

```bash
crystal run example/3_object_information.cr -- \
  --device-id <ID> \
  --vmac <VMAC> \
  --object-type <TYPE> \
  --object-instance <INSTANCE>
```

### Required Arguments

- `--device-id <ID>` - Device instance number
- `--vmac <VMAC>` - Virtual MAC address (12 hex characters)
- `--object-type <TYPE>` - BACnet object type name (case-insensitive)
- `--object-instance <NUM>` - Object instance number

### Examples

#### Query an analog input:
```bash
crystal run example/3_object_information.cr -- \
  --device-id 2803 \
  --vmac 22062a1b6dcb \
  --object-type AnalogInput \
  --object-instance 201
```

#### Query a binary value:
```bash
crystal run example/3_object_information.cr -- \
  --device-id 2803 \
  --vmac 22062a1b6dcb \
  --object-type BinaryValue \
  --object-instance 1
```

#### Query an object on a sub-device:
```bash
crystal run example/3_object_information.cr -- \
  --device-id 183101 \
  --vmac 22062a1b6dcb \
  --object-type AnalogValue \
  --object-instance 6
```

### Sample Output

```
================================================================================
BACnet Object Information
================================================================================
Device Instance: 2803
VMAC: 22062a1b6dcb
Object: AnalogInput:201

Object Name: CH_L8_03_CHW_FLOW
Description: Chiller 3 chilled water flow meter

Present Value: 245.5
Units: gallons-per-minute

Status Flags:
  In-Alarm: false
  Fault: false
  Overridden: false
  Out-Of-Service: false

Out-Of-Service: false
================================================================================
```

### Understanding the Output

#### Basic Properties
- **Object Name** - Human-readable identifier
- **Description** - Additional information about the object's purpose

#### Value Properties
- **Present Value** - Current value of the object
  - For analog objects: Numeric value (with units)
  - For binary objects: Active/Inactive or true/false
  - For multi-state objects: Current state number/name
- **Units** - Engineering units (only for analog objects)
  - Examples: degrees-fahrenheit, percent, pounds-per-square-inch

#### Status Information
- **Status Flags** - Four standard BACnet status bits:
  - `In-Alarm` - Object is in an alarm condition
  - `Fault` - Object has detected a fault
  - `Overridden` - Value is being manually overridden
  - `Out-Of-Service` - Object is out of service (disabled)
- **Out-Of-Service** - Detailed out-of-service status

### Property Query Behavior

The script attempts to read these standard properties (if not all are available, it continues):
- ObjectName (always attempted)
- Description (if available)
- PresentValue (if object type supports it)
- Units (for analog objects only)
- StatusFlags (standard property)
- OutOfService (standard property)

If a property doesn't exist or isn't readable, the script will skip it gracefully.

---

## Common Workflows

### Workflow 1: Find and Query a Specific Sensor

```bash
# Step 1: Discover all devices
crystal run example/1_discovery.cr > devices.txt

# Review output, find device [2803] with VMAC 22062a1b6dcb

# Step 2: List all objects on that device
crystal run example/2_device_details.cr -- \
  --device-id 2803 \
  --vmac 22062a1b6dcb > device_2803.txt

# Review output, find AnalogInput [201] named CH_L8_03_CHW_FLOW

# Step 3: Query the specific sensor
crystal run example/3_object_information.cr -- \
  --device-id 2803 \
  --vmac 22062a1b6dcb \
  --object-type AnalogInput \
  --object-instance 201
```

### Workflow 2: Explore a Sub-Device

```bash
# Step 1: Discover devices and identify sub-devices
crystal run example/1_discovery.cr

# Output shows:
#   Device [2803] - BMS_L8_03
#     VMAC: 22062a1b6dcb
#     Sub-device [183101] - Chiller 3

# Step 2: Query the sub-device using parent's VMAC
crystal run example/2_device_details.cr -- \
  --device-id 183101 \
  --vmac 22062a1b6dcb

# Step 3: Query an object on the sub-device
crystal run example/3_object_information.cr -- \
  --device-id 183101 \
  --vmac 22062a1b6dcb \
  --object-type AnalogValue \
  --object-instance 6
```

### Workflow 3: Monitor Multiple Points

Create a shell script to monitor several points:

```bash
#!/bin/bash
# monitor_chiller.sh

DEVICE_ID=183101
VMAC=22062a1b6dcb

echo "=== Chiller 3 Status at $(date) ==="

echo -n "Leaving Temp: "
crystal run example/3_object_information.cr -- \
  --device-id $DEVICE_ID --vmac $VMAC \
  --object-type AnalogValue --object-instance 6 \
  | grep "Present Value:" | awk '{print $3, $4}'

echo -n "Entering Temp: "
crystal run example/3_object_information.cr -- \
  --device-id $DEVICE_ID --vmac $VMAC \
  --object-type AnalogValue --object-instance 7 \
  | grep "Present Value:" | awk '{print $3, $4}'

echo -n "Running Status: "
crystal run example/3_object_information.cr -- \
  --device-id $DEVICE_ID --vmac $VMAC \
  --object-type BinaryValue --object-instance 1 \
  | grep "Present Value:" | awk '{print $3}'
```

---

## Troubleshooting

### Connection Issues

**Problem:** `Failed to connect` or `Connection refused`

**Solutions:**
1. Verify `BACNET_HOST` and `BACNET_PATH` are correct
2. Check certificate files exist and are readable
3. Ensure you have network connectivity to the hub
4. Verify the hub is accepting connections

### Authentication Issues

**Problem:** Connection closes immediately or `TLS handshake failed`

**Solutions:**
1. Verify certificate files are correct and not expired
2. Check `BACNET_UUID` matches your registered client UUID
3. Ensure private key matches the client certificate

### Device Not Found

**Problem:** Device appears in discovery but details query fails

**Solutions:**
1. For sub-devices, use the parent device's VMAC, not the sub-device ID
2. Verify you copied the device ID correctly (numbers only)
3. Verify you copied the VMAC correctly (12 hex characters)
4. Some devices may be offline or unreachable

### Object Not Found

**Problem:** Object appears in device listing but query fails with "UnknownObject"

**Solutions:**
1. Verify object type name is spelled correctly (case-insensitive but must match)
2. Ensure object instance number is correct
3. Some objects may be write-only or have restricted read access
4. The object may have been removed after the device listing was generated

### Timeout Issues

**Problem:** Script hangs or times out

**Solutions:**
1. Increase timeout value in the script (default is 30 seconds for details, 10 seconds for object info)
2. Device may be slow to respond - wait and retry
3. Check network connectivity and latency
4. Device may be overloaded or unresponsive

---

## Tips and Best Practices

### Performance
- Discovery can take 10-20 seconds depending on network size
- Device details queries take longer for devices with many objects
- Consider caching discovery results if querying frequently

### VMAC Formatting
- Always use 12 hex characters with no separators
- ✅ Correct: `22062a1b6dcb`
- ❌ Wrong: `22:06:2a:1b:6d:cb`
- ❌ Wrong: `22-06-2a-1b-6d-cb`

### Object Type Names
- Must match BACnet standard names
- Case-insensitive (`analoginput`, `AnalogInput`, `ANALOGINPUT` all work)
- Common types: `AnalogInput`, `AnalogOutput`, `AnalogValue`, `BinaryInput`, `BinaryOutput`, `BinaryValue`, `Device`, `MultiStateValue`

### Sub-Device Addressing
- Sub-devices always use their **parent's VMAC**
- Use the **sub-device's own device ID**
- Example: Sub-device [183101] under parent [2803] with VMAC 22062a1b6dcb:
  - Use `--device-id 183101 --vmac 22062a1b6dcb`
  - NOT `--device-id 2803`

### Output Redirection
Save output for later analysis:
```bash
crystal run example/1_discovery.cr > discovery_$(date +%Y%m%d).txt
crystal run example/2_device_details.cr -- --device-id 2803 --vmac 22062a1b6dcb > device_2803.txt
```

---

## Advanced Usage

### Custom Environment Configuration

Create a `.env` file for your specific installation:

```bash
# .env file
export BACNET_HOST="your-hub-address.com"
export BACNET_PATH="/bacnet/hub"
export BACNET_UUID="your-unique-uuid"
export BACNET_PRIVATE_KEY="./certs/my-private.key"
export BACNET_CLIENT_CERT="./certs/my-client.pem"
```

Load it before running scripts:
```bash
source .env
crystal run example/1_discovery.cr
```

### Building Standalone Binaries

For better performance, compile the scripts:

```bash
# Compile all three examples
crystal build example/1_discovery.cr -o bin/bacnet-discover
crystal build example/2_device_details.cr -o bin/bacnet-device
crystal build example/3_object_information.cr -o bin/bacnet-object

# Run compiled binaries (much faster!)
./bin/bacnet-discover
./bin/bacnet-device --device-id 2803 --vmac 22062a1b6dcb
./bin/bacnet-object --device-id 2803 --vmac 22062a1b6dcb --object-type AnalogInput --object-instance 201
```

### Integration with Other Tools

#### Export to JSON (requires `jq` tool)

```bash
# Simple CSV export of device list
crystal run example/1_discovery.cr | \
  grep "Device \[" | \
  awk -F'[][]' '{print $2 "," $4}' > devices.csv

# Export object names
crystal run example/2_device_details.cr -- --device-id 2803 --vmac 22062a1b6dcb | \
  grep "^\s*\[" | \
  sed 's/^\s*\[\([0-9]*\)\] \(.*\)/\1,\2/' > objects_2803.csv
```

---

## Reference: Object Types

Complete list of supported BACnet object types:

| Object Type | Description | Has Present Value | Has Units |
|-------------|-------------|-------------------|-----------|
| AnalogInput | Physical analog sensor | Yes | Yes |
| AnalogOutput | Physical analog control output | Yes | Yes |
| AnalogValue | Virtual analog point | Yes | Yes |
| BinaryInput | Physical digital input | Yes | No |
| BinaryOutput | Physical digital output | Yes | No |
| BinaryValue | Virtual binary point | Yes | No |
| MultiStateInput | Physical multi-position input | Yes | No |
| MultiStateOutput | Physical multi-position output | Yes | No |
| MultiStateValue | Virtual multi-position point | Yes | No |
| Device | BACnet device or sub-device | No | No |
| File | File storage object | No | No |
| Program | Programmable controller | No | No |
| Schedule | Time-based schedule | No | No |
| Calendar | Calendar definition | No | No |
| NotificationClass | Alarm notification settings | No | No |
| Loop | PID control loop | Yes | No |
| NetworkPort | Network interface | No | No |

---

## Support and Contributing

If you encounter issues or have questions:

1. Check the troubleshooting section above
2. Verify your connection and credentials
3. Review the BACnet/SC specification for protocol details
4. Report issues at: https://github.com/spider-gazelle/crystal-bacnet/issues

### Example Improvements

These example scripts can be extended to:
- Support ReadPropertyMultiple for batch queries
- Add write property functionality
- Implement subscription/COV (Change of Value) notifications
- Export data to time-series databases
- Generate device documentation automatically
- Create network topology visualizations

Pull requests welcome!
