
import picostdlib/[
  pico/stdio,
  hardware/gpio,
  pico/time,
  pico/cyw43_arch
]

import pimoroni_pico/libraries/inky_frame

if cyw43_arch_init() != 0:
  echo "Wifi init failed!"
else:

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)

  discard stdioUsbInit()
  blockUntilUsbConnected()

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)

  var inky: InkyFrame
  inky.init()


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
