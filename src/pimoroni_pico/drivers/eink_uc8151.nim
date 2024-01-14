import std/endians
import ./eink_driver
export eink_driver

# Datasheet
# https://www.orientdisplay.com/wp-content/uploads/2022/09/UC8151C.pdf

type
  Reg = enum
    PSR      = 0x00
    PWR      = 0x01
    POF      = 0x02
    PFS      = 0x03
    PON      = 0x04
    PMES     = 0x05
    BTST     = 0x06
    DSLP     = 0x07
    DTM1     = 0x10
    DSP      = 0x11
    DRF      = 0x12
    DTM2     = 0x13
    LUT_VCOM = 0x20
    LUT_WW   = 0x21
    LUT_BW   = 0x22
    LUT_WB   = 0x23
    LUT_BB   = 0x24
    PLL      = 0x30
    TSC      = 0x40
    TSE      = 0x41
    TSW      = 0x42
    TSR      = 0x43
    CDI      = 0x50
    LPD      = 0x51
    TCON     = 0x60
    TRES     = 0x61
    REV      = 0x70
    FLG      = 0x71
    AMV      = 0x80
    VV       = 0x81
    VDCS     = 0x82
    PTL      = 0x90
    PTIN     = 0x91
    PTOU     = 0x92
    PGM      = 0xa0
    APG      = 0xa1
    ROTP     = 0xa2
    CCSET    = 0xe0
    PWS      = 0xe3
    TSSET    = 0xe5

  PsrResolution = enum
    Res_96x230   = 0b00
    Res_96x252   = 0b01
    Res_128x296  = 0b10
    Res_160x296  = 0b11

  PsrOptions {.packed.} = object
    resetNone {.bitsize: 1.}: bool
    boosterOn {.bitsize: 1.}: bool
    shiftRight {.bitsize: 1.}: bool
    scanUp {.bitsize: 1.}: bool
    formatBw {.bitsize: 1.}: bool
    lutReg {.bitsize: 1.}: bool
    resolution {.bitsize: 2.}: PsrResolution

  PwrVghlLv = enum
    Vghl_16V = 0b00
    Vghl_15V = 0b01
    Vghl_14V = 0b10
    Vghl_13V = 0b11

  PwrOptionsPowerSel = range[0'u8 .. 0b101011'u8]

  PwrOptions {.packed.} = object
    vdgEn {.bitsize: 1.}: bool
    vdsEn {.bitsize: 1.}: bool

    vghlLv {.bitsize: 2, align: 1.}: PwrVghlLv
    vcomHv {.bitsize: 1.}: bool

    vdh: PwrOptionsPowerSel
    vdl: PwrOptionsPowerSel
    vdhr: PwrOptionsPowerSel

  BtstOffTime = enum
    OffTime_0_27us = 0b000
    OffTime_0_34us = 0b001
    OffTime_0_40us = 0b010
    OffTime_0_54us = 0b011
    OffTime_0_80us = 0b100
    OffTime_1_54us = 0b101
    OffTime_3_34us = 0b110
    OffTime_6_58us = 0b111

  BtstStrength = enum
    Strength_1 = 0b000
    Strength_2 = 0b001
    Strength_3 = 0b010
    Strength_4 = 0b011
    Strength_5 = 0b100
    Strength_6 = 0b101
    Strength_7 = 0b110
    Strength_8 = 0b111

  BtstStart = enum
    Start_10ms = 0b00
    Start_20ms = 0b01
    Start_30ms = 0b10
    Start_40ms = 0b11

  BtstOptions {.packed.} = object
    offTimeA {.bitsize: 3.}: BtstOffTime
    strengthA {.bitsize: 3.}: BtstStrength
    startA {.bitsize: 2.}: BtstStart

    offTimeB {.bitsize: 3, align: 1.}: BtstOffTime
    strengthB {.bitsize: 3.}: BtstStrength
    startB {.bitsize: 2.}: BtstStart

    offTimeC {.bitsize: 3, align: 1.}: BtstOffTime
    strengthC {.bitsize: 3.}: BtstStrength

  PfsTimeOff {.size: 1.} = enum
    Frames_1  = 0b00000000
    Frames_2  = 0b00010000
    Frames_3  = 0b00100000
    Frames_4  = 0b00110000

  PllFreq {.size: 1.} = enum
    ## other frequency options exist but there doesn't seem to be much
    ## point in including them - this is a fair range of options...
    Pll_200Hz     = 0b00111001
    Pll_100Hz     = 0b00111010
    Pll_67Hz      = 0b00111011
    Pll_50Hz      = 0b00111100
    Pll_40Hz      = 0b00111101
    Pll_33Hz      = 0b00111110
    Pll_29Hz      = 0b00111111

  CdiOptions {.packed.} = object
    cdi {.bitsize: 4.}: range[0'u8 .. 0b1111'u8]
    ddx {.bitsize: 2.}: range[0'u8 .. 0b11'u8]
    vbd {.bitsize: 2.}: range[0'u8 .. 0b11'u8]

  PtlOptions {.packed.} = object
    hrStart: uint8  # lower 3 bits ignored
    hrEnd: uint8    # lower 3 bits 0b111
    vrStart: uint16 # big endian
    vrEnd: uint16   # big endian
    ptScan {.bitsize: 1.}: bool

  Uc8151* = object of EinkDriver
    updateSpeed*: uint8
    inverted*: bool
    bwr*: bool

converter toEinkReg(reg: Reg): EinkReg = reg.EinkReg

proc reset(self: var Uc8151) =
  self.resetPin.put(Low)
  sleepMs(10)
  self.resetPin.put(High)
  sleepMs(10)
  self.busyWait()

