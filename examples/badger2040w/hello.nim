import picostdlib
import pimoroni_pico/libraries/badger2040w


var badger: Badger2040W

discard stdioInitAll()

echo "Starting up Badger 2040 W"

badger.init()

badger.led(100)


badger.setPen(255)
badger.clear()

for i in 0..<badger.width:
  let l = uint8 i * 256 div badger.width
  badger.setPen(l)
  let r = Rect(x: i, y: 0, w: 1, h: badger.height)
  badger.rectangle(r)

badger.update()

while true:
  badger.led(0)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
  sleepMs(250)
  badger.led(50)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
  sleepMs(250)
  tightLoopContents()
