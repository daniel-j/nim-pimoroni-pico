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
when not defined(mock):
  import ../drivers/psram_display
else:
  import ../drivers/psram_display_mock

export rgb, shapes, luts


##
## Pico Graphics
##

type
  PicoGraphicsPenType* = enum
    Pen_1Bit
    # Pen_P2  # 2-bit is currently unsupported
    Pen_3Bit
    Pen_P4
    Pen_P8
    Pen_Rgb332
    Pen_Rgb565
    Pen_Rgb888

  PicoGraphicsConversionCallbackFunc* = proc (data: pointer; length: uint) {.closure.}

  PicoGraphicsBackend* = enum
    BackendMemory, BackendPsram

  PicoGraphics* = object of RootObj
    case backend*: PicoGraphicsBackend:
    of BackendMemory: frameBuffer*: seq[uint8]
    of BackendPsram: fbPsram*: PsramDisplay
    penType*: PicoGraphicsPenType
    bounds*: Rect
    clip*: Rect
    thickness*: Natural
    conversionCallbackFunc*: PicoGraphicsConversionCallbackFunc
    # nextPixelFunc*: proc (): T
    # bitmapFont*: ref Font
    # hersheyFont*: ref Font

proc setDimensions*(self: var PicoGraphics; width: uint16; height: uint16) =
  self.bounds.x = 0
  self.bounds.y = 0
  self.bounds.w = width.int
  self.bounds.h = height.int
  self.clip.x = 0
  self.clip.y = 0
  self.clip.w = width.int
  self.clip.h = height.int

proc init*(self: var PicoGraphics; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]) =
  self.setDimensions(width, height)
  self.backend = backend
  if self.backend == BackendMemory:
    self.frameBuffer = frameBuffer
  # self.setFont(font6)

# func constructPicoGraphics*(width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]): PicoGraphics {.constructor.} =
#   result.init(width, height, frameBuffer)

method setPen*(self: var PicoGraphics; c: uint) {.base.} = discard
method setPen*(self: var PicoGraphics; c: Rgb) {.base.} = discard
method setPixel*(self: var PicoGraphics; p: Point) {.base.} = discard
method setPixelSpan*(self: var PicoGraphics; p: Point; l: uint) {.base.} = discard
func setThickness*(self: var PicoGraphics; thickness: Positive) = self.thickness = thickness
method createPen*(self: var PicoGraphics; r: uint8; g: uint8; b: uint8): int {.base.} = discard
method updatePen*(self: var PicoGraphics; i: uint8; r: uint8; g: uint8; b: uint8): int {.base.} = discard
method resetPen*(self: var PicoGraphics; i: uint8): int {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb) {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb565) {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: uint8) {.base.} = discard
method frameConvert*(self: var PicoGraphics; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) {.base.} = discard
method sprite*(self: var PicoGraphics; data: pointer; sprite: Point; dest: Point; scale: int; transparent: int) {.base.} = discard

# proc setFont*(self: var PicoGraphics; font: BitmapFont) = discard
# proc setFont*(self: var PicoGraphics; font: HersheyFont) = discard
# proc setFont*(self: var PicoGraphics; font: string) = discard

func setFramebuffer*(self: var PicoGraphics; frameBuffer: seq[uint8]) = self.frameBuffer = frameBuffer

## these seem to be unused?
# proc getData*(self: var PicoGraphics): pointer = discard
# proc getData*(self: var PicoGraphics; `type`: PicoGraphicsPenType; y: uint; rowBuf: pointer) = discard

proc setClip*(self: var PicoGraphics; r: Rect) = self.clip = self.bounds.intersection(r)

proc removeClip*(self: var PicoGraphics) = self.clip = self.bounds

proc pixel*(self: var PicoGraphics; p: Point) =
  if self.clip.contains(p):
    self.setPixel(p)

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

# proc character*(self: var PicoGraphics; c: char; p: Point; s: float = 2.0; a: float = 0.0) =
#   if self.bitmapFont:
#     character(self.bitmapFont, (proc (x: int32; y: int32; w: int32; h: int32) =
#       rectangle(Rect(x: x, y: y, w: w, h: h))), c, p.x, p.y, max(1.0f, s))
#   elif self.hersheyFont:
#     glyph(self.hersheyFont, (proc (x1: int32; y1: int32; x2: int32; y2: int32) =
#       line(Point(x: x1, y: y1), Point(x: x2, y: y2))), c, p.x, p.y, s, a)

