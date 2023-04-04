import std/math

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##
## RGB
##

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  Rgb* {.packed.} = object
    r*: int16
    g*: int16
    b*: int16
  RgbU16* {.packed.} = object
    r*, g*, b*: uint16

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
  result.r = ((c.uint16 and 0b1111100000000000) shr 8).int16
  result.g = ((c.uint16 and 0b0000011111100000) shr 3).int16
  result.b = ((c.uint16 and 0b0000000000011111) shl 3).int16

func constructRgb*(c: Rgb888): Rgb {.constructor.} =
  result.r = int16 (c.uint shr 16) and 0xff
  result.g = int16 (c.uint shr 8) and 0xff
  result.b = int16 c.uint and 0xff

func constructRgbBe*(c: Rgb565): Rgb {.constructor.} =
  result.r = ((builtinBswap16(c.uint16) and 0b1111100000000000) shr 8).int16
  result.g = ((builtinBswap16(c.uint16) and 0b0000011111100000) shr 3).int16
  result.b = ((builtinBswap16(c.uint16) and 0b0000000000011111) shl 3).int16

func constructRgb*(r, g, b: int16): Rgb {.constructor.} =
  result.r = r
  result.g = g
  result.b = b

func constructRgb*(r, g, b: float): Rgb {.constructor.} =
  result.r = int16 round(r * 255)
  result.g = int16 round(g * 255)
  result.b = int16 round(b * 255)

func constructRgb*(l: int16): Rgb {.constructor.} =
  result.r = l
  result.g = l
  result.b = l

func `+`*(self: Rgb; c: Rgb): Rgb =
  return constructRgb(self.r + c.r, self.g + c.g, self.b + c.b)
func `+`*(self: Rgb; i: int16): Rgb =
  return constructRgb(self.r + i, self.g + i, self.b + i)
func `+`*(self: Rgb; i: float): Rgb =
  return constructRgb(int16 self.r.float + i, int16 self.g.float + i, int16 self.b.float + i)

func `*`*(self: Rgb; i: int16): Rgb =
  return Rgb(r: self.r * i, g: self.g * i, b: self.b * i)
func `*`*(self: Rgb; i: float): Rgb =
  return Rgb(r: (self.r.float * i).int16, g: (self.g.float * i).int16, b: (self.b.float * i).int16)

func `div`*(self: Rgb; i: int16): Rgb =
  return Rgb(r: self.r div i, g: self.g div i, b: self.b div i)



proc `+=`*(self: var Rgb; c: Rgb) =
  self.r += c.r
  self.g += c.g
  self.b += c.b

proc inc*(self: var Rgb; c: Rgb) =
  self += c

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
  return Rgb(r: self.r - c.r, g: self.g - c.g, b: self.b - c.b)
func `-`*(self: Rgb; i: int16): Rgb =
  return Rgb(r: self.r - i, g: self.g - i, b: self.b - i)

func luminance*(self: Rgb): int =
  ##  weights based on https://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/
  self.r * 21 + self.g * 72 + self.b * 7

const luminanceMax* = constructRgb(255, 255, 255).luminance()

func roundClamp(i: int): uint16 =
  if i < 0:
    return 0

  if i > 65535:
    return 65535

  return uint16(i)

func `+`*(c: RgbU16; i: int): RgbU16 =
  return RgbU16(
    r: roundClamp c.r.int + i,
    g: roundClamp c.g.int + i,
    b: roundClamp c.b.int + i
  )

const defaultGamma*: float = 2.2

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func linearize1*(v: float; gamma = defaultGamma): float =
  if v <= 0.04045:
    return v / 12.92
  return ((v+0.055)/1.055).pow(gamma)

func delinearize1*(v: float; gamma = defaultGamma): float =
  if v <= 0.0031308:
    return v * 12.92
  return (v * 1.055).pow(1 / gamma) - 0.055

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func toLinear*(c: Rgb; gamma = defaultGamma; cheat = false): RgbU16 =
  # # 257 = 65535 / 255
  if cheat:
    result.r = uint16 round(c.r.clamp(0, 255).float * 257.0)
    result.g = uint16 round(c.g.clamp(0, 255).float * 257.0)
    result.b = uint16 round(c.b.clamp(0, 255).float * 257.0)
  else:
    result.r = uint16 round((c.r.float / 255.0).clamp(0, 1).linearize1(gamma) * 65535.0)
    result.g = uint16 round((c.g.float / 255.0).clamp(0, 1).linearize1(gamma) * 65535.0)
    result.b = uint16 round((c.b.float / 255.0).clamp(0, 1).linearize1(gamma) * 65535.0)

