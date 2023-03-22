import std/bitops

import picostdlib

type
  ShiftRegister* = tuple[pinLatch, pinClock, pinOut: Gpio; bits: int]

proc read*(self: ShiftRegister): uint =
  gpioPut(self.pinLatch, Low)
  asm "NOP;"
  gpioPut(self.pinLatch, High)
  asm "NOP;"
  for i in countdown(self.bits - 1, 0):
    if gpioGet(self.pinOut) == High:
      result.setBit(i)
    gpioPut(self.pinClock, Low)
    asm "NOP;"
    gpioPut(self.pinClock, High)
    asm "NOP;"

proc readBit*(self: ShiftRegister; index: uint): bool =
  self.read().int.testBit(index)
