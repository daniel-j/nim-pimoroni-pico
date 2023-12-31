import ./eink_uc8159, ./eink_ac073tc1a, ./eink_uc8151

export eink_driver

proc init*(self: var EinkDriver; width: uint16; height: uint16; pins: SpiPins; resetPin: Gpio; isBusyProc: IsBusyProc = nil; blocking: bool = true) =
  DisplayDriver(self).init(width, height)
  case self.kind:
  of KindUnknown: discard
  of KindUc8151: Uc8151(self).initUc8151(width, height, pins, resetPin, isBusyProc, blocking)
  of KindUc8159: self.initUc8159(width, height, pins, resetPin, isBusyProc, blocking)
  of KindAc073tc1a: self.initAc073tc1a(width, height, pins, resetPin, isBusyProc, blocking)

proc update*(self: var EinkDriver; graphics: var PicoGraphicsBase) =
  case self.kind:
  of KindUnknown: discard
  of KindUc8151: Uc8151(self).updateUc8151(PicoGraphicsPen1Bit(graphics))
  of KindUc8159: self.updateUc8159(PicoGraphicsPen3Bit(graphics))
  of KindAc073tc1a: self.updateAc073tc1a(PicoGraphicsPen3Bit(graphics))

proc partialUpdate*(self: var EinkDriver; graphics: var PicoGraphicsBase; region: Rect) =
  case self.kind:
  of KindUc8151: Uc8151(self).partialUpdateUc8151(PicoGraphicsPen1Bit(graphics), region)
  else: discard

proc powerOff*(self: var EinkDriver) =
  case self.kind:
  of KindUnknown: discard
  of KindUc8151: Uc8151(self).powerOffUc8151()
  of KindUc8159: self.powerOffUc8159()
  of KindAc073tc1a: self.powerOffAc073tc1a()
