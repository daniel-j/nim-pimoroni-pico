import std/math

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##
## RGB
##

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  Rgb* {.bycopy, packed.} = object
    r*: int16
    g*: int16
    b*: int16

func clamp*(self: Rgb): Rgb =
  result.r = self.r.clamp(0, 255)
  result.g = self.g.clamp(0, 255)
  result.b = self.b.clamp(0, 255)

func clamp*(self: var Rgb) =
  self.r = self.r.clamp(0, 255)
  self.g = self.g.clamp(0, 255)
  self.b = self.b.clamp(0, 255)

func constructRgb*(): Rgb {.constructor.} =
  result.r = 0
  result.g = 0
  result.b = 0

func constructRgb*(c: Rgb332): Rgb {.constructor.} =
  result.r = ((c.uint8 and 0b11100000) shr 0).int16
  result.g = ((c.uint8 and 0b00011100) shl 3).int16
  result.b = ((c.uint8 and 0b00000011) shl 6).int16

func constructRgb*(c: Rgb565): Rgb {.constructor.} =
  result.r = (((c.uint16) and 0b1111100000000000) shr 8).int16
  result.g = (((c.uint16) and 0b0000011111100000) shr 3).int16
  result.b = (((c.uint16) and 0b0000000000011111) shl 3).int16

func constructRgbBe*(c: Rgb565): Rgb {.constructor.} =
  result.r = ((builtinBswap16(c.uint16) and 0b1111100000000000) shr 8).int16
  result.g = ((builtinBswap16(c.uint16) and 0b0000011111100000) shr 3).int16
  result.b = ((builtinBswap16(c.uint16) and 0b0000000000011111) shl 3).int16

func constructRgb*(r, g, b: int16): Rgb {.constructor.} =
  result.r = r
  result.g = g
  result.b = b
  result.clamp()

func constructRgb*(r, g, b: float): Rgb {.constructor.} =
  result.r = int16 r * 255
  result.g = int16 g * 255
  result.b = int16 b * 255
  result.clamp()

func hsvToRgb*(h, s, v: float): Rgb =
  ## Converts from HSV to RGB
  ## HSV values are between 0.0 and 1.0
  if s <= 0.0:
    return constructRgb(v, v, v)

  let i = int(h * 6.0)
  let f = h * 6.0 - float(i)
  let p = v * (1.0 - s)
  let q = v * (1.0 - f * s)
  let t = v * (1.0 - (1.0 - f) * s)

  case i mod 6:
    of 0: return constructRgb(v, t, p)
    of 1: return constructRgb(q, v, p)
    of 2: return constructRgb(p, v, t)
    of 3: return constructRgb(p, q, v)
    of 4: return constructRgb(t, p, v)
    of 5: return constructRgb(v, p, q)
    else: return constructRgb(0, 0, 0)

func `+`*(self: Rgb; c: Rgb): Rgb =
  return constructRgb(self.r + c.r, self.g + c.g, self.b + c.b)

func `*`*(self: Rgb; i: int16): Rgb =
  return constructRgb(self.r * i, self.g * i, self.b * i)
func `*`*(self: Rgb; i: float): Rgb =
  return constructRgb((self.r.float * i).int16, (self.g.float * i).int16, (self.b.float * i).int16)

func `div`*(self: Rgb; i: int16): Rgb =
  return constructRgb(self.r div i, self.g div i, self.b div i)


proc inc*(self: var Rgb; c: Rgb) =
  inc(self.r, c.r)
  inc(self.g, c.g)
  inc(self.b, c.b)

proc inc*(self: var Rgb; i: int) =
  inc(self.r, i)
  inc(self.g, i)
  inc(self.b, i)

proc dec*(self: var Rgb; c: Rgb) =
  dec(self.r, c.r)
  dec(self.g, c.g)
  dec(self.b, c.b)

proc dec*(self: var Rgb; i: int) =
  dec(self.r, i)
  dec(self.g, i)
  dec(self.b, i)

func `-`*(self: Rgb; c: Rgb): Rgb =
  return constructRgb(self.r - c.r, self.g - c.g, self.b - c.b)
func `-`*(self: Rgb; i: int16): Rgb =
  return constructRgb(self.r - i, self.g - i, self.b - i)

func luminance*(self: Rgb): int =
  ##  weights based on https://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/
  return self.r * 21 + self.g * 72 + self.b * 7

