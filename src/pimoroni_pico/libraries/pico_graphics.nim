# import
#   libraries/hersheyFonts/hersheyFonts, libraries/bitmapFonts/bitmapFonts,
#   libraries/bitmapFonts/font6Data, libraries/bitmapFonts/font8Data,
#   libraries/bitmapFonts/font14OutlineData
import ../common/pimoroni_common

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##  A tiny graphics library for our Pico products
##  supports:
##    - 16-bit (565) RGB
##    - 8-bit (332) RGB
##    - 8-bit with 16-bit 256 entry palette
##    - 4-bit with 16-bit 8 entry palette

##
## RGB
##

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  Rgb* {.bycopy.} = object
    r*: int16
    g*: int16
    b*: int16

func constructRgb*(): Rgb {.constructor.} =
  result.r = 0
  result.g = 0
  result.b = 0

func constructRgb*(c: Rgb332): Rgb {.constructor.} =
  result.r = ((c.uint8 and 0b11100000) shr 0).int16
  result.g = ((c.uint8 and 0b00011100) shl 3).int16
  result.b = ((c.uint8 and 0b00000011) shl 6).int16

func constructRgb*(c: Rgb565): Rgb {.constructor.} =
  result.r = ((builtinBswap16(c.uint16) and 0b1111100000000000) shr 8).int16
  result.g = ((builtinBswap16(c.uint16) and 0b0000011111100000) shr 3).int16
  result.b = ((builtinBswap16(c.uint16) and 0b0000000000011111) shl 3).int16

func constructRgb*(r: int16; g: int16; b: int16): Rgb {.constructor.} =
  result.r = r
  result.g = g
  result.b = b

func `+`*(self: Rgb; c: Rgb): Rgb =
  return constructRgb(self.r + c.r, self.g + c.g, self.b + c.b)

proc `+=`*(self: var Rgb; c: Rgb): var Rgb =
  inc(self.r, c.r)
  inc(self.g, c.g)
  inc(self.b, c.b)
  return self

proc `-=`*(self: var Rgb; c: Rgb): var Rgb =
  dec(self.r, c.r)
  dec(self.g, c.g)
  dec(self.b, c.b)
  return self

func `-`*(self: Rgb; c: Rgb): Rgb =
  return constructRgb(self.r - c.r, self.g - c.g, self.b - c.b)

func luminance*(self: Rgb): int =
  ##  weights based on https://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/
  return self.r * 21 + self.g * 72 + self.b * 7

func distance*(self: Rgb; c: Rgb): int =
  var rmean = (self.r + c.r) div 2
  var rx = self.r - c.r
  var gx = self.g - c.g
  var bx = self.b - c.b
  return abs((int)((((512 + rmean) * rx * rx) shr 8) + 4 * gx * gx +
      (((767 - rmean) * bx * bx) shr 8)))

func closest*(self: Rgb; palette: openArray[Rgb]; len: int): int =
  var
    d = int.high
    m = -1
  var i = 0
  while i < len:
    var dc = self.distance(palette[i])
    if dc < d:
      m = i
      d = dc
    inc(i)
  return m

func toRgb565*(self: Rgb): Rgb565 =
  let p = ((self.r and 0b11111000) shl 8).uint16 or ((self.g and 0b11111100) shl 3).uint16 or ((self.b and 0b11111000) shr 3).uint16
  return builtinBswap16(p).Rgb565

func toRgb332*(self: Rgb): Rgb332 =
  ((self.r and 0b11100000) or ((self.g and 0b11100000) shr 3) or ((self.b and 0b11000000) shr 6)).Rgb332

func toRgb888*(self: Rgb): Rgb888 =
  ((self.r shl 16).uint32 or (self.g shl 8).uint32 or (self.b shl 0).uint32).Rgb888


##
## Point & Rect
##


type
  Pen* = int

  Point* {.bycopy.} = object
    x*: int
    y*: int
  
  Rect* {.bycopy.} = object
    x*: int
    y*: int
    w*: int
    h*: int

func constructPoint*(x: int32; y: int32): Point {.constructor.} =
  result.x = x
  result.y = y

proc `-=`*(self: var Point; a: Point): var Point {.inline.} =
  dec(self.x, a.x)
  dec(self.y, a.y)
  return self

