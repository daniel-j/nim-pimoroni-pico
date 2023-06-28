import ../common/pimoroni_i2c

const
  Bme68xI2cAddrLow* = 0x76.I2cAddress
  Bme68xI2cAddrHigh* = 0x77.I2cAddress

when defined(useFuthark) or defined(useFutharkForPimoroniPico):
  import std/os, std/macros
  import picostdlib/helpers
  import futhark

  const bme68xInclude = currentSourcePath.parentDir / ".." / "vendor" / "BME68x-Sensor-API"

  importc:
    outputPath currentSourcePath.parentDir / "futhark_bme68x.nim"

    compilerArg "--target=arm-none-eabi"
    compilerArg "-mthumb"
    compilerArg "-mcpu=cortex-m0plus"
    compilerArg "-fsigned-char"
    compilerArg "-fshort-enums" # needed to get the right struct size

    sysPath armSysrootInclude
    sysPath armInstallInclude
    path bme68xInclude

    renameCallback futharkRenameCallback

    "bme68x.h"
else:
  include ./futhark_bme68x

##  Nim helpers

import picostdlib
import ../common/vla

type
  Bme68x* = object
    i2cInterface*: I2cIntf
    debug*: bool
    status*: int8
    lastOpMode: uint8

    device: Bme68xDev
    conf: Bme68xConf
    heatr_conf: Bme68xHeatrConf
    i2c: ptr I2c
    address: I2cAddress
    interrupt: GpioOptional

  I2cIntf = object
    i2c*: ptr I2cInst
    address*: I2cAddress

proc createBme68x*(debug: bool = false): Bme68x =
  result.debug = debug

proc bme68xCheckRslt*(self: Bme68x; apiName: string; rslt: int8) =
  if not self.debug: return
  case rslt:
  of BME68X_OK: echo apiName & " [ OK ]"
  of BME68X_E_NULL_PTR: echo apiName & ": Error [" & $rslt & "] : Null pointer"
  of BME68X_E_COM_FAIL: echo apiName & ": Error [" & $rslt & "] : Communication failure"
  of BME68X_E_INVALID_LENGTH: echo apiName & ": Error [" & $rslt & "] : Incorrect length parameter"
  of BME68X_E_DEV_NOT_FOUND: echo apiName & ": Error [" & $rslt & "] : Device not found"
  of BME68X_E_SELF_TEST: echo apiName & ": Error [" & $rslt & "] : Self test error"
  of BME68X_W_NO_NEW_DATA: echo apiName & ": Error [" & $rslt & "] : No new data found"
  else: echo apiName & ": Error [" & $rslt & "] : Unknown error code"

# Bindings for bme68x_dev
proc bme68xReadBytes(regAddr: uint8; regData: ptr uint8; length: uint32; intfPtr: pointer): int8 {.cdecl.} =
  let i2c = cast[ptr I2cIntf](intfPtr)

  var register = regAddr
  var res = i2c.i2c.i2cWriteBlocking(i2c.address, addr(register), 1.csize_t, true)
  res = i2c.i2c.i2cReadBlocking(i2c.address, regData, length.csize_t, false)

  return if res == PicoErrorGeneric.int8: 1 else: 0

proc bme68xWriteBytes(regAddr: uint8; regData: ptr uint8; length: uint32; intfPtr: pointer): int8 {.cdecl.} =
  let i2c = cast[ptr I2cIntf](intfPtr)
  var buffer = newVLA(uint8, int length + 1)
  let regDataArr = cast[ptr UncheckedArray[uint8]](regData)
  buffer[0] = regAddr
  for i in 0..<length:
    buffer[i + 1] = regDataArr[i]

  let res = i2c.i2c.i2cWriteBlocking(i2c.address, buffer[0].addr, length.csize_t + 1, false)

  return if res == PicoErrorGeneric.int8: 1 else: 0

proc bme68xDelayUs*(period: uint32; intfPtr: pointer) {.cdecl.} =
  sleepUs(period)


proc configure*(self: var Bme68x; filter, odr, osHumidity, osPressure, osTemp: uint): bool =
  var res: int8 = 0

  self.conf.filter = filter.uint8
  self.conf.odr = odr.uint8
  self.conf.os_hum = osHumidity.uint8
  self.conf.os_pres = osPressure.uint8
  self.conf.os_temp = osTemp.uint8

  res = bme68x_set_conf(self.conf.addr, self.device.addr)
  self.bme68xCheckRslt("bme68x_set_conf", res)
  if res != BME68X_OK: return false

  return true

proc setTPH*(self: var Bme68x; osTemp, osPres, osHum: uint8) =
  ## Function to set the Temperature, Pressure and Humidity over-sampling
  self.status = bme68x_get_conf(self.conf.addr, self.device.addr)
  if self.status == BME68X_OK:
    self.conf.os_temp = osTemp
    self.conf.os_pres = osPres
    self.conf.os_hum = osHum
    self.status = bme68x_set_conf(self.conf.addr, self.device.addr)

