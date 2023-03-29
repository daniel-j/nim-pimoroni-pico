import picostdlib
import ../common/pimoroni_common
import ../common/pimoroni_bus
import ../libraries/pico_graphics/display_driver
import ./eink_common

export display_driver, pimoroni_bus, Colour

type
  Reg = enum
    Psr   = 0x00
    Pwr   = 0x01
    Pof   = 0x02
    Pfs   = 0x03
    Pon   = 0x04
    Btst1 = 0x05
    Btst2 = 0x06
    Dslp  = 0x07
    Btst3 = 0x08
    Dtm1  = 0x10
    Dsp   = 0x11
    Drf   = 0x12
    Ipc   = 0x13
    # LutC  = 0x20
    # LutB  = 0x21
    # LutW  = 0x22
    # LutG1 = 0x23
    # LutG2 = 0x24
    # LutR0 = 0x25
    # LutR1 = 0x26
    # LutR2 = 0x27
    # LutR3 = 0x28
    # LutXon = 0x29
    Pll   = 0x30
    Tsc   = 0x40
    Tse   = 0x41
    Tsw   = 0x42
    Tsr   = 0x43
    Cdi   = 0x50
    Lpd   = 0x51
    Tcon  = 0x60
    Tres  = 0x61
    Dam   = 0x65
    Rev   = 0x70
    Flg   = 0x71
    Amv   = 0x80
    Vv    = 0x81
    Vdcs  = 0x82
    TVdcs = 0x84
    Agid  = 0x86
    Cmdh  = 0xAA
    Ccset = 0xE0
    Pws   = 0xE3
    Tsset = 0xE6 # E5 or E6

  IsBusyProc* = proc (): bool

  EinkAc073tc1a* = object of DisplayDriver
    spi: ptr SpiInst
    csPin: Gpio
    dcPin: Gpio
    sckPin: Gpio
    mosiPin: Gpio
    resetPin: Gpio
    timeout: AbsoluteTime
    blocking: bool
    borderColour: Colour
    isBusyProc: IsBusyProc

