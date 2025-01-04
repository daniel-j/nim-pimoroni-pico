import picostdlib
import pimoroni_pico/libraries/pico_display

stdioInitAll()

echo "hello pico display pack!"

var display = createPicoDisplay(PicoDisplay2_8)

display.setPen(Rgb(r: 255, g: 0, b: 0))

display.setPixel(Point(x: 30, y: 30))

display.rectangle(Rect(x: 30, y: 30, w: 100, h: 50))

display.setPen(Rgb(r: 0, g: 255, b: 0))

display.rectangle(Rect(x: 60, y: 60, w: 100, h: 50))

display.setPen(Rgb(r: 0, g: 0, b: 255))

display.rectangle(Rect(x: 90, y: 90, w: 100, h: 50))

echo "updating"

display.update()

display.setBacklight(100)

echo "ok"

var h = 0

display.led.setBrightness(10)

var rect = Rect(x: 120, y: 120, w: 100, h: 50)

while true:
  var btns = ""
  if display.btnA.raw():
    btns.add "A"
    rect.x -= 1
    rect.y -= 1
  if display.btnB.raw():
    btns.add "B"
    rect.x -= 1
    rect.y += 1
  if display.btnX.raw():
    btns.add "X"
    rect.x += 1
    rect.y -= 1
  if display.btnY.raw():
    btns.add "Y"
    rect.x += 1
    rect.y += 1

  let c = LChToLab(0.7, 1.0, float h mod 360).fromLab().fromLinear()
  display.setPen(c)
  display.rectangle(rect)
  display.led.setColor(c)
  display.led.update()
  display.update()
  if btns.len > 0:
    echo btns
  h += 1
  sleepMs(1)
  
