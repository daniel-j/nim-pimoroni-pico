import std/math

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##
## RGB
##

const defaultGamma* = 2.2
const rgbBits* = 10
const rgbMultiplier* = (1 shl rgbBits) - 1

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  Rgb* {.packed.} = object
    r*, g*, b*: int16
  RgbLinearComponent* = int16
  RgbLinear* {.packed.} = object
    r*, g*, b*: RgbLinearComponent
  Lab* {.packed.} = object
    L*, a*, b*: float32
  Hsv* {.packed.} = object
    h*, s*, v*: float32
  Hsl* {.packed.} = object
    h*, s*, l*: float32

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

func constructRgb*(r, g, b: float32): Rgb {.constructor.} =
  result.r = int16 round(r * 255.0f)
  result.g = int16 round(g * 255.0f)
  result.b = int16 round(b * 255.0f)

func constructRgb*(l: int16): Rgb {.constructor.} =
  result.r = l
  result.g = l
  result.b = l


func saturate*(self: Rgb; factor: float32): Rgb =
  const luR = 0.3086'f32
  const luG = 0.6094'f32
  const luB = 0.0820'f32

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

func level*(self: Rgb; black: float32 = 0; white: float32 = 1; gamma: float32 = 1): Rgb =
  var r = self.r.float32 / 255.0f
  var g = self.g.float32 / 255.0f
  var b = self.b.float32 / 255.0f

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

  result.r = (r * 255.0f).int16
  result.g = (g * 255.0f).int16
  result.b = (b * 255.0f).int16

func toRgb*(hsv: Hsv): Rgb =
  ## Converts from HSV to RGB
  ## HSV values are between 0.0 and 1.0
  let s = hsv.s
  let v = hsv.v
  if s <= 0.0:
    return constructRgb(v, v, v)

  let h = hsv.h

  let i = int(h * 6.0f)
  let f = h * 6.0f - float32(i)
  let p = v * (1.0f - s)
  let q = v * (1.0f - f * s)
  let t = v * (1.0f - (1.0f - f) * s)

  case i mod 6:
    of 0: return constructRgb(v, t, p)
    of 1: return constructRgb(q, v, p)
    of 2: return constructRgb(p, v, t)
    of 3: return constructRgb(p, q, v)
    of 4: return constructRgb(t, p, v)
    of 5: return constructRgb(v, p, q)
    else: return constructRgb(0, 0, 0)

func toRgb*(hsl: Hsl): Rgb =
  ## Converts from HSL to RGB
  ## HSL values are between 0.0 and 1.0
  let s = hsl.s
  let l = hsl.l
  if s <= 0.0:
    return constructRgb(l, l, l)

  let h = hsl.h

  proc hue2rgb(p, q, t: float32): float32 =
    var t2 = t
    if t2 < 0.0: t2 += 1.0
    if t2 > 1.0: t2 -= 1.0
    if t2 < 1/6: return p + (q - p) * 6 * t2
    if t2 < 1/2: return q
    if t2 < 2/3: return p + (q - p) * (2/3 - t2) * 6
    return p

  let q = if l < 0.5f: l * (1 + s) else: l + s - l * s
  let p = 2.0f * l - q

  result.r = int16 round(hue2rgb(p, q, h + 1.0f/3.0f).clamp(0, 1) * 255.0f)
  result.g = int16 round(hue2rgb(p, q, h).clamp(0, 1) * 255.0f)
  result.b = int16 round(hue2rgb(p, q, h - 1.0f/3.0f).clamp(0, 1) * 255.0f)

func toHsl*(col: Rgb): Hsl =
  let r = col.r.float32 / 255.0f
  let g = col.g.float32 / 255.0f
  let b = col.b.float32 / 255.0f
  let valMin = min(r, min(g, b))
  let valMax = max(r, max(g, b))
  let delta = valMax - valMin
  var h = 0.0f

  if delta == 0.0f:
    h = 0.0f
  elif valMax == r:
    h = ((g - b) / delta)
  elif valMax == g:
    h = (b - r) / delta + 2
  elif valMax == b:
    h = (r - g) / delta + 4

  h = h * 60.0f / 360.0f

  if h < 0: h += 1.0f

  let l = (valMin + valMax) / 2

  let s = (
    if delta == 0.0f:
      0.0f
    elif l <= 0.5f:
      delta / (valMax + valMin)
    else:
      delta / (2 - valMax - valMin)
  )

  result.h = h
  result.s = s
  result.l = l


func `+`*(lhs: RgbLinear; rhs: RgbLinear): RgbLinear =
  return RgbLinear(r: lhs.r + rhs.r, g: lhs.g + rhs.g, b: lhs.b + rhs.b)
func `+`*(lhs: RgbLinear; rhs: RgbLinearComponent): RgbLinear =
  return RgbLinear(r: lhs.r + rhs, g: lhs.g + rhs, b: lhs.b + rhs)
