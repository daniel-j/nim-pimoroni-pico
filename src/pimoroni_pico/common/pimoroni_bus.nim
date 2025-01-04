import ./pimoroni_common
export pimoroni_common

type
  SpiPins* = object
    spi*: ptr SpiInst
    cs*: Gpio
    sck*: Gpio
    mosi*: Gpio
    miso*: GpioOptional
    dc*: Gpio
    bl*: GpioOptional

  ParallelPins* = object
    cs*: Gpio
    dc*: Gpio
    wrSck*: Gpio
    rdSck*: GpioOptional
    d0*: Gpio
    bl*: GpioOptional

proc getSpiPins*(slot: BgSpiSlot = Front): SpiPins =
  case slot:
  of PicoExplorerOnboard:
    return SpiPins(spi: PimoroniSpiDefaultInstance, cs: SPI_BG_FRONT_CS, sck: SPI_DEFAULT_SCK, mosi: SPI_DEFAULT_MOSI, miso: GpioUnused, dc: SPI_DEFAULT_DC, bl: GpioUnused)
  of Front:
    return SpiPins(spi: PimoroniSpiDefaultInstance, cs: SPI_BG_FRONT_CS, sck: SPI_DEFAULT_SCK, mosi: SPI_DEFAULT_MOSI, miso: GpioUnused, dc: SPI_DEFAULT_DC, bl: GpioOptional(SPI_BG_FRONT_PWM))
  of Back:
    return SpiPins(spi: PimoroniSpiDefaultInstance, cs: SPI_BG_BACK_CS, sck: SPI_DEFAULT_SCK, mosi: SPI_DEFAULT_MOSI, miso: GpioUnused, dc: SPI_DEFAULT_DC, bl: GpioOptional(SPI_BG_BACK_PWM))
