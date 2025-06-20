import std/math

proc builtinBswap16(a: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, noSideEffect.}

##
## RGB
##

const defaultGamma*: float = 2.4
const rgbBits* = 9
const rgbMultiplier* = 1 shl rgbBits

type
  Rgb332* = distinct uint8
  Rgb565* = distinct uint16
  Rgb888* = distinct uint32
  RgbComponent* = uint8
  Rgb* {.packed.} = object
    b*, g*, r*: RgbComponent
  RgbLinearComponent* = int16
  RgbLinear* {.packed.} = object
    b*, g*, r*: RgbLinearComponent
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
  result.r = RgbComponent (c.uint8 and 0b11100000) shr 0
  result.g = RgbComponent (c.uint8 and 0b00011100) shl 3
  result.b = RgbComponent (c.uint8 and 0b00000011) shl 6

func constructRgb*(c: Rgb565): Rgb =
  result.r = RgbComponent (c.uint16 and 0b1111100000000000) shr 8
  result.g = RgbComponent (c.uint16 and 0b0000011111100000) shr 3
  result.b = RgbComponent (c.uint16 and 0b0000000000011111) shl 3

func constructRgb*(c: Rgb888): Rgb =
  result.r = RgbComponent (c.uint32 shr 16) and 0xff
  result.g = RgbComponent (c.uint32 shr 8) and 0xff
  result.b = RgbComponent c.uint32 and 0xff

func constructRgbBe*(c: Rgb565): Rgb =
  result.r = RgbComponent (builtinBswap16(c.uint16) and 0b1111100000000000) shr 8
  result.g = RgbComponent (builtinBswap16(c.uint16) and 0b0000011111100000) shr 3
  result.b = RgbComponent (builtinBswap16(c.uint16) and 0b0000000000011111) shl 3

func constructRgb*(r, g, b: RgbComponent): Rgb =
  result.r = r
  result.g = g
  result.b = b

func constructRgb*(r, g, b: float32): Rgb =
  result.r = RgbComponent round(r * 255.0f)
  result.g = RgbComponent round(g * 255.0f)
  result.b = RgbComponent round(b * 255.0f)

func constructRgb*(l: RgbComponent): Rgb =
  result.r = l
  result.g = l
  result.b = l

func blend*(s, d, a: uint8): uint8 =
  return d + ((a * (s - d) + 127) shr 8)

func blend*(self: Rgb; with: Rgb; alpha: uint8): Rgb =
  result.r = blend(with.r, self.r, alpha)
  result.g = blend(with.g, self.g, alpha)
  result.b = blend(with.b, self.b, alpha)


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

  result.r = RgbComponent round(hue2rgb(p, q, h + 1.0f/3.0f).clamp(0, 1) * 255.0f)
  result.g = RgbComponent round(hue2rgb(p, q, h).clamp(0, 1) * 255.0f)
  result.b = RgbComponent round(hue2rgb(p, q, h - 1.0f/3.0f).clamp(0, 1) * 255.0f)

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

func clamp*(self: RgbLinear; lower: RgbLinearComponent = 0; upper: RgbLinearComponent = rgbMultiplier - 1): RgbLinear =
  result.r = self.r.clamp(lower, upper)
  result.g = self.g.clamp(lower, upper)
  result.b = self.b.clamp(lower, upper)

func clamp*(palette: openArray[RgbLinear]): seq[RgbLinear] =
  result.setLen(palette.len)
  for i, c in palette:
    result[i] = c.clamp()

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

func generateRgbToLinearCache(gamma: float = defaultGamma): array[256, RgbLinearComponent] {.compileTime.} =
  for i, _ in result:
    result[i] = RgbLinearComponent round((i / 255).linearize1(gamma) * rgbMultiplier)

func generateRgbFromLinearCache(gamma: float = defaultGamma): array[rgbMultiplier, RgbComponent] {.compileTime.} =
  for i, _ in result:
    result[i] = RgbComponent round((i / rgbMultiplier).delinearize1(gamma) * 255)

