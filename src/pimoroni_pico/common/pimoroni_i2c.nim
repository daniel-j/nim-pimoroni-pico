import picostdlib/[hardware/i2c, hardware/gpio]
import pimoroni_common

export i2c, gpio, pimoroni_common

const i2cTimeout = 100_0000

type
  I2c* = object
    i2c: ptr I2cInst
    sda: Gpio
    scl: Gpio
    baudrate: uint

proc pinToInst*(pin: Gpio): ptr I2cInst =
  if ((pin.uint shr 1) and 0b1).bool: i2c1 else: i2c0

proc init*(self: var I2c; sda: Gpio = I2cDefaultSda; scl: Gpio = I2cDefaultScl; baudrate: uint = I2cDefaultBaudrate) =
  self.sda = sda
  self.scl = scl
  self.baudrate = baudrate
  self.i2c = PimoroniI2cDefaultInstance

  #self.i2c = pinToInst(self.sda)
  ## TODO call pin_to_inst on sda and scl, and verify they are a valid i2c pin pair
  ## TODO maybe also fall back to PIO i2c for non-standard pin combinations
  ## Since it's easy to leave the I2C in a bad state when experimenting in the MicroPython REPL
  ##  self loop will find any I2C pins relevant to the current instance and reset them.
  var pin = 0
  while pin < 30:
    if pinToInst(Gpio(pin)) == self.i2c and Gpio(pin).getFunction() == GpioFunction.I2c:
      Gpio(pin).disablePulls()
      Gpio(pin).setFunction(GpioFunction.Null)
    inc(pin)
  discard self.i2c.init(self.baudrate.cuint)
  self.sda.setFunction(GpioFunction.I2c)
  self.scl.setFunction(GpioFunction.I2c)
  self.sda.pullUp()
  self.scl.pullUp()

proc deinit*(self: var I2c) =
  if self.i2c != nil:
    self.i2c.deinit()
    self.sda.disablePulls()
    self.sda.setFunction(GpioFunction.Null)
    self.scl.disablePulls()
    self.scl.setFunction(GpioFunction.Null)
    self.i2c = nil

proc getI2c*(self: var I2c|ptr I2c): auto = self.i2c
proc getScl*(self: var I2c|ptr I2c): auto = self.scl
proc getSda*(self: var I2c|ptr I2c): auto = self.sda
proc getBaudrate*(self: var I2c|ptr I2c): auto = self.baudrate

##  Basic wrappers for devices using i2c functions directly

# proc writeTimeoutUs*(self: var I2c|ptr I2c; `addr`: I2cAddress; src: ptr uint8; len: csize_t; nostop: bool): cint =
#   return self.i2c.writeTimeoutUs(`addr`, src, len, nostop)

# proc readTimeoutUs*(self: var I2c|ptr I2c; `addr`: I2cAddress; dst: ptr uint8; len: csize_t; nostop: bool): cint =
#   return self.i2c.readTimeoutUs(`addr`, dst, len, nostop)

##  Convenience functions for various common i2c operations

proc readBytes*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; buf: ptr uint8; len: uint): cint =
  let res = self.i2c.writeTimeoutUs(address, reg.unsafeAddr, 1, true, i2cTimeout)
  if res <= 0: return res
  return self.i2c.readTimeoutUs(address, buf, len.csize_t, false, i2cTimeout)

proc writeBytes*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; buf: ptr uint8; len: uint): cint =
  var buffer: seq[uint8]
  buffer.setLen(len + 1)
  buffer[0] = reg
  var x = 0'u
  while x < len:
    buffer[x + 1] = cast[ptr UncheckedArray[uint8]](buf)[x]
    inc(x)
  return self.i2c.writeTimeoutUs(address, buffer[0].addr, buffer.len.cuint, false, i2cTimeout)


proc regWriteUint8*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; value: uint8): cint =
  var buffer: array[2, uint8] = [reg, value]
  return self.i2c.writeTimeoutUs(address, buffer[0].addr, 2, false, i2cTimeout)

proc regReadUint8*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8): uint8 =
  var value: uint8
  discard self.i2c.writeTimeoutUs(address, reg.unsafeAddr, 1, false, i2cTimeout)
  discard self.i2c.readTimeoutUs(address, value.addr, 1, false, i2cTimeout)
  return value

proc regReadUint16*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8): uint16 =
  var value: uint16
  discard self.i2c.writeTimeoutUs(address, reg.unsafeAddr, 1, true, i2cTimeout)
  discard self.i2c.readTimeoutUs(address, cast[ptr uint8](addr(value)), sizeof((uint16)).csize_t, false, i2cTimeout)
  return value

proc regReadUint32*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8): uint32 =
  var value: uint32
  discard self.i2c.writeTimeoutUs(address, reg.unsafeAddr, 1, true, i2cTimeout)
  discard self.i2c.readTimeoutUs(address, cast[ptr uint8](addr(value)), sizeof((uint32)).csize_t, false, i2cTimeout)
  return value

proc regReadInt16*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8): int16 =
  var value: int16
  discard self.i2c.writeTimeoutUs(address, reg.unsafeAddr, 1, true, i2cTimeout)
  discard self.i2c.readTimeoutUs(address, cast[ptr uint8](addr(value)), sizeof((int16)).csize_t, false, i2cTimeout)
  return value


proc getBits*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8 = 0b1): uint8 =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  return value and (mask shl shift)

proc setBits*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8 = 0b1) =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  value = value or mask shl shift
  discard self.writeBytes(address, reg, addr(value), 1)

proc clearBits*(self: var I2c|ptr I2c; address: I2cAddress; reg: uint8; shift: uint8; mask: uint8 = 0b1) =
  var value: uint8
  discard self.readBytes(address, reg, addr(value), 1)
  value = value and not (mask shl shift)
  discard self.writeBytes(address, reg, addr(value), 1)
