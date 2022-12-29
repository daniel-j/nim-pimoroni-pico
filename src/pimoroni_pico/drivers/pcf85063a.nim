import picostdlib/[
  hardware/i2c, hardware/rtc
]
import ../common/[pimoroni_common, pimoroni_i2c]

const
  ## Constants
  DefaultI2cAddress* = 0x51.I2cAddress
  ParamUnused* = -1

type
  Pcf85063a* = object
    i2c: I2c               ##  Interface pins with our standard defaults where appropriate
    address: I2cAddress
    interrupt: int8

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

  Registers {.pure.} = enum
    CONTROL_1         = 0x00
    CONTROL_2         = 0x01
    OFFSET            = 0x02
    RAM_BYTE          = 0x03
    # OSCILLATOR_STATUS = 0x04  ## flag embedded in seconds register (see below)
    SECONDS           = 0x04    ## contains oscillator status flag   (see above)
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

const OSCILLATOR_STATUS = Registers.SECONDS


##  binary coded decimal conversion helper functions
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

proc init*(self: var Pcf85063a; interrupt: int8 = PinUnused) =
  self.address = DefaultI2cAddress
  self.interrupt = interrupt
  if self.interrupt != PinUnused:
    gpioSetFunction(self.interrupt.Gpio, GpioFunction.Sio)
    gpioSetDir(self.interrupt.Gpio, In)
    gpioSetPulls(self.interrupt.Gpio, up=false, down=true)
  self.i2c.init()

proc reset*(self: var Pcf85063a) =
  ##  magic soft reset command
  self.i2c.regWriteUint8(self.address, Registers.CONTROL_1.uint8, 0x58'u8)
  ##  read the oscillator status bit until it is cleared
  var status: uint8 = 0x80
  while (status and 0x80) != 0:
    ##  attempt to clear oscillator stop flag, then read it back
    self.i2c.regWriteUint8(self.address, OSCILLATOR_STATUS.uint8, 0x00)
    status = self.i2c.regReadUint8(self.address, OSCILLATOR_STATUS.uint8)

##  i2c helper methods
proc getI2c*(self: var Pcf85063a): ptr I2cInst {.noSideEffect.} =
  return self.i2c.getI2c()

proc getAddress*(self: var Pcf85063a): I2cAddress {.noSideEffect.} =
  return self.address

proc getSda*(self: var Pcf85063a): Gpio {.noSideEffect.} =
  return self.i2c.getSda()

proc getScl*(self: var Pcf85063a): Gpio {.noSideEffect.} =
  return self.i2c.getScl()

proc getInt*(self: var Pcf85063a): Gpio {.noSideEffect.} =
  return self.interrupt.Gpio

proc getDatetime*(self: var Pcf85063a): DateTime =
  var resultArray: array[7, uint8]
  discard self.i2c.readBytes(self.address, Registers.SECONDS.uint8, resultArray[0].addr, 7)
  result.year = (int16)(bcdDecode(resultArray[6]) + 2000)
  result.month = cast[int8](bcdDecode(resultArray[5]))
  result.day = cast[int8](bcdDecode(resultArray[3]))
  result.dotw = cast[int8](bcdDecode(resultArray[4]))
  result.hour = cast[int8](bcdDecode(resultArray[2]))
  result.min = cast[int8](bcdDecode(resultArray[1]))
  result.sec = cast[int8](bcdDecode(resultArray[0] and 0x7f))     ##  mask out status bit

proc setDatetime*(self: var Pcf85063a; t: ptr DateTime) =
  var data: array[7, uint8] = [bcdEncode(t.sec.uint),
                               bcdEncode(t.min.uint),
                               bcdEncode(t.hour.uint),
                               bcdEncode(t.day.uint),
                               bcdEncode(t.dotw.uint),
                               bcdEncode(t.month.uint),
                               bcdEncode(t.year.uint - 2000)] ##  offset year
  discard self.i2c.writeBytes(self.address, Registers.SECONDS.uint8, data[0].addr, data.len.cuint)

proc setAlarm*(self: var Pcf85063a; second: int; minute: int; hour: int; day: int) =
  var alarm: array[5, uint8] = [
    if second != ParamUnused: bcdEncode(second.uint) else: 0x80,
    if minute != ParamUnused: bcdEncode(minute.uint) else: 0x80,
    if hour != ParamUnused: bcdEncode(hour.uint) else: 0x80,
    if day != ParamUnused: bcdEncode(day.uint) else: 0x80,
    0x80]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, alarm[0].addr, alarm.len.cuint)

proc setWeekdayAlarm*(self: var Pcf85063a; second: int; minute: int; hour: int; dotw: DayOfWeek) =
  var alarm: array[5, uint8] = [
    if second != ParamUnused: bcdEncode(second.uint) else: 0x80,
    if minute != ParamUnused: bcdEncode(minute.uint) else: 0x80,
    if hour != ParamUnused: bcdEncode(hour.uint) else: 0x80,
    0x80,
    if dotw != None: bcdEncode(dotw.uint) else: 0x80]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, alarm[0].addr, alarm.len.cuint)

proc enableAlarmInterrupt*(self: var Pcf85063a; enable: bool) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits = if enable: (bits or 0x80) else: (bits and not 0x80'u8)
  bits = bits or 0x40
  ##  ensure alarm flag isn't reset
  self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc readAlarmFlag*(self: var Pcf85063a): bool =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  return (bits and 0x40'u8).bool

proc clearAlarmFlag*(self: var Pcf85063a) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits = bits and not 0x40'u8
  self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc unsetAlarm*(self: var Pcf85063a) =
  var dummy: array[5, uint8]
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, dummy[0].addr, dummy.len.cuint)

proc setTimer*(self: var Pcf85063a; ticks: uint8; ttp: TimerTickPeriod) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  var timer: array[2, uint8] = [ticks, uint8(
      (bits and not 0x18'u8) or (ttp.uint8 shl 3) or 0x04'u8)] ##  mask out current ttp and set new + enable
  discard self.i2c.writeBytes(self.address, Registers.TIMER_VALUE.uint8, timer[0].addr, timer.len.cuint)

proc enableTimerInterrupt*(self: var Pcf85063a; enable: bool; flagOnly: bool) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  bits = (bits and not 0x03'u8) or (if enable: 0x02 else: 0x00) or
      (if flagOnly: 0x01 else: 0x00)
  self.i2c.regWriteUint8(self.address, Registers.TIMER_MODE.uint8, bits)

proc readTimerFlag*(self: var Pcf85063a): bool =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  return (bits and 0x08).bool

proc clearTimerFlag*(self: var Pcf85063a) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits = bits and not 0x08'u8
  self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc unsetTimer*(self: var Pcf85063a) =
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8)
  bits = bits and not 0x04'u8
  self.i2c.regWriteUint8(self.address, Registers.TIMER_MODE.uint8, bits)

proc setClockOutput*(self: var Pcf85063a; co: ClockOut) =
  ##  set the speed of (or turn off) the clock output
  var bits: uint8 = self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8)
  bits = (bits and not 0x07'u8) or co.uint8
  self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, bits)

proc setByte*(self: var Pcf85063a; v: uint8) =
  self.i2c.regWriteUint8(self.address, Registers.RAM_BYTE.uint8, v)

proc getByte*(self: var Pcf85063a): uint8 =
  self.i2c.regReadUint8(self.address, Registers.RAM_BYTE.uint8)
