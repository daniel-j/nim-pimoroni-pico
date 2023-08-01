import pixie
import ./pico_graphics
export pixie, pico_graphics

const paletteGamma = 1.8

# const palette = [
#   hslToRgb(      0, 1.00, 0.00).toLinear(paletteGamma), ##  black
#   hslToRgb(      0, 1.00, 1.00).toLinear(paletteGamma), ##  white
#   hslToRgb(120/360, 0.90, 0.37).toLinear(paletteGamma), ##  green
#   hslToRgb(260/360, 0.98, 0.43).toLinear(paletteGamma), ##  blue
#   hslToRgb( 10/360, 0.98, 0.45).toLinear(paletteGamma), ##  red
#   hslToRgb( 60/360, 1.00, 0.60).toLinear(paletteGamma), ##  yellow
#   hslToRgb( 29/360, 0.95, 0.45).toLinear(paletteGamma), ##  orange
#   hslToRgb(      0, 1.00, 1.00).toLinear(paletteGamma), ##  clean - do not use on inky7 as colour
# ]

const palette7_3 = [
  Hsv(h: 200/360, s: 0.80, v: 0.10).toRgb().toLinear(paletteGamma), ##  black
  Hsv(h:  30/360, s: 0.10, v: 0.88).toRgb().toLinear(paletteGamma), ##  white
  Hsv(h:  90/360, s: 1.00, v: 0.62).toRgb().toLinear(paletteGamma), ##  green
  Hsv(h: 215/360, s: 0.60, v: 0.60).toRgb().toLinear(paletteGamma), ##  blue
  Hsv(h:  20/360, s: 0.75, v: 0.80).toRgb().toLinear(paletteGamma), ##  red
  Hsv(h:  53/360, s: 0.75, v: 0.90).toRgb().toLinear(paletteGamma), ##  yellow
  Hsv(h:  24/360, s: 0.62, v: 0.87).toRgb().toLinear(paletteGamma), ##  orange
  constructRgb(255, 0, 255).toLinear(paletteGamma), ##  clean - do not use on inky7 as colour
]

const palette5_7 = [
  Hsv(h: 180/360, s: 1.00, v: 0.20).toRgb().toLinear(paletteGamma), ##  black
  palette7_3[1], ##  white
  Hsv(h: 90/360, s: 1.00, v: 0.65).toRgb().toLinear(paletteGamma), ##  green
  Hsv(h: 215/360, s: 0.70, v: 0.60).toRgb().toLinear(paletteGamma), ##  blue
  Hsv(h:  20/360, s: 0.75, v: 0.80).toRgb().toLinear(paletteGamma), ##  red
  palette7_3[5], ##  yellow
  Hsv(h:  32/360, s: 0.65, v: 0.90).toRgb().toLinear(paletteGamma), ##  orange
  Rgb(r: 245, g: 215, b: 191).toLinear(paletteGamma), ##  clean
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
  self.cacheNearest = if self.kind == InkyFrame7_3: PicoGraphicsPen3BitPaletteLut7_3 else: PicoGraphicsPen3BitPaletteLut5_7
  self.cacheNearestBuilt = true

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