proc setup*(self: var Uc8151) =
  self.reset()
  self.busyWait()

  var psr = cast[PsrOptions](0b00001111)
  psr.resolution = Res_128x296
  psr.formatBw = not self.bwr
  psr.boosterOn = true
  psr.resetNone = true

  if self.rotation == Rotate_0:
    psr.shiftRight = true
    psr.scanUp = false
  elif self.rotation == Rotate_180:
    psr.shiftRight = false
    psr.scanUp = true

  self.command(Psr, sizeof(psr), cast[ptr uint8](psr.addr))

  # case self.updateSpeed:
  # of 1: self.mediumLuts()
  # of 2: self.fastLuts()
  # of 3: self.turboLuts()
  # else: discard

  var pwr = cast[PwrOptions](0b00000011_00100110_00100110_00000000_00000011)
  pwr.vdsEn = true
  pwr.vdgEn = true
  pwr.vcomHv = false
  pwr.vghlLv = Vghl_16V
  pwr.vdh = 0b101011
  pwr.vdl = 0b101011
  pwr.vdhr = if psr.formatBw: 0b000011 else: 0b101011
  self.command(Pwr, sizeof(pwr), cast[ptr uint8](pwr.addr))

  self.command(Pon) # power on
  self.busyWait()

  # booster soft start configuration
  var btst = cast[BtstOptions](0b00010111_00010111_00010111)
  btst.startA = Start_10ms
  btst.startB = Start_10ms
  btst.strengthA = Strength_3
  btst.strengthB = Strength_3
  btst.strengthC = Strength_3
  btst.offTimeA = OffTime_6_58us
  btst.offTimeB = OffTime_6_58us
  btst.offTimeC = OffTime_6_58us
  self.command(Btst, sizeof(btst), cast[ptr uint8](btst.addr))

  self.command(Pfs, Frames_1.uint8)

  self.command(Tse, 0)

  self.command(Tcon, 0b0010_0010) # tcon setting

  # vcom and data interval
  var cdi = cast[CdiOptions](0b01_00_0111)
  cdi.cdi = 0b1100
  cdi.ddx = if self.inverted: 0b01 else: 0b00
  cdi.vbd = if self.getBorder() == White: 0b10 else: 0b01
  self.command(Cdi, sizeof(cdi), cast[ptr uint8](cdi.addr))

  self.command(Pll, Pll_100Hz.uint8)

  self.command(Pof)
  self.busyWait()

proc initUc8151*(self: var Uc8151; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  assert self.kind == KindUc8151
  self.spi = pins.spi
  self.csPin = pins.cs
  self.sckPin = pins.sck
  self.dcPin = pins.dc
  self.mosiPin = pins.mosi

  self.isBusyProc = isBusyProc
  self.resetPin = resetPin

  self.inverted = true

  self.setBlocking(blocking)
  self.setBorder(White)

  ##  configure spi interface and pins
  # set clock speed to 12MHz to reduce the maximum current draw on the
  # battery. when updating a small, monochrome, display only every few
  # seconds or so then you don't need much processing power anyway...
  echo "Eink Uc8151 SPI init: ", self.spi.init(12_000_000)

  self.dcPin.setFunction(Sio)
  self.dcPin.setDir(Out)

  self.csPin.setFunction(Sio)
  self.csPin.setDir(Out)
  self.csPin.put(High)

  self.resetPin.setFunction(Sio)
  self.resetPin.setDir(Out)
  self.resetPin.put(High)

  # Busy detection is handled externally

  self.sckPin.setFunction(Spi)
  self.mosiPin.setFunction(Spi)

  self.setup()


proc powerOffUc8151*(self: var Uc8151) =
  self.busyWait()
  self.command(Pof) ##  turn off

proc setUpdateSpeed*(self: var Uc8151; updateSpeed: uint8): bool =
  self.updateSpeed = updateSpeed
  self.setup()
  return true

proc updateTime*(self: Uc8151): uint =
  case self.updateSpeed:
  of 1: return 2000
  of 2: return 800
  of 3: return 250
  else: return 4500

proc partialUpdateUc8151*(self: var Uc8151; graphics: var PicoGraphicsPen1Bit; region: Rect) =
  # region.y is given in columns ("banks"), which are groups of 8 horiontal pixels
  # region.x is given in pixels

  var fb = cast[ptr UncheckedArray[uint8]](graphics.frameBuffer[0].addr)
  if self.getBlocking():
    self.busyWait()

  let cols = region.h div 8
  let y1 = region.y div 8
  let rows = region.w
  let x1 = region.x

  var ptl = PtlOptions()
  ptl.hrStart = uint8 region.y
  ptl.hrEnd = uint8 region.y + region.h - 1
  var vrStart: uint16 = uint16 region.x
  var vrEnd: uint16 = uint16 region.x + region.w - 1
  bigEndian16(ptl.vrStart.addr, vrStart.addr)
  bigEndian16(ptl.vrEnd.addr, vrEnd.addr)
  ptl.ptScan = true

  self.command(Pon) # turn on
  self.command(Ptin) # enable partial mode
  self.command(Ptl, sizeof(ptl), cast[ptr uint8](ptl.addr))

  self.command(Dtm2)
  # TODO: send partial data
  self.command(Dsp) # data start
  self.command(Drf) # start display refresh

  # disable partial window???

  if self.getBlocking():
    self.powerOffUc8151()

proc updateUc8151*(self: var Uc8151; graphics: var PicoGraphicsPen1Bit) =

  if self.getBlocking():
    self.busyWait()

  self.command(Pon) # turn on

  self.command(Ptou) # disable partial mode

  self.command(Dtm2, graphics.frameBuffer.len, graphics.frameBuffer[0].addr) # transmit framebuffer
  self.command(Dsp) # data stop

  self.command(Drf) # start display refresh

  if self.getBlocking():
    self.powerOffUc8151()
