import inkyframe/[
  pico_graphics, uc8159, pcf85063a
]
import picostdlib/[
  hardware/gpio, hardware/i2c,
  hardware/pwm, pico/time, pico/platform
]
import std/math

const
  PinHoldSysEn = 2.Gpio
  #PinI2cInt = 3.Gpio
  #PinI2cSda = 4.Gpio
  #PinI2CScl = 5.Gpio
  PinSrClock = 8.Gpio
  PinSrLatch = 9.Gpio
  PinSrOut = 10.Gpio
  #PinMiso = 16.Gpio
  #PinEinkCs = 17.Gpio
  #PinClk = 18.Gpio
  #PinMosi = 19.Gpio
  #PinSdDat0 = 19.Gpio
  #PinSdDat1 = 20.Gpio
  #PinSdDat2 = 21.Gpio
  #PinSdDat3 = 22.Gpio
  #PinSdCs = 22.Gpio
  #PinAdc0 = 26.Gpio
  #PinEinkReset = 27.Gpio
  #PinEinkDc = 28.Gpio

type
  Button* {.pure.} = enum
    A = 0
    B = 1
    C = 2
    D = 3
    E = 4

  Led* {.pure.} = enum
    Activity = 6.Gpio
    Connection = 7.Gpio
    A = 11.Gpio
    B = 12.Gpio
    C = 13.Gpio
    D = 14.Gpio
    E = 15.Gpio
  
  Flags* {.pure.} = enum
    RtcAlarm = 5
    ExternalTrigger = 6
    EinkBusy = 7
  
  WakeUpEvent* {.pure.} = enum
    Unknown = 0
    ButtonA = 1
    ButtonB = 2
    ButtonC = 3
    ButtonD = 4
    ButtonE = 5
    RtcAlarm = 6
    ExternalTrigger = 7
  
  Pen* = uc8159.Colour

  InkyFrame* = object of PicoGraphicsPen3Bit
    uc8159*: Uc8159
    i2c*: I2cInst
    rtc*: Pcf85063a
    width*, height*: int
    wakeUpEvent: WakeUpEvent


proc gpioConfigure*(gpio: Gpio; dir: bool; value: Value = Low) =
  gpioSetFunction(gpio, GpioFunction.Sio)
  gpioSetDir(gpio, dir)
  gpioPut(gpio, value)

proc gpioConfigurePwm*(gpio: Gpio) =
  var cfg: PwmConfig = pwmGetDefaultConfig()
  pwmSetWrap(pwmGpioToSliceNum(gpio), 65535)
  pwmInit(pwmGpioToSliceNum(gpio), addr(cfg), true)
  gpioSetFunction(gpio, GpioFunction.Pwm)

proc readShiftRegister*(): uint8 =
  gpioPut(PinSrLatch, Low)
  sleepUs(1)
  gpioPut(PinSrLatch, High)
  sleepUs(1)
  var bits: uint8 = 8
  while bits > 0:
    result = result shl 1
    result = result or (if gpioGet(PinSrOut).bool: 1 else: 0).uint8
    gpioPut(PinSrClock, Low)
    sleepUs(1)
    gpioPut(PinSrClock, High)
    sleepUs(1)
    dec(bits)

