import std/math, std/bitops, std/options, std/times

import picostdlib
import picostdlib/[hardware/i2c, hardware/pwm, hardware/adc]
import picostdlib/power

import ../drivers/[eink_driver_wrapper, rtc_pcf85063a, shiftregister, fatfs, sdcard, psram_display]
import ./pico_graphics
import ../drivers/wakeup

export options, pico_graphics, fatfs, sdcard, psram_display, Colour, rtc_pcf85063a, wakeup

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
  PinEinkReset = 27.Gpio
  PinEinkDc = 28.Gpio

  FlagEinkBusy = 0x07

const sr = ShiftRegister(pinClock: PinSrClock, pinLatch: PinSrLatch, pinOut: PinSrOut, bits: 8)

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

  Pen* = Colour

  InkyFrameKind* = enum
    InkyFrame4_0, InkyFrame5_7, InkyFrame7_3

  InkyFrame* = object of PicoGraphicsPen3Bit
    kind*: InkyFrameKind
    einkDriver: EinkDriver
    rtc*: RtcPcf85063a
    width*, height*: int
    wakeUpEvents: set[WakeUpEvent]

proc gpioConfigure*(gpio: Gpio; dir: Direction; value: Value = Low) =
  gpio.setFunction(Sio)
  gpio.setDir(dir)
  gpio.put(value)

proc gpioConfigurePwm*(gpio: static[Gpio]) =
  const pwmSlice = gpio.toPwmSliceNum()
  pwmSlice.setWrap(65535)
  var cfg = pwmGetDefaultConfig()
  pwmSlice.init(cfg.addr, true)
  gpio.setFunction(Pwm)

proc detectInkyFrameModel*(): Option[InkyFrameKind] =
  ## Experimental function to detect the model
  ## Call before InkyFrame.init, since it changes the gpio states
  const mask = {PinSrLatch, PinI2cInt}
  mask.init()
  mask.setDirIn()
  PinSrLatch.pullDown()
  PinI2cInt.pullDown()
  let switchLatch = PinSrLatch.get()
  let i2cInt = PinI2cInt.get()
  PinSrLatch.deinit()
  PinI2cInt.deinit()

  if switchLatch == High and i2cInt == High: return some(InkyFrame4_0)
  elif switchLatch == Low and i2cInt == High: return some(InkyFrame5_7)
  elif switchLatch == Low and i2cInt == Low: return some(InkyFrame7_3)

  sr.init()

proc isBusy*(): bool =
  ## Check busy flag on shift register
  not sr.readBit(FlagEinkBusy)

proc boot*(self: var InkyFrame) =
  # keep the pico awake by holding vsys_en high
  if PinHoldSysEn notin wakeup.getGpioState():
    gpioConfigure(PinHoldSysEn, Out, High)

  # setup the shift register
  sr.init()

  var i2c: I2c
  i2c.init(PinI2cSda, PinI2cScl)

  # initialise the rtc
  self.rtc.init(move i2c)
  self.rtc.setClockOutput(coOff) # Turn off CLOCK_OUT
  var rambyte = self.rtc.getRamByte()
  if rambyte == 0:
    self.rtc.reset()
    rambyte.setBit(0)
    self.rtc.setRamByte(rambyte)

  # let bits = sr.read()
  # determine wake up event
  # self.wakeUpEvents = cast[set[WakeUpEvent]](bits.bitsliced(static WakeUpEvent.low.ord..WakeUpEvent.high.ord))
  self.wakeUpEvents = cast[set[WakeUpEvent]](wakeup.getShiftState().bitsliced(static WakeUpEvent.low.ord..WakeUpEvent.high.ord))

  # there are other reasons a wake event can occur: connect power via usb,
  # connect a battery, or press the reset button. these cannot be
  # disambiguated so we don't attempt to report them

  # setup led pwm
  gpioConfigurePwm(PinLedA)
  gpioConfigurePwm(PinLedB)
  gpioConfigurePwm(PinLedC)
  gpioConfigurePwm(PinLedD)
  gpioConfigurePwm(PinLedE)
  gpioConfigurePwm(PinLedActivity)
  gpioConfigurePwm(PinLedConnection)

proc init*(self: var InkyFrame) =
  (self.width, self.height) =
    case self.kind:
    of InkyFrame4_0: (640, 400)
    of InkyFrame5_7: (600, 448)
    of InkyFrame7_3: (800, 480)

  PicoGraphicsPen3Bit(self).init(
    width = self.width.uint16,
    height = self.height.uint16,
    backend = if self.kind == InkyFrame7_3: BackendPsram else: BackendMemory,
    palette = if self.kind == InkyFrame7_3: PicoGraphicsPen3BitPalette7_3 else: PicoGraphicsPen3BitPalette5_7,
    # paletteSize = if self.kind == InkyFrame5_7: 8 else: 7 # clean colour is a greenish gradient on inky7, so avoid it
  )
  # self.cacheNearest = if self.kind == InkyFrame7_3: PicoGraphicsPen3BitPaletteLut7_3 else: PicoGraphicsPen3BitPaletteLut5_7
  # self.cacheNearestBuilt = true

  let pins = SpiPins(spi: PimoroniSpiDefaultInstance, cs: PinEinkCs, sck: PinClk, mosi: PinMosi, dc: PinEinkDc)

  self.einkDriver.kind = if self.kind == InkyFrame7_3: KindAc073tc1a else: KindUc8159

  self.einkDriver.init(
    self.width.uint16,
    self.height.uint16,
    pins,
    resetPin = PinEinkReset,
    isBusy,
    blocking = true)

  # init adc for vsys reading
  adcInit()

