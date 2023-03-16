import std/bitops

import picostdlib

type
  ShiftRegister* = tuple[pinLatch, pinClock, pinOut: Gpio; bits: int]

proc read*(self: ShiftRegister): uint =
  gpioPut(self.pinLatch, Low)
  sleepUs(1)
  gpioPut(self.pinLatch, High)
  sleepUs(1)
  for i in countdown(self.bits - 1, 0):
    if gpioGet(self.pinOut) == High:
      result.setBit(i)
    gpioPut(self.pinClock, Low)
    sleepUs(1)
    gpioPut(self.pinClock, High)
    sleepUs(1)

proc readBit*(self: ShiftRegister; index: uint): bool =
  self.read().int.testBit(index)
