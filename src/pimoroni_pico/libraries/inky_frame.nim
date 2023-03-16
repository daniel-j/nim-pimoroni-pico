import std/math, std/bitops, std/options
import picostdlib
import picostdlib/[hardware/i2c, hardware/pwm]

import ../drivers/[uc8159, pcf85063a, fatfs, psram_display]
import ./pico_graphics

export options, pico_graphics, fatfs, Colour

const
  PinHoldSysEn = 2.Gpio
  PinI2cInt = 3.Gpio
  PinI2cSda = 4.Gpio
  PinI2CScl = 5.Gpio
  PinLedActivity* = 6.Gpio
  PinLedConnection* = 7.Gpio
  PinSrClock = 8.Gpio
  PinSrLatch = 9.Gpio
  PinSrOut = 10.Gpio
  PinLedA* = 11.Gpio
  PinLedB* = 12.Gpio
  PinLedC* = 13.Gpio
  PinLedD* = 14.Gpio
  PinLedE* = 15.Gpio
  #PinMiso = 16.Gpio
  PinEinkCs = 17.Gpio
  PinClk = 18.Gpio
  PinMosi = 19.Gpio
  #PinSdDat0 = 19.Gpio
  #PinSdDat1 = 20.Gpio
  #PinSdDat2 = 21.Gpio
  #PinSdDat3 = 22.Gpio
  #PinSdCs = 22.Gpio
  #PinAdc0 = 26.Gpio
  #PinEinkReset = 27.Gpio
  PinEinkDc = 28.Gpio

  FlagEinkBusy = 0x07

type
  Led* = enum
    LedActivity = PinLedActivity
    LedConnection = PinLedConnection
    LedA = PinLedA
    LedB = PinLedB
    LedC = PinLedC
    LedD = PinLedD
    LedE = PinLedE

  Button* = enum
    BtnA = 0
    BtnB = 1
    BtnC = 2
    BtnD = 3
    BtnE = 4

  # Must come before InkyFrame object, where set[WakeUpEvent] is
  WakeUpEvent* = enum
    EvtBtnA
    EvtBtnB
    EvtBtnC
    EvtBtnD
    EvtBtnE
    EvtRtcAlarm
    EvtExternalTrigger

  Pen* = uc8159.Colour

  InkyFrameKind* = enum
    InkyFrame4_0, InkyFrame5_7, InkyFrame7_3

  InkyFrame*[kind: static[InkyFrameKind]] = object of PicoGraphicsPenP3
    uc8159*: Uc8159
    rtc*: Pcf85063a
    width*, height*: int
    wakeUpEvents: set[WakeUpEvent]
    when kind == InkyFrame7_3:
      ramDisplay*: PsRamDisplay

proc gpioConfigure*(gpio: Gpio; dir: Direction; value: Value = Low) =
  gpioSetFunction(gpio, Sio)
  gpioSetDir(gpio, dir)
  gpioPut(gpio, value)

proc gpioConfigurePwm*(gpio: Gpio) =
  var cfg = pwmGetDefaultConfig()
  pwmSetWrap(pwmGpioToSliceNum(gpio), 65535)
  pwmInit(pwmGpioToSliceNum(gpio), cfg.addr, true)
  gpioSetFunction(gpio, Pwm)

proc readShiftRegister*(): uint8 =
  gpioPut(PinSrLatch, Low)
  sleepUs(1)
  gpioPut(PinSrLatch, High)
  sleepUs(1)
  for i in countdown(7, 0):
    if gpioGet(PinSrOut) == High:
      result.setBit(i)
    gpioPut(PinSrClock, Low)
    sleepUs(1)
    gpioPut(PinSrClock, High)
    sleepUs(1)

proc readShiftRegisterBit*(index: uint8): bool =
  readShiftRegister().testBit(index)

proc detectInkyFrameModel*(): Option[InkyFrameKind] =
  ## Experimental function to detect the model
  ## Call before InkyFrame.init, since it changes the gpio states
  const mask = {PinSrLatch, PinI2cInt}
  gpioInitMask(mask)
  gpioSetDirInMasked(mask)
  gpioMaskCall(mask, gpioPullDown)
  let switchLatch = gpioGet(PinSrLatch)
  let i2cInt = gpioGet(PinI2cInt)
  gpioMaskCall(mask, gpioDeinit)

  if (switchLatch, i2cInt) == (High, High): return some(InkyFrame4_0)
  elif (switchLatch, i2cInt) == (Low, High): return some(InkyFrame5_7)
  elif (switchLatch, i2cInt) == (Low, Low): return some(InkyFrame7_3)