proc `+=`*(self: var Point; a: Point): var Point {.inline.} =
  inc(self.x, a.x)
  inc(self.y, a.y)
  return self

proc `/=`*(lhs: var Point; rhs: int32): var Point {.inline.} =
  lhs.x = lhs.x div rhs
  lhs.y = lhs.y div rhs
  return lhs

func `==`*(lhs: Point; rhs: Point): bool {.inline.} =
  return lhs.x == rhs.x and lhs.y == rhs.y

func `!=`*(lhs: Point; rhs: Point): bool {.inline.} =
  return not (lhs == rhs)

func `-`*(rhs: Point): Point {.inline.} =
  return Point(x: -rhs.x, y: -rhs.y)

func clamp*(self: Point; r: Rect): Point =
  result.x = min(max(self.x, r.x), r.x + r.w)
  result.y = min(max(self.y, r.y), r.y + r.h)


func constructRect*(x: int32; y: int32; w: int32; h: int32): Rect {.constructor.} =
  result.x = x
  result.y = y
  result.w = w
  result.h = h

func constructRect*(tl: Point; br: Point): Rect {.constructor.} =
  result.x = tl.x
  result.y = tl.y
  result.w = br.x - tl.x
  result.h = br.y - tl.y

func empty*(self: Rect): bool =
  return self.w <= 0 or self.h <= 0

func contains*(self: Rect; p: Point): bool =
  return p.x >= self.x and p.y >= self.y and p.x < self.x + self.w and p.y < self.y + self.h

func contains*(self: Rect; p: Rect): bool =
  return p.x >= self.x and p.y >= self.y and p.x + p.w < self.x + self.w and p.y + p.h < self.y + self.h

func intersects*(self: Rect; r: Rect): bool =
  return not (self.x > r.x + r.w or self.x + self.w < r.x or self.y > r.y + r.h or self.y + self.h < r.y)

func intersection*(self: Rect; r: Rect): Rect =
  result.x = max(self.x, r.x)
  result.y = max(self.y, r.y)
  result.w = min(self.x + self.w, r.x + r.w) - max(self.x, r.x)
  result.h = min(self.y + self.h, r.y + r.h) - max(self.y, r.y)

proc inflate*(self: var Rect; v: int32) =
  dec(self.x, v)
  dec(self.y, v)
  inc(self.w, v * 2)
  inc(self.h, v * 2)

proc deflate*(self: var Rect; v: int32) =
  inc(self.x, v)
  inc(self.y, v)
  dec(self.w, v * 2)
  dec(self.h, v * 2)

##
## LUT
##

