import picostdlib/[pico/types, pico/platform]
import ../common/pimoroni_common, ../libraries/pico_graphics

export pico_graphics

type
  Uc8159* = object of DisplayDriver
    spi: ptr SpiInst
    csPin: Gpio
    dcPin: Gpio
    sckPin: Gpio
    mosiPin: Gpio
    busyPin: int8
    resetPin: Gpio
    timeout: AbsoluteTime
    blocking: bool
    borderColour: Colour

  Colour* = enum
    Black
    White
    Green
    Blue
    Red
    Yellow
    Orange
    Clean

  Reg = enum
    Psr   = 0x00
    Pwr   = 0x01
    Pof   = 0x02
    Pfs   = 0x03
    Pon   = 0x04
    Btst  = 0x06
    Dslp  = 0x07
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
    Pws   = 0xE3


proc init*(self: var Uc8159; width: uint16; height: uint16) =
  DisplayDriver(self).init(width, height)

  self.spi = spi0
  self.csPin = SpiBgFrontCs
  self.dcPin = 28.Gpio
  self.sckPin = SpiDefaultSck
  self.mosiPin = SpiDefaultMosi
  self.busyPin = PinUnused
  self.resetPin = 27.Gpio
  self.blocking = false
  self.borderColour = White

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
  if self.busyPin != PinUnused:
    gpioSetFunction(self.busyPin.Gpio, GpioFunction.Sio)
    gpioSetDir(self.busyPin.Gpio, In)
    gpioSetPulls(self.busyPin.Gpio, up=true, down=false)
  gpioSetFunction(self.sckPin, GpioFunction.Spi)
  gpioSetFunction(self.mosiPin, GpioFunction.Spi)

proc isBusy*(self: Uc8159): bool =
  if self.busyPin == PinUnused:
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

proc data*(self: var Uc8159, len: uint; data: varargs[uint8]) =
  gpioPut(self.csPin, Low)
  ##  data mode
  gpioPut(self.dcPin, High)

  discard spiWriteBlocking(self.spi, data)
  gpioPut(self.csPin, High)

proc command*(self: var Uc8159; reg: Reg; data: varargs[uint8]) =
  gpioPut(self.csPin, Low)
  ##  command mode
  gpioPut(self.dcPin, Low)
  discard spiWriteBlocking(self.spi, reg.uint8)
  if data.len > 0:
    ##  data mode
    gpioPut(self.dcPin, High)
    discard spiWriteBlocking(self.spi, data)
  gpioPut(self.csPin, High)

proc setup*(self: var Uc8159) =
  self.reset()
  self.busyWait()

  var psr = [uint8 0, 0x08]
  if self.width == 600:
    if self.rotation == Rotate_0:
      psr[0] = 0xE3
    else:
      psr[0] = 0xEF
  else:
    if self.rotation == Rotate_0:
      psr[0] = 0xA3
    else:
      psr[0] = 0xAF

  let tres = [
    uint8((self.width shr 8) and 0b11),
    uint8(self.width and 0b11111111),
    uint8((self.height shr 8) and 0b1),
    uint8(self.height and 0b11111111)
  ]

  let cdi = (self.borderColour.uint8 shl 5) or 0b1_0111 # DDX = 1, CDI = 10 (default)

  # Power Setting
  self.command(Pwr,
    0b1_1_0_1_1_1, # VCM_HZ = 0
    0b00, # VG_LVL = VGH=20V, VGL= -20V
    35, # VSHC_LVL = 10V
    35  # VSLC_LVL = -10V
  )

  # Booster Soft Start
  self.command(Btst,
    0b11_000_111, # Soft Start Phase Period = 40 ms, Driving Strength = (reserved), Minimum OFF Time = 6.77 us
    0b11_000_111, # Soft Start Phase Period = 40 ms, Driving Strength = (reserved), Minimum OFF Time = 6.77 us
    0b011_101 # Driving strength = 2, Minimum OFF Time = 1.61 us
  )

  # Panel Setting
  self.command(Psr, psr)

  # TCON resolution
  self.command(Tres, tres)

  # Vcom and data interval setting
  self.command(Cdi, cdi)

  # Power OFF Sequence Setting
  # self.command(Pfs, 0x00)


  # PLL control
  # self.command(Pll, 0b111_100) # Frame Rate = 50 Hz

  # TCON setting
  # self.command(Tcon, 0b0010_0010)

  # Temperature Sensor Command
  # self.command(Tsc, 0x00, 0x00)

  # Power Saving
  # self.command(Pws, 0b1010_1010)

  # sleepMs(100)

proc setBlocking*(self: var Uc8159; blocking: bool) =
  self.blocking = blocking

proc setBorder*(self: var Uc8159; colour: Colour) =
  self.borderColour = colour

proc powerOff*(self: var Uc8159) =
  self.busyWait()
  self.command(Pof)
  ##  turn off

method update*(self: var Uc8159; graphics: var PicoGraphics) =
  if graphics.penType != Pen_3Bit:
    return

  if self.blocking:
    self.busyWait()

  self.setup()

  gpioPut(self.csPin, Low)
  ##  command mode
  gpioPut(self.dcPin, Low)
  discard spiWriteBlocking(self.spi, Dtm1.uint8)

  ##  data mode
  gpioPut(self.dcPin, High)

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