# proc text*(self: var PicoGraphics; t: string; p: Point; wrap: int32; s: float = 2.0; a: float = 0.0; letterSpacing: uint8 = 1) =
#   if self.bitmapFont:
#     text(self.bitmapFont, (proc (x: int32; y: int32; w: int32; h: int32) =
#       rectangle(Rect(x: x, y: y, w: w, h: h))), t, p.x, p.y, wrap, max(1.0f, s), letter_spacing)
#   elif self.hersheyFont:
#     text(self.hersheyFont, (proc (x1: int32; y1: int32; x2: int32; y2: int32) =
#       line(Point(x: x1, y: y1), Point(x: x2, y: y2))), t, p.x, p.y, s, a)

# proc measureText*(self: var PicoGraphics; t: string; s: float = 2.0; letterSpacing: uint8 = 1): int32 =
#   if self.bitmapFont:
#     return measureText(self.bitmapFont, t, max(1.0, s), letterSpacing)
#   elif self.hersheyFont:
#     return measureText(self.hersheyFont, t, s)
#   return 0

proc polygon*(self: var PicoGraphics; points: openArray[Point]) =
  var
    nodes: array[64, int]  ##  maximum allowed number of nodes per scanline for polygon rendering

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
        let px = int(sx.float + float(fy - sy) / float(ey - sy) * float(ex - sx))
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
    var s = abs(dx)  ##  number of steps
    let sx = if dx < 0: -1 else: 1  ##  x step value
    let sy = (dy shl 16) div s  ##  y step value in fixed 16:16
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
    var s = abs(dy)  ##  number of steps
    let sy = if dy < 0: -1 else: 1  ##  y step value
    let sx = (dx shl 16) div s  ##  x step value in fixed 16:16
    var y = p1.y
    var x = p1.x shl 16
    while s > 0:
      let p = Point(x: x shr 16, y: y)
      self.pixel(p)
      inc(y, sy)
      inc(x, sx)
      dec(s)

proc thickLine*(self: var PicoGraphics; p1, p2: Point; thickness: Positive = self.thickness) =
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
    var s = abs(dx)  ##  number of steps
    let sx = if dx < 0: -1 else: 1  ##  x step value
    let sy = (dy shl 16) div s  ##  y step value in fixed 16:16
    var x = p1.x
    var y = p1.y shl 16
    while s > 0:
      self.rectangle(Rect(x: x - ht, y: (y shr 16) - ht, w: t, h: t))
      inc(y, sy)
      inc(x, sx)
      dec(s)

  else:
    ##  steep version
    var s = abs(dy)  ##  number of steps
    let sy = if dy < 0: -1 else: 1  ##  y step value
    let sx = (dx shl 16) div s  ##  x step value in fixed 16:16
    var y = p1.y
    var x = p1.x shl 16
    while s > 0:
      self.rectangle(Rect(x: (x shr 16) - ht, y: y - ht, w: t, h: t))
      inc(y, sy)
      inc(x, sx)
      dec(s)

proc frameConvert*[T: Rgb565|Rgb888](self: var PicoGraphics; callback: PicoGraphicsConversionCallbackFunc, getNextPixel: proc(): T) =
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


##
## Pico Graphics Pen 1-Bit
##

type
  PicoGraphicsPen1Bit* = object of PicoGraphics
    color*: uint8

func bufferSize*(self: PicoGraphicsPen1Bit; w: uint; h: uint): uint =
  return w * h div 8

proc init*(self: var PicoGraphicsPen1Bit; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]) {.constructor.} =
  init(PicoGraphics(self), width, height, backend, frameBuffer)
  self.penType = Pen_1Bit
  if self.backend == BackendMemory:
    if self.frameBuffer.len == 0:
      self.frameBuffer = newSeq[uint8](self.bufferSize(width, height))

method setPen*(self: var PicoGraphicsPen1Bit; c: uint) =
  self.color = c.uint8

method setPen*(self: var PicoGraphicsPen1Bit; c: Rgb) =
  self.color = (max(c.r, max(c.g, c.b)) shr 4).uint8

method setPixel*(self: var PicoGraphicsPen1Bit; p: Point) =
  ##  pointer to byte in framebuffer that contains this pixel
  let f = self.frameBuffer[(p.x div 8) + (p.y * self.bounds.w div 8)].addr
  let bo: uint = 7 - (uint p.x and 0b111)
  var dc: uint8 = 0
  if self.color == 0:
    dc = 0
  elif self.color == 15:
    dc = 1
  else:
    let dmv = dither16Pattern[(p.x and 0b11) or ((p.y and 0b11) shl 2)]
    dc = if self.color > dmv: 1 else: 0
  ##  forceably clear the bit
  f[] = f[] and not (uint8 1 shl bo)
  ##  set pixel
  f[] = f[] or (dc shl bo)

