import picostdlib/hardware/gpio
import picostdlib/pico/platform
import ../common/pimoroni_common
import ../common/pimoroni_bus
import ./display_driver

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

  IsBusyProc* = proc (): bool

  EinkDriverKind* = enum
    KindUc8159, KindAc073tc1a

  EinkDriver* = object of DisplayDriver
    kind*: EinkDriverKind
    spi*: ptr SpiInst
    csPin*: Gpio
    dcPin*: Gpio
    sckPin*: Gpio
    mosiPin*: Gpio
    resetPin*: Gpio
    timeout*: AbsoluteTime
    blocking*: bool
    borderColour*: Colour
    isBusyProc*: IsBusyProc

# proc init*(self: var EinkDriver) =
#   DisplayDriver(self).init(self.width, self.height)

proc getBlocking*(self: EinkDriver): bool = self.blocking

proc setBlocking*(self: var EinkDriver; blocking: bool) = self.blocking = blocking

proc setBorder*(self: var EinkDriver; colour: Colour) = self.borderColour = colour

proc isBusy*(self: EinkDriver): bool =
  ## Wait for the timeout to complete, then check the busy callback.
  ## This is to avoid polling the callback constantly
  if absoluteTimeDiffUs(getAbsoluteTime(), self.timeout) > 0:
    return true
  if not self.isBusyProc.isNil:
    return self.isBusyProc()

proc busyWait*(self: var EinkDriver, minimumWaitMs: uint32 = 0) =
  # echo "busyWait ", minimumWaitMs
  # let startTime = getAbsoluteTime()
  self.timeout = makeTimeoutTimeMs(minimumWaitMs)
  while self.isBusy():
    tightLoopContents()
  # let endTime = getAbsoluteTime()
  # echo absoluteTimeDiffUs(startTime, endTime)

proc command*(self: var EinkDriver; reg: uint8; data: varargs[uint8]) =
  self.csPin.put(Low)
  ##  command mode
  self.dcPin.put(Low)
  discard self.spi.writeBlocking(reg)
  if data.len > 0:
    ##  data mode
    self.dcPin.put(High)
    discard self.spi.writeBlocking(data)
  self.csPin.put(High)

proc data*(self: var EinkDriver, len: uint; data: varargs[uint8]) =
  self.csPin.put(Low)
  ##  data mode
  self.dcPin.put(High)

  discard self.spi.writeBlocking(data)
  self.csPin.put(High)
