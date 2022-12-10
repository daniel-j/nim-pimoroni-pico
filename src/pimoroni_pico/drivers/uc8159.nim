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


proc isBusy*(this: Uc8159): bool =
  if this.busyPin.int == PinUnused:
    if absoluteTimeDiffUs(getAbsoluteTime(), this.timeout) > 0:
      return true
    else:
      return false
  return not gpioGet(this.busyPin.Gpio).bool

proc busyWait*(this: var Uc8159, minimumWaitMs: uint32 = 0) =
  this.timeout = makeTimeoutTimeMs(minimumWaitMs)
  while this.isBusy():
    tightLoopContents()

proc reset*(this: var Uc8159) =
  gpioPut(this.resetPin, Low)
  sleepMs(10)
  gpioPut(this.resetPin, High)
  sleepMs(10)
  this.busyWait()

proc command*(this: var Uc8159; reg: Reg; data: openArray[uint8] = []) =
  gpioPut(this.csPin, Low)
  gpioPut(this.dcPin, Low)
  var regNum = reg.uint8
  ##  command mode
  discard spiWriteBlocking(this.spi, regNum.addr, 1)
  if data.len > 0:
    gpioPut(this.dcPin, High)
    ##  data mode
    discard spiWriteBlocking(this.spi, cast[ptr uint8](data.unsafeAddr), data.len.csize_t)
  gpioPut(this.csPin, High)

proc init*(this: var Uc8159) =
  this.spi = spi0
  this.csPin = SpiBgFrontCs
  this.dcPin = 28.Gpio
  this.sckPin = SpiDefaultSck
  this.mosiPin = SpiDefaultMosi
  this.busyPin = PinUnused
  this.resetPin = 27.Gpio
  this.blocking = false
  ##  configure spi interface and pins
  discard spiInit(this.spi, 3_000_000.cuint)
  gpioSetFunction(this.dcPin, GpioFunction.Sio)
  gpioSetDir(this.dcPin, Out)
  gpioSetFunction(this.csPin, GpioFunction.Sio)
  gpioSetDir(this.csPin, Out)
  gpioPut(this.csPin, High)
  gpioSetFunction(this.resetPin, GpioFunction.Sio)
  gpioSetDir(this.resetPin, Out)
  gpioPut(this.resetPin, High)
  gpioSetFunction(this.busyPin.Gpio, GpioFunction.Sio)
  gpioSetDir(this.busyPin.Gpio, In)
  gpioSetPulls(this.busyPin.Gpio, up=true, down=false)
  gpioSetFunction(this.sckPin, GpioFunction.Spi)
  gpioSetFunction(this.mosiPin, GpioFunction.Spi)

proc setup*(this: var Uc8159) =
  this.reset()
  this.busyWait()
  var dimensions = [uint8(this.width shr 8),  uint8(this.width),
                    uint8(this.height shr 8), uint8(this.height)]
  if this.width == 600:
    if this.rotation == Rotate_0:
      this.command(Psr, [uint8 0xE3, 0x08])
    else:
      this.command(Psr, [uint8 0xEF, 0x08])
  else:
    if this.rotation == Rotate_0:
      this.command(Psr, [uint8 0xA3, 0x08])
    else:
      this.command(Psr, [uint8 0xAF, 0x08])
  this.command(Pwr, [uint8 0x37, 0x00, 0x23, 0x23])
  this.command(Pfs, [uint8 0x00,])
  this.command(Btst, [uint8 0xC7, 0xC7, 0x1D])
  this.command(Pll, [uint8 0x3C,])
  this.command(Tsc, [uint8 0x00,])
  this.command(Cdi, [uint8 0x37,])
  this.command(Tcon, [uint8 0x22,])
  this.command(Tres, dimensions)
  this.command(Pws, [uint8 0xAA,])
  sleepMs(100)
  this.command(Cdi, [uint8 0x37,])

proc setBlocking*(this: var Uc8159; blocking: bool) =
  this.blocking = blocking

proc powerOff*(this: var Uc8159) =
  this.busyWait()
  this.command(Pof)
  ##  turn off

proc data*(this: var Uc8159, len: uint; data: ptr uint8) =
  gpioPut(this.csPin, Low)
  gpioPut(this.dcPin, High)

  ##  data mode
  discard spiWriteBlocking(this.spi, data, len)
  gpioPut(this.csPin, High)

proc update*(this: var Uc8159, graphics: var PicoGraphics) =
  if graphics.penType != Pen3Bit:
    return
  if this.blocking:
    this.busyWait()
  this.setup()
  gpioPut(this.csPin, Low)
  var reg = Dtm1.uint8
  gpioPut(this.dcPin, Low)
  ##  command mode
  discard spiWriteBlocking(this.spi, reg.addr, 1)
  gpioPut(this.dcPin, High)
  ##  data mode
  ##  HACK: Output 48 rows of data since our buffer is 400px tall
  ##  but the display has no offset configuration and H/V scan
  ##  are reversed.
  ##  Any garbage data will do.
  ##  2px per byte, so we need width * 24 bytes
  if this.height == 400 and this.rotation == Rotate_0:
    discard spiWriteBlocking(this.spi, cast[ptr uint8](graphics.frameBuffer), this.width * 24)
  graphics.frameConvert(Pen_P4, (proc (buf: pointer; length: csize_t): auto =
    if length > 0:
      discard spiWriteBlocking(this.spi, cast[ptr uint8](buf), length)))
  gpioPut(this.csPin, High)
  this.busyWait()
  this.command(Pon)
  ##  turn on
  this.busyWait(200)
  this.command(Drf)
  ##  start display refresh
  this.busyWait(200)
  if this.blocking:
    this.busyWait(32 * 1000)
    this.command(Pof)
    ##  turn off
  else:
    this.timeout = makeTimeoutTimeMs(32 * 1000)
