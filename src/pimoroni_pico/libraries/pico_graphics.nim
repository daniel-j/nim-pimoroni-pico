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

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  Rgb* {.bycopy.} = object
    r*: int16
    g*: int16
    b*: int16

proc constructRgb*(): Rgb {.constructor.} =
  discard

proc constructRgb*(c: Rgb332): Rgb {.constructor.} =
  discard

proc constructRgb*(c: Rgb565): Rgb {.constructor.} =
  discard

proc constructRgb*(r: int16; g: int16; b: int16): Rgb {.constructor.} =
  discard

proc `+`*(self: Rgb; c: Rgb): Rgb {.noSideEffect.} =
  return constructRGB(self.r + c.r, self.g + c.g, self.b + c.b)

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

proc `-`*(self: Rgb; c: Rgb): Rgb {.noSideEffect.} =
  return constructRGB(self.r - c.r, self.g - c.g, self.b - c.b)

proc luminance*(self: Rgb): int {.noSideEffect.} =
  ##  weights based on https://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/
  return self.r * 21 + self.g * 72 + self.b * 7

proc distance*(self: Rgb; c: Rgb): int {.noSideEffect.} =
  var rmean = (self.r + c.r) div 2
  var rx = self.r - c.r
  var gx = self.g - c.g
  var bx = self.b - c.b
  return abs((int)((((512 + rmean) * rx * rx) shr 8) + 4 * gx * gx +
      (((767 - rmean) * bx * bx) shr 8)))

proc closest*(self: Rgb; palette: openArray[Rgb]; len: int): int {.noSideEffect.} =
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

proc toRgb565*(self: Rgb): Rgb565 =
  let p = ((self.r and 0b11111000) shl 8).uint16 or ((self.g and 0b11111100) shl 3).uint16 or ((self.b and 0b11111000) shr 3).uint16
  return builtinBswap16(p).Rgb565

proc toRgb332*(self: Rgb): Rgb332 =
  ((self.r and 0b11100000) or ((self.g and 0b11100000) shr 3) or ((self.b and 0b11000000) shr 6)).Rgb332

proc toRgb888*(self: Rgb): Rgb888 =
  ((self.r shl 16).uint32 or (self.g shl 8).uint32 or (self.b shl 0).uint32).Rgb888

type
  Pen* = int

type
  Point* {.bycopy.} = object
    x*: int
    y*: int
  
  Rect* {.bycopy.} = object
    x*: int
    y*: int
    w*: int
    h*: int

proc constructPoint*(): Point {.constructor.} = discard
proc constructPoint*(x: int32; y: int32): Point {.constructor.} =
  discard

proc `-=`*(self: var Point; a: Point): var Point {.inline.} =
  dec(self.x, a.x)
  dec(self.y, a.y)
  return self

proc `+=`*(self: var Point; a: Point): var Point {.inline.} =
  inc(self.x, a.x)
  inc(self.y, a.y)
  return self

proc `/=`*(self: var Point; a: int32): var Point {.inline.} =
  self.x = self.x div a
  self.y = self.y div a
  return self

proc clamp*(self: Point; r: Rect): Point {.noSideEffect.} =
  result.x = min(max(self.x, r.x), r.x + r.w)
  result.y = min(max(self.y, r.y), r.y + r.h)

proc `==`*(lhs: Point; rhs: Point): bool {.inline.} =
  return lhs.x == rhs.x and lhs.y == rhs.y
proc `!=`*(lhs: Point; rhs: Point): bool {.inline.} =
  return not (lhs == rhs)


## !!!Ignored construct:  inline bool operator != ( const Point & lhs , const Point & rhs ) { return ! ( lhs == rhs ) ; } inline Point operator - ( Point lhs , const Point & rhs ) { lhs -= rhs ; return lhs ; } inline Point operator - ( const Point & rhs ) { return Point ( - rhs . x , - rhs . y ) ; } inline Point operator + ( Point lhs , const Point & rhs ) { lhs += rhs ; return lhs ; } inline Point operator / ( Point lhs , const int32_t a ) { lhs /= a ; return lhs ; } struct Rect { int32_t x = 0 , y = 0 , w = 0 , h = 0 ; Rect ( ) = default ; Rect ( int32_t x , int32_t y , int32_t w , int32_t h ) : x ( x ) , y ( y ) , w ( w ) , h ( h ) { } Rect ( const Point & tl , const Point & br ) : x ( tl . x ) , y ( tl . y ) , w ( br . x - tl . x ) , h ( br . y - tl . y ) { } bool empty ( ) const ; bool contains ( const Point & p ) const ; bool contains ( const Rect & p ) const ; bool intersects ( const Rect & r ) const ; Rect intersection ( const Rect & r ) const ; void inflate ( int32_t v ) ; void deflate ( int32_t v ) ; } ;
## Error: token expected: ; but got: [identifier]!!!

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

