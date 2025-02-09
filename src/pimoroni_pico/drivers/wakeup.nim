import picostdlib/pico/time
import picostdlib/hardware/[gpio, i2c]
import ./shiftregister
import wakeup_config

# var runtime_wakeup_gpio_state {.importc: "runtime_wakeup_gpio_state".}: set[Gpio]

type
  Wakeup = object
    wakeup_gpio_state: set[Gpio]
    when WAKEUP_HAS_SHIFT_REGISTER:
      shift_register_state: uint8

const sr* = ShiftRegister(pinLatch: WAKEUP_SHIFT_REG_LATCH, pinClock: WAKEUP_SHIFT_REG_CLK, pinOut: WAKEUP_SHIFT_REG_DATA, bits: 8)

proc initWakeup*(): Wakeup =
  when WAKEUP_PIN_MASK != {}:
    # Assert wakeup pins (indicator LEDs, VSYS hold etc)
    static: echo "Wakeup pin states: ", (WAKEUP_PIN_MASK, WAKEUP_PIN_DIR, WAKEUP_PIN_VALUE)
    WAKEUP_PIN_MASK.init()
    WAKEUP_PIN_MASK.setDirMasked(WAKEUP_PIN_DIR)
    WAKEUP_PIN_MASK.putMasked(WAKEUP_PIN_VALUE)

  result.wakeup_gpio_state = gpioGetAll()
  sleepMs(5)
  result.wakeup_gpio_state.incl(gpioGetAll())

  when WAKEUP_HAS_RTC:
    static: echo "Wakeup has RTC"
    # Set up RTC I2C pins and send reset command
    discard WAKEUP_RTC_I2C_INST.init(100_000)
    WAKEUP_RTC_SDA.init()
    WAKEUP_RTC_SCL.init()
    WAKEUP_RTC_SDA.setFunction(I2c); WAKEUP_RTC_SDA.pullUp()
    WAKEUP_RTC_SCL.setFunction(I2c); WAKEUP_RTC_SCL.pullUp()

    # Turn off CLOCK_OUT by writing 0b111 to CONTROL_2 (0x01) register
    const data = [uint8 0x01, 0b111]
    discard WAKEUP_RTC_I2C_INST.writeBlocking(WAKEUP_RTC_I2C_ADDR, data[0].addr, data.len.csize_t, false)

    WAKEUP_RTC_I2C_INST.deinit()

    # Cleanup
    WAKEUP_RTC_SDA.init()
    WAKEUP_RTC_SCL.init()

  when WAKEUP_HAS_SHIFT_REGISTER:
    static: echo "Wakeup has shift register ", sr
    sr.init()
    result.shift_register_state = sr.read().uint8
    sr.deinit()

# init_priority is C++ only, but gcc doesn't give error
var wakeup0 {.codegenDecl: "$# $# __attribute__ ((init_priority (101)))".} = initWakeup()

proc getGpioState*(): set[Gpio] = wakeup0.wakeup_gpio_state
proc resetGpioState*() = wakeup0.wakeup_gpio_state.reset()

proc getShiftState*(): uint8 =
  when WAKEUP_HAS_SHIFT_REGISTER:
    return wakeup0.shift_register_state
  else:
    {.error: "wakeup.getShiftState: board does not have a shift register.".}

proc resetShiftState*() =
  when WAKEUP_HAS_SHIFT_REGISTER:
    wakeup0.shift_register_state.reset()
  else:
    {.error: "wakeup.resetShiftState: board does not have a shift register.".}
