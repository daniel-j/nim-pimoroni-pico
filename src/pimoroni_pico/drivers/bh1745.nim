## BH1745 Luminance and Colour Sensor

import std/bitops, std/math
import ../common/pimoroni_i2c

const
  Bh1745ChipId*       = 0b00001011
  Bh1745Manufacturer* = 0b11100000

  Bh1745I2cAddrDefault*     = 0x38.I2cAddress
  Bh1745I2cAddrAlternative* = 0x39.I2cAddress

  bh1745MeasurementTimes* = [160, 320, 640, 1280, 2560, 5120]
  bh1745AdcGains* = [1, 2, 16]

type
  Rgbc* {.packed.} = object
    r*, g*, b*, c*: uint16

  Bh1745Reg* {.pure.} = enum
    Bh1745RegSystemControl = 0x40
    Bh1745RegModeControl1  = 0x41
    Bh1745RegModeControl2  = 0x42
    Bh1745RegModeControl3  = 0x44
    Bh1745RegColourData    = 0x50
    # Bh1745RegDintData      = 0x58
    Bh1745RegInterrupt     = 0x60
    Bh1745RegPersistence   = 0x61
    Bh1745RegThresholdHigh = 0x62
    Bh1745RegThresholdLow  = 0x64
    Bh1745RegManufacturer  = 0x92

  Bh1745MeasurementTime* {.pure.} = enum
    MeasTime_160  = 0b000
    MeasTime_320  = 0b001
    MeasTime_640  = 0b010
    MeasTime_1280 = 0b011
    MeasTime_2560 = 0b100
    MeasTime_5120 = 0b101

  Bh1745AdcGain* {.pure.} = enum
    AdcGain_1X  = 0b00
    AdcGain_2X  = 0b01
    AdcGain_16X = 0b10

  Bh1745Persistence* {.pure.} = enum
    PerIntToggle
    PerIntUpdate
    PerIntUpdateOn4
    PerIntUpdateOn8

  Bh1745* = object
    i2c: ptr I2c
    address: I2cAddress
    interrupt: GpioOptional
    channelCompensation: array[4, float]

proc createBh1745*(i2c: var I2c; address: I2cAddress = Bh1745I2cAddrDefault; interrupt: GpioOptional = GpioUnused): Bh1745 =
  result.i2c = i2c.addr
  result.address = address
  result.interrupt = interrupt
  result.channelCompensation = [2.2, 1.0, 1.8, 10.0]

proc powerDown*(self: var Bh1745) =
  self.i2c.setBits(self.address, Bh1745RegSystemControl.uint8, 7)

proc reset*(self: var Bh1745) =
  self.powerDown()

  while self.i2c.getBits(self.address, Bh1745RegSystemControl.uint8, 7) != 0:
    sleepMs(10)

proc getChipId*(self: var Bh1745): uint8 =
  let chipId = self.i2c.getBits(self.address, Bh1745RegSystemControl.uint8, 0, 0b00111111)
  return chipId

proc getManufacturer*(self: var Bh1745): uint8 =
  let manufacturer = self.i2c.regReadUint8(self.address, Bh1745RegManufacturer.uint8)
  return manufacturer

proc setMeasurementTimeMs*(self: var Bh1745; value: Bh1745MeasurementTime) =
  var val = value.uint8
  discard self.i2c.writeBytes(self.address, Bh1745RegModeControl1.uint8, val.addr, 1)

proc setAdcGain*(self: var Bh1745; gain: Bh1745AdcGain) =
  var regMC2: uint8
  discard self.i2c.readBytes(self.address, Bh1745RegModeControl2.uint8, regMC2.addr, 1)
  regMC2.clearMask(0b11)
  regMC2.mask(gain.uint8 and 0b11)
  discard self.i2c.writeBytes(self.address, Bh1745RegModeControl2.uint8, regMC2.addr, 1)

proc setThresholdHigh*(self: var Bh1745; value: uint16) =
  discard self.i2c.writeBytes(self.address, Bh1745RegThresholdHigh.uint8, cast[ptr uint8](value.unsafeAddr), 2)

proc setThresholdLow*(self: var Bh1745; value: uint16) =
  discard self.i2c.writeBytes(self.address, Bh1745RegThresholdLow.uint8, cast[ptr uint8](value.unsafeAddr), 2)

