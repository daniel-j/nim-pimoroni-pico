import std/bitops
import std/strutils

import picostdlib/[
  hardware/i2c, hardware/rtc
]
import ../common/[pimoroni_common, pimoroni_i2c]

export pimoroni_i2c

type
  BcdNum = distinct range[0x00'u8 .. 0x99'u8]

proc `==`*(a, b: BcdNum): bool {.borrow.}

proc bcdEncode(val: range[0'u8 .. 99'u8]): BcdNum = BcdNum ((val.uint div 10) shl 4) or (val.uint mod 10)
proc bcdDecode(val: BcdNum): uint8 = ((val.uint8 shr 4) * 10) + (val.uint8 and 0b1111)


converter encodeBcd(value: int): BcdNum = bcdEncode(value.uint8)
# converter decodeBcd(bcdNum: BcdNum): uint8 = bcdDecode(bcdNum)
converter toInt(bcdNum: BcdNum): int = bcdDecode(bcdNum).int

static:
  # simple test for the bcd number encode/decode
  for i in 0'u8 .. 99'u8:
    doAssert bcdDecode(bcdEncode(i)) == i, "Failed to convert " & $i & " to BcdNum and back"
    doAssert $bcdEncode(i) == $i, "Failed to convert " & $i & " to BcdNum and compare string"

const
  # Constants
  DefaultI2cAddress* = 0x51.I2cAddress
  ParamUnused* = -1

type
  Pcf85063a* = object
    i2c*: I2c # Interface pins with our standard defaults where appropriate
    address: I2cAddress
    interrupt: GpioOptional
    initialState: Pcf85063aState
    wasReset: bool

  CapSel {.pure.} = enum
    cap7pF
    cap12_5pF

  ClockOutFreq* {.pure.} = enum
    co32768Hz = 0
    co16384Hz = 1
    co8192Hz  = 2
    co4096Hz  = 3
    co2048Hz  = 4
    co1024Hz  = 5
    co1Hz     = 6
    coOff     = 7

  DayOfWeek* {.pure.} = enum
    SUNDAY    = 0
    MONDAY    = 1
    TUESDAY   = 2
    WEDNESDAY = 3
    THURSDAY  = 4
    FRIDAY    = 5
    SATURDAY  = 6

  TimerClockFrequency* {.pure.} = enum
    tcf4096Hz       = 0b00,
    tcf64Hz         = 0b01
    tcf1Hz          = 0b10
    tcf1Over60Hz    = 0b11

  Registers {.pure, size: sizeof(uint8).} = enum
    CONTROL_1         = 0x00
    CONTROL_2         = 0x01

    OFFSET            = 0x02

    RAM_BYTE          = 0x03

    SECONDS           = 0x04  # contains oscillator stop flag
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

  RegControl1* {.packed.} = object
    capSel* {.bitsize: 1.}: CapSel
    isAmPm* {.bitsize: 1.}: bool
    cie* {.bitsize: 1.}: bool
    un1 {.bitsize: 1.}: uint8
    sr* {.bitsize: 1.}: bool
    stop* {.bitsize: 1.}: bool
    un2 {.bitsize: 1.}: uint8
    extTest* {.bitsize: 1.}: bool
  RegControl2* {.packed.} = object
    cof* {.bitsize: 3.}: ClockOutFreq
    tf* {.bitsize: 1.}: bool
    hmi* {.bitsize: 1.}: bool
    mi* {.bitsize: 1.}: bool
    af* {.bitsize: 1.}: bool
    aie* {.bitsize: 1.}: bool
  RegOffset* {.packed.} = object
    offset* {.bitsize: 7.}: uint8
    modeCoarse* {.bitsize: 1.}: bool

  RegSeconds* {.packed.} = object
    seconds* {.bitsize: 7.}: BcdNum
    os* {.bitsize: 1.}: bool
  RegMinutes* {.packed.} = object
    minutes* {.bitsize: 7.}: BcdNum
    _ {.bitsize: 1.}: uint8
  RegHours12* {.packed.} = object
    hours* {.bitsize: 5.}: BcdNum
    amPm* {.bitsize: 1.}: bool
    _ {.bitsize: 2.}: uint8
  RegHours24* {.packed.} = object
    hours* {.bitsize: 6.}: BcdNum
    _ {.bitsize: 2.}: uint8
  RegDays* {.packed.} = object
    days* {.bitsize: 6.}: BcdNum
    _ {.bitsize: 2.}: uint8
  RegWeekdays* {.packed.} = object
    weekdays* {.bitsize: 3.}: DayOfWeek
    _ {.bitsize: 5.}: uint8
  RegMonths* {.packed.} = object
    months* {.bitsize: 5.}: BcdNum
    _ {.bitsize: 3.}: uint8
  RegYears* {.packed.} = object
    years: BcdNum

  RegSecondAlarm* {.packed.} = object
    secondAlarm* {.bitsize: 7.}: BcdNum
    disable* {.bitsize: 1.}: bool
  RegMinuteAlarm* {.packed.} = object
    minuteAlarm* {.bitsize: 7.}: BcdNum
    disable* {.bitsize: 1.}: bool
  RegHourAlarm12* {.packed.} = object
    hourAlarm* {.bitsize: 5.}: BcdNum
    amPm* {.bitsize: 1.}: bool
    _ {.bitsize: 1.}: uint8
    disable* {.bitsize: 1.}: bool
  RegHourAlarm24* {.packed.} = object
    hourAlarm* {.bitsize: 6.}: BcdNum
    _ {.bitsize: 1.}: uint8
    disable* {.bitsize: 1.}: bool
  RegDayAlarm* {.packed.} = object
    dayAlarm* {.bitsize: 6.}: BcdNum
    _ {.bitsize: 1.}: uint8
    disable* {.bitsize: 1.}: bool
  RegWeekdayAlarm* {.packed.} = object
    weekdayAlarm* {.bitsize: 3.}: DayOfWeek
    _ {.bitsize: 4.}: uint8
    disable* {.bitsize: 1.}: bool

  RegTimerValue* {.packed.} = object
    timerValue: uint8
  RegTimerMode* {.packed.} = object
    tiTp* {.bitsize: 1.}: bool
    tie* {.bitsize: 1.}: bool
    te* {.bitsize: 1.}: bool
    tcf* {.bitsize: 2.}: TimerClockFrequency
    _ {.bitsize: 3.}: uint8

  Pcf85063aTimestamp* {.packed.} = object
    seconds*: RegSeconds
    minutes*: RegMinutes
    hours*: RegHours24
    days*: RegDays
    weekdays*: RegWeekdays
    months*: RegMonths
    years*: RegYears

  Pcf85063aAlarms* {.packed.} = object
    secondAlarm*: RegSecondAlarm
    minuteAlarm*: RegMinuteAlarm
    hourAlarm*: RegHourAlarm24
    dayAlarm*: RegDayAlarm
    weekdayAlarm*: RegWeekdayAlarm

  Pcf85063aState* {.packed.} = object
    control1*: RegControl1
    control2*: RegControl2
    offset*: RegOffset
    ramByte*: byte

    timestamp*: Pcf85063aTimestamp

    alarm*: Pcf85063aAlarms

    timerValue*: RegTimerValue
    timerMode*: RegTimerMode

