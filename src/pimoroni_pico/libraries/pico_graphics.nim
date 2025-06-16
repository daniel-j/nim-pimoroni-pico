# import
#   libraries/hersheyFonts/hersheyFonts, libraries/bitmapFonts/bitmapFonts,
#   libraries/bitmapFonts/font6Data, libraries/bitmapFonts/font8Data,
#   libraries/bitmapFonts/font14OutlineData

##  A tiny graphics library for our Pico products
##  supports:
##    - 16-bit (565) RGB
##    - 8-bit (332) RGB
##    - 8-bit with 16-bit 256 entry palette
##    - 4-bit with 16-bit 8 entry palette

import std/algorithm, std/bitops
import ./pico_graphics/[rgb, shapes, luts]
import ./hershey_fonts
when not defined(mock):
  import ../drivers/psram_display
else:
  import ../drivers/psram_display_mock

export rgb, shapes, luts


##
## Pico Graphics
##

type

  PicoGraphicsConversionCallbackFunc* = proc (data: pointer; length: uint) {.closure.}

  PicoGraphicsBackend* = enum
    BackendMemory, BackendPsram

  PicoGraphicsBase* = object of RootObj
    backend*: PicoGraphicsBackend
    frameBuffer*: pointer
    fbPsram*: PsramDisplay
    bounds*: Rect
    clip*: Rect
    thickness*: Natural
    conversionCallbackFunc*: PicoGraphicsConversionCallbackFunc
    # nextPixelFunc*: proc (): T
    bitmapFont*: pointer # ptr BitmapFont
    hersheyFont*: ptr HersheyFont

const RGB_FLAG: uint = 0x7f000000

proc setDimensions*(self: var PicoGraphicsBase; width: uint16; height: uint16) =
  self.bounds.x = 0
  self.bounds.y = 0
  self.bounds.w = width.int
  self.bounds.h = height.int
  self.clip.x = 0
  self.clip.y = 0
  self.clip.w = width.int
  self.clip.h = height.int

proc init*(self: var PicoGraphicsBase; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: pointer) =
  self.setDimensions(width, height)
  self.backend = backend
  if self.backend == BackendMemory:
    self.frameBuffer = frameBuffer
    if self.frameBuffer.isNil:
      raise newException(ValueError, "frameBuffer is nil")
  # self.setFont(font6)

# func constructPicoGraphics*(width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]): PicoGraphics =
#   result.init(width, height, frameBuffer)

func setThickness*(self: var PicoGraphicsBase; thickness: Positive) = self.thickness = thickness

# proc setFont*(self: var PicoGraphicsBase; font: BitmapFont) =
#   self.bitmapFont = font.unsafeAddr
#   self.hersheyFont = nil
proc setFont*(self: var PicoGraphicsBase; font: HersheyFont) =
  self.bitmapFont = nil
  self.hersheyFont = font.unsafeAddr
# proc setFont*(self: var PicoGraphicsBase; font: string) = discard

func setFramebuffer*(self: var PicoGraphicsBase; frameBuffer: pointer) = self.frameBuffer = frameBuffer

## these seem to be unused?
# proc getData*(self: var PicoGraphicsBase): pointer = discard
# proc getData*(self: var PicoGraphicsBase; `type`: PicoGraphicsPenType; y: uint; rowBuf: pointer) = discard

proc setClip*(self: var PicoGraphicsBase; r: Rect) = self.clip = self.bounds.intersection(r)

proc removeClip*(self: var PicoGraphicsBase) = self.clip = self.bounds


##
## Pico Graphics Pen 1-Bit
##

type
  PicoGraphicsPen1Bit* = object of PicoGraphicsBase
    color*: uint8

func bufferSize*(_: typedesc[PicoGraphicsPen1Bit]; w: uint; h: uint): uint =
  return w * h div 8

func bufferSize*(self: PicoGraphicsPen1Bit): uint {.inline.} =
  return PicoGraphicsPen1Bit.bufferSize(self.bounds.w.uint, self.bounds.h.uint)

proc init*(self: var PicoGraphicsPen1Bit; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: pointer) =
  PicoGraphicsBase(self).init(width, height, backend, frameBuffer)
  if self.backend == BackendMemory:
    if self.frameBuffer.isNil:
      raise newException(ValueError, "frameBuffer is nil")

proc setPen*(self: var PicoGraphicsPen1Bit; c: uint) {.inline.} =
  self.color = c.clamp(0, 255).uint8

proc setPen*(self: var PicoGraphicsPen1Bit; c: Rgb) =
  self.color = (c.toLinear().toLab().L * 255).int.clamp(0, 255).uint8

proc setPixel*(self: var PicoGraphicsPen1Bit; p: Point) =
  if not self.bounds.contains(p) or not self.clip.contains(p):
    return

  let base = (p.y div 8) + (p.x * self.bounds.h div 8)
  let bitOffsetMask = 1'u8 shl (7 - (p.y and 0b111))
  let buf = cast[ptr UncheckedArray[uint8]](self.frameBuffer)[base].addr

  let bit = if self.color == uint8.low:
    false
  elif self.color == uint8.high:
    true
  else:
    # dither
    const mask = (1 shl ditherPatternSize) - 1
    # find the pattern coordinate offset
    let patternIndex = (p.x and mask) or ((p.y and mask) shl ditherPatternSize)
    let error = when ditherMatrix.len == 0: 0 else: ditherMatrix[patternIndex]
    Gamma8Bit[self.color] > (error.uint * 256) div min(256, ditherPatternLength)

  if bit:
    buf[].setMask(bitOffsetMask)
  else:
    buf[].clearMask(bitOffsetMask)