var rgb332ToRgb565Lut*: array[256, uint16] = [
    0x0000.uint16, 0x0800, 0x1000, 0x1800, 0x0001,
    0x0801, 0x1001, 0x1801, 0x0002, 0x0802, 0x1002, 0x1802, 0x0003, 0x0803, 0x1003,
    0x1803, 0x0004, 0x0804, 0x1004, 0x1804, 0x0005, 0x0805, 0x1005, 0x1805, 0x0006,
    0x0806, 0x1006, 0x1806, 0x0007, 0x0807, 0x1007, 0x1807, 0x0020, 0x0820, 0x1020,
    0x1820, 0x0021, 0x0821, 0x1021, 0x1821, 0x0022, 0x0822, 0x1022, 0x1822, 0x0023,
    0x0823, 0x1023, 0x1823, 0x0024, 0x0824, 0x1024, 0x1824, 0x0025, 0x0825, 0x1025,
    0x1825, 0x0026, 0x0826, 0x1026, 0x1826, 0x0027, 0x0827, 0x1027, 0x1827, 0x0040,
    0x0840, 0x1040, 0x1840, 0x0041, 0x0841, 0x1041, 0x1841, 0x0042, 0x0842, 0x1042,
    0x1842, 0x0043, 0x0843, 0x1043, 0x1843, 0x0044, 0x0844, 0x1044, 0x1844, 0x0045,
    0x0845, 0x1045, 0x1845, 0x0046, 0x0846, 0x1046, 0x1846, 0x0047, 0x0847, 0x1047,
    0x1847, 0x0060, 0x0860, 0x1060, 0x1860, 0x0061, 0x0861, 0x1061, 0x1861, 0x0062,
    0x0862, 0x1062, 0x1862, 0x0063, 0x0863, 0x1063, 0x1863, 0x0064, 0x0864, 0x1064,
    0x1864, 0x0065, 0x0865, 0x1065, 0x1865, 0x0066, 0x0866, 0x1066, 0x1866, 0x0067,
    0x0867, 0x1067, 0x1867, 0x0080, 0x0880, 0x1080, 0x1880, 0x0081, 0x0881, 0x1081,
    0x1881, 0x0082, 0x0882, 0x1082, 0x1882, 0x0083, 0x0883, 0x1083, 0x1883, 0x0084,
    0x0884, 0x1084, 0x1884, 0x0085, 0x0885, 0x1085, 0x1885, 0x0086, 0x0886, 0x1086,
    0x1886, 0x0087, 0x0887, 0x1087, 0x1887, 0x00a0, 0x08a0, 0x10a0, 0x18a0, 0x00a1,
    0x08a1, 0x10a1, 0x18a1, 0x00a2, 0x08a2, 0x10a2, 0x18a2, 0x00a3, 0x08a3, 0x10a3,
    0x18a3, 0x00a4, 0x08a4, 0x10a4, 0x18a4, 0x00a5, 0x08a5, 0x10a5, 0x18a5, 0x00a6,
    0x08a6, 0x10a6, 0x18a6, 0x00a7, 0x08a7, 0x10a7, 0x18a7, 0x00c0, 0x08c0, 0x10c0,
    0x18c0, 0x00c1, 0x08c1, 0x10c1, 0x18c1, 0x00c2, 0x08c2, 0x10c2, 0x18c2, 0x00c3,
    0x08c3, 0x10c3, 0x18c3, 0x00c4, 0x08c4, 0x10c4, 0x18c4, 0x00c5, 0x08c5, 0x10c5,
    0x18c5, 0x00c6, 0x08c6, 0x10c6, 0x18c6, 0x00c7, 0x08c7, 0x10c7, 0x18c7, 0x00e0,
    0x08e0, 0x10e0, 0x18e0, 0x00e1, 0x08e1, 0x10e1, 0x18e1, 0x00e2, 0x08e2, 0x10e2,
    0x18e2, 0x00e3, 0x08e3, 0x10e3, 0x18e3, 0x00e4, 0x08e4, 0x10e4, 0x18e4, 0x00e5,
    0x08e5, 0x10e5, 0x18e5, 0x00e6, 0x08e6, 0x10e6, 0x18e6, 0x00e7, 0x08e7, 0x10e7, 0x18e7]

var dither16Pattern*: array[16, uint8]

##
## Pico Graphics
##

type
  PicoGraphics* = object of RootObj
    frameBuffer*: pointer
    penType*: PicoGraphicsPenType
    bounds*: Rect
    clip*: Rect
    conversionCallbackFunc*: PicoGraphicsConversionCallbackFunc
    nextPixelFunc*: PicoGraphicsNextPixelFunc
    #bitmapFont*: ref Font
    #hersheyFont*: ref Font

  PicoGraphicsPenType* {.pure.} = enum
    Pen1Bit, Pen3Bit, PenP2, PenP4, PenP8, PenRGB332, PenRGB565, PenRGB888

  PicoGraphicsConversionCallbackFunc* = proc (data: pointer; length: uint)
  PicoGraphicsNextPixelFunc* = proc (): Rgb565

func rgbToRgb332*(r: uint8; g: uint8; b: uint8): Rgb332 = constructRgb(r.int16, g.int16, b.int16).toRgb332()

func rgb332ToRgb565*(c: Rgb332): Rgb565 =
  let p = ((c.uint8 and 0b11100000) shl 8).uint16 or ((c.uint8 and 0b00011100) shl 6).uint16 or
      ((c.uint8 and 0b00000011) shl 3).uint16
  return builtinBswap16(p).Rgb565

func rgb565ToRgb332*(c: Rgb565): Rgb332 =
  let c2 = builtinBswap16(c.uint16)
  return (((c2 and 0b1110000000000000) shr 8).uint8 or ((c2 and 0b0000011100000000) shr 6).uint8 or
      ((c2 and 0b0000000000011000) shr 3).uint8).Rgb332

func rgbToRgb565*(r: uint8; g: uint8; b: uint8): Rgb565 =
  return constructRgb(r.int16, g.int16, b.int16).toRgb565()

