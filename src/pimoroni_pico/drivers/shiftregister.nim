import std/bitops
import picostdlib/hardware/gpio

type
  ShiftRegister* = tuple[pinLatch, pinClock, pinOut: Gpio; bits: int]

proc gpioConfigure(gpio: Gpio; dir: Direction; value: Value = Low) =
  gpioSetFunction(gpio, Sio)
  gpioSetDir(gpio, dir)
  gpioPut(gpio, value)

proc init*(self: ShiftRegister) =
  gpioConfigure(self.pinClock, Out, High)
  gpioConfigure(self.pinLatch, Out, High)
  gpioConfigure(self.pinOut, In)

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
