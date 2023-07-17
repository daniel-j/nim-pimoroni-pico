import std/math
import picostdlib
import pimoroni_pico/libraries/galactic_unicorn

# discard setSysClockKhz(200000, false)

stdioInitAll()

var graphics: PicoGraphicsPenRgb888
graphics.init(GalacticUnicornWidth, GalacticUnicornHeight)

var unicorn: GalacticUnicorn
unicorn.init()

unicorn.setBrightness(0.5)

const hueMap = static:
  var result: array[GalacticUnicornWidth, Rgb]
  for i, _ in result:
    result[i] = hslToRgb((h: i.float / GalacticUnicornWidth.float, s: 1.0, l: 0.5))
  result

var i: float32 = 0.0
var animate = true
var stripeWidth: float32 = 3.0
var speed: float32 = 1.0
var curve: float32 = 0.0
var p = Point()

var lastTime = getAbsoluteTime()
var deltaTime: float32

proc drawRows(first, last: int) =
  for x in 0 ..< GalacticUnicornWidth:
    p.x = x
    let hsvColor = hueMap[x]
    # let hsvColor = hsvToRgb((x / GalacticUnicornWidth + hueOffset) mod 1.0, 1.0, 1.0)
    for y in first ..< last:
      p.y = y
      let v = (sin((x + y).float32 / stripeWidth + (sin((y.float32 * PI.float32 * 2.0) / 11.0) * curve) + i / 15.0) + 1.5) / 2.5

      let color = 
        (hsvColor.r.float * v).uint.clamp(0, 255) or
        (hsvColor.g.float * v).uint.clamp(0, 255) shl 8 or
        (hsvColor.b.float * v).uint.clamp(0, 255) shl 16

      graphics.setPenImpl(color)
      graphics.setPixelImpl(p)

while true:

  if animate:
    i += deltaTime * 100 * speed
  

  if unicorn.isPressed(SwitchVolumeUp):
    curve += 0.05
    if curve > 1.0:
      curve = 1.0

  if unicorn.isPressed(SwitchVolumeDown):
    curve -= 0.05
    if curve < -1.0:
      curve = -1.0

  if unicorn.isPressed(SwitchBrightnessUp):
    unicorn.adjustBrightness(+0.01)

  if unicorn.isPressed(SwitchBrightnessDown):
    unicorn.adjustBrightness(-0.01)

  if unicorn.isPressed(SwitchSleep):
    animate = false

  if unicorn.isPressed(SwitchA):
    speed += 0.1
    speed = if speed >= 10.0: 10.0 else: speed
    animate = true

  if unicorn.isPressed(SwitchB):
    speed -= 0.1
    speed = if speed <= -10.0: -10.0 else: speed
    animate = true

  if unicorn.isPressed(SwitchC):
    stripeWidth += 0.05
    stripeWidth = if stripeWidth >= 10.0: 10.0 else: stripeWidth

  if unicorn.isPressed(SwitchD):
    stripeWidth -= 0.05
    stripeWidth = if stripeWidth <= 1.0: 1.0 else: stripeWidth

  drawRows(0, GalacticUnicornHeight)

  unicorn.update(graphics)

  # while absoluteTimeDiffUs(lastTime, getAbsoluteTime()) < 1000_000 div 10:
  #   tightLoopContents()

  let now = getAbsoluteTime()
  let diff = absoluteTimeDiffUs(lastTime, now)
  deltaTime = diff.float / 1000_1000
  echo diff
  lastTime = now
