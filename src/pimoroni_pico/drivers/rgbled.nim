
import picostdlib/hardware/gpio
import picostdlib/hardware/pwm

import ../common/pimoroni_common
import ../libraries/pico_graphics/rgb
import ../libraries/pico_graphics/luts

export gpio, pimoroni_common, rgb

type
  RgbLed* = object
    pinR: Gpio
    pinG: Gpio
    pinB: Gpio
    polarity: Polarity
    brightness: uint8
    color: Rgb
    pwmCfg: PwmConfig

proc `=destroy`*(self: RgbLed) =
  self.pinR.setFunction(Null)
  self.pinG.setFunction(Null)
  self.pinB.setFunction(Null)

proc update*(self: RgbLed) =
  var r16 = Gamma8Bit[self.color.r].uint16
  var g16 = Gamma8Bit[self.color.g].uint16
  var b16 = Gamma8Bit[self.color.b].uint16
  r16 *= self.brightness.uint16
  g16 *= self.brightness.uint16
  b16 *= self.brightness.uint16

  if self.polarity == ActiveLow:
    r16 = uint16.high - r16
    g16 = uint16.high - g16
    b16 = uint16.high - b16

  self.pinR.setPwmLevel(r16)
  self.pinG.setPwmLevel(g16)
  self.pinB.setPwmLevel(b16)


proc createRgbLed*(pinR: Gpio; pinG: Gpio; pinB: Gpio; polarity: Polarity = ActiveLow; brightness: uint8 = 255): RgbLed =
  result.pinR = pinR
  result.pinG = pinG
  result.pinB = pinB
  result.polarity = polarity
  result.brightness = brightness

  result.pwmCfg = pwmGetDefaultConfig()
  result.pwmCfg.addr.setWrap(uint16.high)
  result.pinR.toPwmSliceNum().init(result.pwmCfg.addr, true)
  result.pinR.setFunction(Pwm)
  result.pinG.toPwmSliceNum().init(result.pwmCfg.addr, true)
  result.pinG.setFunction(Pwm)
  result.pinB.toPwmSliceNum().init(result.pwmCfg.addr, true)
  result.pinB.setFunction(Pwm)

  result.update()

proc setRgb*(self: var RgbLed; r, g, b: uint8) =
  self.color.r = r
  self.color.g = g
  self.color.b = b

proc setColor*(self: var RgbLed; color: Rgb) =
  self.color = color

proc setBrightness*(self: var RgbLed; brightness: uint8) =
  self.brightness = brightness
