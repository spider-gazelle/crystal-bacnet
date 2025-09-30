require "bindata"

module BACnet
  Log = ::Log.for(self)

  class_property logger : ::Log = Log

  class Error < RuntimeError; end

  class UnknownPropertyError < Error; end

  alias PropertyType = PropertyIdentifier::PropertyType

  # http://kargs.net/BACnet/BACnet_IP_Details.pdf (page 14)
  enum RequestTypeIP6
    BVCLResult                    =    0
    OriginalUnicastNPDU           =    1
    OriginalBroadcastNPDU         =    2
    AddressResolution             =    3
    ForwardedAddressResolution    =    4
    AddressResolutionAck          =    5
    VirtualAddressResolution      =    6
    VirtualAddressResolutionAck   =    7
    ForwardedNPDU                 =    8
    RegisterForeignDevice         =    9
    DeleteForeignDeviceTableEntry = 0x0a
    SecureBVLL                    = 0x0b
    DistributeBroadcastToNetwork  = 0x0c
  end

  enum Priority
    Normal     = 0
    Urgent
    Critical
    LifeSafety
  end

  # APDU Message Type
  enum MessageType
    ConfirmedRequest   = 0
    UnconfirmedRequest
    SimpleACK
    ComplexACK
    SegmentACK
    Error
    Reject
    Abort
  end

  # ConfirmedRequest messages (NPDU description page 7)
  enum ConfirmedService : UInt8
    # Alarm and Event Services
    AcknowledgeAlarm     = 0
    CovNotification      = 1 # change of value
    EventNotification    = 2
    GetAlarmSummary      = 3
    GetEnrollmentSummary = 4
    SubscribeCov         = 5

    # File Access Services
    AtomicReadFile  = 6
    AtomicWriteFile = 7

    # Object Access Services
    AddListElement          =  8
    RemoveListElement       =  9
    CreateObject            = 10
    DeleteObject            = 11
    ReadProperty            = 12
    ReadPropertyConditional = 13
    ReadPropertyMuliple     = 14
    WriteProperty           = 15
    WritePropertyMultiple   = 16

    # Remote Device Management
    DeviceCommunicationControl = 17
    PrivateTransfer            = 18
    TextMessage                = 19
    ReinitializeDevice         = 20

    # Virtual Terminal
    VtOpen  = 21
    VtClose = 22
    VtData  = 23

    # Security Services
    Authenticate = 24
    RequestKey   = 25

    # Object Access Service
    ReadRange = 26

    # Alarm and Event Services
    LifeSafteyOperation  = 27
    SubscribeCovProperty = 28
    GetEvenInformation   = 29

    SubscribeCovPropertyMultiple     = 30
    ConfirmedCovNotificationMultiple = 31
  end

  # UnconfirmedRequest messages (NPDU description page 8)
  enum UnconfirmedService : UInt8
    IAm                     =  0
    IHave                   =  1
    CovNotification         =  2 # change of value
    EventNotification       =  3
    PrivateTransfer         =  4
    TextMessage             =  5
    TimeSync                =  6
    WhoHas                  =  7
    WhoIs                   =  8
    TimeSyncUTC             =  9
    WriteGroup              = 10
    CovNotificationMultiple = 11
  end

  enum SegmentationSupport
    Both         = 0
    Transmit
    Receive
    NotSupported
  end

  # https://reference.opcfoundation.org/BACnet/v200/docs/11
  enum Unit
    MetersPerSecondPerSecond        = 166
    SquareMeters                    =   0
    SquareCentimeters               = 116
    SquareFeet                      =   1
    SquareInches                    = 115
    Currency1                       = 105
    Currency2                       = 106
    Currency3                       = 107
    Currency4                       = 108
    Currency5                       = 109
    Currency6                       = 110
    Currency7                       = 111
    Currency8                       = 112
    Currency9                       = 113
    Currency10                      = 114
    Milliamperes                    =   2
    Amperes                         =   3
    AmperesPerMeter                 = 167
    AmperesPerSquareMeter           = 168
    AmpereSquareMeters              = 169
    Decibels                        = 199
    DecibelsMillivolt               = 200
    DecibelsVolt                    = 201
    Farads                          = 170
    Henrys                          = 171
    Ohms                            =   4
    OhmMeters                       = 172
    OhmMeterPerSquareMeter          = 237
    Milliohms                       = 145
    Kilohms                         = 122
    Megohms                         = 123
    MicroSiemens                    = 190
    Millisiemens                    = 202
    Siemens                         = 173
    SiemensPerMeter                 = 174
    Teslas                          = 175
    Volts                           =   5
    Millivolts                      = 124
    Kilovolts                       =   6
    Megavolts                       =   7
    VoltAmperes                     =   8
    KilovoltAmperes                 =   9
    MegavoltAmperes                 =  10
    AmpereSeconds                   = 238
    AmpereSquareHours               = 246
    VoltAmpereHours                 = 239
    KilovoltAmpereHours             = 240
    MegavoltAmpereHours             = 241
    VoltAmperesReactive             =  11
    KilovoltAmperesReactive         =  12
    MegavoltAmperesReactive         =  13
    VoltAmpereHoursReactive         = 242
    KilovoltAmpereHoursReactive     = 243
    MegavoltAmpereHoursReactive     = 244
    VoltsPerDegreeKelvin            = 176
    VoltsPerMeter                   = 177
    VoltsSquareHours                = 245
    DegreesPhase                    =  14
    PowerFactor                     =  15
    Webers                          = 178
    Joules                          =  16
    Kilojoules                      =  17
    KilojoulesPerKilogram           = 125
    Megajoules                      = 126
    JoulesPerHours                  = 247
    WattHours                       =  18
    KilowattHours                   =  19
    MegawattHours                   = 146
    WattHoursReactive               = 203
    KilowattHoursReactive           = 204
    MegawattHoursReactive           = 205
    Btus                            =  20
    KiloBtus                        = 147
    MegaBtus                        = 148
    Therms                          =  21
    TonHours                        =  22
    JoulesPerKilogramDryAir         =  23
    KilojoulesPerKilogramDryAir     = 149
    MegajoulesPerKilogramDryAir     = 150
    BtusPerPoundDryAir              =  24
    BtusPerPound                    = 117
    JoulesPerDegreeKelvin           = 127
    KilojoulesPerDegreeKelvin       = 151
    MegajoulesPerDegreeKelvin       = 152
    JoulesPerKilogramDegreeKelvin   = 128
    Newton                          = 153
    CyclesPerHour                   =  25
    CyclesPerMinute                 =  26
    Hertz                           =  27
    Kilohertz                       = 129
    Megahertz                       = 130
    PerHour                         = 131
    GramsOfWaterPerKilogramDryAir   =  28
    PercentRelativeHumidity         =  29
    Micrometers                     = 194
    Millimeters                     =  30
    Centimeters                     = 118
    Kilometers                      = 193
    Meters                          =  31
    Inches                          =  32
    Feet                            =  33
    Candelas                        = 179
    CandelasPerSquareMeter          = 180
    WattsPerSquareFoot              =  34
    WattsPerSquareMeter             =  35
    Lumens                          =  36
    Luxes                           =  37
    FootCandles                     =  38
    Milligrams                      = 196
    Grams                           = 195
    Kilograms                       =  39
    PoundsMass                      =  40
    Tons                            =  41
    GramsPerSecond                  = 154
    GramsPerMinute                  = 155
    KilogramsPerSecond              =  42
    KilogramsPerMinute              =  43
    KilogramsPerHour                =  44
    PoundsMassPerSecond             = 119
    PoundsMassPerMinute             =  45
    PoundsMassPerHour               =  46
    TonsPerHour                     = 156
    Milliwatts                      = 132
    Watts                           =  47
    Kilowatts                       =  48
    Megawatts                       =  49
    BtusPerHour                     =  50
    KiloBtusPerHour                 = 157
    Horsepower                      =  51
    TonsRefrigeration               =  52
    Pascals                         =  53
    Hectopascals                    = 133
    Kilopascals                     =  54
    PascalSeconds                   = 253
    Millibars                       = 134
    Bars                            =  55
    PoundsForcePerSquareInch        =  56
    MillimetersOfWater              = 206
    CentimetersOfWater              =  57
    InchesOfWater                   =  58
    MillimetersOfMercury            =  59
    CentimetersOfMercury            =  60
    InchesOfMercury                 =  61
    DegreesCelsius                  =  62
    DegreesKelvin                   =  63
    DegreesKelvinPerHour            = 181
    DegreesKelvinPerMinute          = 182
    DegreesFahrenheit               =  64
    DegreeDaysCelsius               =  65
    DegreeDaysFahrenheit            =  66
    DeltaDegreesFahrenheit          = 120
    DeltaDegreesKelvin              = 121
    Years                           =  67
    Months                          =  68
    Weeks                           =  69
    Days                            =  70
    Hours                           =  71
    Minutes                         =  72
    Seconds                         =  73
    HundredthsSeconds               = 158
    Milliseconds                    = 159
    NewtonMeters                    = 160
    MillimetersPerSecond            = 161
    MillimetersPerMinute            = 162
    MetersPerSecond                 =  74
    MetersPerMinute                 = 163
    MetersPerHour                   = 164
    KilometersPerHour               =  75
    FeetPerSecond                   =  76
    FeetPerMinute                   =  77
    MilesPerHour                    =  78
    CubicFeet                       =  79
    CubicFeetPerDay                 = 248
    CubicMeters                     =  80
    CubicMetersPerDay               = 249
    ImperialGallons                 =  81
    Milliliters                     = 197
    Liters                          =  82
    UsGallons                       =  83
    CubicFeetPerSecond              = 142
    CubicFeetPerMinute              =  84
    CubicFeetPerHour                = 191
    CubicMetersPerSecond            =  85
    CubicMetersPerMinute            = 165
    CubicMetersPerHour              = 135
    ImperialGallonsPerMinute        =  86
    MillilitersPerSecond            = 198
    LitersPerSecond                 =  87
    LitersPerMinute                 =  88
    LitersPerHour                   = 136
    UsGallonsPerMinute              =  89
    UsGallonsPerHour                = 192
    DegreesAngular                  =  90
    DegreesCelsiusPerHour           =  91
    DegreesCelsiusPerMinute         =  92
    DegreesFahrenheitPerHour        =  93
    DegreesFahrenheitPerMinute      =  94
    JouleSeconds                    = 183
    KilogramsPerCubicMeter          = 186
    KilowattHoursPerSquareMeter     = 137
    KilowattHoursPerSquareFoot      = 138
    MegajoulesPerSquareMeter        = 139
    MegajoulesPerSquareFoot         = 140
    NoUnits                         =  95
    NewtonSeconds                   = 187
    NewtonsPerMeter                 = 188
    PartsPerMillion                 =  96
    PartsPerBillion                 =  97
    Percent                         =  98
    PercentObscurationPerFoot       = 143
    PercentObscurationPerMeter      = 144
    PercentPerSecond                =  99
    PerMinute                       = 100
    PerSecond                       = 101
    PsiPerDegreeFahrenheit          = 102
    Radians                         = 103
    RadiansPerSecond                = 184
    RevolutionsPerMinute            = 104
    SquareMetersPerNewton           = 185
    WattsPerMeterPerDegreeKelvin    = 189
    WattsPerSquareMeterDegreeKelvin = 141
    PerMille                        = 207
    GramsPerGram                    = 208
    KilogramsPerKilogram            = 209
    GramsPerKilogram                = 210
    MilligramsPerGram               = 211
    MilligramsPerKilogram           = 212
    GramsPerMilliliter              = 213
    GramsPerLiter                   = 214
    MilligramsPerLiter              = 215
    MicrogramsPerLiter              = 216
    GramsPerCubicMeter              = 217
    MilligramsPerCubicMeter         = 218
    MicrogramsPerCubicMeter         = 219
    NanogramsPerCubicMeter          = 220
    GramsPerCubicCentimeter         = 221
    WattHoursPerCubicMeter          = 250
    JoulesPerCubicMeter             = 251
    Becquerels                      = 222
    Kilobecquerels                  = 223
    Megabecquerels                  = 224
    Gray                            = 225
    Milligray                       = 226
    Microgray                       = 227
    Sieverts                        = 228
    Millisieverts                   = 229
    Microsieverts                   = 230
    MicrosievertsPerHour            = 231
    DecibelsA                       = 232
    NephelometricTurbidityUnit      = 233
    PH                              = 234
    GramsPerSquareMeter             = 235
    MinutesPerDegreeKelvin          = 236
  end

  # ASN.1 message tags (NPDU description page 5)
  # enum ApplicationTags
  # end
end

require "./bacnet/*"
require "./bacnet/objects/*"
require "./bacnet/services/*"
require "./bacnet/virtual_link_control/*"
require "./bacnet/client/*"
require "./bacnet/client/**"
