import std/bitops
import picostdlib/[
  hardware/i2c, hardware/rtc
]
import ../common/[pimoroni_common, pimoroni_i2c]
export pimoroni_i2c

const
  # Constants
  DefaultI2cAddress* = 0x51.I2cAddress
  ParamUnused* = -1

type
  RtcPcf85063a* = object
    i2c: I2c               # Interface pins with our standard defaults where appropriate
    address: I2cAddress
    interrupt: GpioOptional

  ClockOut* {.pure.} = enum
    co32768Hz = 0
    co16384Hz = 1
    co8192Hz  = 2
    co4096Hz  = 3
    co2048Hz  = 4
    co1024Hz  = 5
    co1Hz     = 6
    coOff     = 7

  DayOfWeek* {.pure.} = enum
    NONE      = ParamUnused
    SUNDAY    = 0
    MONDAY    = 1
    TUESDAY   = 2
    WEDNESDAY = 3
    THURSDAY  = 4
    FRIDAY    = 5
    SATURDAY  = 6

  TimerTickPeriod* {.pure.} = enum
    tt4096Hz       = 0b00,
    tt64Hz         = 0b01
    tt1Hz          = 0b10
    tt1Over60Hz    = 0b11

  Registers {.pure, size: sizeof(uint8).} = enum
    CONTROL_1         = 0x00
    CONTROL_2         = 0x01

    OFFSET            = 0x02

    RAM_BYTE          = 0x03

    SECONDS           = 0x04  # contains oscillator status flag
    MINUTES           = 0x05
    HOURS             = 0x06
    DAYS              = 0x07
    WEEKDAYS          = 0x08
    MONTHS            = 0x09
    YEARS             = 0x0A

    SECOND_ALARM      = 0x0B
    MINUTE_ALARM      = 0x0C
    HOUR_ALARM        = 0x0D
    DAY_ALARM         = 0x0E
    WEEKDAY_ALARM     = 0x0F

    TIMER_VALUE       = 0x10
    TIMER_MODE        = 0x11


# binary coded decimal conversion helper functions
proc bcdEncode*(v: uint): uint8 =
  let
    v10: uint = v div 10
    v1: uint = v - (v10 * 10)
  return (v1 or (v10 shl 4)).uint8

proc bcdDecode*(v: uint): int8 =
  let
    v10: uint = (v shr 4) and 0x0f
    v1: uint = v and 0x0f
  return (v1 + (v10 * 10)).int8

proc init*(self: var RtcPcf85063a; i2c: I2c; interrupt: GpioOptional = GpioUnused) =
  self.address = DefaultI2cAddress
  self.i2c = i2c
  self.interrupt = interrupt
  if self.interrupt != GpioUnused:
    Gpio(self.interrupt).setFunction(GpioFunction.Sio)
    Gpio(self.interrupt).setDir(In)
    Gpio(self.interrupt).setPulls(up=false, down=true)

  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_1.uint8, 0x00) # ensure rtc is running (this should be default?)

proc reset*(self: var RtcPcf85063a) =
  # magic soft reset command
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_1.uint8, 0x58)
  # read the oscillator status bit until it is cleared
  var status = self.i2c.regReadUint8(self.address, SECONDS.uint8)
  while status.testBit(7):
    # attempt to clear oscillator stop flag, then read it back
    discard self.i2c.regWriteUint8(self.address, SECONDS.uint8, 0x00)
    status = self.i2c.regReadUint8(self.address, SECONDS.uint8)

# i2c helper methods
proc getI2c*(self: var RtcPcf85063a): ptr I2cInst {.noSideEffect.} =
  return self.i2c.getI2c()

proc getAddress*(self: var RtcPcf85063a): I2cAddress {.noSideEffect.} =
  return self.address

proc getSda*(self: var RtcPcf85063a): Gpio {.noSideEffect.} =
  return self.i2c.getSda()

proc getScl*(self: var RtcPcf85063a): Gpio {.noSideEffect.} =
  return self.i2c.getScl()

proc getInt*(self: var RtcPcf85063a): Gpio {.noSideEffect.} =
  return Gpio(self.interrupt)

proc getDatetime*(self: var RtcPcf85063a): Datetime =
  var data: array[7, uint8]
  discard self.i2c.readBytes(self.address, Registers.SECONDS.uint8, data[0].addr, data.len.cuint)
  return Datetime(
    year:  bcdDecode(data[6]).int16 + 2000,
    month: bcdDecode(data[5]),
    day:   bcdDecode(data[3]),
    dotw:  bcdDecode(data[4]),
    hour:  bcdDecode(data[2]),
    min:   bcdDecode(data[1]),
    sec:   bcdDecode(data[0] and 0x7f)  # mask out oscillator status bit
  )