method setPixelSpan*(self: var PicoGraphicsPen1Bit; p: Point; l: uint) =
  var lp: Point = p
  var length = l.int
  if p.x + length >= self.bounds.w:
    length = self.bounds.w - p.x
  while length > 0:
    self.setPixel(lp)
    inc(lp.x)
    dec(length)


##
## Pico Graphics Pen 1-Bit Y
##

type
  PicoGraphicsPen1BitY* = object of PicoGraphicsPen1Bit

method setPen*(self: var PicoGraphicsPen1BitY; c: Rgb) =
  self.color = (max(c.r, max(c.g, c.b)) shr 4).uint8

method setPixel*(self: var PicoGraphicsPen1BitY; p: Point) =
  ##  pointer to byte in framebuffer that contains this pixel
  let f = self.frameBuffer[(p.y div 8) + (p.x * self.bounds.h div 8)].addr
  let bo: uint = 7 - (uint p.y and 0b111)
  var dc: uint8 = 0
  if self.color == 0:
    dc = 0
  elif self.color == 15:
    dc = 1
  else:
    let dmv = dither16Pattern[(p.x and 0b11) or ((p.y and 0b11) shl 2)]
    dc = if self.color > dmv: 1 else: 0
  ##  forceably clear the bit
  f[] = f[] and not (uint8 1 shl bo)
  ##  set pixel
  f[] = f[] or (dc shl bo)

method setPixelSpan*(self: var PicoGraphicsPen1BitY; p: Point; l: uint) =
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
  PicoGraphicsPen3Bit* = object of PicoGraphics
    color*: uint
    palette: array[8, Rgb]
    paletteSize: uint16
    cacheDither*: array[512, array[16, uint8]]
    cacheDitherBuilt*: bool
    cacheNearest*: array[512, uint8]
    cacheNearestBuilt*: bool

const PicoGraphicsPen3BitPalette* = [
  Rgb(r:   1, g:  16, b:   2), ##  black
  Rgb(r: 238, g: 255, b: 246), ##  white
  Rgb(r:   0, g: 153, b:  28), ##  green
  Rgb(r:  57, g:  41, b: 185), ##  blue
  Rgb(r: 223, g:  14, b:  19), ##  red
  Rgb(r: 238, g: 220, b:  16), ##  yellow
  Rgb(r: 255, g: 130, b:  35), ##  orange
  Rgb(r: 245, g: 215, b: 191), ##  clean - not used on inky7
]

const RGB_FLAG*: uint = 0x7f000000

func bufferSize*(self: PicoGraphicsPen3Bit; w: uint; h: uint): uint =
  return (w * h div 8) * 3

proc init*(self: var PicoGraphicsPen3Bit; width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]) =
  PicoGraphics(self).init(width, height, backend, frameBuffer)
  self.palette = PicoGraphicsPen3BitPalette
  self.penType = Pen_3Bit
  self.paletteSize = 8
  self.cacheDitherBuilt = false
  self.cacheNearestBuilt = false
  case self.backend:
  of BackendMemory:
    if self.frameBuffer.len == 0:
      self.frameBuffer = newSeq[uint8](self.bufferSize(width, height))
  of BackendPsram:
    self.fbPsram.init(width, height)

# proc constructPicoGraphicsPen3Bit*(width: uint16; height: uint16; backend: PicoGraphicsBackend = BackendMemory; frameBuffer: seq[uint8] = @[]): PicoGraphicsPen3Bit {.constructor.} =
#   result.init(width, height, frameBuffer)

