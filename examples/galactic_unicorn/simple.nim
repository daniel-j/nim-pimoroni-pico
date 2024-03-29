import picostdlib
import pimoroni_pico/libraries/galactic_unicorn

var unicorn: GalacticUnicorn
unicorn.init()

unicorn.setBrightness(0.5)

var counter = 0

while true:
  for x in 0..<GalacticUnicornWidth:
    for y in 0..<GalacticUnicornHeight:
      unicorn.setPixel((x + counter) mod GalacticUnicornWidth, y, uint8 x * 4, uint8 y *  15, 0)
  inc(counter, 2)

  tightLoopContents()
