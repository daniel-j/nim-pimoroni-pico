import pixie
import ./pico_graphics
export pixie, pico_graphics

const paletteGamma = 2.0

const palette = [
  hslToRgbU16(      0, 1.00, 0.00).toLinear(paletteGamma), ##  black
  hslToRgbU16(      0, 1.00, 1.00).toLinear(paletteGamma), ##  white
  hslToRgbU16(125/360, 0.75, 0.40).toLinear(paletteGamma), ##  green
  hslToRgbU16(260/360, 0.98, 0.45).toLinear(paletteGamma), ##  blue
  hslToRgbU16( 10/360, 1.00, 0.50).toLinear(paletteGamma), ##  red
  hslToRgbU16( 60/360, 0.98, 0.60).toLinear(paletteGamma), ##  yellow
  hslToRgbU16( 29/360, 1.00, 0.50).toLinear(paletteGamma), ##  orange
  hslToRgbU16(      0, 1.00, 1.00).toLinear(paletteGamma), ##  clean - do not use on inky7 as colour
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
  PicoGraphicsPen3Bit(self).init(self.width.uint16, self.height.uint16, BackendMemory)
  if self.kind == InkyFrame7_3:
    self.setPaletteSize(7)

  self.image = newImage(self.width, self.height)

proc update*(self: var InkyFrame) =
  let image = self.image
  # let palette = self.getRawPalette()
  var y = 0
  self.frameConvert(Pen_P4, (proc (buf: pointer; length: uint) =
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
