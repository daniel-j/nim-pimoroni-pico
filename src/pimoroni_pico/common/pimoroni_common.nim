import picostdlib/[
  hardware/i2c, hardware/spi, hardware/gpio,
  pico/time
]

export i2c, spi, gpio, time

let
  PimoroniI2cDefaultInstance* = i2c0
  PimoroniSpiDefaultInstance* = spi0

const
  ## I2C
  I2cDefaultBaudrate* = 400_000
  I2cDefaultSda* = 20.Gpio
  I2cDefaultScl* = 21.Gpio
  I2cDefaultInt* = 22.Gpio
  I2cBgSda* = 4.Gpio
  I2cBgScl* = 5.Gpio
  I2cBgInt* = 3.Gpio
  I2cHeaderSda* = 20.Gpio
  I2cHeaderScl* = 21.Gpio
  I2cHeaderInt* = 19.Gpio

  ## SPI
  SpiDefaultMosi* = 19.Gpio # DefaultSpiTxPin
  SpiDefaultMiso* = 16.Gpio # DefaultSpiRxPin
  SpiDefaultDc* = 16.Gpio
  SpiDefaultSck* = 18.Gpio  # DefaultSpiSckPin
  SpiBgFrontPwm* = 20.Gpio
  SpiBgFrontCs* = 17.Gpio   # DefaultSpiCsnPin
  SpiBgBackPwm* = 21.Gpio
  SpiBgBackCs* = 22.Gpio

type
  BgSpiSlot* {.pure.} = enum
    Front, Back, PicoExplorerOnboard

  Board* {.pure.} = enum
    BreakoutGarden, PicoExplorer, PlasmaStick, Plasma2040, Interstate75,
    Servo2040, Motor2040

  Rotation* {.pure.} = enum
    Rotate_0 = 0, Rotate_90 = 90, Rotate_180 = 180, Rotate_270 = 270

  Polarity* {.pure.} = enum
    ActiveLow = 0, ActiveHigh = 1

  # Direction* {.pure.} = enum
  #   NormalDir = 0, ReversedDir = 1

##  Template to return a value clamped between a minimum and maximum
# template clamp*(a, mn, mx: untyped): untyped =
#   (if (a) < (mx): (if (a) > (mn): (a) else: (mn)) else: (mx))

proc millis*(): uint32 {.inline.} = toMsSinceBoot(getAbsoluteTime())
