import std/math
import picostdlib
import pimoroni_pico/libraries/galactic_unicorn

# discard setSysClockKhz(250_000, false)

stdioInitAll()

# var graphics: PicoGraphicsPenRgb888
# graphics.init(GalacticUnicornWidth, GalacticUnicornHeight)

var unicorn: GalacticUnicorn
unicorn.init()

unicorn.setBrightness(0.5)

const PI2: float32 = PI * 2.0

const hueMap = static:
  var arr: array[GalacticUnicornWidth, Rgb]
  for i, _ in arr:
    arr[i] = Hsl(h: i / GalacticUnicornWidth, s: 1.0, l: 0.5).toRgb()
  arr

const sinCache2 = static:
  var arr: array[GalacticUnicornHeight, float32]
  for y in 0 ..< GalacticUnicornHeight:
    arr[y] = sin((y.float32 * PI2) / 11.0'f32)
  arr

var i: float32 = 0.0
var animate = true
var stripeWidth: float32 = 3.0
var speed: float32 = 1.0
var curve: float32 = 0.0

var lastTime = getAbsoluteTime()
var deltaTime: float32

while true:

  if unicorn.isPressed(SwitchVolumeUp):
    curve += 0.05
    if curve > 2.0:
      curve = 2.0

  if unicorn.isPressed(SwitchVolumeDown):
    curve -= 0.05
    if curve < -2.0:
      curve = -2.0

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

  if animate:
    i += deltaTime * 30 * speed

  let idiv: float32 = i / 15.0'f32

  for pos in 0 ..< GalacticUnicornWidth * GalacticUnicornHeight:
    let x = pos mod GalacticUnicornWidth
    let y = pos div GalacticUnicornWidth
    let hsvColor = hueMap[x]
    var v: float32 = (sin((x + y).float32 / stripeWidth + (sinCache2[y] * curve) + idiv) + 1.5'f32) / 2.5'f32

    if x > 0 and y > 0 and x < GalacticUnicornWidth - 1 and y < GalacticUnicornHeight - 1:
      v *= 0.7'f32

    unicorn.setPixel(x, y, uint8 hsvColor.r.float32 * v, uint8 hsvColor.g.float32 * v, uint8 hsvColor.b.float32 * v)

    # let color = constructRgb(
    #   int16 hsvColor.r.float32 * v,
    #   int16 hsvColor.g.float32 * v,
    #   int16 hsvColor.b.float32 * v
    # )

    # graphics.setPen(color)
    # graphics.setPixel(Point(x: x, y: y))



  # unicorn.update(graphics)

  # while diffUs(lastTime, getAbsoluteTime()) < 1000_000 div 30:
  #   tightLoopContents()

  let now = getAbsoluteTime()
  let diff = diffUs(lastTime, now).int
  deltaTime = diff / 1000_000
  when not defined(release):
    echo "fps: ", (1000_000 / diff)
  lastTime = now
