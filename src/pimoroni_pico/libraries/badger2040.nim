import std/math
import picostdlib/hardware/[pwm]
import ../drivers/eink_uc8151

export pico_graphics, Colour

type
  Button* = enum
    BtnA
    BtnB
    BtnC
    BtnUp
    BtnDown
    BtnUser

const
  PinA* = 12.Gpio
  PinB* = 13.Gpio
  PinC* = 14.Gpio
  PinUp* = 15.Gpio
  PinDown* = 16.Gpio
  PinUser* = 23.Gpio
  PinLed* = 25.Gpio

  PinEinkCs* = 17.Gpio
  PinClk* = 18.Gpio
  PinMosi* = 19.Gpio
  PinEinkDc* = 20.Gpio
  PinReset* = 21.Gpio
  PinEinkBusy* = 26.Gpio

  PinVbusDetect* = 24.Gpio
  PinBattery* = 29.Gpio
  PinEnable3v3* = 10.Gpio

  buttons* = {BtnA, BtnB, BtnC, BtnUp, BtnDown, BtnUser}
  buttonPins* = {PinA, PinB, PinC, PinUp, PinDown, PinUser}

type
  Badger2040* = object of PicoGraphicsPen1Bit
    einkDriver*: Uc8151
    buttonStates*: set[Gpio]
    wakeButtonStates*: set[Gpio]

proc width*(self: Badger2040): int {.inline.} = self.bounds.w
proc height*(self: Badger2040): int {.inline.} = self.bounds.h

proc isBusy*(): bool =
  return PinEinkBusy.get() == Low

proc init*(self: var Badger2040) =
  PinEnable3v3.setFunction(Sio)
  PinEnable3v3.setDir(Out)
  PinEnable3v3.put(High)

  for pin in buttonPins:
    pin.setFunction(Sio)
    pin.setDir(In)
    pin.setPulls(false, true)
  
  PinVbusDetect.setFunction(Sio)
  PinVbusDetect.setDir(In)
  PinVbusDetect.put(High)

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

  PicoGraphicsPen1Bit(self).init(296, 128)

  let pins = SpiPins(spi: PimoroniSpiDefaultInstance, cs: PinEinkCs, sck: PinClk, mosi: PinMosi, dc: PinEinkDc)

  self.einkDriver.kind = KindUc8151
  self.einkDriver.initUc8151(
    self.width.uint16, self.height.uint16,
    pins, PinReset, isBusy,
    blocking = true
  )

proc setBorder*(self: var Badger2040; colour: Colour) =
  self.einkDriver.setBorder(colour)
  self.einkDriver.setup()

proc update*(self: var Badger2040) =
  if not self.einkDriver.getBlocking():
    while isBusy():
      tightLoopContents()
  self.einkDriver.updateUc8151(self)
  if not self.einkDriver.getBlocking():
    while isBusy():
      tightLoopContents()
    self.einkDriver.powerOffUc8151()
    while isBusy():
      tightLoopContents()

proc updateButtonStates*(self: var Badger2040) =
  self.buttonStates = gpioGetAll() * buttonPins
  if self.buttonStates.contains(PinUser):
    self.buttonStates.excl(PinUser)
  else:
    self.buttonStates.incl(PinUser)


proc pressed*(button: Button): bool =
  let btnPin = case button:
  of BtnA: PinA
  of BtnB: PinB
  of BtnC: PinC
  of BtnUp: PinUp
  of BtnDown: PinDown
  of BtnUser: PinUser
  return btnPin.get() == High

proc led*(self: Badger2040; brightness: range[0.uint8..100.uint8]) =
  ## Set the LED brightness by generating a gamma corrected target value for
  ## the 16-bit pwm channel. Brightness values are from 0 to 100.
  PinLed.setPwmLevel((pow(brightness.float / 100, 2.8) * 65535.0f + 0.5f).uint16)

