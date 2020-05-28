require "../object"

module BACnet
  class ObjectIdentifier < BinData
    endian :big

    bit_field do
      bits 10, :object_type
      bits 22, :instance_number
    end

    OBJECT_TYPES = {
      analog_input:           0,
      analog_output:          1,
      analog_value:           2,
      binary_input:           3,
      binary_output:          4,
      binary_value:           5,
      calendar:               6,
      command:                7,
      device:                 8,
      event_enrollment:       9,
      file:                   10,
      group:                  11,
      loop:                   12,
      multi_state_input:      13,
      multi_state_output:     14,
      notification_class:     15,
      program:                16,
      schedule:               17,
      averaging:              18,
      multi_state_value:      19,
      trend_log:              20,
      life_safety_point:      21,
      life_safety_zone:       22,
      accumulator:            23,
      pulse_converter:        24,
      event_log:              25,
      global_group:           26,
      trend_log_multiple:     27,
      load_control:           28,
      structured_view:        29,
      access_door:            30,
      timer:                  31,
      access_credential:      32,
      access_point:           33,
      access_rights:          34,
      access_user:            35,
      access_zone:            36,
      credential_data_input:  37,
      network_security:       38,
      bitstring_value:        39,
      characterstring_value:  40,
      date_pattern_value:     41,
      date_value:             42,
      datetime_pattern_value: 43,
      datetime_value:         44,
      integer_value:          45,
      large_analog_value:     46,
      octetstring_value:      47,
      positive_integer_value: 48,
      time_pattern_value:     49,
      time_value:             50,
      notification_forwarder: 51,
      alert_enrollment:       52,
      channel:                53,
      lighting_output:        54,
      binary_lighting_output: 55,
      network_port:           56,
      elevator_group:         57,
      escalator:              58,
      lift:                   59,
    }
  end
end