func rgb332ToRgb*(c: Rgb332): Rgb = constructRgb(c)

func rgb565ToRgb*(c: Rgb565): Rgb = constructRgb(c)

func constructPicoGraphics*(width: uint16; height: uint16; frameBuffer: pointer): PicoGraphics {.constructor.} =
  result.bounds.x = 0
  result.bounds.y = 0
  result.bounds.w = width.int
  result.bounds.h = height.int
  result.clip.x = 0
  result.clip.y = 0
  result.clip.w = width.int
  result.clip.h = height.int
  result.frameBuffer = frameBuffer
  # setFont(font6)

method setPen*(self: var PicoGraphics; c: uint) {.base.} = discard
method setPen*(self: var PicoGraphics; r: uint8; g: uint8; b: uint8) {.base.} = discard
method setPixel*(self: var PicoGraphics; p: Point) {.base.} = discard
method setPixelSpan*(self: var PicoGraphics; p: Point; l: uint) {.base.} = discard
method createPen*(self: var PicoGraphics; r: uint8; g: uint8; b: uint8): int {.base.} = discard
method updatePen*(self: var PicoGraphics; i: uint8; r: uint8; g: uint8; b: uint8): int {.base.} = discard
method resetPen*(self: var PicoGraphics; i: uint8): int {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb) {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb565) {.base.} = discard
method setPixelDither*(self: var PicoGraphics; p: Point; c: uint8) {.base.} = discard
method frameConvert*(self: var PicoGraphics; `type`: PicoGraphicsPenType; callback: PicoGraphicsconversionCallbackFunc) {.base.} = discard
method sprite*(self: var PicoGraphics; data: pointer; sprite: Point; dest: Point; scale: int; transparent: int) {.base.} = discard

# proc setFont*(self: var PicoGraphics; font: BitmapFont) = discard
# proc setFont*(self: var PicoGraphics; font: HersheyFont) = discard
# proc setFont*(self: var PicoGraphics; font: string) = discard

proc setDimensions*(self: var PicoGraphics; width: uint16; height: uint16) =
  self.bounds.x = 0
  self.bounds.y = 0
  self.bounds.w = width.int
  self.bounds.h = height.int
  self.clip.x = 0
  self.clip.y = 0
  self.clip.w = width.int
  self.clip.h = height.int

proc setFramebuffer*(self: var PicoGraphics; frameBuffer: pointer) = self.frameBuffer = frameBuffer

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
  var clipped: Rect = r.intersection(self.clip)
  if clipped.empty():
    return
  var dest = Point(x: clipped.x, y: clipped.y)

  while clipped.h > 0:
    ##  draw span of pixels for this row
    self.setPixelSpan(dest, clipped.w.uint)
    ##  move to next scanline
    inc(dest.y)
    dec(clipped.h)

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

func orient2d(p1: Point; p2: Point; p3: Point): int =
  return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)

func isTopLeft(p1: Point; p2: Point): bool =
  return (p1.y == p2.y and p1.x > p2.x) or (p1.y < p2.y)

proc triangle*(self: var PicoGraphics; p1: var Point; p2: var Point; p3: var Point) =
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

proc line*(self: var PicoGraphics; p1: Point; p2: Point) =
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

proc frameConvertRgb565*(self: var PicoGraphics; callback: PicoGraphicsconversionCallbackFunc; getNextPixel: PicoGraphicsNextPixelFunc) =
  ##  Allocate two temporary buffers, as the callback may transfer by DMA
  ##  while we're preparing the next part of the row
  const BUF_LEN = 64
  var rowBuf: array[2, array[BUF_LEN, uint16]]
  var bufIdx = 0
  var bufEntry = 0
  for i in 0 ..< self.bounds.w * self.bounds.h:
    rowBuf[bufIdx][bufEntry] = getNextPixel().uint16
    inc(bufEntry)

    ##  Transfer a filled buffer and swap to the next one
    if bufEntry == BUF_LEN:
      callback(rowBuf[bufIdx].addr, BUF_LEN * sizeof(RGB565))
      bufIdx = bufIdx xor 1
      bufEntry = 0

  ##  Transfer any remaining pixels ( < BUF_LEN )
  if bufEntry > 0:
    callback(rowBuf[bufIdx].addr, uint(bufEntry * sizeof(RGB565)))

  ##  Callback with zero length to ensure previous buffer is fully written
  callback(rowBuf[bufIdx].addr, 0)


