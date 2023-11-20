import pixie
import ./pico_graphics
export pixie, pico_graphics

const paletteGamma = 1.8

const palette7_3 = [
  Hsl(h: 200/360, s: 0.67, l: 0.05).toRgb().toLinear(paletteGamma), ##  black
  Hsl(h:  45/360, s: 0.25, l: 0.80).toRgb().toLinear(paletteGamma), ##  white
  Hsl(h: 125/360, s: 0.60, l: 0.38).toRgb().toLinear(paletteGamma), ##  green
  Hsl(h: 220/360, s: 0.15, l: 0.52).toRgb().toLinear(paletteGamma), ##  blue
  Hsl(h:  14/360, s: 0.50, l: 0.55).toRgb().toLinear(paletteGamma), ##  red
  Hsl(h:  50/360, s: 0.60, l: 0.60).toRgb().toLinear(paletteGamma), ##  yellow
  Hsl(h:  28/360, s: 0.60, l: 0.57).toRgb().toLinear(paletteGamma), ##  orange
  constructRgb(255, 0, 255).toLinear(paletteGamma), ##  clean - do not use on inky7 as colour
]

# const palette7_3 = [
#   Hsv(h: 0, s: 0, v: 0).toRgb().toLinear(1.0), ##  black
#   Hsv(h: 0, s: 0, v: 1).toRgb().toLinear(1.0), ##  white
#   Hsv(h: 121/360, s: 0.90, v: 0.53).toRgb().toLinear(1.0), ##  green
#   Hsv(h: 230/360, s: 0.34, v: 0.63).toRgb().toLinear(1.0), ##  blue
#   Hsv(h:   7/360, s: 0.61, v: 0.88).toRgb().toLinear(1.0), ##  red
#   Hsv(h:  51/360, s: 0.80, v: 1.00).toRgb().toLinear(1.0), ##  yellow
#   Hsv(h:  28/360, s: 0.76, v: 0.95).toRgb().toLinear(1.0), ##  orange
#   constructRgb(255, 0, 255).toLinear(paletteGamma), ##  clean - do not use on inky7 as colour
# ]

const palette5_7 = [
  Hsl(h: 200/360, s: 0.67, l: 0.18).toRgb().toLinear(paletteGamma), ##  black
  Hsl(h:  45/360, s: 0.25, l: 0.80).toRgb().toLinear(paletteGamma), ##  white
  Hsl(h: 125/360, s: 0.82, l: 0.35).toRgb().toLinear(paletteGamma), ##  green
  Hsl(h: 245/360, s: 0.10, l: 0.45).toRgb().toLinear(paletteGamma), ##  blue
  Hsl(h:  10/360, s: 0.55, l: 0.62).toRgb().toLinear(paletteGamma), ##  red
  Hsl(h:  50/360, s: 0.80, l: 0.60).toRgb().toLinear(paletteGamma), ##  yellow
  Hsl(h:  25/360, s: 0.80, l: 0.62).toRgb().toLinear(paletteGamma), ##  orange
  Hsl(h:  32/360, s: 0.70, l: 0.80).toRgb().toLinear(paletteGamma), ##  clean
]


type
  Colour* = enum
    Black
    White
    Green
    Blue
    Red
    Yellow
    Orange
    Clean

  Pen* = Colour

  InkyFrameKind* = enum
     InkyFrame4_0, InkyFrame5_7, InkyFrame7_3
  InkyFrame* = object of PicoGraphicsPen3Bit
    kind*: InkyFrameKind
    width*, height*: int
    image*: Image

proc init*(self: var InkyFrame) =
  (self.width, self.height) =
    case self.kind:
    of InkyFrame4_0: (640, 400)
    of InkyFrame5_7: (600, 448)
    of InkyFrame7_3: (800, 480)
  PicoGraphicsPen3Bit(self).init(
    width = self.width.uint16,
    height = self.height.uint16,
    backend = BackendMemory,
    palette = if self.kind == InkyFrame7_3: PicoGraphicsPen3BitPalette7_3 else: PicoGraphicsPen3BitPalette5_7,
    # paletteSize = if self.kind == InkyFrame5_7: 8 else: 7 # clean colour is a greenish gradient on inky7, so avoid it
  )
  # self.cacheNearest = if self.kind == InkyFrame7_3: PicoGraphicsPen3BitPaletteLut7_3 else: PicoGraphicsPen3BitPaletteLut5_7
  # self.cacheNearestBuilt = true

  self.image = newImage(self.width, self.height)

proc update*(self: var InkyFrame) =
  let image = self.image
  let palette = if self.kind == InkyFrame7_3: palette7_3 else: palette5_7
  var y = 0
  self.frameConvert(PicoGraphicsPenP4, (proc (buf: pointer; length: uint) =
    if length > 0:
      let arr = cast[ptr UncheckedArray[uint8]](buf)
      for i in 0..<length.int * 2:
        let x = i div 2
        let offset = (i mod 2)
        let pen = if offset == 0: (arr[x] shr 4) else: (arr[x] and 0b1111)
        let color = palette[pen].fromLinear(cheat=true)
        image[i, y] = ColorRGB(
          r: color.r.uint8,
          g: color.g.uint8,
          b: color.b.uint8
        )
      inc(y)
  ))

template setPen*(self: var InkyFrame; c: Pen) = self.setPen(c.uint8)