proc init*(self: var EinkAc073tc1a; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  DisplayDriver(self).init(width, height)

  self.spi = pins.spi
  self.csPin = pins.cs
  self.sckPin = pins.sck
  self.dcPin = pins.dc
  self.mosiPin = pins.mosi

  self.isBusyProc = isBusyProc
  self.resetPin = resetPin

  self.blocking = blocking
  self.borderColour = White

  ##  configure spi interface and pins
  discard spiInit(self.spi, 20_000_000)

  gpioSetFunction(self.dcPin, Sio)
  gpioSetDir(self.dcPin, Out)

  gpioSetFunction(self.csPin, Sio)
  gpioSetDir(self.csPin, Out)
  gpioPut(self.csPin, High)

  gpioSetFunction(self.resetPin, Sio)
  gpioSetDir(self.resetPin, Out)
  gpioPut(self.resetPin, High)

  gpioSetFunction(self.sckPin, Spi)
  gpioSetFunction(self.mosiPin, Spi)

proc isBusy*(self: EinkAc073tc1a): bool =
  ## Wait for the timeout to complete, then check the busy callback.
  ## This is to avoid polling the callback constantly
  if absoluteTimeDiffUs(getAbsoluteTime(), self.timeout) > 0:
    return true
  if not self.isBusyProc.isNil:
    return self.isBusyProc()

proc busyWait*(self: var EinkAc073tc1a, minimumWaitMs: uint32 = 0) =
  # echo "busyWait ", minimumWaitMs
  # let startTime = getAbsoluteTime()
  self.timeout = makeTimeoutTimeMs(minimumWaitMs)
  while self.isBusy():
    tightLoopContents()
  # let endTime = getAbsoluteTime()
  # echo absoluteTimeDiffUs(startTime, endTime)

proc reset*(self: var EinkAc073tc1a) =
  gpioPut(self.resetPin, Low)
  sleepMs(10)
  gpioPut(self.resetPin, High)
  sleepMs(10)
  self.busyWait()

proc data*(self: var EinkAc073tc1a, len: uint; data: varargs[uint8]) =
  gpioPut(self.csPin, Low)
  ##  data mode
  gpioPut(self.dcPin, High)

  discard spiWriteBlocking(self.spi, data)
  gpioPut(self.csPin, High)

proc command*(self: var EinkAc073tc1a; reg: Reg; data: varargs[uint8]) =
  gpioPut(self.csPin, Low)
  ##  command mode
  gpioPut(self.dcPin, Low)
  discard spiWriteBlocking(self.spi, reg.uint8)
  if data.len > 0:
    ##  data mode
    gpioPut(self.dcPin, High)
    discard spiWriteBlocking(self.spi, data)
  gpioPut(self.csPin, High)

proc setup*(self: var EinkAc073tc1a) =
  self.reset()
  self.busyWait()

  self.command(Cmdh, 0x49, 0x55, 0x20, 0x08, 0x09, 0x18)
  self.command(Pwr,0x3F, 0x00, 0x32, 0x2A, 0x0E, 0x2A)
  if self.rotation == Rotate_0:
    self.command(Psr, 0x53, 0x69)
  else:
    self.command(Psr, 0x5F, 0x69)

  self.command(Pfs, 0x00, 0x54, 0x00, 0x44)
  self.command(Btst1, 0x40, 0x1F, 0x1F, 0x2C)
  self.command(Btst2, 0x6F, 0x1F, 0x1F, 0x22)
  self.command(Btst3, 0x6F, 0x1F, 0x1F, 0x22)
  self.command(Ipc, 0x00, 0x04)
  self.command(Pll, 0x3C)
  self.command(Tse, 0x00)
  self.command(Cdi, 0x3F)
  self.command(Tcon, 0x02, 0x00)
  self.command(Tres, 0x03, 0x20, 0x01, 0xE0)
  self.command(Vdcs, 0x1E)
  self.command(TVdcs, 0x00)
  self.command(Agid, 0x00)
  self.command(Pws, 0x2F)
  self.command(Ccset, 0x00)
  self.command(Tsset, 0x00)

proc getBlocking*(self: EinkAc073tc1a): bool = self.blocking

proc setBlocking*(self: var EinkAc073tc1a; blocking: bool) = self.blocking = blocking

proc setBorder*(self: var EinkAc073tc1a; colour: Colour) = self.borderColour = colour

proc powerOff*(self: var EinkAc073tc1a) =
  self.busyWait()
  self.command(Pof) ##  turn off

proc update*(self: var EinkAc073tc1a; graphics: var PicoGraphics) =
  if graphics.penType != Pen_P3:
    return

  if self.blocking:
    self.busyWait()

  self.setup()

  gpioPut(self.csPin, Low)

  gpioPut(self.dcPin, Low) ##  command mode
  discard spiWriteBlocking(self.spi, Dtm1.uint8)

  gpioPut(self.dcPin, High) ##  data mode

  ## HACK: Output 48 rows of data since our buffer is 400px tall
  ##  but the display has no offset configuration and H/V scan
  ##  are reversed.
  ## Any garbage data will do.
  ##  2px per byte, so we need width * 24 bytes
  if self.height == 400 and self.rotation == Rotate_0:
    discard spiWriteBlocking(self.spi, graphics.frameBuffer[0].addr, self.width * 24)

  let spiPtr = self.spi
  graphics.frameConvert(Pen_P4, (proc (buf: pointer; length: uint) =
    if length > 0:
      discard spiWriteBlocking(spiPtr, cast[ptr uint8](buf), length.csize_t)
  ))

  gpioPut(self.csPin, High)

  self.busyWait()

  self.command(Pon) ##  turn on
  self.busyWait(100)

  self.command(Drf) ##  start display refresh

  if self.blocking:
    self.busyWait(28 * 1000)
    self.command(Pof) ##  turn off
  else:
    self.timeout = makeTimeoutTimeMs(28 * 1000)
