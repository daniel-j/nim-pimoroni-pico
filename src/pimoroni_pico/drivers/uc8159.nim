import picostdlib/[pico/types, pico/platform]
import ../common/pimoroni_common, ../libraries/pico_graphics

type
  Reg {.pure, size: sizeof(uint8).} = enum
    PSR   = 0x00'u8
    PWR   = 0x01'u8
    POF   = 0x02'u8
    PFS   = 0x03'u8
    PON   = 0x04'u8
    BTST  = 0x06'u8
    DSLP  = 0x07'u8
    DTM1  = 0x10'u8
    DSP   = 0x11'u8
    DRF   = 0x12'u8
    IPC   = 0x13'u8
    PLL   = 0x30'u8
    TSC   = 0x40'u8
    TSE   = 0x41'u8
    TSW   = 0x42'u8
    TSR   = 0x43'u8
    CDI   = 0x50'u8
    LPD   = 0x51'u8
    TCON  = 0x60'u8
    TRES  = 0x61'u8
    DAM   = 0x65'u8
    REV   = 0x70'u8
    FLG   = 0x71'u8
    AMV   = 0x80'u8
    VV    = 0x81'u8
    VDCS  = 0x82'u8
    PWS   = 0xE3'u8
    TSSET = 0xE5'u8
  
  Colour* {.pure.} = enum
    Black
    White
    Green
    Blue
    Red
    Yellow
    Orange
    Clean

  Uc8159* {.bycopy.} = object of DisplayDriver
    spi: ptr SpiInst
    csPin: Gpio
    dcPin: Gpio
    sckPin: Gpio
    mosiPin: Gpio
    busyPin: int
    resetPin: Gpio
    timeout: AbsoluteTime
    blocking: bool


proc isBusy*(self: Uc8159): bool =
  if self.busyPin.int == PinUnused:
    if absoluteTimeDiffUs(getAbsoluteTime(), self.timeout) > 0:
      return true
    else:
      return false
  return not gpioGet(self.busyPin.Gpio).bool

proc busyWait*(self: var Uc8159, minimumWaitMs: uint32 = 0) =
  self.timeout = makeTimeoutTimeMs(minimumWaitMs)
  while self.isBusy():
    tightLoopContents()

proc reset*(self: var Uc8159) =
  gpioPut(self.resetPin, Low)
  sleepMs(10)
  gpioPut(self.resetPin, High)
  sleepMs(10)
  self.busyWait()

proc command*(self: var Uc8159; reg: Reg; data: openArray[uint8] = []) =
  gpioPut(self.csPin, Low)
  gpioPut(self.dcPin, Low)
  var regNum = reg.uint8
  ##  command mode
  discard spiWriteBlocking(self.spi, regNum.addr, 1)
  if data.len > 0:
    gpioPut(self.dcPin, High)
    ##  data mode
    discard spiWriteBlocking(self.spi, cast[ptr uint8](data.unsafeAddr), data.len.csize_t)
  gpioPut(self.csPin, High)

proc init*(self: var Uc8159) =
  self.spi = spi0
  self.csPin = SpiBgFrontCs
  self.dcPin = 28.Gpio
  self.sckPin = SpiDefaultSck
  self.mosiPin = SpiDefaultMosi
  self.busyPin = PinUnused
  self.resetPin = 27.Gpio
  self.blocking = false
  ##  configure spi interface and pins
  discard spiInit(self.spi, 3_000_000.cuint)
  gpioSetFunction(self.dcPin, GpioFunction.Sio)
  gpioSetDir(self.dcPin, Out)
  gpioSetFunction(self.csPin, GpioFunction.Sio)
  gpioSetDir(self.csPin, Out)
  gpioPut(self.csPin, High)
  gpioSetFunction(self.resetPin, GpioFunction.Sio)
  gpioSetDir(self.resetPin, Out)
  gpioPut(self.resetPin, High)
  gpioSetFunction(self.busyPin.Gpio, GpioFunction.Sio)
  gpioSetDir(self.busyPin.Gpio, In)
  gpioSetPulls(self.busyPin.Gpio, up=true, down=false)
  gpioSetFunction(self.sckPin, GpioFunction.Spi)
  gpioSetFunction(self.mosiPin, GpioFunction.Spi)

proc setup*(self: var Uc8159) =
  self.reset()
  self.busyWait()
  var dimensions = [uint8(self.width shr 8),  uint8(self.width),
                    uint8(self.height shr 8), uint8(self.height)]
  if self.width == 600:
    if self.rotation == Rotate_0:
      self.command(Psr, [uint8 0xE3, 0x08])
    else:
      self.command(Psr, [uint8 0xEF, 0x08])
  else:
    if self.rotation == Rotate_0:
      self.command(Psr, [uint8 0xA3, 0x08])
    else:
      self.command(Psr, [uint8 0xAF, 0x08])
  self.command(Pwr, [uint8 0x37, 0x00, 0x23, 0x23])
  self.command(Pfs, [uint8 0x00,])
  self.command(Btst, [uint8 0xC7, 0xC7, 0x1D])
  self.command(Pll, [uint8 0x3C,])
  self.command(Tsc, [uint8 0x00,])
  self.command(Cdi, [uint8 0x37,])
  self.command(Tcon, [uint8 0x22,])
  self.command(Tres, dimensions)
  self.command(Pws, [uint8 0xAA,])
  sleepMs(100)
  self.command(Cdi, [uint8 0x37,])

proc setBlocking*(self: var Uc8159; blocking: bool) =
  self.blocking = blocking

proc powerOff*(self: var Uc8159) =
  self.busyWait()
  self.command(Pof)
  ##  turn off

proc data*(self: var Uc8159, len: uint; data: ptr uint8) =
  gpioPut(self.csPin, Low)
  gpioPut(self.dcPin, High)

  ##  data mode
  discard spiWriteBlocking(self.spi, data, len)
  gpioPut(self.csPin, High)

proc update*(self: var Uc8159, graphics: var PicoGraphics) =
  if graphics.penType != Pen3Bit:
    return
  if self.blocking:
    self.busyWait()
  self.setup()
  gpioPut(self.csPin, Low)
  var reg = Dtm1.uint8
  gpioPut(self.dcPin, Low)
  ##  command mode
  discard spiWriteBlocking(self.spi, reg.addr, 1)
  gpioPut(self.dcPin, High)
  ##  data mode
  ##  HACK: Output 48 rows of data since our buffer is 400px tall
  ##  but the display has no offset configuration and H/V scan
  ##  are reversed.
  ##  Any garbage data will do.
  ##  2px per byte, so we need width * 24 bytes
  if self.height == 400 and self.rotation == Rotate_0:
    discard spiWriteBlocking(self.spi, cast[ptr uint8](graphics.frameBuffer), self.width * 24)
  graphics.frameConvert(Pen_P4, (proc (buf: pointer; length: csize_t): auto =
    if length > 0:
      discard spiWriteBlocking(self.spi, cast[ptr uint8](buf), length)))
  gpioPut(self.csPin, High)
  self.busyWait()
  self.command(Pon)
  ##  turn on
  self.busyWait(200)
  self.command(Drf)
  ##  start display refresh
  self.busyWait(200)
  if self.blocking:
    self.busyWait(32 * 1000)
    self.command(Pof)
    ##  turn off
  else:
    self.timeout = makeTimeoutTimeMs(32 * 1000)
