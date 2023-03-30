import picostdlib
import picostdlib/hardware/spi
import ../common/[pimoroni_common, pimoroni_bus]
import ../libraries/pico_graphics/shapes

type
  PsramAddress* = range[0x000000'u32 .. 0xFFFFFF'u32]
  PsramDisplay* = object
    spi: ptr SpiInst
    pinCs: Gpio
    pinSck: Gpio
    pinMosi: Gpio
    pinMiso: Gpio
    startAddress: PsramAddress
    width, height: uint16
    timeout: AbsoluteTime
    blocking: bool

  Reg = enum
    Write = 0x02
    Read = 0x03
    ResetEnable = 0x66
    Reset = 0x99
    ReadId = 0x9F

proc init(self: var PsramDisplay) =
  let baud = spiInit(self.spi, 31_250_000)
  echo "PSRAM connected at ", baud
  gpioSetFunction(self.pinCs, Sio)
  gpioSetDir(self.pinCs, Out)
  gpioPut(self.pinCs, High)

  gpioSetFunction(self.pinSck, Spi)
  gpioSetFunction(self.pinMosi, Spi)
  gpioSetFunction(self.pinMiso, Spi)

  gpioPut(self.pinCs, Low)
  discard spiWriteBlocking(self.spi, ResetEnable.uint8, Reset.uint8)
  gpioPut(self.pinCs, High)

proc init*(self: var PsramDisplay; width, height: uint16; pins: SpiPins = SpiPins(spi: PimoroniSpiDefaultInstance, cs: 3.Gpio, sck: SpiDefaultSck, mosi: SpiDefaultMosi, miso: SpiDefaultMiso)) =
  self.spi = pins.spi
  self.pinCs = pins.cs
  self.pinSck = pins.sck
  self.pinMosi = pins.mosi
  self.pinMiso = pins.miso
  self.width = width
  self.height = height
  self.startAddress = 0x000000
  self.init()

proc spiSetBlocking*(self: var PsramDisplay; uSrc: uint16; uLen: csize_t): int {.codegenDecl: "$# __not_in_flash_func($#)$#".} =
  # Deliberately overflow FIFO, then clean up afterward, to minimise amount
  # of APB polling required per halfword
  for i in 0..<uLen:
    while (not spiIsWritable(self.spi)):
      tightLoopContents()
    spiGetHw(self.spi).dr = uSrc

  while spiIsReadable(self.spi):
    discard spiGetHw(self.spi).dr
  while (spiGetHw(self.spi).sr and SPI_SSPSR_BSY_BITS).bool:
    tightLoopContents()
  while spiIsReadable(self.spi):
    discard spiGetHw(self.spi).dr

  # Don't leave overrun flag set
  spiGetHw(self.spi).icr = SPI_SSPICR_RORIC_BITS

  return uLen.int

proc write*(self: var PsramDisplay; address: PsramAddress; len: uint; data: ptr uint8) =
  gpioPut(self.pinCs, Low)
  discard spiWriteBlocking(self.spi, Write.uint8, uint8 address shr 16, uint8 address shr 8, uint8 address)
  discard spiWriteBlocking(self.spi, data, len)
  gpioPut(self.pinCs, High)

proc write*(self: var PsramDisplay; address: PsramAddress; len: uint; data: uint8) =
  gpioPut(self.pinCs, Low)
  discard spiWriteBlocking(self.spi, Write.uint8, uint8 address shr 16, uint8 address shr 8, uint8 address)
  discard self.spiSetBlocking(data.uint16, len.csize_t)
  gpioPut(self.pinCs, High)

proc read*(self: PsramDisplay; address: PsramAddress; len: uint; data: ptr uint8) =
  gpioPut(self.pinCs, Low)
  discard spiWriteBlocking(self.spi, Read.uint8, uint8 (address shr 16) and 0xFF, uint8 (address shr 8) and 0xFF, uint8 address and 0xFF)
  discard spiReadBlocking(self.spi, 0, data, len.csize_t)
  gpioPut(self.pinCs, High)

proc test*(self: var PsramDisplay) =
  var writeBuffer = newStringOfCap(1024)
  var readBuffer = newStringOfCap(1024)

  let mb = 8

  for k in 0 ..< 1024 * mb:
    writeBuffer = $k
    self.write(uint32 k * 1024, uint writeBuffer.len, cast[ptr uint8](writeBuffer[0].addr))

  var same = true
  for k in 0 ..< 1024 * mb:
    if not same: break
    writeBuffer = $k
    readBuffer.setLen(writeBuffer.len)
    self.read(uint32 k * 1024, uint writeBuffer.len, cast[ptr uint8](readBuffer[0].addr))
    same = writeBuffer == readBuffer
    echo "[", k, "] ", writeBuffer, " == ", readBuffer, " ? ", (if same: "Success" else: "Failure")

# Pixel-specific stuff

proc pointToAddress(self: PsramDisplay; p: Point): PsramAddress =
  return self.startAddress + (p.y.uint32 * self.width) + p.x.uint32

proc writePixel*(self: var PsramDisplay; p: Point; colour: uint8) =
  self.write(self.pointToAddress(p), 1, colour)

proc writePixelSpan*(self: var PsramDisplay; p: Point; l: uint, colour: uint8) =
  # echo "writing pixel span ", p, " ", l, " ", colour
  self.write(self.pointToAddress(p), l, colour)

proc readPixel*(self: PsramDisplay; p: Point; l: uint; data: var uint8) =
  self.read(self.pointToAddress(p), 1, data.addr)

proc readPixelSpan*(self: PsramDisplay; p: Point; l: uint; data: ptr uint8) =
  # echo "reading pixel span ", p, " ", l
  self.read(self.pointToAddress(p), l, data)
