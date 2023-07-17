# import std/strutils
import picostdlib
import pimoroni_pico/libraries/galactic_unicorn

stdioInitAll()

echo "hello!"

var unicorn: GalacticUnicorn
unicorn.init()
echo "init ok"

unicorn.setBrightness(0.5)

echo "light level: ", unicorn.light()
echo "light ok"

var counter = 0

while true:
  for x in 0..<GalacticUnicornWidth:
    for y in 0..<GalacticUnicornHeight:
      unicorn.setPixel((x + counter) mod GalacticUnicornWidth, y, uint8 x * 4, 0, uint8 y *  15)
  inc(counter, 2)

  # echo "bitstream:"
  # for i, val in unicorn.bitstream:
  #   if i mod 60 == 0: stdout.write("\n")
  #   stdout.write(val.BiggestUint.toHex(2) & " ")
  # stdout.flushFile()
  # echo ""

  # sleepMs(1000)
  tightLoopContents()