func distance*(self: Rgb; c: Rgb; whitepoint: Rgb = Rgb(r: 255, g: 255, b: 255)): float =
  let e1 = (self)
  let e2 = (c)
  ##  algorithm from https://www.compuphase.com/cmetric.htm
  let rmean = ((e1.r.float + e2.r.float) / 2) * (whitepoint.r.float / 255)
  let rx = (e1.r.float - e2.r.float) * (whitepoint.r.float / 255)
  let gx = (e1.g.float - e2.g.float) * (whitepoint.g.float / 255)
  let bx = (e1.b.float - e2.b.float) * (whitepoint.b.float / 255)
  return ((((512 + rmean) * rx * rx).int64 shr 8).float + 4.0 * gx * gx + (((767 - rmean) * bx * bx).int64 shr 8).float).abs()
  #return ((2 + (rmean / 256)) * rx * rx + 4 * gx * gx + (2 + (255 - rmean) / 256) * bx * bx).abs()

func closest*(self: Rgb; palette: openArray[Rgb]; fallback: int = 0; whitepoint: Rgb = Rgb(r: 255, g: 255, b: 255)): int =
  assert(palette.len > 0)
  assert(fallback >= 0 and fallback < palette.len)
  var
    d = float.high
    m = fallback
  for i in 0 ..< palette.len:
    let dc = self.distance(palette[i], whitepoint)
    if dc < d:
      m = i
      d = dc
  return m

func saturate*(self: Rgb; factor: float): Rgb =
  const luR = 0.3086
  const luG = 0.6094
  const luB = 0.0820
  #const luR = 0.25
  #const luG = 0.7
  #const luB = 0.10

  let nfactor = (1 - factor)

  let dz = nfactor * luR
  let bz = nfactor * luG
  let cz = nfactor * luB
  let az = dz + factor
  let ez = bz + factor
  let iz = cz + factor
  let fz = cz
  let gz = dz
  let hz = bz

  let red = self.r / 255
  let green = self.g / 255
  let blue = self.b / 255

  result.r = ((az*red + bz*green + cz*blue) * 255).int16
  result.g = ((dz*red + ez*green + fz*blue) * 255).int16
  result.b = ((gz*red + hz*green + iz*blue) * 255).int16

  result.clamp()

func level*(self: Rgb; black: float = 0; white: float = 1; gamma: float = 1): Rgb =
  var r = self.r / 255
  var g = self.g / 255
  var b = self.b / 255

  if black > 0 or white < 1:
    let wb = white - black
    r = (r - black) / wb
    g = (g - black) / wb
    b = (b - black) / wb
    r = clamp(r, 0, 1)
    g = clamp(g, 0, 1)
    b = clamp(b, 0, 1)

  if gamma != 1:
    let ngamma = 1 / gamma
    r = pow(r, ngamma)
    g = pow(g, ngamma)
    b = pow(b, ngamma)

  result.r = (r * 255).int16
  result.g = (g * 255).int16
  result.b = (b * 255).int16

func toRgb565*(self: Rgb): Rgb565 =
  let rgb = self.clamp()
  result = Rgb565(
    ((rgb.r.uint16 and 0b11111000) shl 8) or
    ((rgb.g.uint16 and 0b11111100) shl 3) or
    ((rgb.b.uint16 and 0b11111000) shr 3)
  )

func toRgb565Be*(self: Rgb): Rgb565 =
  let p =
    ((self.r and 0b11111000) shl 8).uint16 or
    ((self.g and 0b11111100) shl 3).uint16 or
    ((self.b and 0b11111000) shr 3).uint16
  return builtinBswap16(p).Rgb565

func toRgb332*(self: Rgb): Rgb332 =
  (
    (self.r and 0b11100000) or
    ((self.g and 0b11100000) shr 3) or
    ((self.b and 0b11000000) shr 6)
  ).Rgb332

func toRgb888*(self: Rgb): Rgb888 =
  (
    (self.r shl 16).uint32 or
    (self.g shl 8).uint32 or
    (self.b shl 0).uint32
  ).Rgb888

func rgbToRgb332*(r, g, b: uint8): Rgb332 =
  constructRgb(r.int16, g.int16, b.int16).toRgb332()

func rgb332ToRgb565Be*(c: Rgb332): Rgb565 =
  let p =
    ((c.uint8 and 0b11100000) shl 8).uint16 or
    ((c.uint8 and 0b00011100) shl 6).uint16 or
    ((c.uint8 and 0b00000011) shl 3).uint16
  return builtinBswap16(p).Rgb565

func rgb565ToRgb332*(c: Rgb565): Rgb332 =
  let c2 = builtinBswap16(c.uint16)
  return (
    ((c2 and 0b1110000000000000) shr 8).uint8 or
    ((c2 and 0b0000011100000000) shr 6).uint8 or
    ((c2 and 0b0000000000011000) shr 3).uint8
  ).Rgb332

func rgbToRgb565*(r, g, b: uint8): Rgb565 =
  constructRgb(r.int16, g.int16, b.int16).toRgb565Be()

func rgb332ToRgb*(c: Rgb332): Rgb = constructRgb(c)

func rgb565ToRgb*(c: Rgb565): Rgb = constructRgb(c)
