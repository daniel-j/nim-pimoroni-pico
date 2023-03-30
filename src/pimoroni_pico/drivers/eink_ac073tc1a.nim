import ./eink_driver
export eink_driver

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
    Tsset = 0xE6

proc initAc073tc1a*(self: var EinkDriver; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  self.spi = pins.spi
  self.csPin = pins.cs
  self.sckPin = pins.sck
  self.dcPin = pins.dc
  self.mosiPin = pins.mosi

  self.isBusyProc = isBusyProc
  self.resetPin = resetPin

  self.blocking = blocking

  ##  configure spi interface and pins
  echo "Eink Ac073tc1a SPI init: ", spiInit(self.spi, 20_000_000)

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

proc reset(self: var EinkDriver) =
  gpioPut(self.resetPin, Low)
  sleepMs(10)
  gpioPut(self.resetPin, High)
  sleepMs(10)
  self.busyWait()

proc command(self: var EinkDriver; reg: Reg; data: varargs[uint8]) =
  self.command(reg.uint8, data)

proc setup(self: var EinkDriver) =
  assert(self.width == 800 and self.height == 480, "Panel size must be 800x480!")

  self.reset()
  self.busyWait()

  let cdi = (self.borderColour.uint8 shl 5) or 0b11111

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
  self.command(Cdi, cdi)
  self.command(Tcon, 0x02, 0x00)
  self.command(Tres, 0x03, 0x20, 0x01, 0xE0)
  self.command(Vdcs, 0x1E)
  self.command(TVdcs, 0x00)
  self.command(Agid, 0x00)
  self.command(Pws, 0x2F)
  self.command(Ccset, 0x00)
  self.command(Tsset, 0x00)

proc powerOffAc073tc1a*(self: var EinkDriver) =
  self.busyWait()
  self.command(Pof) ##  turn off

proc updateAc073tc1a*(self: var EinkDriver; graphics: var PicoGraphics) =
  if graphics.penType != Pen_P3:
    return

  if self.blocking:
    self.busyWait()

  self.setup()

  gpioPut(self.csPin, Low)

  gpioPut(self.dcPin, Low) ##  command mode
  discard spiWriteBlocking(self.spi, Dtm1.uint8)

  gpioPut(self.dcPin, High) ##  data mode

  let spiPtr = self.spi
  let csPin = self.csPin
  gpioPut(csPin, High) # ???
  graphics.frameConvert(Pen_P4, (proc (buf: pointer; length: uint) =
    if length > 0:
      gpioPut(csPin, Low)
      discard spiWriteBlocking(spiPtr, cast[ptr uint8](buf), length.csize_t)
      gpioPut(csPin, High)
  ))

  gpioPut(self.dcPin, Low) ##  data mode

  gpioPut(self.csPin, High)

  self.busyWait()

  self.command(Pon, 0) ##  turn on
  self.busyWait(170)

  self.command(Drf, 0) ##  start display refresh

  if self.blocking:
    self.busyWait(28 * 1000)
    self.command(Pof) ##  turn off
  else:
    self.timeout = makeTimeoutTimeMs(28 * 1000)