proc setPixelSpan*(self: var PicoGraphicsPen1Bit; p: Point; l: uint) =
  var lp: Point = p
  var length = l.int
  if p.x + length >= self.bounds.w:
    length = self.bounds.w - p.x
  while length > 0:
    self.setPixel(lp)
    inc(lp.x)
    dec(length)


##
## Pico Graphics Pen 3Bit
##

type
  PicoGraphicsPen3Bit* = object of PicoGraphicsBase
    color*: uint
    palette: array[8, RgbLinear]
    paletteLuma: seq[int]
    paletteSize: uint8
    cacheNearest*: ptr NearestColorCache
    # cacheNearestBuilt*: bool
    when not ditherGenerateCache:
      ditherCandidateCache*: array[ditherCacheLength, uint8]
      ditherCandidateColor*: RgbLinear
      paletteLab*: seq[Lab]

const luma7_3 = 1/1.00
const sat7_3 = 1/1.65

const PicoGraphicsPen3BitPalette7_3* = [
  LChToLab(0.15, sat7_3 * 0.30, 150), ##  black
  LChToLab(1.00, sat7_3 * 0.01,  90), ##  white
  LChToLab(luma7_3 * 0.53, sat7_3 * 0.65, 150), ##  green
  LChToLab(luma7_3 * 0.52, sat7_3 * 0.52, 265), ##  blue
  LChToLab(luma7_3 * 0.58, sat7_3 * 0.60,  30), ##  red
  LChToLab(luma7_3 * 0.90, sat7_3 * 0.70, 110), ##  yellow
  LChToLab(luma7_3 * 0.67, sat7_3 * 0.65,  60), ##  orange
  LChToLab(luma7_3 * 0.98, sat7_3 * 0.00,  90), ##  clean - do not use on inky7 as colour
].fromLab()

# const PicoGraphicsPen3BitPalette7_3* = [
#   LChToLab(0.00, 0.00,   0).saturate(saturation7_3).fromLab(), ##  black
#   LChToLab(1.00, 0.00, 139).saturate(saturation7_3).fromLab(), ##  white
#   LChToLab(0.49, 0.68, 135).saturate(saturation7_3).fromLab(), ##  green
#   LChToLab(0.49, 0.40, 280).saturate(saturation7_3).fromLab(), ##  blue
#   LChToLab(0.59, 0.58,  35).saturate(saturation7_3).fromLab(), ##  red
#   LChToLab(0.90, 0.80,  90).saturate(saturation7_3).fromLab(), ##  yellow
#   LChToLab(0.69, 0.69,  60).saturate(saturation7_3).fromLab(), ##  orange
#   LChToLab(1.00, 0.00, 139).saturate(saturation7_3).fromLab(), ##  clean - do not use on inky7 as colour
# ]

const luma5_7 = 1/1.20
const sat5_7 = 1/1.50

const PicoGraphicsPen3BitPalette5_7* = [
  LChToLab(0.12, sat5_7 * 0.25, 200), ##  black
  LChToLab(0.98, sat5_7 * 0.01,  90), ##  white
  LChToLab(luma5_7 * 0.66, sat5_7 * 0.82, 138), ##  green
  LChToLab(luma5_7 * 0.58, sat5_7 * 0.40, 260), ##  blue
  LChToLab(luma5_7 * 0.60, sat5_7 * 0.60,  30), ##  red
  LChToLab(0.88, sat5_7 * 0.80, 100), ##  yellow
  LChToLab(luma5_7 * 0.70, sat5_7 * 0.85,  50), ##  orange
  LChToLab(luma5_7 * 0.90, sat5_7 * 0.60,  80), ##  clean
].fromLab()

# import strutils
# static:
#   echo "Inky Frame 7.3\" palette:"
#   for c in PicoGraphicsPen3BitPalette7_3:
#     echo "#", c.fromLinear().toRgb888().BiggestInt.toHex(6)
#   echo "Inky Frame 5.7\" palette:"
#   for c in PicoGraphicsPen3BitPalette5_7:
#     echo "#", c.fromLinear().toRgb888().BiggestInt.toHex(6)

func bufferSize*(_: typedesc[PicoGraphicsPen3Bit]; w: uint; h: uint): uint =
  return (w * h div 8) * 3

func bufferSize*(self: PicoGraphicsPen3Bit): uint {.inline.} =
  return PicoGraphicsPen3Bit.bufferSize(self.bounds.w.uint, self.bounds.h.uint)

