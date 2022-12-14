
import picostdlib/[
  pico/stdio,
  pico/time,
  pico/cyw43_arch
]
#import pimoroni_pico/libraries/jpegdec

import pimoroni_pico/libraries/inky_frame


#proc mydraw(pDraw: ptr JPEGDRAW): cint {.noconv.} =
#  echo pDraw.x
#  return 1

if cyw43_arch_init() != 0:
  echo "Wifi init failed!"
else:

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)

  discard stdioUsbInit()
  blockUntilUsbConnected()

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)

  var inky: InkyFrame
  inky.init()

  #var jpeg: JPEGDEC
  #discard jpeg.openRAM(nil, 0, mydraw)

  inky.setPen(Colour.Clean)
  inky.clear()
  inky.setPen(Colour.Red)
  inky.rectangle(Rect(x: 20, y: 20, w: 100, h: 100))
  inky.update()

  echo "Starts!"

  echo "Wake Up Event: ", inky.getWakeUpEvent()

  while true:
    inky.led(Led.Activity, 0)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
    sleepMs(250)
    inky.led(Led.Activity, 100)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
    sleepMs(250)

    echo "Loop!"