func toLinear*(c: RgbU16; gamma = defaultGamma): RgbU16 =
  result.r = uint16 round((c.r.float / 65535.0).linearize1(gamma).clamp(0, 1) * 65535.0)
  result.g = uint16 round((c.g.float / 65535.0).linearize1(gamma).clamp(0, 1) * 65535.0)
  result.b = uint16 round((c.b.float / 65535.0).linearize1(gamma).clamp(0, 1) * 65535.0)

func fromLinear*(c: RgbU16; gamma = defaultGamma; cheat = false): Rgb =
  # 257 = 65535 / 255
  if cheat:
    result.r = int16 round(c.r.float / 257.0)
    result.g = int16 round(c.g.float / 257.0)
    result.b = int16 round(c.b.float / 257.0)
  else:
    result.r = int16 round((c.r.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 255.0)
    result.g = int16 round((c.g.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 255.0)
    result.b = int16 round((c.b.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 255.0)

func fromLinearU16*(c: RgbU16; gamma = defaultGamma): RgbU16 =
  result.r = uint16 round((c.r.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 65535.0)
  result.g = uint16 round((c.g.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 65535.0)
  result.b = uint16 round((c.b.float / 65535.0).delinearize1(gamma).clamp(0, 1) * 65535.0)


# From https://github.com/makew0rld/dither/blob/master/dither.go
func sqDiff(v1, v2: uint16): uint32 =
  let d = uint32(v1) - uint32(v2)
  return (d * d) shr 2

# From https://github.com/makew0rld/dither/blob/master/dither.go
func distance*(c1, c2: RgbU16): uint32 =
  ## Euclidean distance, but the square root part is removed
  ## Weight by luminance value to approximate radiant power / luminance
  ## as humans perceive it.
  ##
  ## These values were taken from Wikipedia:
  ## https://en.wikipedia.org/wiki/Grayscale#Colorimetric_(perceptual_luminance-preserving)_conversion_to_grayscale
  ## 0.2126, 0.7152, 0.0722
  ## The are changed to fractions here to keep everything in integer math:
  ##     1063/5000, 447/625, 361/5000
  ## Unfortunately this requires promoting them to uint64 to prevent overflow
  return uint32(
    1063 * uint64(sqDiff(c1.r, c2.r)) div 5000 +
    447 * uint64(sqDiff(c1.g, c2.g)) div 625 +
    361 * uint64(sqDiff(c1.b, c2.b)) div 5000
  )

func closest*(self: RgbU16; palette: openArray[RgbU16]): int =
  ## closest() returns the index of the color in the palette that's closest to
  ## the provided one, using Euclidean distance in linear RGB space. The provided
  ## RGB values must be linear RGB.
  # Go through each color and find the closest one
  var best = uint32.high
  for i, c in palette:
    let dist = self.distance(c)

    if dist < best:
      if dist == 0:
        return i
      result = i
      best = dist

# func distance*(self: Rgb; c: Rgb; whitepoint: Rgb = Rgb(r: 255, g: 255, b: 255)): float =
#   let e1 = (self)
#   let e2 = (c)
#   ##  algorithm from https://www.compuphase.com/cmetric.htm
#   let rmean = ((e1.r.float + e2.r.float) / 2) * (whitepoint.r.float / 255)
#   let rx = (e1.r.float - e2.r.float) * (whitepoint.r.float / 255)
#   let gx = (e1.g.float - e2.g.float) * (whitepoint.g.float / 255)
#   let bx = (e1.b.float - e2.b.float) * (whitepoint.b.float / 255)
#   return ((((512 + rmean) * rx * rx).int64 shr 8).float + 4.0 * gx * gx + (((767 - rmean) * bx * bx).int64 shr 8).float).abs()
#   #return ((2 + (rmean / 256)) * rx * rx + 4 * gx * gx + (2 + (255 - rmean) / 256) * bx * bx).abs()

func distanceLinear*(a, b: Rgb): int =
  return (b.r - a.r).int * (b.r - a.r).int + (b.g - a.g).int * (b.g - a.g).int + (b.b - a.b).int * (b.b - a.b).int

func distance*(self: Rgb; c: Rgb): int =
  ##  algorithm from https://www.compuphase.com/cmetric.htm
  let rmean: int64 = (self.r + c.r) div 2
  let rx: int64 = (self.r - c.r)
  let gx: int64 = (self.g - c.g)
  let bx: int64 = (self.b - c.b)
  return int (((512 + rmean) * rx * rx) shr 8) + 4 * gx * gx + (((767 - rmean) * bx * bx) shr 8)

func closest*(self: Rgb; palette: openArray[Rgb]; fallback: int = 0; whitepoint: Rgb = Rgb(r: 255, g: 255, b: 255)): int =
  assert(palette.len > 0)
  let col = self.clamp()
  var
    d = int.high
    m = fallback
  for i in 0 ..< palette.len:
    let dc = col.distance(palette[i]) # whitepoint
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

func hslToRgbU16*(h, s, l: float): RgbU16 =
  ## Converts from HSL to RGB
  ## HSL values are between 0.0 and 1.0
  if s <= 0.0:
    return constructRgb(l, l, l).toLinear(cheat=true)

  proc hue2rgb(p, q, t: float): float =
    var t2 = t
    if t2 < 0.0: t2 += 1.0
    if t2 > 1.0: t2 -= 1.0
    if t2 < 1/6: return p + (q - p) * 6 * t2
    if t2 < 1/2: return q
    if t2 < 2/3: return p + (q - p) * (2/3 - t2) * 6
    return p

  let q = if l < 0.5: l * (1 + s) else: l + s - l * s
  let p = 2 * l - q

  result.r = uint16 round(hue2rgb(p, q, h + 1/3).clamp(0, 1) * 65535.0)
  result.g = uint16 round(hue2rgb(p, q, h).clamp(0, 1) * 65535.0)
  result.b = uint16 round(hue2rgb(p, q, h - 1/3).clamp(0, 1) * 65535.0)



func toRgb565*(self: Rgb): Rgb565 =
  let c = self.clamp()
  result = Rgb565(
    ((c.r.uint16 and 0b11111000) shl 8) or
    ((c.g.uint16 and 0b11111100) shl 3) or
    ((c.b.uint16 and 0b11111000) shr 3)
  )

func toRgb565Be*(self: Rgb): Rgb565 =
  let p =
    ((self.r and 0b11111000) shl 8).uint16 or
    ((self.g and 0b11111100) shl 3).uint16 or
    ((self.b and 0b11111000) shr 3).uint16
  return builtinBswap16(p).Rgb565

func toRgb332*(self: Rgb): Rgb332 =
  let c = self.clamp()
  Rgb332(
    (c.r and 0b11100000) or
    ((c.g and 0b11100000) shr 3) or
    ((c.b and 0b11000000) shr 6)
  )

func toRgb888*(self: Rgb): Rgb888 =
  let c = self.clamp()
  Rgb888(
    (c.r.uint32 shl 16) or
    (c.g.uint32 shl 8) or
    (c.b.uint32 shl 0)
  )

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

# Vector helpers
import pkg/vmath
export vmath

proc clamp*(v: Vec3; min, max: float): Vec3 =
  return vec3(
    clamp(v.x, min, max),
    clamp(v.y, min, max),
    clamp(v.z, min, max)
  )

proc `<=`*(f: Vec3, value: float): Vec3 =
  return vec3(
    if f.x <= value: 1.0 else: 0.0,
    if f.y <= value: 1.0 else: 0.0,
    if f.z <= value: 1.0 else: 0.0
  )

proc pow*(v: Vec3; f: float): Vec3 =
  return vec3(
    pow(v.x, f),
    pow(v.y, f),
    pow(v.z, f)
  )

proc rgbToVec3*(self: Rgb): Vec3 =
  return vec3(
    self.r / 255,
    self.g / 255,
    self.b / 255
  )

proc vec3ToRgb*(v: Vec3): Rgb =
  return Rgb(
    r: int16 v.x * 255,
    g: int16 v.y * 255,
    b: int16 v.z * 255
  )

proc linearToSRGB*(rgb: Vec3; gamma: float = 2.4): Vec3 =
  let rgbClamped = clamp(rgb, 0.0, 1.0)
  return mix(
    pow(rgbClamped * 1.055, 1 / gamma) - 0.055,
    rgbClamped * 12.92,
    rgbClamped <= 0.0031308
  )

proc srgbToLinear*(rgb: Vec3; gamma: float = 2.4): Vec3 =
  let rgbClamped = clamp(rgb, 0.0, 1.0)
  return mix(
    pow((rgbClamped + 0.055) / 1.055, gamma),
    rgbClamped / 12.92,
    rgbClamped <= 0.04045
  )
