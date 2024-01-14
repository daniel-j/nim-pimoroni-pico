import picostdlib/hardware/gpio
import picostdlib/pico/platform
import ../common/pimoroni_common
import ../common/pimoroni_bus
import ./display_driver

# from std/strutils import toHex

export gpio, platform
export pimoroni_common, pimoroni_bus, display_driver

type
  Colour* = enum
    Black
    White
    Green
    Blue
    Red
    Yellow
    Orange
    Clean

  EinkReg* = distinct uint8

  IsBusyProc* = proc (): bool

  EinkDriverKind* = enum
    KindUnknown, KindUc8151, KindUc8159, KindAc073tc1a

  EinkDriver* = object of DisplayDriver
    kind*: EinkDriverKind
    spi*: ptr SpiInst
    csPin*: Gpio
    dcPin*: Gpio
    sckPin*: Gpio
    mosiPin*: Gpio
    resetPin*: Gpio
    timeout*: AbsoluteTime
    blocking: bool
    borderColour: Colour
    isBusyProc*: IsBusyProc


proc `==`*(a, b: EinkReg): bool {.borrow.}
proc `$`*(a: EinkReg): string {.borrow.}

# proc init*(self: var EinkDriver) =
#   DisplayDriver(self).init(self.width, self.height)

proc getBlocking*(self: EinkDriver): bool {.inline.} = self.blocking
proc setBlocking*(self: var EinkDriver; blocking: bool) {.inline.} = self.blocking = blocking

proc getBorder*(self: EinkDriver): Colour {.inline.} = self.borderColour
proc setBorder*(self: var EinkDriver; colour: Colour) {.inline.} = self.borderColour = colour

proc isBusy*(self: EinkDriver): bool =
  ## Wait for the timeout to complete, then check the busy callback.
  ## This is to avoid polling the callback constantly
  if diffUs(getAbsoluteTime(), self.timeout) > 0:
    return true
  if not self.isBusyProc.isNil:
    return self.isBusyProc()

proc busyWait*(self: var EinkDriver; minimumWaitMs: uint32 = 0) =
  # echo "busyWait ", minimumWaitMs
  # let startTime = getAbsoluteTime()
  self.timeout = makeTimeoutTimeMs(minimumWaitMs)
  while self.isBusy():
    tightLoopContents()
  # let endTime = getAbsoluteTime()
  # echo diffUs(startTime, endTime)

proc command*(self: var EinkDriver; reg: EinkReg; len: Natural; data: ptr uint8) =
  # var d = newSeq[uint8](len)
  # for i in 0..<len:
  #   d[i] = cast[ptr uint8](cast[uint](data) + i.uint)[]
  # echo "Command ", reg.uint.toHex(2), " ", len, " ", d
  self.csPin.put(Low)
  # command mode
  self.dcPin.put(Low)
  discard self.spi.writeBlocking(reg.uint8)
  if len > 0:
    # data mode
    self.dcPin.put(High)
    discard self.spi.writeBlocking(data, len.csize_t)
  self.csPin.put(High)

proc command*(self: var EinkDriver; reg: EinkReg; data: varargs[uint8]) =
  if data.len > 0:
    self.command(reg, data.len, data[0].unsafeAddr)
  else:
    self.command(reg, 0, nil)

proc data*(self: var EinkDriver; len: uint; data: varargs[uint8]) =
  self.csPin.put(Low)
  # data mode
  self.dcPin.put(High)

  discard self.spi.writeBlocking(data)
  self.csPin.put(High)
