import std/strutils
import std/random

import pixie

import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/pico_graphics

type
  InkyFrameKind* = enum
     InkyFrame4_0, InkyFrame5_7, InkyFrame7_3
  InkyFrame* = object of PicoGraphicsPen3Bit
    kind*: InkyFrameKind
    width*, height*: int

proc init(self: var InkyFrame) = PicoGraphicsPen3Bit(self).init(self.width.uint16, self.height.uint16, BackendMemory)

var inky = InkyFrame(width: 800, height: 480, kind: InkyFrame7_3)

inky.init()
#echo "Wake Up Events: ", inky.getWakeUpEvents()

proc drawFile(filename: string) =

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  if inky.drawJpeg(filename, x, y, w, h, gravity=(0.5, 0.5)) == 1:
    echo "jpeg update"

    let image = newImage(inky.bounds.w, inky.bounds.h)
    var y = 0
    inky.frameConvert(Pen_P4, (proc (buf: pointer; length: uint) =
      if length > 0:
        let arr = cast[ptr UncheckedArray[uint8]](buf)
        for i in 0..<length * 2:
          let x = i div 2
          let offset = (i mod 2)
          let color = inky.getRawPalette()[if offset == 0: (arr[x] shr 4) else: (arr[x] and 0b1111)].fromLinear(gamma=0.5, cheat=true)
          image[i.int, y] = ColorRGB(
            r: color.r.uint8,
            g: color.g.uint8,
            b: color.b.uint8
          )
        inc(y)
    ))
    image.writeFile("inky.png")
  else:
    echo "jpeg error"
  #  inky.led(LedActivity, 0)

proc inkyProc() =
  echo "Starting..."

  drawFile("image.jpg")


inkyProc()