proc setLeds*(self: var Bh1745; state: bool) =
  if state:
    self.i2c.setBits(self.address, Bh1745RegInterrupt.uint8, 0)
  else:
    self.i2c.clearBits(self.address, Bh1745RegInterrupt.uint8, 0)

proc setPersistence*(self: var Bh1745; persistence: Bh1745Persistence) =
  var value = persistence.uint8
  discard self.i2c.writeBytes(self.address, Bh1745RegModeControl2.uint8, value.addr, 1)

proc init*(self: var Bh1745): bool =
  self.reset()

  if self.getChipId() != Bh1745ChipId or self.getManufacturer() != Bh1745Manufacturer:
    return false

  self.reset()

  self.i2c.clearBits(self.address, Bh1745RegSystemControl.uint8, 6) # Clear INT reset bit
  self.setMeasurementTimeMs(MeasTime_640)
  self.setAdcGain(AdcGain_1X)
  self.i2c.setBits(self.address, Bh1745RegModeControl2.uint8, 4) # Enable RGBC
  self.i2c.regWriteUint8(self.address, Bh1745RegModeControl3.uint8, 0x02) # Turn on sensor
  self.setThresholdHigh(0x0000) # Set threshold so int will always fire
  self.setThresholdLow(0xFFFF) # this lets us turn on the LEDs with the int pin
  self.i2c.clearBits(self.address, Bh1745RegInterrupt.uint8, 4) # Enable interrupt latch

  sleepMs(320)

  return true

proc getRgbcRaw*(self: var Bh1745): Rgbc =
  while self.i2c.getBits(self.address, Bh1745RegModeControl2.uint8, 7) == 0:
    sleepMs(1)

  discard self.i2c.readBytes(self.address, Bh1745RegColourData.uint8, cast[ptr uint8](result.r.addr), 8)
  result.r = uint16 result.r.float * self.channelCompensation[0]
  result.g = uint16 result.g.float * self.channelCompensation[1]
  result.b = uint16 result.b.float * self.channelCompensation[2]
  result.c = uint16 result.c.float * self.channelCompensation[3]


# Utilities

proc toScaled*(self: var Bh1745; colour: Rgbc): Rgbc =
  let c = colour.c

  if c > 0:
    result.r = uint16 (colour.r.uint32 * 255 div c).clamp(0, 255)
    result.g = uint16 (colour.g.uint32 * 255 div c).clamp(0, 255)
    result.b = uint16 (colour.b.uint32 * 255 div c).clamp(0, 255)
  else:
    result.r = 0
    result.g = 0
    result.b = 0

proc toClamped*(self: var Bh1745; colour: Rgbc): Rgbc =
  let vmax = max(colour.r, max(colour.g, colour.b))

  result.r = uint16 (colour.r.uint32 * 255 div vmax)
  result.g = uint16 (colour.g.uint32 * 255 div vmax)
  result.b = uint16 (colour.b.uint32 * 255 div vmax)

proc toLux*(colour: Rgbc; gain: Bh1745AdcGain = AdcGain_1X; time: Bh1745MeasurementTime = MeasTime_160): uint =
  let integrationTime = bh1745MeasurementTimes[time.ord]
  let gain = bh1745AdcGains[gain.ord]

  var tmp =
    if colour.g < 1:
      0.0
    elif colour.c.float / colour.g.float < 0.160:
      0.202 * colour.r.float + 0.766 * colour.g.float
    else:
      0.159 * colour.r.float + 0.646 * colour.g.float
  if tmp < 0: tmp = 0
  return round(tmp / gain.float / integration_time.float * 160).uint

proc toColourTemperature*(colour: Rgbc): uint =
  let all = colour.r.float + colour.g.float + colour.b.float
  if colour.g < 1 or all < 1:
    return 0
  let r_ratio = colour.r.float / all
  let b_ratio = colour.b.float / all
  var ct = 0.0
  if colour.c.float / colour.g.float < 0.160:
    let b_eff = min(b_ratio * 3.13, 1)
    ct = ((1 - b_eff) * 12746 * (E.pow(-2.911 * r_ratio))) + (b_eff * 1637 * (E.pow(4.865 * b_ratio)))
  else:
    let b_eff = min(b_ratio * 10.67, 1)
    ct = ((1 - b_eff) * 16234 * (E.pow(-2.781 * r_ratio))) + (b_eff * 1882 * (E.pow(4.448 * b_ratio)))
  if ct > 10000:
    ct = 10000
  return round(ct).uint
