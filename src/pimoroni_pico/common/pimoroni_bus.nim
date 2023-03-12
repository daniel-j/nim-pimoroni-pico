import ./pimoroni_common
export pimoroni_common

type
  SPIPins* = object
    spi*: ptr SpiInst
    cs*: Gpio
    sck*: Gpio
    mosi*: Gpio
    miso*: Gpio
    dc*: Gpio
    bl*: Gpio

  ParallelPins* = object
    cs*: Gpio
    dc*: Gpio
    wrSck*: Gpio
    rdSck*: Gpio
    d0*: Gpio
    bl*: Gpio
