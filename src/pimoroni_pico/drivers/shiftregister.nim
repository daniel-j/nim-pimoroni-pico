import std/bitops
import picostdlib/pico/time
import picostdlib/hardware/gpio

type
  ShiftRegister* = object
    pinClock*, pinLatch*, pinOut*: Gpio
    bits*: int

proc gpioConfigure(gpio: Gpio; dir: Direction; value: Value = Low) =
  gpio.setFunction(Sio)
  gpio.setDir(dir)
  gpio.put(value)

proc init*(self: ShiftRegister) =
  gpioConfigure(self.pinClock, Out, High)
  gpioConfigure(self.pinLatch, Out, High)
  gpioConfigure(self.pinOut, In)

proc deinit*(self: ShiftRegister) =
  self.pinClock.init()
  self.pinLatch.init()
  self.pinOut.init()

proc read*(self: ShiftRegister): uint =
  # self.init()
  self.pinLatch.put(Low)
  sleepUs(1)
  self.pinLatch.put(High)
  sleepUs(1)
  result = 0
  for i in countdown(self.bits - 1, 0):
    self.pinClock.put(Low)
    sleepUs(1)
    if self.pinOut.get() == High:
      result.setBit(i)
    self.pinClock.put(High)
    sleepUs(1)

proc readBit*(self: ShiftRegister; index: uint): bool =
  self.read().int.testBit(index)
