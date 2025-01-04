import picostdlib/hardware/gpio

import ../common/pimoroni_common

export gpio, pimoroni_common

type
  Button* = object
    pin: Gpio
    polarity: Polarity
    repeatTime: uint32
    holdTime: uint32
    pressed: bool
    lastState: bool
    pressedTime: uint32
    lastTime: uint32

proc createButton*(pin: Gpio; polarity: Polarity = ActiveLow; repeatTime: uint32 = 200; holdTime: uint32 = 1000): Button =
  result.pin = pin
  result.polarity = polarity
  result.repeatTime = repeatTime
  result.holdTime = holdTime
  result.pin.setFunction(Sio)
  result.pin.setDir(In)
  if result.polarity == ActiveLow:
    result.pin.pullUp()
  else:
    result.pin.pullDown()

proc raw*(self: Button): bool =
  result = self.pin.get() == High
  if self.polarity == ActiveLow:
    result = not result

proc read*(self: var Button): bool =
  let time = millis()
  let state = self.raw()
  let changed = state != self.lastState
  self.lastState = state

  if changed:
    if state:
      self.pressedTime = time
      self.pressed = true
      self.lastTime = time
      return true
    else:
      self.pressedTime = 0
      self.pressed = false
      self.lastTime = 0

  if self.repeatTime == 0: return false

  if self.pressed:
    var repeatRate = self.repeatTime
    if self.holdTime > 0 and time - self.pressedTime > self.holdTime:
      repeatRate = repeatRate div 3

    if time - self.lastTime > repeatRate:
      self.lastTime = time
      return true

  return false