##
## Pico Graphics Pen 1-Bit
##

type
  PicoGraphicsPen1Bit* {.bycopy.} = object of PicoGraphics
    color*: uint8


proc constructPicoGraphicsPen1Bit*(width: uint16; height: uint16;
                                  frameBuffer: pointer): PicoGraphicsPen1Bit {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPen1Bit; c: uint) = discard
proc setPen*(self: var PicoGraphicsPen1Bit; r: uint8; g: uint8; b: uint8) = discard
proc setPixel*(self: var PicoGraphicsPen1Bit; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPen1Bit; p: Point; l: uint) =
  discard
proc bufferSize*(self: var PicoGraphicsPen1Bit; w: uint; h: uint): csize_t =
  return w * h div 8


##
## Pico Graphics Pen 1-Bit Y
##

type
  PicoGraphicsPen1BitY* {.bycopy.} = object of PicoGraphics
    color*: uint8


proc constructPicoGraphicsPen1BitY*(width: uint16; height: uint16;
                                   frameBuffer: pointer): PicoGraphicsPen1BitY {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPen1BitY; c: uint) =
  discard
proc setPen*(self: var PicoGraphicsPen1BitY; r: uint8; g: uint8; b: uint8) =
  discard
proc setPixel*(self: var PicoGraphicsPen1BitY; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPen1BitY; p: Point; l: uint) =
  discard
proc bufferSize*(self: var PicoGraphicsPen1BitY; w: uint; h: uint): csize_t =
  return w * h div 8


##
## Pico Graphics Pen 3-Bit
##

type
  PicoGraphicsPen3Bit* {.bycopy.} = object of PicoGraphics
    color*: uint8
    palette*: array[8, Rgb]
    candidateCache*: array[512, array[16, uint8]]
    cacheBuilt*: bool
    candidates*: array[16, uint8]

const PicoGraphicsPen3BitPalette*: array[8, Rgb] = [
  Rgb(r: 0, g: 0, b: 0), ##  black
  Rgb(r: 255, g: 255, b: 255), ##  white
  Rgb(r: 0, g: 255, b: 0), ##  green
  Rgb(r: 0, g: 0, b: 255), ##  blue
  Rgb(r: 255, g: 0, b: 0), ##  red
  Rgb(r: 255, g: 255, b: 0), ##  yellow
  Rgb(r: 255, g: 128, b: 0), ##  orange
  Rgb(r: 220, g: 180, b: 200), ##  clean / taupe
]

const PicoGraphicsPen3BitPaletteSize*: uint16 = 8

proc constructPicoGraphicsPen3Bit*(width: uint16; height: uint16;
                                  frameBuffer: pointer): PicoGraphicsPen3Bit {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPen3Bit; c: uint) = discard
proc setPen*(self: var PicoGraphicsPen3Bit; r: uint8; g: uint8; b: uint8) = discard
proc setPixel*(self: var PicoGraphicsPen3Bit; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPen3Bit; p: Point; l: uint) = discard
proc getDitherCandidates*(self: var PicoGraphicsPen3Bit; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPen3Bit; p: Point; c: Rgb) = discard
proc frameConvert*(self: var PicoGraphicsPen3Bit; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsconversionCallbackFunc) = discard
proc bufferSize*(self: var PicoGraphicsPen3Bit; w: uint; h: uint): csize_t =
  return (w * h div 8) * 3


##
## Pico Graphics Pen P4
##

const PicoGraphicsPenP4PaletteSize*: uint16 = 16

type
  PicoGraphicsPenP4* {.bycopy.} = object of PicoGraphics
    color*: uint8
    palette*: array[PicoGraphicsPenP4PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP4PaletteSize, bool]
    candidateCache*: array[512, array[16, uint8]]
    cacheBuilt*: bool
    candidates*: array[16, uint8]

proc constructPicoGraphicsPenP4*(width: uint16; height: uint16;
                                frameBuffer: pointer): PicoGraphicsPenP4 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenP4; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenP4; r: uint8; g: uint8; b: uint8) = discard
