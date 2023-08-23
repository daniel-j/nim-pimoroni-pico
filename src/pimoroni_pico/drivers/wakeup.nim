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

  when WAKEUP_HAS_SHIFT_REGISTER:
    static: echo "Shift register ", sr
    sr.init()
    result.shift_register_state = sr.read().uint8
    sr.deinit()

var wakeup0* {.codegenDecl: "$# $# __attribute__ ((init_priority (101)))".} = initWakeup()

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
