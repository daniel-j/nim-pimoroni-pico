import std/math

import picostdlib/hardware/spi
import picostdlib/hardware/dma
import picostdlib/hardware/pwm

import ../common/pimoroni_bus
import ./display_driver

import picostdlib/helpers

export pimoroni_bus, display_driver

proc builtin_bswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

# The ST7789 requires 16 ns between SPI rising edges.
# 16 ns = 62,500,000 Hz
# RP2350 doesn't support 62,500,000 so use 75,000,000 seems to work.
when picoRp2040:
  const spiBaud = 62_500_000
else:
  const spiBaud = 75_000_000

type
  St7789* = object of DisplayDriver
    spi*: ptr SpiInst
    round*: bool
    csPin*: Gpio
    dcPin*: Gpio
    wrSckPin*: Gpio
    rdSckPin*: GpioOptional
    d0Pin*: Gpio
    backlightPin*: GpioOptional
    stDma*: DmaChannel

  St7789Cmd = enum
    SWRESET   = 0x01
    TEOFF     = 0x34
    TEON      = 0x35
    MADCTL    = 0x36
    COLMOD    = 0x3A
    GCTRL     = 0xB7
    VCOMS     = 0xBB
    LCMCTRL   = 0xC0
    VDVVRHEN  = 0xC2
    VRHS      = 0xC3
    VDVS      = 0xC4
    FRCTRL2   = 0xC6
    PWCTRL1   = 0xD0
    UNKNOWN   = 0xD6
    PORCTRL   = 0xB2
    GMCTRP1   = 0xE0
    GMCTRN1   = 0xE1
    INVOFF    = 0x20
    SLPOUT    = 0x11
    DISPON    = 0x29
    GAMSET    = 0x26
    DISPOFF   = 0x28
    RAMWR     = 0x2C
    INVON     = 0x21
    CASET     = 0x2A
    RASET     = 0x2B
    PWMFRSEL  = 0xCC

  MadCtlEnum = enum
    ROW_ORDER   = 0b10000000
    COL_ORDER   = 0b01000000
    SWAP_XY     = 0b00100000  # AKA "MV"
    SCAN_ORDER  = 0b00010000
    RGB_BGR     = 0b00001000
    HORIZ_ORDER = 0b00000100

var caset: array[2, uint16]
var raset: array[2, uint16]
var madctl: uint8

proc setBacklight*(self: St7789; brightness: uint8) =
  # gamma correct the provided 0-255 brightness value onto a
  # 0-65535 range for the pwm counter
  if self.backlightPin == GpioUnused: return
  let gamma = 2.8
  let value = uint16(pow(brightness.float / 255, gamma) * 65535 + 0.5)
  Gpio(self.backlightPin).setPwmLevel(value)

proc command*(self: St7789; cmd: St7789Cmd; len: Natural; data: ptr uint8) =
  # echo "command ", cmd, " ", len, " ", not data.isNil
  # command mode
  self.dcPin.put(Low)

  self.csPin.put(Low)
  if not self.spi.isNil:
    discard self.spi.writeBlocking(cmd.uint8)
  # else:
  #   writeBlockingParallel(cmd, 1)
  if len > 0 and not data.isNil:
    # data mode
    self.dcPin.put(High)
    if not self.spi.isNil:
      discard self.spi.writeBlocking(data, len.csize_t)
    # else:
    #   writeBlockingParallel(data, len)
  self.csPin.put(High)

proc command(self: St7789; cmd: St7789Cmd; data: varargs[uint8]) =
  if data.len > 0:
    self.command(cmd, data.len, data[0].unsafeAddr)
  else:
    self.command(cmd, 0, nil)