type
  PicoGraphics* = object of RootObj
    frameBuffer*: pointer
    penType*: PicoGraphicsPenType
    bounds*: Rect
    clip*: Rect
    #bitmapFont*: ptr FontT
    #hersheyFont*: ptr FontT

  PicoGraphicsPenType* = enum
    Pen1Bit, Pen3Bit, PenP2, PenP4, PenP8, PenRGB332, PenRGB565, PenRGB888


type
  PicoGraphicsConversionCallbackFunc* = proc (data: pointer; length: uint)
  PicoGraphicsnextPixelFunc* = proc (): Rgb565

proc rgbToRgb332*(r: uint8; g: uint8; b: uint8): Rgb332 =
  return constructRGB(r.int16, g.int16, b.int16).toRgb332().Rgb332

proc rgb332ToRgb565*(c: Rgb332): Rgb565 =
  let p = ((c.uint8 and 0b11100000) shl 8).uint16 or ((c.uint8 and 0b00011100) shl 6).uint16 or
      ((c.uint8 and 0b00000011) shl 3).uint16
  return builtinBswap16(p).Rgb565

proc rgb565ToRgb332*(c: Rgb565): Rgb332 =
  let c2 = builtinBswap16(c.uint16)
  return (((c2 and 0b1110000000000000) shr 8).uint8 or ((c2 and 0b0000011100000000) shr 6).uint8 or
      ((c2 and 0b0000000000011000) shr 3).uint8).Rgb332

proc rgbToRgb565*(r: uint8; g: uint8; b: uint8): Rgb565 =
  return constructRGB(r.int16, g.int16, b.int16).toRgb565()

proc rgb332ToRgb*(c: Rgb332): Rgb =
  return constructRGB(cast[Rgb332](c))

proc rgb565ToRgb*(c: Rgb565): Rgb =
  return constructRGB(cast[Rgb565](c))

# proc constructPicoGraphics*(width: uint16; height: uint16; frameBuffer: pointer): PicoGraphics {.constructor.} =
#   setFont(addr(font6))

proc setPen*(self: var PicoGraphics; c: uint) = discard
proc setPen*(self: var PicoGraphics; r: uint8; g: uint8; b: uint8) = discard
proc setPixel*(self: var PicoGraphics; p: Point) =
  discard
proc setPixelSpan*(self: var PicoGraphics; p: Point; l: uint) = discard
proc createPen*(self: var PicoGraphics; r: uint8; g: uint8; b: uint8): cint = discard
proc updatePen*(self: var PicoGraphics; i: uint8; r: uint8; g: uint8; b: uint8): cint = discard
proc resetPen*(self: var PicoGraphics; i: uint8): cint = discard
proc setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb) =
  discard
proc setPixelDither*(self: var PicoGraphics; p: Point; c: Rgb565) =
  discard
proc setPixelDither*(self: var PicoGraphics; p: Point; c: uint8) =
  discard
proc frameConvert*(self: var PicoGraphics; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsconversionCallbackFunc) = discard
proc sprite*(self: var PicoGraphics; data: pointer; sprite: Point; dest: Point;
            scale: cint; transparent: cint) =
  discard
# proc setFont*(self: var PicoGraphics; font: ptr FontT)
# proc setFont*(self: var PicoGraphics; font: ptr FontT) = discard
proc setFont*(self: var PicoGraphics; font: string) =
  discard
proc setDimensions*(self: var PicoGraphics; width: cint; height: cint) = discard
proc setFramebuffer*(self: var PicoGraphics; frameBuffer: pointer) = discard
proc getData*(self: var PicoGraphics): pointer = discard
proc getData*(self: var PicoGraphics; `type`: PicoGraphicsPenType; y: uint;
             rowBuf: pointer) = discard
proc setClip*(self: var PicoGraphics; r: Rect) = discard
proc removeClip*(self: var PicoGraphics) = discard
proc clear*(self: var PicoGraphics) = discard
proc pixel*(self: var PicoGraphics; p: Point) = discard
proc pixelSpan*(self: var PicoGraphics; p: Point; l: int32) = discard
proc rectangle*(self: var PicoGraphics; r: Rect) = discard
proc circle*(self: var PicoGraphics; p: Point; r: int32) = discard
proc character*(self: var PicoGraphics; c: char; p: Point; s: cfloat = 2.0f;
               a: cfloat = 0.0f) = discard
proc text*(self: var PicoGraphics; t: string; p: Point; wrap: int32; s: cfloat = 2.0f;
          a: cfloat = 0.0f; letterSpacing: uint8 = 1) = discard
proc measureText*(self: var PicoGraphics; t: string; s: cfloat = 2.0f;
                 letterSpacing: uint8 = 1): int32 = discard