func getPaletteSize*(self: PicoGraphicsPen3Bit): uint8 = self.paletteSize
func setPaletteSize*(self: var PicoGraphicsPen3Bit; paletteSize: uint8) =
  self.paletteSize = paletteSize.clamp(1'u8, self.palette.len.uint8)

proc init*(self: var PicoGraphicsPen3Bit; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: pointer; palette: array[8, RgbLinear];
    paletteSize: uint8 = 7) =
  PicoGraphicsBase(self).init(width, height, backend, frameBuffer)
  self.palette = palette
  self.setPaletteSize(paletteSize)
  # self.cacheNearestBuilt = false
  when not ditherGenerateCache:
    self.paletteLab.setLen(paletteSize)
    for i in 0 ..< paletteSize.int:
      self.paletteLab[i] = self.palette[i].toLab()

  self.paletteLuma.setLen(self.palette.len)
  for i, c in palette:
    self.paletteLuma[i] = int c.toLab().L * 100
  case self.backend:
  of BackendMemory:
    if self.frameBuffer.isNil:
      raise newException(ValueError, "frameBuffer is nil")
  of BackendPsram:
    self.fbPsram.init(width, height)

# proc constructPicoGraphicsPen3Bit*(width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]): PicoGraphicsPen3Bit =
#   result.init(width, height, frameBuffer)

func getRawPalette*(self: PicoGraphicsPen3Bit): auto {.inline.} = self.palette
func getPalette*(self: PicoGraphicsPen3Bit): auto {.inline.} = self.palette[0..<self.paletteSize]

proc setPen*(self: var PicoGraphicsPen3Bit; c: uint) {.inline.} =
  self.color = c

proc setPen*(self: var PicoGraphicsPen3Bit; c: Rgb) =
  self.color = c.toRgb888().uint or RGB_FLAG

proc createPen*(self: PicoGraphicsPen3Bit; c: Rgb): uint =
  c.toRgb888().uint or RGB_FLAG

proc createPenHsv*(self: PicoGraphicsBase; h, s, v: float32): RgbLinear =
  Hsv(h: h, s: s, v: v).toRgb().toLinear()
proc createPenHsl*(self: PicoGraphicsBase; h, s, l: float32): RgbLinear =
  Hsl(h: h, s: s, l: l).toRgb().toLinear()

proc createPenNearestLut*(self: var PicoGraphicsPen3Bit; c: RgbLinear; ditherIndex: uint = ditherPatternLength): uint8 =
  # if not self.cacheNearestBuilt:
  #   self.cacheNearest.generateNearestCache(self.getPalette().toLab())
  #   self.cacheNearestBuilt = true
  let cacheKey = c.fromLinear().getCacheKey()
  if self.cacheNearest.isNil:
    return
  if ditherIndex == ditherPatternLength:
    when ditherGenerateCache:
      return self.cacheNearest[cacheKey][0]
    else:
      return self.cacheNearest[cacheKey]
  when ditherGenerateCache:
    return self.cacheNearest[cacheKey][1][ditherIndex * ditherCacheLength div ditherPatternLength]
  else:
    if self.ditherCandidateColor != c:
      getDitherCandidates(c, self.getPalette(), self.paletteLab, self.paletteLuma, self.ditherCandidateCache, self.cacheNearest[])
      self.ditherCandidateColor = c
    return self.ditherCandidateCache[ditherIndex * ditherCacheLength div ditherPatternLength]

proc createPenNearest*(self: var PicoGraphicsPen3Bit; c: RgbLinear; ditherIndex: uint = ditherPatternLength): uint8 =
  return self.createPenNearestLut(c, ditherIndex)

  # # Warning: This is slooow:
  # var paletteLab = newSeq[Lab](self.paletteSize)
  # for i, col in self.getPalette():
  #   paletteLab[i] = col.toLab()
  # return c.clamp().toLab().closest(paletteLab).uint

# proc getPenColor*(self: PicoGraphicsPen3Bit): RgbLinear =
#   if (self.color and RGB_FLAG) == RGB_FLAG:
#     constructRgb(Rgb888(self.color)).toLinear()
#   else:
#     self.palette[self.color]

proc setPixelImpl*(self: var PicoGraphicsPen3Bit; p: Point; col: uint8) =
  if not self.bounds.contains(p) or not self.clip.contains(p):
    return
  case self.backend:
  of BackendMemory:
    let offset = (self.bounds.w * self.bounds.h) div 8
    let base = (p.x div 8) + (p.y * self.bounds.w div 8)
    let bitOffsetMask = 1'u8 shl (7 - (p.x and 0b111))
    let fb = cast[ptr UncheckedArray[uint8]](self.frameBuffer)
    let bufA = fb[base].addr
    let bufB = fb[base + offset].addr
    let bufC = fb[base + offset + offset].addr
    if col.testBit(2):
      bufA[].setMask(bitOffsetMask)
    else:
      bufA[].clearMask(bitOffsetMask)
    if col.testBit(1):
      bufB[].setMask(bitOffsetMask)
    else:
      bufB[].clearMask(bitOffsetMask)
    if col.testBit(0):
      bufC[].setMask(bitOffsetMask)
    else:
      bufC[].clearMask(bitOffsetMask)
  of BackendPsram:
    self.fbPsram.writePixel(p, col.uint8)

proc setPixelDither*(self: var PicoGraphicsPen3Bit; p: Point; c: RgbLinear): uint8 =
  ## Set pixel using an ordered dither (using lookup tables, see luts.nim)

  const mask = (1 shl ditherPatternSize) - 1
  # find the pattern coordinate offset
  let patternIndex = (p.x and mask) or ((p.y and mask) shl ditherPatternSize)

  let ditherIndex = when ditherMatrix.len == 0: 0'u8 else: ditherMatrix[patternIndex]
  let paletteCol = self.createPenNearest(c, ditherIndex)

  # let plan = deviseBestMixingPlan2(c.fromLinear(), 16, self.getPalette(), self.paletteLuma)
  # let paletteCol = plan[ditherIndex.int * plan.len div ditherPatternLength]

  # set the pixel
  self.setPixelImpl(p, paletteCol)

  return paletteCol

proc setPixel*(self: var PicoGraphicsPen3Bit; p: Point) =
  if (self.color and RGB_FLAG) == RGB_FLAG:
    discard self.setPixelDither(p, constructRgb(Rgb888(self.color)).toLinear())
  else:
    self.setPixelImpl(p, self.color.uint8)

proc getPixel*(self: PicoGraphicsPen3Bit; p: Point): uint8 =
  if not self.bounds.contains(p) or not self.clip.contains(p):
    return

  let fb = cast[ptr UncheckedArray[uint8]](self.frameBuffer)
  let base = (p.x div 8) + (p.y * self.bounds.w div 8)
  let offset = (self.bounds.w * self.bounds.h) div 8
  let offA = base
  let offB = offA + offset
  let offC = offB + offset
  let bo = 7 - (uint8 p.x and 0b111)
  result =
    ((fb[offA] and (1'u8 shl bo)) shr bo shl 2) or
    ((fb[offB] and (1'u8 shl bo)) shr bo shl 1) or
    ((fb[offC] and (1'u8 shl bo)) shr bo)

proc setPixelSpan*(self: var PicoGraphicsPen3Bit; p: Point; l: uint) =
  if self.backend == BackendPsram and (self.color and RGB_FLAG) != RGB_FLAG:
    # is not an rgb color
    self.fbPsram.writePixelSpan(p, l, self.color.uint8)
    return
  var lp: Point = p

  # a bit messy, but it is way faster than calling self.setPixel(lp)
  if (self.color and RGB_FLAG) == RGB_FLAG:
    let col = constructRgb(Rgb888(self.color)).toLinear()
    for i in 0..<l:
      discard self.setPixelDither(lp, col)
      inc(lp.x)
  else:
    for i in 0..<l:
      # could use some optimization here
      # to set multiple adjacent pixels?
      self.setPixelImpl(lp, self.color.uint8)
      inc(lp.x)

##
## Pico Graphics Pen P4
##

const PicoGraphicsPenP4PaletteSize*: uint16 = 16

type
  PicoGraphicsPenP4* = object of PicoGraphicsBase
    color*: uint8
    palette*: array[PicoGraphicsPenP4PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP4PaletteSize, bool]
    cacheDitherBuilt*: bool
    candidates*: array[16, uint8]

# proc constructPicoGraphicsPenP4*(width: uint16; height: uint16;
#                                 frameBuffer: pointer): PicoGraphicsPenP4 {.
#     constructor.} = discard
proc setPen*(self: var PicoGraphicsPenP4; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenP4; c: Rgb) = discard
proc updatePen*(self: var PicoGraphicsPenP4; i: uint8; c: Rgb): uint = discard
proc createPen*(self: var PicoGraphicsPenP4; c: Rgb): uint = discard
proc resetPen*(self: var PicoGraphicsPenP4; i: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenP4; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP4; p: Point; l: uint) = discard
func getDitherCandidates*(self: var PicoGraphicsPenP4; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP4; p: Point; c: RgbLinear) = discard
# proc frameConvert*(self: var PicoGraphicsPenP4; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: var PicoGraphicsPenP4; w: uint; h: uint): csize_t =
  return w * h div 2


##
## Pico Graphics Pen P8
##

const PicoGraphicsPenP8PaletteSize*: uint16 = 256

type
  PicoGraphicsPenP8* = object of PicoGraphicsBase
    color*: uint8
    palette*: array[PicoGraphicsPenP8PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP8PaletteSize, bool]
    cacheDither*: array[512, array[16, uint8]]
    cacheDitherBuilt*: bool
    candidates*: array[16, uint8]


# proc constructPicoGraphicsPenP8*(width: uint16; height: uint16;
#                                 frameBuffer: pointer): PicoGraphicsPenP8 {.
#     constructor.} = discard
proc setPen*(self: var PicoGraphicsPenP8; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenP8; c: Rgb) = discard
proc updatePen*(self: var PicoGraphicsPenP8; i: uint8; c: Rgb): uint = discard
proc createPen*(self: var PicoGraphicsPenP8; c: Rgb): uint = discard
proc resetPen*(self: var PicoGraphicsPenP8; i: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenP8; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP8; p: Point; l: uint) = discard
func getDitherCandidates*(self: var PicoGraphicsPenP8; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP8; p: Point; c: RgbLinear) = discard
# proc frameConvert*(self: var PicoGraphicsPenP8; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: PicoGraphicsPenP8; w: uint; h: uint): uint =
  return w * h


##
## Pico Graphics Pen RGB332
##

type
  PicoGraphicsPenRgb332* = object of PicoGraphicsBase
    color*: Rgb332


# proc constructPicoGraphicsPenRGB332*(width: uint16; height: uint16;
#                                     frameBuffer: pointer): PicoGraphicsPenRgb332 {.
#     constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRgb332; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRgb332; c: Rgb) = discard
proc createPen*(self: var PicoGraphicsPenRgb332; c: Rgb): uint = discard
proc setPixel*(self: var PicoGraphicsPenRgb332; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRgb332; p: Point; l: uint) = discard
proc setPixelDither*(self: var PicoGraphicsPenRgb332; p: Point; c: RgbLinear) = discard
# proc setPixelDither*(self: var PicoGraphicsPenRgb332; p: Point; c: Rgb565) = discard
proc sprite*(self: var PicoGraphicsPenRgb332; data: pointer; sprite: Point; dest: Point;
            scale: int; transparent: int) = discard
# proc frameConvert*(self: var PicoGraphicsPenRgb332; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: PicoGraphicsPenRgb332; w: uint; h: uint): uint =
  return w * h


##
## Pico Graphics Pen RGB565
##

type
  PicoGraphicsPenRgb565* = object of PicoGraphicsBase
    srcColor*: Rgb
    color*: Rgb565

proc setPen*(self: var PicoGraphicsPenRgb565; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRgb565; c: Rgb) =
  self.srcColor = c
  self.color = c.toRgb565()

proc createPen*(self: var PicoGraphicsPenRgb565; c: Rgb): uint = discard
proc setPixel*(self: var PicoGraphicsPenRgb565; p: Point) =
  let offset = (p.y * self.bounds.w + p.x) * 2
  cast[ptr UncheckedArray[Rgb565]](self.frameBuffer)[offset] = self.color.toRgb565Be()

proc setPixelSpan*(self: var PicoGraphicsPenRgb565; p: Point; l: uint) =
  let startOffset = p.y * self.bounds.w + p.x
  let fb = cast[ptr UncheckedArray[Rgb565]](self.frameBuffer)
  let colBe = self.color.toRgb565Be()
  for i in 0 ..< l.int:
    fb[startOffset + i] = colBe

func bufferSize*(self: PicoGraphicsPenRgb565; w: uint; h: uint): uint =
  return w * h * uint sizeof(Rgb565)

proc init*(self: var PicoGraphicsPenRgb565; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: pointer) =
  PicoGraphicsBase(self).init(width, height, backend, frameBuffer)
  if self.backend == BackendMemory:
    if self.frameBuffer.isNil:
      raise newException(ValueError, "frameBuffer is nil")

##
## Pico Graphics Pen RGB888
##

type
  PicoGraphicsPenRgb888* = object of PicoGraphicsBase
    srcColor*: Rgb
    color*: Rgb888


func bufferSize*(self: PicoGraphicsPenRgb888; w: uint; h: uint): uint =
  return w * h * 3

proc init*(self: var PicoGraphicsPenRgb888; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: pointer) =
  init(PicoGraphicsBase(self), width, height, backend, frameBuffer)
  if self.backend == BackendMemory:
    if self.frameBuffer.isNil:
      raise newException(ValueError, "frameBuffer is nil")

proc setPen*(self: var PicoGraphicsPenRgb888; c: uint) =
  self.srcColor = constructRgb(c.Rgb888)
  self.color = c.Rgb888

proc setPen*(self: var PicoGraphicsPenRgb888; c: Rgb) =
  self.srcColor = c
  self.color = c.toRgb888()

proc createPen*(self: var PicoGraphicsPenRgb888; c: Rgb): uint =
  c.toRgb888().uint

proc setPixel*(self: var PicoGraphicsPenRgb888; p: Point) =
  let offset = (p.y * self.bounds.w + p.x) * 3

  let fb = cast[ptr UncheckedArray[uint8]](self.frameBuffer)
  fb[offset + 0] = (self.color.uint32 shr 16).uint8
  fb[offset + 1] = (self.color.uint32 shr 8).uint8
  fb[offset + 2] = self.color.uint8

proc setPixelSpan*(self: var PicoGraphicsPenRgb888; p: Point; l: uint) =
  let fb = cast[ptr UncheckedArray[uint8]](self.frameBuffer)
  let r = uint8 self.color.uint32 and 0xff
  let g = uint8 (self.color.uint32 shr 8) and 0xff
  let b = uint8 (self.color.uint32 shr 16) and 0xff
  let startOffset = p.y * self.bounds.w + p.x
  for i in 0 ..< l.int:
    fb[(startOffset + i) * 3 + 0] = r
    fb[(startOffset + i) * 3 + 1] = g
    fb[(startOffset + i) * 3 + 2] = b


##
## Pico Graphics common methods
##

type
  PicoGraphics* = PicoGraphicsPen1Bit | # PicoGraphicsPen1BitY |
    PicoGraphicsPen3Bit | PicoGraphicsPenP4 | PicoGraphicsPenP8 |
    PicoGraphicsPenRgb332 | PicoGraphicsPenRgb565 | PicoGraphicsPenRgb888

proc pixel*(self: var PicoGraphics; p: Point) =
  if self.clip.contains(p):
    self.setPixel(p)

proc pixelDither*(self: var PicoGraphics; p: Point; c: RgbLinear) =
  if self.clip.contains(p):
    self.setPixelDither(p, c)

proc pixelSpan*(self: var PicoGraphics; p: Point; l: int) =
  ##  check if span in bounds
  if p.x + l < self.clip.x or p.x >= self.clip.x + self.clip.w or p.y < self.clip.y or p.y >= self.clip.y + self.clip.h:
    return
  ##  clamp span horizontally
  var clipped = p
  var length = l
  if clipped.x < self.clip.x:
    inc(length, clipped.x - self.clip.x)
    clipped.x = self.clip.x
  if clipped.x + length >= self.clip.x + self.clip.w:
    length = self.clip.x + self.clip.w - clipped.x
  var dest = Point(x: clipped.x, y: clipped.y)
  self.setPixelSpan(dest, length.uint)

proc rectangle*(self: var PicoGraphics; r: Rect) =
  ##  clip and/or discard depending on rectangle visibility
  let clipped: Rect = r.intersection(self.clip)
  if clipped.empty():
    return

  var dest = Point(x: clipped.x, y: clipped.y)
  for i in 0..<clipped.h:
    ##  draw span of pixels for this row
    self.setPixelSpan(dest, clipped.w.uint)
    ##  move to next scanline
    inc(dest.y)

proc circle*(self: var PicoGraphics; p: Point; radius: int) =
  ##  circle in screen bounds?
  var bounds: Rect = Rect(x: p.x - radius, y: p.y - radius, w: radius * 2, h: radius * 2)
  if not bounds.intersects(self.clip):
    return
  var
    ox = radius
    oy = 0
    err = -radius
  while ox >= oy:
    let last_oy = oy
    inc(err, oy)
    inc(oy)
    inc(err, oy)
    self.pixelSpan(Point(x: p.x - ox, y: p.y + last_oy), ox * 2 + 1)
    if last_oy != 0:
      self.pixelSpan(Point(x: p.x - ox, y: p.y - last_oy), ox * 2 + 1)
    if err >= 0 and ox != last_oy:
      self.pixelSpan(Point(x: p.x - last_oy, y: p.y + ox), last_oy * 2 + 1)
      if ox != 0:
        self.pixelSpan(Point(x: p.x - last_oy, y: p.y - ox), last_oy * 2 + 1)
      dec(err, ox)
      dec(ox)
      dec(err, ox)

proc clear*(self: var PicoGraphics) = self.rectangle(self.clip)

proc character*(self: var PicoGraphics; c: char; p: Point; s: float32 = 2.0; a: float32 = 0.0) =
  if self.bitmapFont:
    self.bitmapFont.character((proc (x: int32; y: int32; w: int32; h: int32) =
      self.rectangle(Rect(x: x, y: y, w: w, h: h))), c, p.x, p.y, max(1.0f, s))
  elif self.hersheyFont:
    self.hersheyFont.glyph((proc (x1: int32; y1: int32; x2: int32; y2: int32) =
      self.line(Point(x: x1, y: y1), Point(x: x2, y: y2))), c, p.x, p.y, s, a)

proc text*(self: var PicoGraphics; t: string; p: Point; wrap: int32; s: float32 = 2.0; a: float32 = 0.0; letterSpacing: uint8 = 1) =
  let graphics = self.addr
  # if self.bitmapFont != nil:
  #   self.bitmapFont.text((proc (x: int32; y: int32; w: int32; h: int32) =
  #     self.rectangle(Rect(x: x, y: y, w: w, h: h))), t, p.x, p.y, wrap, max(1.0f, s), letterSpacing)
  if self.hersheyFont != nil:
    self.hersheyFont[].text((proc (x1: int32; y1: int32; x2: int32; y2: int32) {.closure.} =
      if graphics[].thickness <= 1:
        graphics[].line(Point(x: x1, y: y1), Point(x: x2, y: y2))
      else:
        graphics[].thickLine(Point(x: x1, y: y1), Point(x: x2, y: y2), graphics[].thickness)
    ), t, p.x.int32, p.y.int32, s, a)

proc measureText*(self: var PicoGraphics; t: string; s: float32 = 2.0; letterSpacing: uint8 = 1): int32 =
  if self.bitmapFont != nil:
    return self.bitmapFont.measureText(t, max(1.0, s), letterSpacing)
  elif self.hersheyFont != nil:
    return self.hersheyFont[].measureText(t, s)
  return 0

proc polygon*(self: var PicoGraphics; points: openArray[Point]) =
  var
    nodes: array[64, int] ##  maximum allowed number of nodes per scanline for polygon rendering

    miny = points[0].y
    maxy = points[0].y

  for i in 1 ..< points.len():
    miny = min(miny, points[i].y)
    maxy = max(maxy, points[i].y)

  ##  for each scanline within the polygon bounds (clipped to clip rect)
  var p: Point

  p.y = max(self.clip.y, miny)
  while p.y <= min(self.clip.y + self.clip.h, maxy):
    var n = 0
    for i in 0 ..< points.len():
      let j = (i + 1) mod points.len()
      let sy = points[i].y
      let ey = points[j].y
      let fy = p.y
      if (sy < fy and ey >= fy) or (ey < fy and sy >= fy):
        let sx = points[i].x
        let ex = points[j].x
        let px = int(sx.float32 + float32(fy - sy) / float32(ey - sy) * float32(ex - sx))
        nodes[n] =
          if px < self.clip.x:
            self.clip.x
          else:
            if px >= self.clip.x + self.clip.w:
              self.clip.x + self.clip.w - 1
            else:
              px
        inc(n)
        ##  clamp(int(sx + float(fy - sy) / float(ey - sy) * float(ex - sx)), clip.x, clip.x + clip.w);

    var i = 0
    while i < n - 1:
      if nodes[i] > nodes[i + 1]:
        let s = nodes[i]
        nodes[i] = nodes[i + 1]
        nodes[i + 1] = s
        if i != 0:
          dec(i)
      else:
        inc(i)

    for i in countup(0, n - 1, 2):
      self.pixelSpan(Point(x: nodes[i], y: p.y), nodes[i + 1] - nodes[i] + 1)

    inc(p.y)

func orient2d(p1, p2, p3: Point): int =
  return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)

func isTopLeft(p1, p2: Point): bool =
  return (p1.y == p2.y and p1.x > p2.x) or (p1.y < p2.y)

proc triangle*(self: var PicoGraphics; p1, p2, p3: var Point) =
  var triangleBounds = constructRect(
    Point(x: min(p1.x, min(p2.x, p3.x)), y: min(p1.y, min(p2.y, p3.y))),
    Point(x: max(p1.x, max(p2.x, p3.x)), y: max(p1.y, max(p2.y, p3.y)))
  )
  ##  clip extremes to frame buffer size
  triangle_bounds = self.clip.intersection(triangleBounds)

  ##  if triangle completely out of bounds then don't bother!
  if triangleBounds.empty():
    return

  ##  fix "winding" of vertices if needed
  let winding = orient2d(p1, p2, p3)
  if winding < 0:
    var t: Point
    t = p1
    p1 = p3
    p3 = t

  ##  bias ensures no overdraw between neighbouring triangles
  let bias0 = if isTopLeft(p2, p3): 0 else: -1
  let bias1 = if isTopLeft(p3, p1): 0 else: -1
  let bias2 = if isTopLeft(p1, p2): 0 else: -1

  let a01 = p1.y - p2.y
  let b01 = p2.x - p1.x
  let a12 = p2.y - p3.y
  let b12 = p3.x - p2.x
  let a20 = p3.y - p1.y
  let b20 = p1.x - p3.x

  let tl = Point(x: triangleBounds.x, y: triangleBounds.y)
  var w0row = orient2d(p2, p3, tl) + bias0
  var w1row = orient2d(p3, p1, tl) + bias1
  var w2row = orient2d(p1, p2, tl) + bias2

  for y in 0 ..< triangleBounds.h:
    var w0 = w0row
    var w1 = w1row
    var w2 = w2row

    var dest = Point(x: triangleBounds.x, y: triangleBounds.y + y)
    for x in 0 ..< triangleBounds.w:
      if (w0 or w1 or w2) >= 0:
        self.setPixel(dest)
      inc(dest.x)

      inc(w0, a12)
      inc(w1, a20)
      inc(w2, a01)

    inc(w0row, b12)
    inc(w1row, b20)
    inc(w2row, b01)

proc line*(self: var PicoGraphics; p1, p2: Point) =
  ##  fast horizontal line
  if p1.y == p2.y:
    let start = min(p1.x, p2.x)
    let `end` = max(p1.x, p2.x)
    self.pixelSpan(Point(x: start, y: p1.y), `end` - start)
    return

  ##  fast vertical line
  if p1.x == p2.x:
    let start = min(p1.y, p2.y)
    var length = max(p1.y, p2.y) - start
    var dest = Point(x: p1.x, y: start)
    while length > 0:
      self.pixel(dest)
      inc(dest.y)
      dec(length)
    return

  ##  general purpose line
  ##  lines are either "shallow" or "steep" based on whether the x delta
  ##  is greater than the y delta
  let dx = p2.x - p1.x
  let dy = p2.y - p1.y
  var shallow = abs(dx) > abs(dy)
  if shallow:
    ##  shallow version
    var s = abs(dx) ##  number of steps
    let sx = if dx < 0: -1 else: 1 ##  x step value
    let sy = (dy shl 16) div s ##  y step value in fixed 16:16
    var x = p1.x
    var y = p1.y shl 16
    while s > 0:
      let p = Point(x: x, y: y shr 16)
      self.pixel(p)
      inc(y, sy)
      inc(x, sx)
      dec(s)

  else:
    ##  steep version
    var s = abs(dy) ##  number of steps
    let sy = if dy < 0: -1 else: 1 ##  y step value
    let sx = (dx shl 16) div s ##  x step value in fixed 16:16
    var y = p1.y
    var x = p1.x shl 16
    while s > 0:
      let p = Point(x: x shr 16, y: y)
      self.pixel(p)
      inc(y, sy)
      inc(x, sx)
      dec(s)

proc thickLine*(self: var PicoGraphics; p1, p2: Point; thickness: Positive) =
  let ht = thickness div 2 # half thickness
  let t = thickness # alias for thickness

  ##  fast horizontal line
  if p1.y == p2.y:
    let start = min(p1.x, p2.x)
    let `end` = max(p1.x, p2.x)
    self.rectangle(Rect(x: start, y: p1.y - ht, w: `end` - start, h: t))
    return

  ##  fast vertical line
  if p1.x == p2.x:
    let start = min(p1.y, p2.y)
    var length = max(p1.y, p2.y) - start
    self.rectangle(Rect(x: p1.x - ht, y: start, w: t, h: length))
    return

  ##  general purpose line
  ##  lines are either "shallow" or "steep" based on whether the x delta
  ##  is greater than the y delta
  let dx = p2.x - p1.x
  let dy = p2.y - p1.y
  var shallow = abs(dx) > abs(dy)
  if shallow:
    ##  shallow version
    var s = abs(dx) ##  number of steps
    let sx = if dx < 0: -1 else: 1 ##  x step value
    let sy = (dy shl 16) div s ##  y step value in fixed 16:16
    var x = p1.x
    var y = p1.y shl 16
    while s > 0:
      self.rectangle(Rect(x: x - ht, y: (y shr 16) - ht, w: t, h: t))
      inc(y, sy)
      inc(x, sx)
      dec(s)

  else:
    ##  steep version
    var s = abs(dy) ##  number of steps
    let sy = if dy < 0: -1 else: 1 ##  y step value
    let sx = (dx shl 16) div s ##  x step value in fixed 16:16
    var y = p1.y
    var x = p1.x shl 16
    while s > 0:
      self.rectangle(Rect(x: (x shr 16) - ht, y: y - ht, w: t, h: t))
      inc(y, sy)
      inc(x, sx)
      dec(s)

proc frameConvert*(self: var PicoGraphicsPen3Bit; `type`: typedesc[PicoGraphics]; callback: PicoGraphicsConversionCallbackFunc) =
  if `type` is PicoGraphicsPenP4:
    case self.backend:
    of BackendMemory:
      let fb = cast[ptr UncheckedArray[uint8]](self.frameBuffer)
      var rowBuf = newSeq[uint8](self.bounds.w div 2)
      var offset = ((self.bounds.w * self.bounds.h) div 8).uint
      for y in 0 ..< self.bounds.h:
        for x in 0 ..< self.bounds.w:
          var bo: uint = 7 - (uint x and 0b111)
          var bufA: ptr uint8 = addr(fb[(x div 8) + (y * self.bounds.w div 8)])
          var bufB: ptr uint8 = cast[ptr uint8](cast[uint](bufA) + offset)
          var bufC: ptr uint8 = cast[ptr uint8](cast[uint](bufA) + offset + offset)
          var nibble: uint8 = (bufA[] shr bo) and 1
          nibble = nibble shl 1
          nibble = nibble or (bufB[] shr bo) and 1
          nibble = nibble shl 1
          nibble = nibble or (bufC[] shr bo) and 1
          nibble = nibble shl (if (x and 0b1).bool: 0 else: 4)
          rowBuf[x div 2] = rowBuf[x div 2] and (if (x and 0b1).bool: 0b11110000 else: 0b00001111)
          rowBuf[x div 2] = rowBuf[x div 2] or nibble

        callback(cast[pointer](rowBuf[0].addr), rowBuf.len.uint)

    of BackendPsram:
      var rowBuf = newSeq[uint8](self.bounds.w)
      let byteCount = uint self.bounds.w div 2
      for y in 0 ..< self.bounds.h:
        self.fbPsram.readPixelSpan(Point(x: 0, y: y), rowBuf.len.uint, rowBuf[0].addr)
        for x in 0..<byteCount:
          var nibble = (rowBuf[x * 2] shl 4) or (rowBuf[x * 2 + 1] and 0xf)
          rowBuf[x] = nibble

        callback(cast[pointer](rowBuf[0].addr), byteCount)

proc frameConvert*[T: Rgb565|Rgb888](self: var PicoGraphics; callback: PicoGraphicsConversionCallbackFunc; getNextPixel: proc(): T) =
  ## Allocate two temporary buffers, as the callback may transfer by DMA
  ##  while we're preparing the next part of the row
  const BUF_LEN = 64
  var rowBuf: array[2, array[BUF_LEN, T]]
  var bufIdx = 0
  var bufEntry = 0
  for i in 0 ..< self.bounds.w * self.bounds.h:
    rowBuf[bufIdx][bufEntry] = getNextPixel()
    inc(bufEntry)

    ## Transfer a filled buffer and swap to the next one
    if bufEntry == BUF_LEN:
      callback(rowBuf[bufIdx][0].addr, BUF_LEN * sizeof(T))
      bufIdx = bufIdx xor 1
      bufEntry = 0

  ## Transfer any remaining pixels ( < BUF_LEN )
  if bufEntry > 0:
    callback(rowBuf[bufIdx][0].addr, uint(bufEntry * sizeof(T)))

  ## Callback with zero length to ensure previous buffer is fully written
  callback(rowBuf[bufIdx][0].addr, 0)