proc configureDisplay(self: var St7789; rotate: Rotation) =
  if rotate == Rotate_90 or rotate == Rotate_270:
    swap self.width, self.height

  # 240x240 Square and Round LCD Breakouts
  if self.width == 240 and self.height == 240:
    var row_offset: uint16 = if self.round: 40 else: 80
    let col_offset: uint16 = 0

    case rotate:
    of Rotate_0:
      if not self.round: row_offset = 0
      caset[0] = col_offset
      caset[1] = self.width + col_offset - 1
      raset[0] = row_offset
      raset[1] = self.width + row_offset - 1
      madctl = HORIZ_ORDER.uint8

    of Rotate_90:
      if not self.round: row_offset = 0
      caset[0] = row_offset
      caset[1] = self.width + row_offset - 1
      raset[0] = col_offset
      raset[1] = self.width + col_offset - 1
      madctl = HORIZ_ORDER.uint8 or COL_ORDER.uint8 or SWAP_XY.uint8

    of Rotate_180:
      caset[0] = col_offset
      caset[1] = self.width + col_offset - 1
      raset[0] = row_offset
      raset[1] = self.width + row_offset - 1
      madctl = HORIZ_ORDER.uint8 or COL_ORDER.uint8 or ROW_ORDER.uint8

    of Rotate_270:
      caset[0] = row_offset
      caset[1] = self.width + row_offset - 1
      raset[0] = col_offset
      raset[1] = self.width + col_offset - 1
      madctl = ROW_ORDER.uint8 or SWAP_XY.uint8


  # Pico Display
  elif self.width == 240 or self.height == 135:
    caset[0] = 40   # 240 cols
    caset[1] = 40 + self.width - 1
    raset[0] = 52   # 135 rows
    raset[1] = 52 + self.height - 1
    if rotate == Rotate_0:
      raset[0] += 1
      raset[1] += 1

    madctl = (if rotate == Rotate_180: ROW_ORDER.uint8 else: COL_ORDER.uint8) or SWAP_XY.uint8 or SCAN_ORDER.uint8

  # Pico Display at 90 degree rotation
  elif self.width == 135 and self.height == 240:
    caset[0] = 52   # 135 cols
    caset[1] = 52 + self.width - 1
    raset[0] = 40   # 240 rows
    raset[1] = 40 + self.height - 1
    madctl = 0
    if rotate == Rotate_90:
      caset[0] += 1
      caset[1] += 1
      madctl = COL_ORDER.uint8 or ROW_ORDER.uint8


  # Pico Display 2.0
  elif self.width == 320 and self.height == 240:
    caset[0] = 0
    caset[1] = 319
    raset[0] = 0
    raset[1] = 239
    madctl = if rotate == Rotate_180 or rotate == Rotate_90: ROW_ORDER.uint8 else: COL_ORDER.uint8
    madctl = madctl or SWAP_XY.uint8 or SCAN_ORDER.uint8

  # Pico Display 2.0 at 90 degree rotation
  elif self.width == 240 and self.height == 320:
    caset[0] = 0
    caset[1] = 239
    raset[0] = 0
    raset[1] = 319
    madctl = if rotate == Rotate_180 or rotate == Rotate_90: COL_ORDER.uint8 or ROW_ORDER.uint8 else: 0

  # Byte swap the 16bit rows/cols values
  caset[0] = builtin_bswap16(caset[0])
  caset[1] = builtin_bswap16(caset[1])
  raset[0] = builtin_bswap16(raset[0])
  raset[1] = builtin_bswap16(raset[1])

  self.command(CASET, 4, cast[ptr uint8](caset.addr))
  self.command(RASET, 4, cast[ptr uint8](raset.addr))
  self.command(MADCTL, madctl)

