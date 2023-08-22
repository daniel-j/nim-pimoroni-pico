import std/strutils
import picostdlib

import pimoroni_pico/libraries/inky_frame
import pimoroni_pico/libraries/hershey_fonts_data

var inky: InkyFrame
inky.boot()

# discard stdioInitAll()

# let m = detectInkyFrameModel()
# if m.isSome:
#   echo "Detected Inky Frame model: ", m.get()
# else:
#   echo "Unknown Inky Frame model"

# assert(m.isSome)

# const inkyKind {.strdefine.} = "Unknown inkyKind"
# let inkyKindEnum = parseEnum[InkyFrameKind](inkyKind, m.get())

inky.kind = InkyFrame7_3

echo("initialising inky frame.. ")

inky.init()

inky.led(Led.LedConnection, 100)

inky.setPen(White)
inky.clear()
inky.setPen(Blue)

inky.setFont(futural)
inky.setThickness(1)
echo "Wake Up Events: ", inky.getWakeUpEvents()


let dt = inky.rtc.getDatetime()

inky.text($dt, Point(x: 10, y: 50), 200, 0.6)

inky.text($inky.getWakeUpEvents(), Point(x: 10, y: 80), 200, 0.6)

inky.text($getGpioState(), Point(x: 10, y: 100), 200, 0.6)

inky.text($gpioGetAll(), Point(x: 10, y: 120), 200, 0.6)

inky.update()
echo "done!"


inky.led(Led.LedConnection, 0)

echo "going to sleep"

inky.sleep(1)

echo "sleeping!"

while true:
  inky.led(LedConnection, 0)
  sleepMs(250)
  inky.led(LedConnection, 100)
  sleepMs(250)
  tightLoopContents()
