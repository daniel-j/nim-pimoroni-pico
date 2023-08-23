import picostdlib/hardware/i2c

const
  WAKEUP_PIN_MASK*: set[Gpio] = {Gpio(2), Gpio(6)}
  WAKEUP_PIN_DIR*: set[Gpio] = {Gpio(2), Gpio(6)}
  WAKEUP_PIN_VALUE*: set[Gpio] = {Gpio(2), Gpio(6)}

const
  WAKEUP_HAS_SHIFT_REGISTER*: bool = true
  WAKEUP_SHIFT_REG_CLK*: Gpio = Gpio(8)
  WAKEUP_SHIFT_REG_LATCH*: Gpio = Gpio(9)
  WAKEUP_SHIFT_REG_DATA*: Gpio = Gpio(10)
