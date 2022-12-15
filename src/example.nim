
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

  echo "Starting..."

  var inky: InkyFrame
  inky.init()

  #var jpeg: JPEGDEC
  #discard jpeg.openFLASH(cast[ptr uint8](myImage[0].unsafeAddr), myImage.len.cint, mydraw)
  #jpeg.setPixelType(RGB565_BIG_ENDIAN)
  #echo "jpeg decode: ", jpeg.decode(0, 0, 0)

  inky.setPen(Colour.White)
  inky.clear()
  inky.setPen(Colour.Red)
  inky.rectangle(Rect(x: 0, y: 0, w: 100, h: 100))
  inky.setPen(Colour.Green)
  inky.polygon([P(200, 400), P(300, 100), P(120, 120)])
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
