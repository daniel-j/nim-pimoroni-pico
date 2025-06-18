import pixie
import ./pico_graphics
export pixie, pico_graphics


const palette13_3 = [
  Hsl(h:   0/360, s: 1.00, l: 0.00).toRgb().toLinear(0.9), ##  black
  Hsl(h:   0/360, s: 0.00, l: 1.00).toRgb().toLinear(0.9), ##  white
  Hsl(h: 145/360, s: 1.00, l: 0.19).toRgb().toLinear(0.9), ##  green
  Hsl(h: 228/360, s: 0.85, l: 0.37).toRgb().toLinear(0.9), ##  blue
  Hsl(h:   0/360, s: 1.00, l: 0.35).toRgb().toLinear(0.9), ##  red
  Hsl(h:  60/360, s: 1.00, l: 0.50).toRgb().toLinear(0.9), ##  yellow
  constructRgb(255, 0, 255).toLinear(0.9), ##  7th colour unused
  constructRgb(255, 0, 255).toLinear(0.9), ##  8th colour unused
]

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

const palette5_7 = [
  Hsl(h: 200/360, s: 0.67, l: 0.18).toRgb().toLinear(paletteGamma), ##  black
  Hsl(h:  45/360, s: 0.25, l: 0.80).toRgb().toLinear(paletteGamma), ##  white
  Hsl(h: 125/360, s: 0.85, l: 0.33).toRgb().toLinear(paletteGamma), ##  green
  Hsl(h: 265/360, s: 0.08, l: 0.45).toRgb().toLinear(paletteGamma), ##  blue
  Hsl(h:  10/360, s: 0.55, l: 0.60).toRgb().toLinear(paletteGamma), ##  red
  Hsl(h:  50/360, s: 0.80, l: 0.60).toRgb().toLinear(paletteGamma), ##  yellow
  Hsl(h:  25/360, s: 0.80, l: 0.62).toRgb().toLinear(paletteGamma), ##  orange
  Hsl(h:  32/360, s: 0.70, l: 0.80).toRgb().toLinear(paletteGamma), ##  clean
]

const basic_palette = [
  Rgb(r:   0, g:   0, b:   0),
  Rgb(r: 255, g: 255, b: 255),
  Rgb(r:   0, g: 255, b:   0),
  Rgb(r:   0, g:   0, b: 255),
  Rgb(r: 255, g:   0, b:   0),
  Rgb(r: 255, g: 255, b:   0),
  Rgb(r: 255, g: 128, b:   0),
  Rgb(r: 255, g:   0, b: 255),
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
    InkyFrame4_0, InkyFrame5_7, InkyFrame7_3, InkyFrame13_3
  InkyFrame*[kind: static[InkyFrameKind]] = object of PicoGraphicsPen3Bit
    width*, height*: int
    colorCount*: int
    image*: Image
    fb: seq[uint8]

const PicoGraphicsPen3BitPaletteLut5_7* = generateNearestCache(PicoGraphicsPen3BitPalette5_7[0..<7])
const PicoGraphicsPen3BitPaletteLut7_3* = generateNearestCache(PicoGraphicsPen3BitPalette7_3[0..<7])
const PicoGraphicsPen3BitPaletteLut13_3* = generateNearestCache(PicoGraphicsPen3BitPalette13_3[0..<6])

proc init*(self: var InkyFrame) =
  (self.width, self.height, self.colorCount) =
    case self.kind:
    of InkyFrame4_0: (640, 400, 7)
    of InkyFrame5_7: (600, 448, 7)
    of InkyFrame7_3: (800, 480, 7)
    of InkyFrame13_3: (1600, 1200, 6)

  self.fb.setLen(PicoGraphicsPen3Bit.bufferSize(self.width.uint, self.height.uint))

  PicoGraphicsPen3Bit(self).init(
    width = self.width.uint16,
    height = self.height.uint16,
    backend = BackendMemory,
    palette = case self.kind:
      of InkyFrame13_3: PicoGraphicsPen3BitPalette13_3
      of InkyFrame7_3: PicoGraphicsPen3BitPalette7_3
      else: PicoGraphicsPen3BitPalette5_7,
    frameBuffer = self.fb[0].addr,
    paletteSize = self.colorCount.uint8
  )
  self.cacheNearest = case self.kind:
    of InkyFrame13_3: PicoGraphicsPen3BitPaletteLut13_3.unsafeAddr
    of InkyFrame7_3: PicoGraphicsPen3BitPaletteLut7_3.unsafeAddr
    else: PicoGraphicsPen3BitPaletteLut5_7.unsafeAddr
  # self.cacheNearestBuilt = true

  self.image = newImage(self.width, self.height)

proc update*(self: var InkyFrame) =
  let image = self.image
  let palette = case self.kind:
    of InkyFrame13_3: palette13_3
    of InkyFrame7_3: palette7_3
    else: palette5_7
  var y = 0
  self.frameConvert(PicoGraphicsPenP4, (proc (buf: pointer; length: uint) =
    if length > 0:
      let arr = cast[ptr UncheckedArray[uint8]](buf)
      for i in 0..<length.int * 2:
        let x = i div 2
        let offset = (i mod 2)
        let pen = if offset == 0: (arr[x] shr 4) else: (arr[x] and 0b1111)
        let color = palette[pen].fromLinear(cheat = true) #basic_palette[pen]
        image[i, y] = ColorRGB(
          r: color.r.uint8,
          g: color.g.uint8,
          b: color.b.uint8
        )
      inc(y)
  ))

template setPen*(self: var InkyFrame; c: Pen) = self.setPen(c.uint8)