const rgbToLinearCache = generateRgbToLinearCache(defaultGamma)
const rgbFromLinearCache = generateRgbFromLinearCache(defaultGamma)

# From https://github.com/makew0rld/dither/blob/master/color_spaces.go
func toLinear*(c: Rgb; gamma: static[float] = defaultGamma; cheat: static[bool] = false): RgbLinear =
  when cheat:
    result.r = RgbLinearComponent round((c.r.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.g = RgbLinearComponent round((c.g.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
    result.b = RgbLinearComponent round((c.b.float / 255).clamp(0, 1).pow(gamma) * rgbMultiplier)
  else:
    when gamma != defaultGamma:
      result.r = RgbLinearComponent round((c.r.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
      result.g = RgbLinearComponent round((c.g.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
      result.b = RgbLinearComponent round((c.b.float / 255).clamp(0, 1).linearize1(gamma).clamp(0, 1) * rgbMultiplier)
    else:
      result.r = rgbToLinearCache[c.r.clamp(0, 255)]
      result.g = rgbToLinearCache[c.g.clamp(0, 255)]
      result.b = rgbToLinearCache[c.b.clamp(0, 255)]

func fromLinear*(c: RgbLinear; gamma: static[float] = defaultGamma; cheat: static[bool] = false): Rgb =
  when cheat:
    result.r = RgbComponent round(c.r.float / (rgbMultiplier.float / 255)).clamp(0, 255)
    result.g = RgbComponent round(c.g.float / (rgbMultiplier.float / 255)).clamp(0, 255)
    result.b = RgbComponent round(c.b.float / (rgbMultiplier.float / 255)).clamp(0, 255)
  else:
    when gamma != defaultGamma:
      result.r = RgbComponent round((c.r.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)
      result.g = RgbComponent round((c.g.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)
      result.b = RgbComponent round((c.b.float / rgbMultiplier).clamp(0, 1).delinearize1(gamma).clamp(0, 1) * 255)
    else:
      result.r = rgbFromLinearCache[c.r.clamp(0, rgbMultiplier - 1)]
      result.g = rgbFromLinearCache[c.g.clamp(0, rgbMultiplier - 1)]
      result.b = rgbFromLinearCache[c.b.clamp(0, rgbMultiplier - 1)]

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
func distance*(c1, c2: RgbLinear): uint =
  return uint(
    1063 * sqDiff(c1.r, c2.r) div 5000 +
    447 * sqDiff(c1.g, c2.g) div 625 +
    361 * sqDiff(c1.b, c2.b) div 5000
  )

# a relatively low cost approximation of how "different" two colours are
# perceived which avoids expensive colour space conversions.
# described in detail at https://www.compuphase.com/cmetric.htm
proc distance*(self, c: Rgb): uint =
  let rmean = (self.r.int64 + c.r.int64) div 2
  let rx = self.r.int64 - c.r.int64
  let gx = self.g.int64 - c.g.int64
  let bx = self.b.int64 - c.b.int64
  return uint abs(
    (((512 + rmean) * rx * rx) shr 8) + 4 * gx * gx + (((767 - rmean) * bx * bx) shr 8)
  )

# https://bisqwit.iki.fi/story/howto/dither/jy/#GammaCorrection
# func distanceYliluoma*(c1: Rgb; c2: Rgb): float64 =
#   let r1 = c1.r.int
#   let g1 = c1.g.int
#   let b1 = c1.b.int
#   let r2 = c2.r.int
#   let g2 = c2.g.int
#   let b2 = c2.b.int
#   let luma1: float64 = (r1*299 + g1*587 + b1*114) / (255*1000)
#   let luma2: float64 = (r2*299 + g2*587 + b2*114) / (255*1000)
#   let lumadiff: float64 = luma1 - luma2
#   let diffR: float64 = (r1-r2)/255
#   let diffG: float64 = (g1-g2)/255
#   let diffB: float64 = (b1-b2)/255
#   return (diffR * diffR * 0.299 + diffG * diffG * 0.587 + diffB * diffB * 0.114) * 0.75 + lumadiff*lumadiff

# func deviseBestMixingPlan2*(input: Rgb; limit: int; palette: seq[RgbLinear]; paletteLuma: seq[int]): seq[uint8] =
#   # Tally so far (gamma-corrected)
#   var soFar: RgbLinear

#   while result.len < limit:
#     var chosenAmount = 1
#     var chosen: uint8 = 0

#     let maxTestCount = if result.len == 0: 1 else: result.len

#     var leastPenalty: float64 = -1
#     for index in 0'u8 ..< palette.len.uint8:
#       var sum: RgbLinear = soFar
#       var add: RgbLinear = palette[index]

#       var p = 1
#       while p <= maxTestCount:
#         sum += add
#         add += add

#         let t = result.len + p

#         let test = RgbLinear(
#           r: RgbLinearComponent sum.r / t,
#           g: RgbLinearComponent sum.g / t,
#           b: RgbLinearComponent sum.b / t
#         ).fromLinear()

#         let penalty = input.distanceYliluoma(test)
#         # LabItem test_lab( test[0], test[1], test[2] );
#         # double penalty = ColorCompare(test_lab, input);
#         if penalty < leastPenalty or leastPenalty < 0:
#           leastPenalty = penalty
#           chosen        = index
#           chosenAmount = p
#         p *= 2

#     # Append "chosenAmount" times "chosen" to the color list
#     for i in 0 ..< chosenAmount:
#       result.add(chosen)

#     soFar += palette[chosen] * chosenAmount.float

#   # Sort the colors according to luminance
#   result.sort(func (a, b: uint8): int {.closure.} =
#     let l1 = paletteLuma[a]
#     let l2 = paletteLuma[b]
#     return int(l1 < l2)
#   )

func closest*(self: RgbLinear; palette: openArray[RgbLinear]): int =
  var best = uint.high
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

func toLab*(palette: openArray[RgbLinear]): seq[Lab] =
  result.setLen(palette.len)
  for i in 0..<palette.len:
    result[i] = palette[i].toLab()

func fromLab*[L](palette: array[L, Lab]): array[L, RgbLinear] {.compileTime.} =
  for i in 0..<palette.len:
    result[i] = palette[i].fromLab()

func level*(self: Rgb; black: float32 = 0; white: float32 = 1; gamma: float32 = 1): Rgb =
  var r = self.r.float32 / 255.0f
  var g = self.g.float32 / 255.0f
  var b = self.b.float32 / 255.0f

  if black != 0 or white != 1:
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

  result.r = RgbComponent r * 255.0f
  result.g = RgbComponent g * 255.0f
  result.b = RgbComponent b * 255.0f

func contrast*(self: Rgb; value: float32): Rgb =
  var r = self.r.float32 / 255.0f
  var g = self.g.float32 / 255.0f
  var b = self.b.float32 / 255.0f

  r = clamp((r - 0.5f) * value + 0.5f, 0, 1)
  g = clamp((g - 0.5f) * value + 0.5f, 0, 1)
  b = clamp((b - 0.5f) * value + 0.5f, 0, 1)

  result.r = RgbComponent r * 255.0f
  result.g = RgbComponent g * 255.0f
  result.b = RgbComponent b * 255.0f

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

func toRgb565Be*(self: Rgb565): Rgb565 =
  return self.uint16.builtinBswap16.Rgb565

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
  constructRgb(r.RgbComponent, g.RgbComponent, b.RgbComponent).toRgb332()

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
  constructRgb(r.RgbComponent, g.RgbComponent, b.RgbComponent).toRgb565Be()

func rgb332ToRgb*(c: Rgb332): Rgb = constructRgb(c)

func rgb565ToRgb*(c: Rgb565): Rgb = constructRgb(c)