func `-`*(self: RgbLinear; c: RgbLinear): RgbLinear =
  return RgbLinear(r: self.r - c.r, g: self.g - c.g, b: self.b - c.b)
func `*`*(self: RgbLinear; i: RgbLinearComponent): RgbLinear =
  return RgbLinear(r: self.r * i, g: self.g * i, b: self.b * i)
func `*`*(self: RgbLinear; i: float32): RgbLinear =
  return RgbLinear(r: RgbLinearComponent self.r.float32 * i, g: RgbLinearComponent self.g.float32 * i, b: RgbLinearComponent self.b.float32 * i)
func `div`*(self: RgbLinear; i: RgbLinearComponent): RgbLinear =
  return RgbLinear(r: self.r div i, g: self.g div i, b: self.b div i)
func `shr`*(self: RgbLinear; i: RgbLinearComponent): RgbLinear =
  return RgbLinear(r: self.r shr i, g: self.g shr i, b: self.b shr i)
func `shl`*(self: RgbLinear; i: RgbLinearComponent): RgbLinear =
  return RgbLinear(r: self.r shl i, g: self.g shl i, b: self.b shl i)

proc `+=`*(self: var RgbLinear; c: RgbLinear) =
  self.r += c.r
  self.g += c.g
  self.b += c.b

func clamp*(self: RgbLinear): RgbLinear =
  result.r = self.r.clamp(0, rgbMultiplier)
  result.g = self.g.clamp(0, rgbMultiplier)
  result.b = self.b.clamp(0, rgbMultiplier)

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func linearize1*(v: float32; gamma: float32 = defaultGamma): float32 =
  if v <= 0.04045f:
    return v / 12.92f
  return ((v + 0.055f) / 1.055f).pow(gamma)

