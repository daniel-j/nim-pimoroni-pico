import pixie
import ./pico_graphics
export pixie, pico_graphics

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
  let palette = self.getRawPalette()
  var y = 0
  self.frameConvert(Pen_P4, (proc (buf: pointer; length: uint) =
    if length > 0:
      let arr = cast[ptr UncheckedArray[uint8]](buf)
      for i in 0..<length.int * 2:
        let x = i div 2
        let offset = (i mod 2)
        let color = palette[if offset == 0: (arr[x] shr 4) else: (arr[x] and 0b1111)].fromLinear(gamma=0.5, cheat=true)
        image[i, y] = ColorRGB(
          r: color.r.uint8,
          g: color.g.uint8,
          b: color.b.uint8
        )
      inc(y)
  ))

template setPen*(self: var InkyFrame; c: Pen) = self.setPen(c.uint8)