proc waitForOscillator*(self: var Pcf85063a) =
  # read the oscillator stop bit until it is cleared
  var status = self.i2c.regReadUint8(self.address, SECONDS.uint8)
  while status.testBit(7):
    # attempt to clear oscillator stop flag, then read it back
    # status.clearBit(7)
    discard self.i2c.regWriteUint8(self.address, SECONDS.uint8, 0x00)
    status = self.i2c.regReadUint8(self.address, SECONDS.uint8)

proc reset*(self: var Pcf85063a) =
  # magic soft reset command
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_1.uint8, 0x58)
  self.waitForOscillator()

proc readAll*(self: var Pcf85063a): Pcf85063aState =
  discard self.i2c.readBytes(self.address, CONTROL_1.uint8, cast[ptr uint8](result.addr), sizeof(result).uint)

proc init*(self: var Pcf85063a; i2c: I2c; interrupt: GpioOptional = GpioUnused) =
  self.address = DefaultI2cAddress
  self.i2c = i2c
  self.interrupt = interrupt
  if self.interrupt != GpioUnused:
    Gpio(self.interrupt).setFunction(GpioFunction.Sio)
    Gpio(self.interrupt).setDir(In)
    Gpio(self.interrupt).setPulls(up = false, down = true)

  # clear timers and alarms, disable clock_out
  var data = [uint8 0x00, 0b111]
  var res = self.i2c.writeBytes(self.address, Registers.CONTROL_1.uint8, data[0].addr, data.len.uint)
  if res <= 0:
    echo "failed to initialize RTC: ", res
    return

  self.initialState = self.readAll()

  let ts = self.initialState.timestamp
  if ts.years.years > 99 or ts.days.days > 31 or ts.hours.hours > 24 or ts.minutes.minutes > 60 or ts.seconds.seconds > 60:
    # started up in a bad state
    self.reset()

  # read the oscillator stop bit and reset if it is set
  var status = self.i2c.regReadUint8(self.address, SECONDS.uint8)

  if status.testBit(7):
    # self.reset()
    self.waitForOscillator()
    self.wasReset = true