proc commonInit(self: var St7789) =
  self.dcPin.setFunction(Sio)
  self.dcPin.setDir(Out)

  self.csPin.setFunction(Sio)
  self.csPin.setDir(Out)

  if self.backlightPin != GpioUnused:
    let bl = Gpio(self.backlightPin)
    let sliceNum = bl.toPwmSliceNum()
    var cfg = pwmGetDefaultConfig()
    sliceNum.setWrap(65535)
    sliceNum.init(cfg.addr, true)
    bl.setFunction(Pwm)
    self.setBacklight(0) # Turn backlight off initially to avoid nasty surprises

  self.command(SWRESET)

  sleepMs(150)

  # Common init
  self.command(TEON)  # enable frame sync signal if used
  self.command(COLMOD, 0x05)  # 16 bits per pixel

  self.command(PORCTRL, 0x0c, 0x0c, 0x00, 0x33, 0x33)
  self.command(LCMCTRL, 0x2c)
  self.command(VDVVRHEN, 0x01)
  self.command(VRHS, 0x12)
  self.command(VDVS, 0x20)
  self.command(PWCTRL1, 0xa4, 0xa1)
  self.command(FRCTRL2, 0x0f)

  if self.width == 240 and self.height == 240:
    self.command(GCTRL, 0x14)
    self.command(VCOMS, 0x37)
    self.command(GMCTRP1, 0xD0, 0x04, 0x0D, 0x11, 0x13, 0x2B, 0x3F, 0x54, 0x4C, 0x18, 0x0D, 0x0B, 0x1F, 0x23)
    self.command(GMCTRN1, 0xD0, 0x04, 0x0C, 0x11, 0x13, 0x2C, 0x3F, 0x44, 0x51, 0x2F, 0x1F, 0x1F, 0x20, 0x23)

  elif self.width == 320 and self.height == 240:
    self.command(GCTRL, 0x35)
    self.command(VCOMS, 0x1f)
    self.command(GMCTRP1, 0xD0, 0x08, 0x11, 0x08, 0x0C, 0x15, 0x39, 0x33, 0x50, 0x36, 0x13, 0x14, 0x29, 0x2D)
    self.command(GMCTRN1, 0xD0, 0x08, 0x10, 0x08, 0x06, 0x06, 0x39, 0x44, 0x51, 0x0B, 0x16, 0x14, 0x2F, 0x31)

  elif self.width == 240 and self.height == 135: # Pico Display Pack (1.14" 240x135)
    self.command(VRHS, 0x00) # VRH Voltage settig
    self.command(GCTRL, 0x75) # VGH and VGL voltags
    self.command(VCOMS, 0x3D) # VCOM voltae
    self.command(UNKNOWN, 0xa1) # ??
    self.command(GMCTRP1, 0x70, 0x04, 0x08, 0x09, 0x09, 0x05, 0x2A, 0x33, 0x41, 0x07, 0x13, 0x13, 0x29, 0x2f)
    self.command(GMCTRN1, 0x70, 0x03, 0x09, 0x0A, 0x09, 0x06, 0x2B, 0x34, 0x41, 0x07, 0x12, 0x14, 0x28, 0x2E)


  self.command(INVON)   # set inversion mode
  self.command(SLPOUT)  # leave sleep mode
  self.command(DISPON)  # turn display on

  # sleepMs(100)

  self.configureDisplay(self.rotation)

  # if self.backlightPin != GpioUnused:
  #   #update() # Send the new buffer to the display to clear any previous content
  #   sleepMs(50) # Wait for the update to apply
  #   self.setBacklight(255) # Turn backlight on now surprises have passed

# serial init
proc init*(self: var St7789; width: uint16; height: uint16; rotation: Rotation; round: bool; pins: SpiPins) =
  DisplayDriver(self).init(width, height, rotation)
  self.spi = pins.spi
  self.round = round
  self.csPin = pins.cs
  self.dcPin = pins.dc
  self.wrSckPin = pins.sck
  self.rdSckPin = GpioUnused
  self.d0Pin = pins.mosi
  self.backlightPin = pins.bl

  discard self.spi.init(spiBaud)

  self.wrSckPin.setFunction(Spi)
  self.d0Pin.setFunction(Spi)

  self.stDma = dmaClaimUnusedChannel(true).DmaChannel
  var config = self.stDma.getDefaultConfig()
  config.addr.setTransferDataSize(DmaSize8)
  config.addr.setBswap(false)
  config.addr.setDreq(self.spi.getDreq(true))
  self.stDma.configure(config.addr, self.spi.getHw().dr.addr, nil, 0, false)

  self.commonInit()


proc update*(self: St7789; graphics: PicoGraphicsPenRgb565) =
  let cmd = RAMWR

  # Display buffer is screen native
  self.command(cmd, self.width.int * self.height.int * sizeof(Rgb565), cast[ptr uint8](graphics.frameBuffer))