proc setDatetime*(self: var RtcPcf85063a; t: Datetime) =
  var data: array[7, uint8] = [
    bcdEncode(t.sec.uint),
    bcdEncode(t.min.uint),
    bcdEncode(t.hour.uint),
    bcdEncode(t.day.uint),
    bcdEncode(t.dotw.uint),
    bcdEncode(t.month.uint),
    bcdEncode(t.year.uint - 2000)  # offset year
  ]
  discard self.i2c.writeBytes(self.address, Registers.SECONDS.uint8, data[0].addr, data.len.cuint)

proc setAlarm*(self: var RtcPcf85063a; second: int; minute: int; hour: int; day: int) =
  var alarm: array[5, uint8] = [
    if second >= 0: bcdEncode(second.uint) else: 0x80,
    if minute >= 0: bcdEncode(minute.uint) else: 0x80,
    if hour >= 0: bcdEncode(hour.uint) else: 0x80,
    if day >= 0: bcdEncode(day.uint) else: 0x80,
    0x80
  ]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, alarm[0].addr, alarm.len.cuint)

proc setWeekdayAlarm*(self: var RtcPcf85063a; second: int; minute: int; hour: int; dotw: DayOfWeek) =
  var alarm: array[5, uint8] = [
    if second >= 0: bcdEncode(second.uint) else: 0x80,
    if minute >= 0: bcdEncode(minute.uint) else: 0x80,
    if hour >= 0: bcdEncode(hour.uint) else: 0x80,
    0x80,
    if dotw != None: bcdEncode(dotw.uint) else: 0x80
  ]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, alarm[0].addr, alarm.len.cuint)

proc enableAlarmInterrupt*(self: var RtcPcf85063a; enable: bool) =
  var bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  if enable:
    bits.setBit(7)
  else:
    bits.clearBit(7)
  bits.setBit(6) # ensure alarm flag isn't reset
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc readAlarmFlag*(self: var RtcPcf85063a): bool =
  let bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  return bits.testBit(6)

proc clearAlarmFlag*(self: var RtcPcf85063a) =
  var bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits.clearBit(6)
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc unsetAlarm*(self: var RtcPcf85063a) =
  var dummy: array[5, uint8]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, dummy[0].addr, dummy.len.cuint)

proc setTimer*(self: var RtcPcf85063a; ticks: uint8; ttp: TimerTickPeriod) =
  if ticks == 0: return
  var bits = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  # mask out current ttp and set new + enable
  bits.clearMask(0b11000)
  bits.setMask(ttp.uint8 shl 3)
  bits.setBit(2)
  var timer: array[2, uint8] = [ticks, bits]
  discard self.i2c.writeBytes(self.address, Registers.TIMER_VALUE.uint8, timer[0].addr, timer.len.cuint)

proc enableTimerInterrupt*(self: var RtcPcf85063a; enable: bool; flagOnly: bool = false) =
  var bits = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  bits.clearMask(0b11)
  if enable:
    bits.setBit(1)
  if flagOnly:
    bits.setBit(0)
  discard self.i2c.regWriteUint8(self.address, Registers.TIMER_MODE.uint8, bits)

proc readTimerFlag*(self: var RtcPcf85063a): bool =
  let bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  return bits.testBit(3)

proc clearTimerFlag*(self: var RtcPcf85063a) =
  var bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits.clearBit(3)
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc unsetTimer*(self: var RtcPcf85063a) =
  var bits = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  bits.clearBit(2)
  discard self.i2c.regWriteUint8(self.address, Registers.TIMER_MODE.uint8, bits)

proc setClockOutput*(self: var RtcPcf85063a; co: ClockOut) =
  # set the speed of (or turn off) the clock output
  var bits = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits.clearMask(0b111)
  bits.setMask(co.uint8)
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc setRamByte*(self: var RtcPcf85063a; v: uint8) =
  discard self.i2c.regWriteUint8(self.address, Registers.RAM_BYTE.uint8, v)

proc getRamByte*(self: var RtcPcf85063a): uint8 =
  return self.i2c.regReadUint8(self.address, Registers.RAM_BYTE.uint8)


proc syncFromPicoRtc*(self: var RtcPcf85063a): bool =
  var dt = createDatetime()
  if not rtcGetDatetime(dt.addr):
    return false
  self.setDatetime(dt)
  return true

proc syncToPicoRtc*(self: var RtcPcf85063a): bool =
  var dt = self.getDatetime()
  return rtcSetDatetime(dt.addr)