proc readShiftRegisterBit*(index: uint8): bool =
  (readShiftRegister() and (1'u shl index).uint8).bool

proc init*(this: var InkyFrame) =
  this.width = 600
  this.height = 448
  this.uc8159.init()

  ##  keep the pico awake by holding vsys_en high
  gpioSetFunction(PinHoldSysEn, GpioFunction.Sio)
  gpioSetDir(PinHoldSysEn, Out)
  gpioPut(PinHoldSysEn, High)
  ##  setup the shift register
  gpioConfigure(PinSrClock, Out, High)
  gpioConfigure(PinSrLatch, Out, High)
  gpioConfigure(PinSrOut, In)
  this.wakeUpEvent = Unknown
  ##  determine wake up event
  if readShiftRegisterBit(Button.A.uint8):
    this.wakeUpEvent = WakeUpEvent.ButtonA
  if readShiftRegisterBit(Button.B.uint8):
    this.wakeUpEvent = WakeUpEvent.ButtonB
  if readShiftRegisterBit(Button.C.uint8):
    this.wakeUpEvent = WakeUpEvent.ButtonC
  if readShiftRegisterBit(Button.D.uint8):
    this.wakeUpEvent = WakeUpEvent.ButtonD
  if readShiftRegisterBit(Button.E.uint8):
    this.wakeUpEvent = WakeUpEvent.ButtonE
  if readShiftRegisterBit(Flags.RtcAlarm.uint8):
    this.wakeUpEvent = WakeUpEvent.RtcAlarm
  if readShiftRegisterBit(Flags.ExternalTrigger.uint8):
    this.wakeUpEvent = WakeUpEvent.ExternalTrigger
  this.uc8159.setBlocking(false)
  ##  initialise the rtc
  this.rtc.init()
  ##  setup led pwm
  gpioConfigurePwm(Led.A.Gpio)
  gpioConfigurePwm(Led.B.Gpio)
  gpioConfigurePwm(Led.C.Gpio)
  gpioConfigurePwm(Led.D.Gpio)
  gpioConfigurePwm(Led.E.Gpio)
  gpioConfigurePwm(Led.Activity.Gpio)
  gpioConfigurePwm(Led.Connection.Gpio)

proc isBusy*(): bool =
  ##  check busy flag on shift register
  not readShiftRegisterBit(Flags.EinkBusy.uint8)

proc update*(this: var InkyFrame; blocking: bool) =
  while isBusy():
    tightLoopContents()
  # uc8159.update(cast[PicoGraphicsPenP4](this))
  while isBusy():
    tightLoopContents()
  this.uc8159.powerOff()

proc pressed*(button: Button): bool =
  readShiftRegisterBit(button.uint8)

##  set the LED brightness by generating a gamma corrected target value for
##  the 16-bit pwm channel. brightness values are from 0 to 100.

proc led*(led: Led; brightness: uint8) =
  pwmSetGpioLevel(led.Gpio, (pow(brightness.float / 100, 2.8) * 65535.0f + 0.5f).uint16)

proc sleep*(this: var InkyFrame; wakeInMinutes: int) =
  if wakeInMinutes != -1:
    ##  set an alarm to wake inky up in wake_in_minutes - the maximum sleep
    ##  is 255 minutes or around 4.5 hours which is the longest timer the RTC
    ##  supports, to sleep any longer we need to specify a date and time to
    ##  wake up
    this.rtc.setTimer(wakeInMinutes.uint8, tt1Over60Hz)
    this.rtc.enableTimerInterrupt(true, false)
  
  ## release the vsys hold pin so that inky can go to sleep
  gpioPut(PinHoldSysEn, Low)
  while true:
    discard


proc sleepUntil*(this: var InkyFrame; second: int; minute: int; hour: int; day: int) =
  if second != -1 or minute != -1 or hour != -1 or day != -1:
    ##  set an alarm to wake inky up at the specified time and day
    this.rtc.setAlarm(second, minute, hour, day)
    this.rtc.enableAlarmInterrupt(true)
  gpioPut(PinHoldSysEn, Low)

proc image*(this: var InkyFrame; data: openArray[uint8]; stride: int; sx: int; sy: int; dw: int; dh: int; dx: int; dy: int) =
  var y = 0
  while y < dh:
    var x = 0
    while x < dw:
      let o = ((y + sy) * (stride div 2)) + ((x + sx) div 2)
      let d: uint8 = if ((x + sx) and 0b1) != 0: data[o] shr 4 else: data[o] and 0xf
      ##  draw the pixel
      this.setPen(d)
      this.pixel(Point(x: dx + x, y: dy + y))
      inc(x)
    inc(y)

proc icon*(this: var InkyFrame; data: openArray[uint8]; sheetWidth: int; iconSize: int; index: int; dx: int; dy: int) =
  ##  Display a portion of an image (icon sheet) at dx, dy
  this.image(data, sheetWidth, iconSize * index, 0, iconSize, iconSize, dx, dy)

proc image*(this: var InkyFrame; data: openArray[uint8]; w: int; h: int; x: int; y: int) =
  ##  Display an image smaller than the screen (sw*sh) at dx, dy
  this.image(data, w, 0, 0, w, h, x, y)

proc image*(this: var InkyFrame; data: openArray[uint8]) =
  ##  Display an image that fills the screen
  this.image(data, this.width, 0, 0, this.width, this.height, 0, 0)