func getPaletteSize*(self: PicoGraphicsPen3Bit): uint16 = self.paletteSize
func setPaletteSize*(self: var PicoGraphicsPen3Bit; paletteSize: uint16) = self.paletteSize = paletteSize.clamp(1'u16, self.palette.len.uint16)
func getRawPalette*(self: PicoGraphicsPen3Bit): auto {.inline.} = self.palette
func getPalette*(self: PicoGraphicsPen3Bit): auto {.inline.} = self.palette[0..<self.paletteSize]

iterator cacheColors*(): tuple[i: int, c: Rgb] =
  for i in 0 ..< 512:
    let r = (i.uint and 0x1c0) shr 1
    let g = (i.uint and 0x38) shl 2
    let b = (i.uint and 0x7) shl 5
    let cacheCol = constructRgb(
      (r or (r shr 3) or (r shr 6)).int16,
      (g or (g shr 3) or (g shr 6)).int16,
      (b or (b shr 3) or (b shr 6)).int16
    )
    yield (i, cacheCol)

proc getDitherCandidates*(col: Rgb; palette: openArray[Rgb]; candidates: var array[16, uint8]) =
  var error: Rgb
  for i in 0 ..< candidates.len:
    candidates[i] = (col + error).closest(palette).uint8
    error += (col - palette[candidates[i]])

  # sort by a rough approximation of luminance, this ensures that neighbouring
  # pixels in the dither matrix are at extreme opposites of luminence
  # giving a more balanced output
  let pal = cast[ptr UncheckedArray[Rgb]](palette[0].unsafeAddr) # openArray workaround
  sort(candidates, func (a: uint8; b: uint8): int =
    (pal[a].luminance() > pal[b].luminance()).int
  )

proc generateDitherCache(cacheDither: var array[512, array[16, uint8]]; palette: openArray[Rgb]) =
  for i, col in cacheColors():
    getDitherCandidates(col, palette, cacheDither[i])

proc generateNearestCache(cacheDither: var array[512, uint8]; palette: openArray[Rgb]) =
  for i, col in cacheColors():
    cacheDither[i] = col.closest(palette).uint8

method setPen*(self: var PicoGraphicsPen3Bit; c: uint) =
  self.color = c

method setPen*(self: var PicoGraphicsPen3Bit; c: Rgb) =
  self.color = c.toRgb888().uint or RGB_FLAG

proc createPen*(self: PicoGraphicsPen3Bit; c: Rgb): uint =
  c.toRgb888().uint or RGB_FLAG

proc createPenHsv*(self: PicoGraphicsPen3Bit; h, s, v: float): Rgb =
  hsvToRgb(h, s, v)
proc createPenHsl*(self: PicoGraphicsPen3Bit; h, s, l: float): Rgb =
  hslToRgb(h, s, l)

proc createPenClosest*(self: var PicoGraphicsPen3Bit; c: Rgb#[; whitepoint: Rgb = Rgb(r: 255, g: 255, b: 255)]#): uint =
  c.closest(self.palette, self.color.int).uint

proc createPenClosestLut*(self: var PicoGraphicsPen3Bit; c: Rgb): uint =
  if not self.cacheNearestBuilt:
    self.cacheNearest.generateNearestCache(self.getPalette())
    self.cacheNearestBuilt = true
  let cacheKey = (((c.r and 0xE0) shl 1) or ((c.g and 0xE0) shr 2) or ((c.b and 0xE0) shr 5))
  return self.cacheNearest[cacheKey]

proc setPixelImpl(self: var PicoGraphicsPen3Bit; p: Point; col: uint) =
  if not self.bounds.contains(p) or not self.clip.contains(p):
    return
  case self.backend:
  of BackendMemory:
    let offset = (self.bounds.w * self.bounds.h) div 8
    let base = (p.x div 8) + (p.y * self.bounds.w div 8)
    let bitOffsetMask = 1'u8 shl (7 - (p.x and 0b111))
    let bufA = self.frameBuffer[base].addr
    let bufB = self.frameBuffer[base + offset].addr
    let bufC = self.frameBuffer[base + offset + offset].addr
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

# method setPixelDither*(self: var PicoGraphicsPen3Bit; p: Point; c: Rgb) =
#   if not self.cacheDitherBuilt:
#     self.cacheDither.generateDitherCache(self.getPalette())
#     self.cacheDitherBuilt = true
#   let cacheKey = (((c.r and 0xE0) shl 1) or ((c.g and 0xE0) shr 2) or ((c.b and 0xE0) shr 5))
#   ##  find the pattern coordinate offset
#   let patternIndex = ((p.x and 0b11) or ((p.y and 0b11) shl 2))
#   ##  set the pixel
#   self.setPixelImpl(p, self.cacheDither[cacheKey][dither16Pattern[patternIndex]])

method setPixelDither*(self: var PicoGraphicsPen3Bit; p: Point; c: Rgb) =
  var threshold = 0.77 #(p.y / self.bounds.h) * 0.3 + 0.4

  let patternIndex = ((p.x and 0b111) or ((p.y and 0b111) shl 3))
  let factor = dither64Pattern[patternIndex].int - dither64Pattern.len div 2
  threshold *= 256 div dither64Pattern.len

  let attempt = (c + (threshold * factor.float)).closest(self.getPalette()).uint8
  self.setPixelImpl(p, attempt)


method setPixel*(self: var PicoGraphicsPen3Bit; p: Point) =
  if (self.color and RGB_FLAG) == RGB_FLAG:
    self.setPixelDither(p, constructRgb(Rgb888(self.color)))
  else:
    self.setPixelImpl(p, self.color)

# proc getPixel*(self: PicoGraphicsPen3Bit; p: Point): uint8 =
#   if not self.bounds.contains(p) or not self.clip.contains(p):
#     return
#
#   let base = (p.x div 8) + (p.y * self.bounds.w div 8)
#   let offset = (self.bounds.w * self.bounds.h) div 8
#   let offA = base
#   let offB = offA + offset
#   let offC = offB + offset
#   let bo = 7 - (uint8 p.x and 0b111)
#   result =
#     ((self.frameBuffer[offA] and (1'u8 shl bo)) shr bo shl 2) or
#     ((self.frameBuffer[offB] and (1'u8 shl bo)) shr bo shl 1) or
#     ((self.frameBuffer[offC] and (1'u8 shl bo)) shr bo)

method setPixelSpan*(self: var PicoGraphicsPen3Bit; p: Point; l: uint) =
  if self.backend == BackendPsram and (self.color and RGB_FLAG) != RGB_FLAG:
    # is not an rgb color
    self.fbPsram.writePixelSpan(p, l, self.color.uint8)
    return
  var lp: Point = p

  # a bit messy, but it is way faster than calling self.setPixel(lp)
  if (self.color and RGB_FLAG) == RGB_FLAG:
    for i in 0..<l:
      self.setPixelDither(lp, constructRgb(Rgb888(self.color)))
      inc(lp.x)
  else:
    for i in 0..<l:
      # could use some optimization here
      # to set multiple adjacent pixels?
      self.setPixelImpl(lp, self.color)
      inc(lp.x)

method frameConvert*(self: var PicoGraphicsPen3Bit; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) =
  if `type` == Pen_P4:
    case self.backend:
    of BackendMemory:
      var rowBuf = newSeq[uint8](self.bounds.w div 2)
      var offset = ((self.bounds.w * self.bounds.h) div 8).uint
      for y in 0 ..< self.bounds.h:
        for x in 0 ..< self.bounds.w:
          var bo: uint = 7 - (uint x and 0b111)
          var bufA: ptr uint8 = addr(self.frameBuffer[(x div 8) + (y * self.bounds.w div 8)])
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


##
## Pico Graphics Pen P4
##

const PicoGraphicsPenP4PaletteSize*: uint16 = 16

type
  PicoGraphicsPenP4* = object of PicoGraphics
    color*: uint8
    palette*: array[PicoGraphicsPenP4PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP4PaletteSize, bool]
    cacheDither*: array[512, array[16, uint8]]
    cacheDitherBuilt*: bool
    candidates*: array[16, uint8]

# proc constructPicoGraphicsPenP4*(width: uint16; height: uint16;
#                                 frameBuffer: pointer): PicoGraphicsPenP4 {.
#     constructor.} = discard
method setPen*(self: var PicoGraphicsPenP4; c: uint) = discard
method setPen*(self: var PicoGraphicsPenP4; c: Rgb) = discard
method updatePen*(self: var PicoGraphicsPenP4; i: uint8; r: uint8; g: uint8; b: uint8): int = discard
method createPen*(self: var PicoGraphicsPenP4; r: uint8; g: uint8; b: uint8): int = discard
method resetPen*(self: var PicoGraphicsPenP4; i: uint8): int = discard
method setPixel*(self: var PicoGraphicsPenP4; p: Point) = discard
method setPixelSpan*(self: var PicoGraphicsPenP4; p: Point; l: uint) = discard
func getDitherCandidates*(self: var PicoGraphicsPenP4; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
method setPixelDither*(self: var PicoGraphicsPenP4; p: Point; c: Rgb) = discard
method frameConvert*(self: var PicoGraphicsPenP4; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: var PicoGraphicsPenP4; w: uint; h: uint): csize_t =
  return w * h div 2


##
## Pico Graphics Pen P8
##

const PicoGraphicsPenP8PaletteSize*: uint16 = 256

type
  PicoGraphicsPenP8* = object of PicoGraphics
    color*: uint8
    palette*: array[PicoGraphicsPenP8PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP8PaletteSize, bool]
    cacheDither*: array[512, array[16, uint8]]
    cacheDitherBuilt*: bool
    candidates*: array[16, uint8]


# proc constructPicoGraphicsPenP8*(width: uint16; height: uint16;
#                                 frameBuffer: pointer): PicoGraphicsPenP8 {.
#     constructor.} = discard
method setPen*(self: var PicoGraphicsPenP8; c: uint) = discard
method setPen*(self: var PicoGraphicsPenP8; c: Rgb) = discard
method updatePen*(self: var PicoGraphicsPenP8; i: uint8; r: uint8; g: uint8; b: uint8): int = discard
method createPen*(self: var PicoGraphicsPenP8; r: uint8; g: uint8; b: uint8): int = discard
method resetPen*(self: var PicoGraphicsPenP8; i: uint8): int = discard
method setPixel*(self: var PicoGraphicsPenP8; p: Point) = discard
method setPixelSpan*(self: var PicoGraphicsPenP8; p: Point; l: uint) = discard
func getDitherCandidates*(self: var PicoGraphicsPenP8; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
method setPixelDither*(self: var PicoGraphicsPenP8; p: Point; c: Rgb) = discard
method frameConvert*(self: var PicoGraphicsPenP8; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: PicoGraphicsPenP8; w: uint; h: uint): uint =
  return w * h


##
## Pico Graphics Pen RGB332
##

type
  PicoGraphicsPenRGB332* = object of PicoGraphics
    color*: Rgb332


# proc constructPicoGraphicsPenRGB332*(width: uint16; height: uint16;
#                                     frameBuffer: pointer): PicoGraphicsPenRGB332 {.
#     constructor.} = discard
method setPen*(self: var PicoGraphicsPenRGB332; c: uint) = discard
method setPen*(self: var PicoGraphicsPenRGB332; c: Rgb) = discard
method createPen*(self: var PicoGraphicsPenRGB332; r: uint8; g: uint8; b: uint8): int = discard
method setPixel*(self: var PicoGraphicsPenRGB332; p: Point) = discard
method setPixelSpan*(self: var PicoGraphicsPenRGB332; p: Point; l: uint) = discard
method setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb) = discard
method setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb565) = discard
method sprite*(self: var PicoGraphicsPenRGB332; data: pointer; sprite: Point; dest: Point;
            scale: int; transparent: int) = discard
method frameConvert*(self: var PicoGraphicsPenRGB332; `type`: PicoGraphicsPenType; callback: PicoGraphicsConversionCallbackFunc) = discard
func bufferSize*(self: PicoGraphicsPenRGB332; w: uint; h: uint): uint =
  return w * h


##
## Pico Graphics Pen RGB565
##

type
  PicoGraphicsPenRgb565* = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb565


# proc constructPicoGraphicsPenRgb565*(width: uint16; height: uint16;
#                                     frameBuffer: pointer): PicoGraphicsPenRgb565 {.
#     constructor.} = discard
method setPen*(self: var PicoGraphicsPenRgb565; c: uint) = discard
method setPen*(self: var PicoGraphicsPenRgb565; c: Rgb) = discard
method createPen*(self: var PicoGraphicsPenRgb565; r: uint8; g: uint8; b: uint8): int = discard
method setPixel*(self: var PicoGraphicsPenRgb565; p: Point) = discard
method setPixelSpan*(self: var PicoGraphicsPenRgb565; p: Point; l: uint) = discard
func bufferSize*(self: PicoGraphicsPenRgb565; w: uint; h: uint): uint =
  return w * h * uint sizeof(Rgb565)


##
## Pico Graphics Pen RGB888
##

type
  PicoGraphicsPenRgb888* = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb888


# proc constructPicoGraphicsPenRgb888*(width: uint16; height: uint16;
#                                     frameBuffer: pointer): PicoGraphicsPenRgb888 {.
#     constructor.} = discard
method setPen*(self: var PicoGraphicsPenRgb888; c: uint) = discard
method setPen*(self: var PicoGraphicsPenRgb888; c: Rgb) = discard
method createPen*(self: var PicoGraphicsPenRgb888; r: uint8; g: uint8; b: uint8): int = discard
method setPixel*(self: var PicoGraphicsPenRgb888; p: Point) = discard
method setPixelSpan*(self: var PicoGraphicsPenRgb888; p: Point; l: uint) = discard
func bufferSize*(self: PicoGraphicsPenRgb888; w: uint; h: uint): uint =
  return w * h * uint sizeof(Rgb888)

