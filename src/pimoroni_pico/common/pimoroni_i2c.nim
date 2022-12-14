import picostdlib/[hardware/i2c, hardware/gpio]
import pimoroni_common

type
  I2c* = object
    i2c: ptr I2cInst
    sda: Gpio
    scl: Gpio
    interrupt: int8
    baudrate: uint

proc pinToInst*(pin: Gpio): ptr I2cInst =
  if ((pin.uint shr 1) and 0b1).bool: i2c1 else: i2c0

proc init*(self: var I2c; sda: Gpio = I2cDefaultSda; scl: Gpio = I2cDefaultScl; baudrate: uint = I2cDefaultBaudrate) =
  self.sda = sda
  self.scl = scl
  self.baudrate = baudrate
  self.interrupt = PinUnused
  self.i2c = PimoroniI2cDefaultInstance

  #self.i2c = pinToInst(self.sda)
  ##  TODO call pin_to_inst on sda and scl, and verify they are a valid i2c pin pair
  ##  TODO maybe also fall back to PIO i2c for non-standard pin combinations
  ##  Since it's easy to leave the I2C in a bad state when experimenting in the MicroPython REPL
  ##  self loop will find any I2C pins relevant to the current instance and reset them.
  var pin = 0
  while pin < 30:
    if pinToInst(pin.Gpio) == self.i2c and gpioGetFunction(pin.Gpio) == GpioFunction.I2c:
      gpioDisablePulls(pin.Gpio)
      gpioSetFunction(pin.Gpio, GpioFunction.Null)
    inc(pin)
  discard i2cInit(self.i2c, self.baudrate.cuint)
  gpioSetFunction(self.sda, GpioFunction.I2c)
  gpioPullUp(self.sda)
  gpioSetFunction(self.scl, GpioFunction.I2c)
  gpioPullUp(self.scl)

proc `=destroy`*(self: var I2c) =
  i2cDeinit(self.i2c)
  gpioDisablePulls(self.sda)
  gpioSetFunction(self.sda, GpioFunction.Null)
  gpioDisablePulls(self.scl)
  gpioSetFunction(self.scl, GpioFunction.Null)


proc getI2c*(self: var I2c): auto = self.i2c
proc getScl*(self: var I2c): auto = self.scl
proc getSda*(self: var I2c): auto = self.sda
proc getBaudrate*(self: var I2c): auto = self.baudrate

##  Basic wrappers for devices using i2c functions directly

proc writeBlocking*(self: var I2c; `addr`: I2cAddress; src: ptr uint8; len: csize_t; nostop: bool): cint =
  return i2cWriteBlocking(self.i2c, `addr`, src, len, nostop)

proc readBlocking*(self: var I2c; `addr`: I2cAddress; dst: ptr uint8; len: csize_t; nostop: bool): cint =
  return i2cReadBlocking(self.i2c, `addr`, dst, len, nostop)

##  Convenience functions for various common i2c operations

proc regWriteUint8*(self: var I2c; address: I2cAddress; reg: uint8; value: uint8) =
  var buffer: array[2, uint8] = [reg, value]
  discard i2cWriteBlocking(self.i2c, address, buffer[0].addr, 2, false)

proc regReadUint8*(self: var I2c; address: I2cAddress; reg: uint8): uint8 =
  var value: uint8
  var register = reg
  discard i2cWriteBlocking(self.i2c, address, register.addr, 1, false)
  discard i2cReadBlocking(self.i2c, address, value.addr, 1, false)
  return value

proc regReadUint16*(self: var I2c; address: I2cAddress; reg: uint8): uint16 =
  var value: uint16
  var register = reg
  discard i2cWriteBlocking(self.i2c, address, register.addr, 1, true)
  discard i2cReadBlocking(self.i2c, address, cast[ptr uint8](addr(value)), sizeof((uint16)).csize_t, false)
  return value

proc regReadUint32*(self: var I2c; address: I2cAddress; reg: uint8): uint32 =
  var value: uint32
  var register = reg
  discard i2cWriteBlocking(self.i2c, address, addr(register), 1, true)
  discard i2cReadBlocking(self.i2c, address, cast[ptr uint8](addr(value)), sizeof((uint32)).csize_t, false)
  return value

proc regReadInt16*(self: var I2c; address: I2cAddress; reg: uint8): int16 =
  var value: int16
  var register = reg
  discard i2cWriteBlocking(self.i2c, address, addr(register), 1, true)
  discard i2cReadBlocking(self.i2c, address, cast[ptr uint8](addr(value)), sizeof((int16)).csize_t, false)
  return value

proc writeBytes*(self: var I2c; address: I2cAddress; reg: uint8; buf: ptr uint8; len: cuint): cint =
  var buffer: seq[uint8]
  buffer.setLen(len + 1)
  buffer[0] = reg
  var x = 0'u
  while x < len:
    buffer[x + 1] = cast[ptr UncheckedArray[uint8]](buf)[x]
    inc(x)
  return i2cWriteBlocking(self.i2c, address, buffer[0].addr, (len + 1), false)


proc readBytes*(self: var I2c; address: I2cAddress; reg: uint8; buf: ptr uint8; len: cint): cint =
  var register = reg
  discard i2cWriteBlocking(self.i2c, address, addr(register), 1, true)
  discard i2cReadBlocking(self.i2c, address, buf, len.csize_t, false)
  return len


proc getBits*(self: var I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8): uint8 =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  return value and (mask shl shift)

proc setBits*(self: var I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8) =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  value = value or mask shl shift
  discard self.writeBytes(address, reg, addr(value), 1)

proc clearBits*(self: var I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8) =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  value = value and not (mask shl shift)
  discard self.writeBytes(address, reg, addr(value), 1)
