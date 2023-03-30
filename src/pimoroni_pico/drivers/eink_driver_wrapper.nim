import ./eink_uc8159, ./eink_ac073tc1a

export eink_driver

proc init*(self: var EinkDriver; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  DisplayDriver(self).init(width, height)
  self.borderColour = White
  case self.kind:
  of KindUc8159: self.initUc8159(width, height, pins, resetPin, isBusyProc, blocking)
  of KindAc073tc1a: self.initAc073tc1a(width, height, pins, resetPin, isBusyProc, blocking)

method update*(self: var EinkDriver; graphics: var PicoGraphics) =
  case self.kind:
  of KindUc8159: self.updateUc8159(graphics)
  of KindAc073tc1a: self.updateAc073tc1a(graphics)

method powerOff*(self: var EinkDriver) =
  case self.kind:
  of KindUc8159: self.powerOffUc8159()
  of KindAc073tc1a: self.powerOffAc073tc1a()
