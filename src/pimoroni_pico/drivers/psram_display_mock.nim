import ../libraries/pico_graphics/shapes

type
  PsramAddress* = range[0x000000'u32 .. 0xFFFFFF'u32]
  PsramDisplay* = object
    startAddress: PsramAddress
    width, height: uint16
    blocking: bool

proc init(self: var PsramDisplay) =
  discard

proc init*(self: var PsramDisplay; width, height: uint16) =
  self.width = width
  self.height = height
  self.startAddress = 0x000000
  self.init()

proc write*(self: var PsramDisplay; address: PsramAddress; len: uint; data: ptr uint8) =
  discard

proc write*(self: var PsramDisplay; address: PsramAddress; len: uint; data: uint8) =
  discard

proc read*(self: PsramDisplay; address: PsramAddress; len: uint; data: ptr uint8) =
  discard

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
