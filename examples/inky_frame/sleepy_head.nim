import std/strutils

import picostdlib
import pimoroni_pico/libraries/inky_frame
import pimoroni_pico/libraries/hershey_fonts_data


var inky: InkyFrame
inky.boot()

discard stdioInitAll()

echo "initialising inky frame.. ", inky.kind

inky.init()

proc drawRtcState*(state: Pcf85063aState; x, y: int) =
  var ii = 0
  for line in iterRtcState(state):
    inky.text(line, Point(x: x, y: y + ii*15), 220, 0.5)
    inc(ii)

inky.led(Led.LedConnection, 100)

inky.setPen(White)
inky.clear()

inky.setPen(Black)

inky.setFont(futural)
inky.setThickness(1)
echo "Wake Up Events: ", inky.getWakeUpEvents()

var dt = inky.rtc.getDatetime().toNimDateTime()

echo "Current time: ", dt, " ", inky.rtc.wasReset

inky.text("Current time: " & $dt & " " & $inky.rtc.wasReset, Point(x: 10, y: 20), 200, 0.8)

inky.text("Wakeup events: " & $inky.getWakeUpEvents(), Point(x: 10, y: 50), 200, 0.8)

let now = inky.rtc.getDatetime().toNimDateTime()
var target = now + initDuration(minutes = 1, seconds = 30)

inky.text("Estimated wakeup: " & $target, Point(x: 10, y: 80), 200, 0.6)

echo "Initial rtc state:"
printRtcState(inky.rtc.initialState)
drawRtcState(inky.rtc.initialState, 1, 120)
echo "Current rtc state:"
printRtcState(inky.rtc.readAll())

if cyw43ArchInit() == PicoOk:
  defer: cyw43ArchDeinit()
  inky.text("Input voltage: " & $inky.getVsysVoltage().formatFloat(ffDecimal, 3) & " V", Point(x: 10, y: 405), 200, 0.8)

echo "updating"
inky.update()

echo "done!"
inky.led(Led.LedConnection, 50)

echo "going to sleep"
inky.sleep(1)

while EvtRtcAlarm notin inky_frame.events():
  inky.led(LedConnection, 100)
  sleepMs(300)
  inky.led(LedConnection, 0)
  sleepMs(700)

echo "wakeup event: ", inky_frame.events()

inky.led(LedConnection, 100)

inky.setPen(White)
inky.clear()

inky.setPen(Black)

dt = inky.rtc.getDatetime().toNimDateTime()

inky.text($dt, Point(x: 10, y: 20), 200, 0.8)

echo "After sleep rtc state:"
printRtcState(inky.rtc.readAll())

drawRtcState(inky.rtc.readAll(), 1, 120)

inky.update()

inky.led(LedConnection, 0)

while true:
  tightLoopContents()