func delinearize1*(v: float32; gamma: float32 = defaultGamma): float32 =
  if v <= 0.0031308f:
    return v * 12.92f
  return (v * 1.055f).pow(1.0f / gamma) - 0.055f

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func toLinear*(c: Rgb; gamma: float32 = defaultGamma; cheat = false): RgbLinear =
  if cheat:
    result.r = RgbLinearComponent round((c.r.float32 / 255.0f).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.g = RgbLinearComponent round((c.g.float32 / 255.0f).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.b = RgbLinearComponent round((c.b.float32 / 255.0f).clamp(0, 1).pow(gamma) * rgbMultiplier)
  else:
    result.r = RgbLinearComponent round((c.r.float32 / 255.0f).clamp(0, 1).linearize1(gamma) * rgbMultiplier)
    result.g = RgbLinearComponent round((c.g.float32 / 255.0f).clamp(0, 1).linearize1(gamma) * rgbMultiplier)
    result.b = RgbLinearComponent round((c.b.float32 / 255.0f).clamp(0, 1).linearize1(gamma) * rgbMultiplier)

func fromLinear*(c: RgbLinear; gamma: float32 = defaultGamma; cheat = false): Rgb =
  if cheat:
    result.r = int16 round(c.r.float32 / (rgbMultiplier.float32 / 255)).clamp(0, 255)
    result.g = int16 round(c.g.float32 / (rgbMultiplier.float32 / 255)).clamp(0, 255)
    result.b = int16 round(c.b.float32 / (rgbMultiplier.float32 / 255)).clamp(0, 255)
  else:
    result.r = int16 round((c.r.float32 / rgbMultiplier).delinearize1(gamma).clamp(0, 1) * 255.0f)
    result.g = int16 round((c.g.float32 / rgbMultiplier).delinearize1(gamma).clamp(0, 1) * 255.0f)
    result.b = int16 round((c.b.float32 / rgbMultiplier).delinearize1(gamma).clamp(0, 1) * 255.0f)

# https://bottosson.github.io/posts/oklab/
# See linear_srgb_to_oklab() and oklab_to_linear_srgb()
func toLab*(c: RgbLinear): Lab =
  let r = c.r.float32 / rgbMultiplier
  let g = c.g.float32 / rgbMultiplier
  let b = c.b.float32 / rgbMultiplier

  let l = cbrt(0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b)
  let m = cbrt(0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b)
  let s = cbrt(0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b)

  result.L = 0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s
  result.a = 1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s
  result.b = 0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s

func fromLab*(c: Lab): RgbLinear =
  let l = c.L + 0.3963377774f * c.a + 0.2158037573f * c.b;
  let m = c.L - 0.1055613458f * c.a - 0.0638541728f * c.b;
  let s = c.L - 0.0894841775f * c.a - 1.2914855480f * c.b;

  let l3 = l * l * l
  let m3 = m * m * m
  let s3 = s * s * s

  result.r = int16 round((+4.0767416621f * l3 - 3.3077115913f * m3 + 0.2309699292f * s3) * rgbMultiplier)
  result.g = int16 round((-1.2684380046f * l3 + 2.6097574011f * m3 - 0.3413193965f * s3) * rgbMultiplier)
  result.b = int16 round((-0.0041960863f * l3 - 0.7034186147f * m3 + 1.7076147010f * s3) * rgbMultiplier)

func LChToLab*(L, C, h: float32): Lab =
  result.L = L
  let rad = degToRad(h * 360.0f)
  result.a = C * cos(rad)
  result.b = C * sin(rad)

# Simple euclidian distance function
func deltaE76*(col1, col2: Lab): float32 =
  let dL = col2.L - col1.L
  let da = col2.a - col1.a
  let db = col2.b - col1.b
  return sqrt(dL * dL + da * da + db * db)

# https://github.com/svgeesus/svgeesus.github.io/blob/master/Color/OKLab-notes.md
func deltaEOK*(col1, col2: Lab): float32 =
  let dL = col1.L - col2.L
  let C1 = sqrt(col1.a * col1.a + col1.b * col1.b)
  let C2 = sqrt(col2.a * col2.a + col2.b * col2.b)
  let dC = C1 - C2
  let da = col1.a - col2.a
  let db = col1.b - col2.b
  let dH = sqrt(da * da + db * db - dC * dC)
  return sqrt(dL * dL + dC * dC + dH * dH)

# http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE2000.html
# https://github.com/hamada147/IsThisColourSimilar/blob/master/Colour.js#L252
func deltaE00*(col1, col2: Lab): float =
  let avgL = (col1.L + col2.L) / 2
  let c1 = sqrt(col1.a * col1.a + col1.b * col1.b)
  let c2 = sqrt(col2.a * col2.a + col2.b * col2.b)
  let avgC = (c1 + c2) / 2
  let avgC7 = pow(avgC, 7)
  const pow25_7 = pow(25.0, 7)
  let g = (1 - sqrt(avgC7 / (avgC7 + pow25_7))) / 2

  let a1p = col1.a * (1 + g)
  let a2p = col2.a * (1 + g)

  let c1p = sqrt(a1p * a1p + col1.b * col1.b)
  let c2p = sqrt(a2p * a2p + col2.b * col2.b)

  let avgCp = (c1p + c2p) / 2

  var h1p = radToDeg(arctan2(col1.b, a1p))
  var h2p = radToDeg(arctan2(col2.b, a2p))
  if h1p < 0:
    h1p += 360
  if h2p < 0:
    h2p += 360

  let avghp = if abs(h1p - h2p) > 180: (h1p + h2p + 360) / 2 else: (h1p + h2p) / 360

  let t = 1 - 0.17 * cos(degToRad(avghp - 30)) + 0.24 * cos(degToRad(2 * avghp)) + 0.32 * cos(degToRad(3 * avghp + 6)) - 0.2 * cos(degToRad(4 * avghp - 63))

  var deltahp = h2p - h1p
  if abs(deltahp) > 180:
    if h2p <= h1p:
      deltahp += 360
    else:
      deltahp -= 360

  let deltalp = col2.L - col1.L
  let deltacp = c2p - c1p

  deltahp = 2 * sqrt(c1p * c2p) * sin(degToRad(deltahp) / 2)

  let sl = 1 + ((0.015 * pow(avgL - 50, 2)) / sqrt(20 + pow(avgL - 50, 2)))
  let sc = 1 + 0.045 * avgCp
  let sh = 1 + 0.015 * avgCp * t


  let deltaro = 30 * exp(-(pow((avghp - 275) / 25, 2)))
  let avgCp7 = pow(avgCp, 7)
  let rc = 2 * sqrt(avgCp7 / (avgCp7 + pow25_7))
  let rt = -rc * sin(2 * degToRad(deltaro))

  const kl = 1
  const kc = 1
  const kh = 1

  return sqrt(pow(deltalp / (kl * sl), 2) + pow(deltacp / (kc * sc), 2) + pow(deltahp / (kh * sh), 2) + rt * (deltacp / (kc * sc)) * (deltahp / (kh * sh)))


# From https://github.com/makew0rld/dither/blob/master/dither.go
# See sqDiff()
func sqDiff(v1, v2: int32): uint64 =
  let d = (v1) - (v2)
  return uint64 (d * d) shr 2

# From https://github.com/makew0rld/dither/blob/master/dither.go
# See closestColor()
func distance*(c1, c2: RgbLinear): uint32 =
  return uint32(
    1063 * sqDiff(c1.r, c2.r) div 5000 +
    447 * sqDiff(c1.g, c2.g) div 625 +
    361 * sqDiff(c1.b, c2.b) div 5000
  )

func closest*(self: RgbLinear; palette: openArray[RgbLinear]): int =
  var best = uint32.high
  for i, c in palette:
    let dist = self.distance(c)

    if dist < best:
      if dist == 0:
        return i
      result = i
      best = dist

func closest*(self: Lab; palette: openArray[Lab]): int =
  var best = float.high
  for i, c in palette:
    let dist = self.deltaEOK(c)

    if dist < best:
      if dist == 0:
        return i
      result = i
      best = dist

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
    (c.b.uint32)
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
