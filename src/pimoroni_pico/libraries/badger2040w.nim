import std/math
import picostdlib/hardware/[pwm]
import ./badger2040 except PinLed, PinUser, Button, buttons, buttonPins
import ../drivers/[eink_uc8151, rtc_pcf85063a]

export badger2040

type
  Button* = enum
    BtnA
    BtnB
    BtnC
    BtnUp
    BtnDown

const
  PinLed* = 22.Gpio

  PinI2cSda* = 4.Gpio
  PinI2CScl* = 5.Gpio

  PinRtcAlarm* = 8.Gpio

  buttons* = {BtnA, BtnB, BtnC, BtnUp, BtnDown}
  buttonPins* = {PinA, PinB, PinC, PinUp, PinDown}

type
  Badger2040W* = object of Badger2040
    rtc*: Pcf85063a

proc init*(self: var Badger2040W) =
  var i2c: I2c
  i2c.init(PinI2cSda, PinI2cScl)

  # initialise the rtc
  self.rtc.init(move i2c)
  self.rtc.setClockOutput(coOff) # Turn off CLOCK_OUT
  self.rtc.enableTimerInterrupt(false)
  # self.rtc.reset()

  PinEnable3v3.setFunction(Sio)
  PinEnable3v3.setDir(Out)
  PinEnable3v3.put(High)

  for pin in buttonPins:
    pin.setFunction(Sio)
    pin.setDir(In)
    pin.setPulls(false, true)
  
  PinEinkBusy.setFunction(Sio)
  PinEinkBusy.setDir(In)
  PinEinkBusy.setPulls(true, false)

  self.wakeButtonStates = gpioGetAll() * buttonPins

  const pwmSlice = PinLed.toPwmSliceNum()
  pwmSlice.setWrap(65535)
  var cfg = pwmGetDefaultConfig()
  pwmSlice.init(cfg.addr, true)
  PinLed.setFunction(Pwm)
  PinLed.setPwmLevel(0)

  PicoGraphicsPen1Bit(self).init(128, 296)

  let pins = SpiPins(spi: PimoroniSpiDefaultInstance, cs: PinEinkCs, sck: PinClk, mosi: PinMosi, dc: PinEinkDc)

  self.einkDriver.kind = KindUc8151
  self.einkDriver.initUc8151(
    self.width.uint16, self.height.uint16,
    pins, PinReset, isBusy,
    blocking = true
  )

proc update*(self: var Badger2040W) {.inline.} =
  Badger2040(self).update()

proc updateButtonStates*(self: var Badger2040W) =
  self.buttonStates = gpioGetAll() * buttonPins

proc pressed*(button: Button): bool =
  let btnPin = case button:
  of BtnA: PinA
  of BtnB: PinB
  of BtnC: PinC
  of BtnUp: PinUp
  of BtnDown: PinDown
  return btnPin.get() == High

proc led*(self: Badger2040W; brightness: range[0.uint8..100.uint8]) =
  ## Set the LED brightness by generating a gamma corrected target value for
  ## the 16-bit pwm channel. Brightness values are from 0 to 100.
  PinLed.setPwmLevel((pow(brightness.float / 100, 2.8) * 65535.0f + 0.5f).uint16)