# i2c helper methods
func getI2c*(self: var Pcf85063a): ptr I2cInst =
  return self.i2c.getI2c()

func getAddress*(self: var Pcf85063a): I2cAddress =
  return self.address

func getSda*(self: var Pcf85063a): Gpio =
  return self.i2c.getSda()

func getScl*(self: var Pcf85063a): Gpio =
  return self.i2c.getScl()

func getInt*(self: var Pcf85063a): Gpio =
  return Gpio(self.interrupt)

func initialState*(self: Pcf85063a): Pcf85063aState = self.initialState

func wasReset*(self: Pcf85063a): bool = self.wasReset

proc getDatetime*(self: var Pcf85063a): DatetimeT =
  var data: Pcf85063aTimestamp
  discard self.i2c.readBytes(self.address, Registers.SECONDS.uint8, cast[ptr uint8](data.addr), sizeof(data).uint)
  return DatetimeT(
    year: data.years.years.bcdDecode().int16 + 2000,
    month: data.months.months.bcdDecode().int8,
    day: data.days.days.bcdDecode().int8,
    dotw: data.weekdays.weekdays.ord.int8,
    hour: data.hours.hours.bcdDecode().int8,
    min: data.minutes.minutes.bcdDecode().int8,
    sec: data.seconds.seconds.bcdDecode().int8
  )

proc setDatetime*(self: var Pcf85063a; t: DatetimeT) =
  var data: Pcf85063aTimestamp
  data.seconds.seconds = t.sec.int
  data.minutes.minutes = t.min.int
  data.hours.hours = t.min.int
  data.days.days = t.day.int
  data.weekdays.weekdays = DayOfWeek(t.dotw)
  data.months.months = t.month.int
  data.years.years = t.year.int - 2000
  discard self.i2c.writeBytes(self.address, Registers.SECONDS.uint8, cast[ptr uint8](data.addr), sizeof(data).uint)

proc setAlarm*(self: var Pcf85063a; second: int; minute: int; hour: int; day: int) =
  var alarm: Pcf85063aAlarms
  if second >= 0: alarm.secondAlarm.secondAlarm = second.int else: alarm.secondAlarm.disable = true
  if minute >= 0: alarm.minuteAlarm.minuteAlarm = minute.int else: alarm.minuteAlarm.disable = true
  if hour >= 0: alarm.hourAlarm.hourAlarm = hour.int else: alarm.hourAlarm.disable = true
  if day >= 0: alarm.dayAlarm.dayAlarm = day.int else: alarm.dayAlarm.disable = true
  alarm.weekdayAlarm.disable = true
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, cast[ptr uint8](alarm.addr), sizeof(alarm).uint)

proc setWeekdayAlarm*(self: var Pcf85063a; second: int; minute: int; hour: int; dotw: DayOfWeek) =
  var alarm: Pcf85063aAlarms
  if second >= 0: alarm.secondAlarm.secondAlarm = second.int else: alarm.secondAlarm.disable = true
  if minute >= 0: alarm.minuteAlarm.minuteAlarm = minute.int else: alarm.minuteAlarm.disable = true
  if hour >= 0: alarm.hourAlarm.hourAlarm = hour.int else: alarm.hourAlarm.disable = true
  alarm.dayAlarm.disable = true
  alarm.weekdayAlarm.weekdayAlarm = dotw
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, cast[ptr uint8](alarm.addr), sizeof(alarm).uint)

proc enableAlarmInterrupt*(self: var Pcf85063a; enable: bool) =
  var control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  control2.aie = enable
  control2.af = false
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, cast[uint8](control2))

proc readAlarmFlag*(self: var Pcf85063a): bool =
  let control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  return control2.af

proc clearAlarmFlag*(self: var Pcf85063a) =
  var control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  control2.af = false
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, cast[uint8](control2))