proc setHeaterProf*(self: var Bme68x; temp, dur: uint16) =
  ## Function to set the heater profile for Forced mode
  self.heatr_conf.enable = BME68X_ENABLE
  self.heatr_conf.heatr_temp = temp
  self.heatr_conf.heatr_dur = dur
  self.status = bme68x_set_heatr_conf(BME68X_FORCED_MODE, self.heatr_conf.addr, self.device.addr)

proc setHeaterProf*(self: var Bme68x; temp, mul: ptr uint16; sharedHeatrDur: uint16; profileLen: uint8) =
  ## Function to set the heater profile for Parallel mode
  self.heatr_conf.enable = BME68X_ENABLE
  self.heatr_conf.heatr_temp_prof = temp
  self.heatr_conf.heatr_dur_prof = mul
  self.heatr_conf.shared_heatr_dur = sharedHeatrDur
  self.heatr_conf.profile_len = profileLen

proc setOpMode*(self: var Bme68x; opMode: uint8) =
  self.status = bme68x_set_op_mode(opMode, self.device.addr)
  if self.status == BME68X_OK and opMode != BME68X_SLEEP_MODE:
    self.lastOpMode = opMode

proc begin*(self: var Bme68x; i2c: var I2c; address: I2cAddress = Bme68xI2cAddrHigh; interrupt: GpioOptional = PinUnused): bool =
  self.i2c = i2c.addr
  self.address = address
  self.interrupt = interrupt

  var res: int8 = 0

  if self.interrupt != PinUnused:
    gpioSetFunction(self.interrupt.Gpio, Sio)
    gpioSetDir(self.interrupt.Gpio, In)
    gpioPullUp(self.interrupt.Gpio)

  self.i2cInterface.i2c = self.i2c.getI2c
  self.i2cInterface.address = self.address

  self.device.intfPtr = self.i2cInterface.addr
  self.device.intf = BME68X_I2C_INTF
  self.device.read = bme68xReadBytes
  self.device.write = bme68xWriteBytes
  self.device.delay_us = bme68xDelayUs
  self.device.amb_temp = 20

  res = bme68x_init(self.device.addr)
  self.bme68xCheckRslt("bme68x_init", res)
  if res != BME68X_OK: return false

  res = bme68x_get_conf(self.conf.addr, self.device.addr)
  self.bme68xCheckRslt("bme68x_get_conf", res)
  if res != BME68X_OK: return false

  return self.configure(
    filter = BME68X_FILTER_OFF,
    odr = BME68X_ODR_NONE,
    osHumidity = BME68X_OS_1X,
    osPressure = BME68X_OS_16X,
    osTemp = BME68X_OS_2X
  )

proc getMeasDur*(self: var Bme68x; opMode: uint8): uint32 =
  ## Function to get the measurement duration in microseconds
  var opModeDyn = opMode
  if opMode == BME68X_SLEEP_MODE:
    opModeDyn = self.lastOpMode

  return bme68x_get_meas_dur(opModeDyn, self.conf.addr, self.device.addr)

proc readForced*(self: var Bme68x; data: var Bme68xData; heater_temp: uint16 = 300; heater_duration: uint16 = 100): bool =
  var res: int8 = 0
  var n_fields: uint8
  var delay_period: uint32

  self.heatr_conf.enable = BME68X_ENABLE.uint8
  self.heatr_conf.heatr_temp = heater_temp
  self.heatr_conf.heatr_dur = heater_duration
  res = bme68x_set_heatr_conf(BME68X_FORCED_MODE.uint8, self.heatr_conf.addr, self.device.addr)
  self.bme68xCheckRslt("bme68x_set_heatr_conf", res)
  if res != BME68X_OK: return false


  res = bme68x_set_op_mode(BME68X_FORCED_MODE.uint8, self.device.addr)
  self.bme68xCheckRslt("bme68x_set_op_mode", res)
  if res != BME68X_OK: return false


  delay_period = bme68x_get_meas_dur(BME68X_FORCED_MODE.uint8, self.conf.addr, self.device.addr) + (self.heatr_conf.heatr_dur * 1000)
  # Could probably just call sleep_us here directly, I guess the API uses this internally
  self.device.delay_us(delay_period, self.device.intf_ptr)

  sleepMs(heater_duration - delay_period div 1000)

  res = bme68x_get_data(BME68X_FORCED_MODE.uint8, data.addr, n_fields.addr, self.device.addr)
  self.bme68xCheckRslt("bme68x_get_data", res)
  if res != BME68X_OK: return false

  return true

proc readParallel*(self: var Bme68x; results: ptr Bme68xData; profile_temps: var uint16; profile_durations: var uint16; profile_length: uint): bool =
  discard

proc getI2c*(self: Bme68x): ptr I2c = self.i2c
proc getInt*(self: Bme68x): GpioOptional = self.interrupt



