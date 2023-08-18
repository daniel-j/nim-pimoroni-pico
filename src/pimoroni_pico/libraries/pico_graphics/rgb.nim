import std/math

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##
## RGB
##

const defaultGamma*: float32 = 2.4
const rgbBits* = 12
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
    L*, a*, b*: float64
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

func constructRgb*(): Rgb =
  result.r = 0
  result.g = 0
  result.b = 0

func constructRgb*(c: Rgb332): Rgb =
  result.r = ((c.uint8 and 0b11100000) shr 0).int16
  result.g = ((c.uint8 and 0b00011100) shl 3).int16
  result.b = ((c.uint8 and 0b00000011) shl 6).int16

func constructRgb*(c: Rgb565): Rgb =
  result.r = ((c.uint16 and 0b1111100000000000) shr 8).int16
  result.g = ((c.uint16 and 0b0000011111100000) shr 3).int16
  result.b = ((c.uint16 and 0b0000000000011111) shl 3).int16

func constructRgb*(c: Rgb888): Rgb =
  result.r = int16 (c.uint shr 16) and 0xff
  result.g = int16 (c.uint shr 8) and 0xff
  result.b = int16 c.uint and 0xff

func constructRgbBe*(c: Rgb565): Rgb =
  result.r = ((builtinBswap16(c.uint16) and 0b1111100000000000) shr 8).int16
  result.g = ((builtinBswap16(c.uint16) and 0b0000011111100000) shr 3).int16
  result.b = ((builtinBswap16(c.uint16) and 0b0000000000011111) shl 3).int16

func constructRgb*(r, g, b: int16): Rgb =
  result.r = r
  result.g = g
  result.b = b

func constructRgb*(r, g, b: float32): Rgb =
  result.r = int16 round(r * 255.0f)
  result.g = int16 round(g * 255.0f)
  result.b = int16 round(b * 255.0f)

func constructRgb*(l: int16): Rgb =
  result.r = l
  result.g = l
  result.b = l


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
func linearize1*(v: float; gamma: float = defaultGamma): float =
  assert v >= 0
  if v <= 0.04045:
    return v / 12.92
  return ((v + 0.055) / 1.055).pow(gamma)

func delinearize1*(v: float; gamma: float = defaultGamma): float =
  assert v >= 0
  if v <= 0.0031308:
    return v * 12.92
  return (v * 1.055).pow(1.0 / gamma) - 0.055

func generateRgbLinearCache(gamma: float = defaultGamma): array[256, RgbLinearComponent] {.compileTime.} =
  for i, _ in result:
    result[i] = RgbLinearComponent round((i / 255).linearize1(gamma) * rgbMultiplier)

const rgbLinearCache = generateRgbLinearCache(defaultGamma)

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func toLinear*(c: Rgb; gamma: float = defaultGamma; cheat = false): RgbLinear =
  if cheat:
    result.r = RgbLinearComponent round((c.r.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.g = RgbLinearComponent round((c.g.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.b = RgbLinearComponent round((c.b.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
  else:
    if gamma != defaultGamma:
      result.r = RgbLinearComponent round((c.r.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
      result.g = RgbLinearComponent round((c.g.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
      result.b = RgbLinearComponent round((c.b.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
    else:
      result.r = rgbLinearCache[c.r.clamp(0, 255)]
      result.g = rgbLinearCache[c.g.clamp(0, 255)]
      result.b = rgbLinearCache[c.b.clamp(0, 255)]

func fromLinear*(c: RgbLinear; gamma: float = defaultGamma; cheat = false): Rgb =
  if cheat:
    result.r = int16 round(c.r.float / (rgbMultiplier.float / 255)).clamp(0, 255)
    result.g = int16 round(c.g.float / (rgbMultiplier.float / 255)).clamp(0, 255)
    result.b = int16 round(c.b.float / (rgbMultiplier.float / 255)).clamp(0, 255)
  else:
    result.r = int16 round((c.r.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)
    result.g = int16 round((c.g.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)
    result.b = int16 round((c.b.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)

# https://bottosson.github.io/posts/oklab/
# See linear_srgb_to_oklab() and oklab_to_linear_srgb()
func toLab*(c: RgbLinear): Lab =
  let r = c.r / rgbMultiplier
  let g = c.g / rgbMultiplier
  let b = c.b / rgbMultiplier

  let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

  result.L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  result.a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  result.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

func fromLab*(c: Lab): RgbLinear =
  let l = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b;
  let m = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b;
  let s = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b;

  let l3 = l * l * l
  let m3 = m * m * m
  let s3 = s * s * s

  result.r = RgbLinearComponent round((+4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3) * rgbMultiplier)
  result.g = RgbLinearComponent round((-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3) * rgbMultiplier)
  result.b = RgbLinearComponent round((-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3) * rgbMultiplier)

func LChToLab*(L, C, h: float): Lab =
  result.L = L
  let rad = degToRad(h)
  result.a = 0.4 * C * cos(rad)
  result.b = 0.4 * C * sin(rad)

func toLCh*(lab: Lab): tuple[L, C, h: float] =
  result.L = lab.L
  result.C = sqrt(lab.a * lab.a + lab.b * lab.b) / 0.4
  result.h = (arctan2(lab.b, lab.a).radToDeg() + 360) mod 360

# Simple euclidian distance function
func deltaE76*(col1, col2: Lab): float =
  let dL = col2.L - col1.L
  let da = col2.a - col1.a
  let db = col2.b - col1.b
  return sqrt(dL * dL + da * da + db * db)

# https://github.com/svgeesus/svgeesus.github.io/blob/master/Color/OKLab-notes.md
func deltaEOK*(col1, col2: Lab): float =
  let dL = col1.L - col2.L
  let C1 = sqrt(col1.a * col1.a + col1.b * col1.b)
  let C2 = sqrt(col2.a * col2.a + col2.b * col2.b)
  let dC = C1 - C2
  let da = col1.a - col2.a
  let db = col1.b - col2.b
  let dH = sqrt(da * da + db * db - dC * dC)
  return sqrt(dL * dL + dC * dC + dH * dH)

# From https://github.com/makew0rld/dither/blob/master/dither.go
# See sqDiff()
func sqDiff(v1, v2: int): uint64 =
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

func contrast*(self: Rgb; value: float32): Rgb =
  var r = self.r.float32 / 255.0f
  var g = self.g.float32 / 255.0f
  var b = self.b.float32 / 255.0f

  r = clamp((r - 0.5f) * value + 0.5f, 0, 1)
  g = clamp((g - 0.5f) * value + 0.5f, 0, 1)
  b = clamp((b - 0.5f) * value + 0.5f, 0, 1)

  result.r = (r * 255.0f).int16
  result.g = (g * 255.0f).int16
  result.b = (b * 255.0f).int16

func saturate*(self: Rgb; factor: float32): Rgb =
  var hsl = self.toHsl()
  hsl.s = clamp(hsl.s * factor, 0, 1)
  return hsl.toRgb()

func saturate*(self: Lab; factor: float): Lab =
  var lch = self.toLch()
  lch.C *= factor
  return LChToLab(lch.L, lch.C, lch.h)


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