proc updatePen*(self: var PicoGraphicsPenP4; i: uint8; r: uint8; g: uint8; b: uint8): int = discard
proc createPen*(self: var PicoGraphicsPenP4; r: uint8; g: uint8; b: uint8): int = discard
proc resetPen*(self: var PicoGraphicsPenP4; i: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenP4; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP4; p: Point; l: uint) = discard
proc getDitherCandidates*(self: var PicoGraphicsPenP4; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP4; p: Point; c: Rgb) = discard
proc frameConvert*(self: var PicoGraphicsPenP4; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(self: var PicoGraphicsPenP4; w: uint; h: uint): csize_t =
  return w * h div 2


##
## Pico Graphics Pen P8
##

const PicoGraphicsPenP8PaletteSize*: uint16 = 256

type
  PicoGraphicsPenP8* {.bycopy.} = object of PicoGraphics
    color*: uint8
    palette*: array[PicoGraphicsPenP8PaletteSize, Rgb]
    used*: array[PicoGraphicsPenP8PaletteSize, bool]
    candidateCache*: array[512, array[16, uint8]]
    cacheBuilt*: bool
    candidates*: array[16, uint8]


proc constructPicoGraphicsPenP8*(width: uint16; height: uint16;
                                frameBuffer: pointer): PicoGraphicsPenP8 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenP8; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenP8; r: uint8; g: uint8; b: uint8) = discard
proc updatePen*(self: var PicoGraphicsPenP8; i: uint8; r: uint8; g: uint8; b: uint8): int = discard
proc createPen*(self: var PicoGraphicsPenP8; r: uint8; g: uint8; b: uint8): int = discard
proc resetPen*(self: var PicoGraphicsPenP8; i: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenP8; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP8; p: Point; l: uint) = discard
proc getDitherCandidates*(self: var PicoGraphicsPenP8; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP8; p: Point; c: Rgb) = discard
proc frameConvert*(self: var PicoGraphicsPenP8; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(w: uint; h: uint): csize_t =
  return w * h


##
## Pico Graphics Pen RGB332
##

type
  PicoGraphicsPenRGB332* {.bycopy.} = object of PicoGraphics
    color*: Rgb332


proc constructPicoGraphicsPenRGB332*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB332 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB332; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB332; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB332; r: uint8; g: uint8; b: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenRGB332; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB332; p: Point; l: uint) = discard
proc setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb) = discard
proc setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb565) = discard
proc sprite*(self: var PicoGraphicsPenRGB332; data: pointer; sprite: Point; dest: Point;
            scale: int; transparent: int) = discard
proc frameConvert*(self: var PicoGraphicsPenRGB332; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB332; w: uint; h: uint): csize_t =
  return w * h


##
## Pico Graphics Pen RGB565
##

type
  PicoGraphicsPenRGB565* {.bycopy.} = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb565


proc constructPicoGraphicsPenRGB565*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB565 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB565; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB565; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB565; r: uint8; g: uint8; b: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenRGB565; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB565; p: Point; l: uint) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB565; w: uint; h: uint): csize_t =
  return w * h * uint sizeof(Rgb565)


##
## Pico Graphics Pen RGB888
##

type
  PicoGraphicsPenRGB888* {.bycopy.} = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb888


proc constructPicoGraphicsPenRGB888*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB888 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB888; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB888; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB888; r: uint8; g: uint8; b: uint8): int = discard
proc setPixel*(self: var PicoGraphicsPenRGB888; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB888; p: Point; l: uint) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB888; w: uint; h: uint): csize_t =
  return w * h * uint sizeof(Rgb888)


##
## Display Driver
##

type
  DisplayDriver* = object of RootObj
    width*: uint16
    height*: uint16
    rotation*: Rotation


proc constructDisplayDriver*(width: uint16; height: uint16; rotation: Rotation): DisplayDriver {.
    constructor.} =
  discard

proc update*(self: var DisplayDriver; display: ptr PicoGraphics) =
  discard

proc partialUpdate*(self: var DisplayDriver; display: ptr PicoGraphics; region: Rect) =
  discard

proc setUpdateSpeed*(self: var DisplayDriver; updateSpeed: int): bool =
  return false

proc setBacklight*(self: var DisplayDriver; brightness: uint8) =
  discard

proc isBusy*(self: var DisplayDriver): bool =
  return false

proc powerOff*(self: var DisplayDriver) =
  discard

proc cleanup*(self: var DisplayDriver) =
  discard