proc polygon*(self: var PicoGraphics; points: openArray[Point]) = discard
proc triangle*(self: var PicoGraphics; p1: Point; p2: Point; p3: Point) = discard
proc line*(self: var PicoGraphics; p1: Point; p2: Point) = discard
proc frameConvertRgb565*(self: var PicoGraphics;
                        callback: PicoGraphicsconversionCallbackFunc;
                        getNextPixel: PicoGraphicsnextPixelFunc) = discard
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
proc updatePen*(self: var PicoGraphicsPenP4; i: uint8; r: uint8; g: uint8; b: uint8): cint = discard
proc createPen*(self: var PicoGraphicsPenP4; r: uint8; g: uint8; b: uint8): cint = discard
proc resetPen*(self: var PicoGraphicsPenP4; i: uint8): cint = discard
proc setPixel*(self: var PicoGraphicsPenP4; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP4; p: Point; l: uint) = discard
proc getDitherCandidates*(self: var PicoGraphicsPenP4; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP4; p: Point; c: Rgb) = discard
proc frameConvert*(self: var PicoGraphicsPenP4; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(self: var PicoGraphicsPenP4; w: uint; h: uint): csize_t =
  return w * h div 2

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
proc updatePen*(self: var PicoGraphicsPenP8; i: uint8; r: uint8; g: uint8; b: uint8): cint = discard
proc createPen*(self: var PicoGraphicsPenP8; r: uint8; g: uint8; b: uint8): cint = discard
proc resetPen*(self: var PicoGraphicsPenP8; i: uint8): cint = discard
proc setPixel*(self: var PicoGraphicsPenP8; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenP8; p: Point; l: uint) = discard
proc getDitherCandidates*(self: var PicoGraphicsPenP8; col: Rgb; palette: ptr Rgb;
                         len: csize_t; candidates: var array[16, uint8]) = discard
proc setPixelDither*(self: var PicoGraphicsPenP8; p: Point; c: Rgb) = discard
proc frameConvert*(self: var PicoGraphicsPenP8; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(w: uint; h: uint): csize_t =
  return w * h

type
  PicoGraphicsPenRGB332* {.bycopy.} = object of PicoGraphics
    color*: Rgb332


proc constructPicoGraphicsPenRGB332*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB332 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB332; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB332; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB332; r: uint8; g: uint8; b: uint8): cint = discard
proc setPixel*(self: var PicoGraphicsPenRGB332; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB332; p: Point; l: uint) = discard
proc setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb) = discard
proc setPixelDither*(self: var PicoGraphicsPenRGB332; p: Point; c: Rgb565) = discard
proc sprite*(self: var PicoGraphicsPenRGB332; data: pointer; sprite: Point; dest: Point;
            scale: cint; transparent: cint) = discard
proc frameConvert*(self: var PicoGraphicsPenRGB332; `type`: PicoGraphicsPenType;
                  callback: PicoGraphicsConversionCallbackFunc) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB332; w: uint; h: uint): csize_t =
  return w * h

type
  PicoGraphicsPenRGB565* {.bycopy.} = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb565


proc constructPicoGraphicsPenRGB565*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB565 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB565; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB565; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB565; r: uint8; g: uint8; b: uint8): cint = discard
proc setPixel*(self: var PicoGraphicsPenRGB565; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB565; p: Point; l: uint) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB565; w: uint; h: uint): csize_t =
  return w * h * uint sizeof(Rgb565)

type
  PicoGraphicsPenRGB888* {.bycopy.} = object of PicoGraphics
    srcColor*: Rgb
    color*: Rgb888


proc constructPicoGraphicsPenRGB888*(width: uint16; height: uint16;
                                    frameBuffer: pointer): PicoGraphicsPenRGB888 {.
    constructor.} = discard
proc setPen*(self: var PicoGraphicsPenRGB888; c: uint) = discard
proc setPen*(self: var PicoGraphicsPenRGB888; r: uint8; g: uint8; b: uint8) = discard
proc createPen*(self: var PicoGraphicsPenRGB888; r: uint8; g: uint8; b: uint8): cint = discard
proc setPixel*(self: var PicoGraphicsPenRGB888; p: Point) = discard
proc setPixelSpan*(self: var PicoGraphicsPenRGB888; p: Point; l: uint) = discard
proc bufferSize*(self: var PicoGraphicsPenRGB888; w: uint; h: uint): csize_t =
  return w * h * uint sizeof(Rgb888)

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

proc setUpdateSpeed*(self: var DisplayDriver; updateSpeed: cint): bool =
  return false

proc setBacklight*(self: var DisplayDriver; brightness: uint8) =
  discard

proc isBusy*(self: var DisplayDriver): bool =
  return false

proc powerOff*(self: var DisplayDriver) =
  discard

proc cleanup*(self: var DisplayDriver) =
  discard






proc empty*(self: Rect): bool {.noSideEffect.} =
  return self.w <= 0 or self.h <= 0

proc contains*(self: Rect; p: Point): bool {.noSideEffect.} =
  return p.x >= self.x and p.y >= self.y and p.x < self.x + self.w and p.y < self.y + self.h

proc contains*(self: Rect; p: Rect): bool {.noSideEffect.} =
  return p.x >= self.x and p.y >= self.y and p.x + p.w < self.x + self.w and p.y + p.h < self.y + self.h

proc intersects*(self: Rect; r: Rect): bool {.noSideEffect.} =
  return not (self.x > r.x + r.w or self.x + self.w < r.x or self.y > r.y + r.h or self.y + self.h < r.y)

proc intersection*(self: Rect; r: Rect): Rect {.noSideEffect.} =
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
