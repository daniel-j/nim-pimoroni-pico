import picostdlib
import pimoroni_pico/libraries/galactic_unicorn

var unicorn: GalacticUnicorn
unicorn.init()

unicorn.setBrightness(0.5)

while true:
  let lightlevel = unicorn.light().int / 2000
  let pos = int lightlevel * GalacticUnicornWidth
  for x in 0..<GalacticUnicornWidth:
    for y in 0..<GalacticUnicornHeight:
      unicorn.setPixel(x, y, if x < pos: 255 else: 0, 0, uint8 y *  15)

  tightLoopContents()
