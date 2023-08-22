import picostdlib/hardware/i2c

const
  WAKEUP_PIN_MASK* = {Gpio(2), Gpio(6)}
  WAKEUP_PIN_DIR* = {Gpio(2), Gpio(6)}
  WAKEUP_PIN_VALUE* = {Gpio(2), Gpio(6)}

const
  WAKEUP_HAS_RTC* = true
  WAKEUP_RTC_SDA* = Gpio(4)
  WAKEUP_RTC_SCL* = Gpio(5)
  WAKEUP_RTC_I2C_ADDR* = I2cAddress(0x51)
let
  WAKEUP_RTC_I2C_INST* = i2c0

const
  WAKEUP_HAS_SHIFT_REGISTER* = true
  WAKEUP_SHIFT_REG_CLK* = Gpio(8)
  WAKEUP_SHIFT_REG_LATCH* = Gpio(9)
  WAKEUP_SHIFT_REG_DATA* = Gpio(10)