proc unsetAlarm*(self: var Pcf85063a) =
  var dummy: array[5, uint8]
  for i, d in dummy:
    dummy[i] = 0b10000000
  discard self.i2c.writeBytes(self.address, Registers.SECOND_ALARM.uint8, dummy[0].addr, dummy.len.uint)

proc setTimer*(self: var Pcf85063a; timerValue: uint8; tcf: TimerClockFrequency = tcf1Over60Hz) =
  if timerValue == 0: return
  var timerMode = cast[RegTimerMode](self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8))
  timerMode.tcf = tcf
  timerMode.te = true
  var timer: array[2, uint8] = [timerValue, cast[uint8](timerMode)]
  discard self.i2c.writeBytes(self.address, Registers.TIMER_VALUE.uint8, timer[0].addr, timer.len.uint)

proc enableTimerInterrupt*(self: var Pcf85063a; enable: bool) =
  var timerMode = cast[RegTimerMode](self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8))
  timerMode.tie = enable
  discard self.i2c.regWriteUint8(self.address, Registers.TIMER_MODE.uint8, cast[uint8](timerMode))

proc readTimerFlag*(self: var Pcf85063a): bool =
  let control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  return control2.tf

proc clearTimerFlag*(self: var Pcf85063a) =
  var control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  control2.tf = false
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, cast[uint8](control2))

proc unsetTimer*(self: var Pcf85063a) =
  var timerMode = cast[RegTimerMode](self.i2c.regReadUint8(self.address, Registers.TIMER_MODE.uint8))
  timerMode.te = false
  var timer: array[2, uint8] = [0, cast[uint8](timerMode)]
  discard self.i2c.writeBytes(self.address, Registers.TIMER_VALUE.uint8, timer[0].addr, timer.len.uint)

proc setClockOutput*(self: var Pcf85063a; cof: ClockOutFreq) =
  # set the speed of (or turn off) the clock output
  var control2 = cast[RegControl2](self.i2c.regReadUint8(self.address, Registers.CONTROL_2.uint8))
  control2.cof = cof
  discard self.i2c.regWriteUint8(self.address, Registers.CONTROL_2.uint8, cast[uint8](control2))

proc setRamByte*(self: var Pcf85063a; v: uint8) =
  discard self.i2c.regWriteUint8(self.address, Registers.RAM_BYTE.uint8, v)

proc getRamByte*(self: var Pcf85063a): uint8 =
  return self.i2c.regReadUint8(self.address, Registers.RAM_BYTE.uint8)


proc syncFromPicoRtc*(self: var Pcf85063a): bool =
  var dt = createDatetime()
  if not rtcGetDatetime(dt.addr):
    return false
  self.setDatetime(dt)
  return true

proc syncToPicoRtc*(self: var Pcf85063a): bool =
  var dt = self.getDatetime()
  return rtcSetDatetime(dt.addr)


iterator iterRtcState*(state: Pcf85063aState): string =
  let arr = cast[array[18, uint8]](state)
  for i, data in arr:
    var str = i.toHex(2) & " " & data.int.toBin(8) & " " & data.toHex(2) & " "
    str.add(case Registers(i):
      of CONTROL_1: $cast[RegControl1](data)
      of CONTROL_2: $cast[RegControl2](data)

      of OFFSET: $cast[RegOffset](data)
      of RAM_BYTE: $data

      of SECONDS: $cast[RegSeconds](data)
      of MINUTES: $cast[RegMinutes](data)
      of HOURS: $cast[RegHours24](data)
      of DAYS: $cast[RegDays](data)
      of WEEKDAYS: $cast[RegWeekdays](data)
      of MONTHS: $cast[RegMonths](data)
      of YEARS: $cast[RegYears](data)

      of SECOND_ALARM: $cast[RegSecondAlarm](data)
      of MINUTE_ALARM: $cast[RegMinuteAlarm](data)
      of HOUR_ALARM: $cast[RegHourAlarm24](data)
      of DAY_ALARM: $cast[RegDayAlarm](data)
      of WEEKDAY_ALARM: $cast[RegWeekdayAlarm](data)

      of TIMER_VALUE: $cast[RegTimerValue](data)
      of TIMER_MODE: $cast[RegTimerMode](data)
    )
    yield str

proc printRtcState*(state: Pcf85063aState) =
  for line in iterRtcState(state):
    echo line