proc update*(self: var InkyFrame) =
  if not self.einkDriver.getBlocking():
    while isBusy():
      tightLoopContents()
  self.einkDriver.update(self)
  if not self.einkDriver.getBlocking():
    while isBusy():
      tightLoopContents()
    self.einkDriver.powerOff()

proc pressed*(button: Button): bool =
  sr.readBit(button.uint8)

proc led*(self: InkyFrame; led: Led; brightness: range[0.uint8..100.uint8]) =
  ## Set the LED brightness by generating a gamma corrected target value for
  ## the 16-bit pwm channel. Brightness values are from 0 to 100.
  Gpio(led).setPwmLevel((pow(brightness.float / 100, 2.8) * 65535.0f + 0.5f).uint16)

proc turnOff*(self: InkyFrame) =
  sleepMs(100)
  # release the vsys hold pin so that inky can go to sleep
  PinHoldSysEn.init()
  sleepMs(100)


proc sleep*(self: var InkyFrame; wakeInMinutes: int = -1) =
  # Set an alarm to wake inky up in wake_in_minutes
  # Negative values means sleep without a wakeup timer (default)

  # self.rtc.clearAlarmFlag()
  # self.rtc.clearTimerFlag()
  # self.rtc.enableTimerInterrupt(false)
  # self.rtc.enableAlarmInterrupt(false)
  # self.rtc.unsetAlarm()
  # self.rtc.unsetTimer()

  # Can't sleep beyond a month, so clamp the sleep to a 28 day maximum
  let minutes = min(40320, wakeInMinutes)

  if wakeInMinutes > 0:
    if minutes <= 255:
      # the maximum sleep is 255 minutes or around 4.5 hours which is the longest timer the RTC
      # supports, to sleep any longer we need to specify a date and time to
      # wake up
      self.rtc.setTimer(minutes.uint8, tt1Over60Hz)
      self.rtc.enableTimerInterrupt(true)
    else:
      # more than 255 minutes, calculate wakeup time and day
      let dt = self.rtc.getDatetime().toNimDateTime() + initDuration(minutes = minutes)
      self.rtc.setAlarm(dt.second, dt.minute, dt.hour, dt.monthday)
      self.rtc.enableAlarmInterrupt(true)

  self.turnOff()

  # emulate sleep on usb power
  if minutes > 0:
    var minutesLeft = minutes
    while minutesLeft > 0:
      echo "Sleeping for ", minutesLeft, " minutes"
      sleepMs(60 * 1000)
      dec(minutesLeft)
  else:
    echo "Sleeping forever."
    while true:
      tightLoopContents()
      sleepMs(1000)

proc sleepUntil*(self: var InkyFrame; second, minute, hour, day: int = -1) =
  self.rtc.clearAlarmFlag()
  if second != -1 or minute != -1 or hour != -1 or day != -1:
    # set an alarm to wake inky up at the specified time and day
    self.rtc.setAlarm(second, minute, hour, day)
    self.rtc.enableAlarmInterrupt(true)

  self.turnOff()

  # TODO: Implement emulation of sleep using rtc
  echo "Sleeping forever."
  while true:
    tightLoopContents()

proc getWakeUpEvents*(self: InkyFrame): set[WakeUpEvent] = self.wakeUpEvents

proc setBorder*(self: var InkyFrame; colour: Colour) =
  self.einkDriver.setBorder(colour)

proc syncRtcFromPicoRtc*(self: var InkyFrame): bool = self.rtc.syncFromPicoRtc()

proc syncRtcToPicoRtc*(self: var InkyFrame): bool = self.rtc.syncToPicoRtc()

proc isBatteryPowered*(self: InkyFrame): bool = powerSourceBattery()

proc getBatteryVoltage*(self: InkyFrame): float32 = powerSourceVoltage()

proc image*(self: var InkyFrame; data: openArray[uint8]; stride: int; sx: int; sy: int; dw: int; dh: int; dx: int; dy: int) =
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

proc icon*(self: var InkyFrame; data: openArray[uint8]; sheetWidth: int; iconSize: int; index: int; dx: int; dy: int) =
  ## Display a portion of an image (icon sheet) at dx, dy
  self.image(data, sheetWidth, iconSize * index, 0, iconSize, iconSize, dx, dy)

proc image*(self: var InkyFrame; data: openArray[uint8]; w: int; h: int; x: int; y: int) =
  ## Display an image smaller than the screen (sw*sh) at dx, dy
  self.image(data, w, 0, 0, w, h, x, y)

proc image*(self: var InkyFrame; data: openArray[uint8]) =
  ## Display an image that fills the screen
  self.image(data, self.width, 0, 0, self.width, self.height, 0, 0)

template setPen*(self: var InkyFrame; c: Pen) = self.setPen(c.uint8)