proc init*[IF: InkyFrame](self: var IF) =
  (self.width, self.height) = static:
    case self.kind:
    of InkyFrame4_0: (640, 480)
    of InkyFrame5_7: (600, 448)
    of InkyFrame7_3: (800, 480)

  PicoGraphicsPenP3(self).init(self.width.uint16, self.height.uint16, noFrameBuffer=static self.kind in {InkyFrame7_3})
  self.uc8159.init(self.width.uint16, self.height.uint16, SPIPins(spi: spi0, cs: PinEinkCs, sck: PinClk, mosi: PinMosi, dc: PinEinkDc))

  # keep the pico awake by holding vsys_en high
  gpioConfigure(PinHoldSysEn, Out, High)

  # setup the shift register
  gpioConfigure(PinSrClock, Out, High)
  gpioConfigure(PinSrLatch, Out, High)
  gpioConfigure(PinSrOut, In)

  # determine wake up event
  let bits = readShiftRegister()
  self.wakeUpEvents = cast[set[WakeUpEvent]](bits.bitsliced(WakeUpEvent.low.ord..WakeUpEvent.high.ord))
  # there are other reasons a wake event can occur: connect power via usb,
  # connect a battery, or press the reset button. these cannot be
  # disambiguated so we don't attempt to report them

  ## Disable display update busy wait, we'll handle it ourselves
  self.uc8159.setBlocking(false)

  var i2c: I2c
  i2c.init(PinI2cSda, PinI2cScl)

  # initialise the rtc
  self.rtc.init(move i2c)

  # setup led pwm
  gpioConfigurePwm(PinLedA)
  gpioConfigurePwm(PinLedB)
  gpioConfigurePwm(PinLedC)
  gpioConfigurePwm(PinLedD)
  gpioConfigurePwm(PinLedE)
  gpioConfigurePwm(PinLedActivity)
  gpioConfigurePwm(PinLedConnection)

  when self.kind == InkyFrame7_3:
    self.ramDisplay.init(self.width.uint16, self.height.uint16)

proc isBusy*(): bool =
  # check busy flag on shift register
  not readShiftRegisterBit(FlagEinkBusy)

proc update*[IF: InkyFrame](self: var IF; blocking: bool = false) =
  while isBusy():
    tightLoopContents()
  self.uc8159.update(self)
  while isBusy():
    tightLoopContents()
  self.uc8159.powerOff()

proc pressed*(button: Button): bool =
  readShiftRegisterBit(button.uint8)

# set the LED brightness by generating a gamma corrected target value for
# the 16-bit pwm channel. brightness values are from 0 to 100.

proc led*[IF: InkyFrame](self: IF; led: Led; brightness: range[0.uint8..100.uint8]) =
  pwmSetGpioLevel(led.Gpio, (pow(brightness.float / 100, 2.8) * 65535.0f + 0.5f).uint16)

proc sleep*[IF: InkyFrame](self: var IF; wakeInMinutes: int = -1) =
  if wakeInMinutes != -1:
    # set an alarm to wake inky up in wake_in_minutes - the maximum sleep
    # is 255 minutes or around 4.5 hours which is the longest timer the RTC
    # supports, to sleep any longer we need to specify a date and time to
    # wake up
    self.rtc.setTimer(wakeInMinutes.uint8, tt1Over60Hz)
    self.rtc.enableTimerInterrupt(true, false)
  
  # release the vsys hold pin so that inky can go to sleep
  gpioPut(PinHoldSysEn, Low)
  while true:
    discard

proc sleepUntil*[IF: InkyFrame](self: var IF; second, minute, hour, day: int = -1) =
  if second != -1 or minute != -1 or hour != -1 or day != -1:
    # set an alarm to wake inky up at the specified time and day
    self.rtc.setAlarm(second, minute, hour, day)
    self.rtc.enableAlarmInterrupt(true)
  gpioPut(PinHoldSysEn, Low)

proc getWakeUpEvents*[IF: InkyFrame](self: IF): set[WakeUpEvent] = self.wakeUpEvents

proc setBorder*[IF: InkyFrame](self: var IF; colour: Colour) = self.uc8159.setBorder(colour)

proc image*[IF: InkyFrame](self: var IF; data: openArray[uint8]; stride: int; sx: int; sy: int; dw: int; dh: int; dx: int; dy: int) =
  var y = 0
  while y < dh:
    var x = 0
    while x < dw:
      let o = ((y + sy) * (stride div 2)) + ((x + sx) div 2)
      let d: uint8 = if ((x + sx) and 0b1) != 0: data[o] shr 4 else: data[o] and 0xf
      # draw the pixel
      self.setPen(d)
      self.pixel(Point(x: dx + x, y: dy + y))
      inc(x)
    inc(y)

proc icon*[IF: InkyFrame](self: var IF; data: openArray[uint8]; sheetWidth: int; iconSize: int; index: int; dx: int; dy: int) =
  ## Display a portion of an image (icon sheet) at dx, dy
  self.image(data, sheetWidth, iconSize * index, 0, iconSize, iconSize, dx, dy)

proc image*[IF: InkyFrame](self: var IF; data: openArray[uint8]; w: int; h: int; x: int; y: int) =
  ## Display an image smaller than the screen (sw*sh) at dx, dy
  self.image(data, w, 0, 0, w, h, x, y)

proc image*[IF: InkyFrame](self: var IF; data: openArray[uint8]) =
  ## Display an image that fills the screen
  self.image(data, self.width, 0, 0, self.width, self.height, 0, 0)

template setPen*[IF: InkyFrame](self: var IF; c: Colour) = self.setPen(c.uint8)
