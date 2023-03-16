import picostdlib
import picostdlib/hardware/spi
import ../common/[pimoroni_common, pimoroni_bus]
import ../libraries/pico_graphics
from ./uc8159 import Colour

type
  PsRamDisplay* = object
    spi: ptr SpiInst
    pinCs: Gpio
    pinSck: Gpio
    pinMosi: Gpio
    pinMiso: Gpio
    startAddress: uint32
    width, height: uint16
    timeout: AbsoluteTime
    blocking: bool

  Reg = enum
    Write = 0x02
    Read = 0x03
    ResetEnable = 0x66
    Reset = 0x99

proc init(self: var PsRamDisplay) =
  let baud = spiInit(self.spi, 31_250_000)
  echo "PsRam connected at ", baud
  gpioSetFunction(self.pinCs, Sio)
  gpioSetDir(self.pinCs, Out)
  gpioPut(self.pinCs, High)

  gpioSetFunction(self.pinSck, Spi)
  gpioSetFunction(self.pinMosi, Spi)
  gpioSetFunction(self.pinMiso, Spi)

  gpioPut(self.pinCs, Low)
  var commandBuffer = [ResetEnable.uint8, Reset.uint8]
  discard spiWriteBlocking(self.spi, commandBuffer[0].addr, commandBuffer.len.csize_t)
  gpioPut(self.pinCs, High)

proc init*(self: var PsRamDisplay; width, height: uint16; pins: SpiPins = SpiPins(spi: spiDefault, cs: 3.Gpio, sck: SpiDefaultSck, mosi: SpiDefaultMosi, miso: SpiDefaultMiso)) =
  self.spi = pins.spi
  self.pinCs = pins.cs
  self.pinSck = pins.sck
  self.pinMosi = pins.mosi
  self.pinMiso = pins.miso
  self.width = width
  self.height = height
  self.init()

proc write(self: PsRamDisplay; address: uint32; len: uint; data: ptr uint8 | uint8) =
  gpioPut(self.pinCs, Low)
  let commandBuffer = [Write.uint8, uint8 (address shr 16) and 0xFF, uint8 (address shr 8) and 0xFF, uint8 address and 0xFF]
  discard spiWriteBlocking(self.spi, commandBuffer[0].unsafeAddr, commandBuffer.len.csize_t)
  when data is ptr uint8:
    # TODO: implement SpiSetBlocking instead?
    discard spiWriteBlocking(self.spi, data, len.csize_t)
  else:
    discard spiWriteBlocking(self.spi, data.unsafeAddr, 1)
  gpioPut(self.pinCs, High)

proc read(self: PsRamDisplay; address: uint32; len: uint; data: ptr uint8) =
  gpioPut(self.pinCs, Low)
  var commandBuffer = [Write.uint8, uint8 (address shr 16) and 0xFF, uint8 (address shr 8) and 0xFF, uint8 address and 0xFF]
  discard spiWriteBlocking(self.spi, commandBuffer[0].addr, commandBuffer.len.csize_t)
  discard spiReadBlocking(self.spi, 0, data, len.csize_t)
  gpioPut(self.pinCs, High)

proc pointToAddress(self: PsRamDisplay; p: Point): uint32 =
  return self.startAddress + (p.y.uint32 * self.width) + p.x.uint32

proc writePixel*(self: PsRamDisplay; p: Point; colour: Colour) =
  self.write(self.pointToAddress(p), 1, colour.uint8)

proc writePixelSpan*(self: PsRamDisplay; p: Point; l: uint, colour: Colour) =
  self.write(self.pointToAddress(p), l, colour.uint8)

proc readPixelSpan*(self: PsRamDisplay; p: Point; l: uint; data: ptr uint8) =
  self.read(self.pointToAddress(p), l, data)
