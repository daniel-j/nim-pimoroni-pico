import ./eink_driver
export eink_driver

type
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

converter toEinkReg(reg: Reg): EinkReg = reg.EinkReg

proc initUc8159*(self: var EinkDriver; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  assert self.kind == KindUc8159
  self.spi = pins.spi
  self.csPin = pins.cs
  self.sckPin = pins.sck
  self.dcPin = pins.dc
  self.mosiPin = pins.mosi

  self.isBusyProc = isBusyProc
  self.resetPin = resetPin

  self.setBlocking(blocking)
  self.setBorder(White)

  ##  configure spi interface and pins
  echo "Eink Uc8159 SPI init: ", self.spi.init(20_000_000)

  self.dcPin.setFunction(Sio)
  self.dcPin.setDir(Out)

  self.csPin.setFunction(Sio)
  self.csPin.setDir(Out)
  self.csPin.put(High)

  self.resetPin.setFunction(Sio)
  self.resetPin.setDir(Out)
  self.resetPin.put(High)

  self.sckPin.setFunction(Spi)
  self.mosiPin.setFunction(Spi)

proc reset(self: var EinkDriver) =
  self.resetPin.put(Low)
  sleepMs(10)
  self.resetPin.put(High)
  sleepMs(10)
  self.busyWait()

proc setup(self: var EinkDriver) =
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

  let cdi = (self.getBorder().uint8 shl 5) or 0b1_0111 # DDX = 1, CDI = 10 (default)

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

proc powerOffUc8159*(self: var EinkDriver) =
  self.busyWait()
  self.command(Pof) ##  turn off

proc updateUc8159*(self: var EinkDriver; graphics: var PicoGraphicsPen3Bit) =

  if self.getBlocking():
    self.busyWait()

  self.setup()

  self.csPin.put(Low)

  self.dcPin.put(Low) ##  command mode
  discard self.spi.writeBlocking(Dtm1.uint8)

  self.dcPin.put(High) ##  data mode

  ## HACK: Output 48 rows of data since our buffer is 400px tall
  ##  but the display has no offset configuration and H/V scan
  ##  are reversed.
  ## Any garbage data will do.
  ##  2px per byte, so we need width * 24 bytes
  if self.height == 400 and self.rotation == Rotate_0:
    discard self.spi.writeBlocking(cast[ptr uint8](graphics.frameBuffer), self.width * 24)

  let spiPtr = self.spi
  let csPin = self.csPin
  csPin.put(High)
  graphics.frameConvert(PicoGraphicsPenP4, (proc (buf: pointer; length: uint) =
    if length > 0:
      csPin.put(Low)
      discard spiPtr.writeBlocking(cast[ptr uint8](buf), length.csize_t)
      csPin.put(High)
  ))

  self.csPin.put(High)

  self.busyWait()

  self.command(Pon, 0) ##  turn on
  self.busyWait(170)

  self.command(Drf, 0) ##  start display refresh

  if self.getBlocking():
    self.busyWait(28 * 1000)
    self.command(Pof) ##  turn off
  else:
    self.timeout = makeTimeoutTimeMs(28 * 1000)
