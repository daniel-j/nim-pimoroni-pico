
import picostdlib/[
  pico/stdio,
  hardware/gpio,
  pico/time,
  pico/cyw43_arch
]

import inkyframe

discard stdioUsbInit()

echo "Starts!"

if cyw43_arch_init() != 0:
  echo "Wifi init failed!"
else:
  let LedPin = Gpio(6)

  LedPin.gpioInit()
  LedPin.gpioSetDir(Out)

  while true:
    LedPin.gpioPut(High)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
    sleepMs(250)
    LedPin.gpioPut(Low)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
    sleepMs(250)

    echo "Loop!"
