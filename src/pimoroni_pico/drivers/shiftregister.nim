import std/bitops
import picostdlib/hardware/gpio

type
  ShiftRegister* = tuple[pinLatch, pinClock, pinOut: Gpio; bits: int]

proc gpioConfigure(gpio: Gpio; dir: Direction; value: Value = Low) =
  gpio.setFunction(Sio)
  gpio.setDir(dir)
  gpio.put(value)

proc init*(self: ShiftRegister) =
  gpioConfigure(self.pinClock, Out, High)
  gpioConfigure(self.pinLatch, Out, High)
  gpioConfigure(self.pinOut, In)

proc read*(self: ShiftRegister): uint =
  self.pinLatch.put(Low)
  asm "NOP;"
  self.pinLatch.put(High)
  asm "NOP;"
  for i in countdown(self.bits - 1, 0):
    if self.pinOut.get() == High:
      result.setBit(i)
    self.pinClock.put(Low)
    asm "NOP;"
    self.pinClock.put(High)
    asm "NOP;"

proc readBit*(self: ShiftRegister; index: uint): bool =
  self.read().int.testBit(index)
