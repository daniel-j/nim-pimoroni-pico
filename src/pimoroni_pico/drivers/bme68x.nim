#
# Copyright (c) 2023 Bosch Sensortec GmbH. All rights reserved.
#
# BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#     contributors may be used to endorse or promote products derived from
#     this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

import ../common/pimoroni_i2c

import std/os, std/macros
import picostdlib/helpers
import futhark

const
  Bme68xI2cAddrLow* = 0x76.I2cAddress
  Bme68xI2cAddrHigh* = 0x77.I2cAddress

const bme68xInclude = currentSourcePath.parentDir / ".." / "vendor" / "BME68x-Sensor-API"

importc:
  outputPath currentSourcePath.parentDir / ".." / "futharkgen" / "futhark_bme68x.nim"

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


##  Nim helpers

import picostdlib

type
  Bme68x* = object
    i2cInterface*: I2cIntf
    debug*: bool
    status*: int8
    lastOpMode: uint8
    sensorData: array[3, Bme68xData]
    nFields, iFields: uint8

    device: Bme68xDev
    conf: Bme68xConf
    heatr_conf: Bme68xHeatrConf
    i2c: ptr I2c
    address: I2cAddress
    interrupt: GpioOptional

  I2cIntf = object
    i2c*: ptr I2c
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

  let res = i2c.i2c.readBytes(i2c.address, regAddr, regData, length)

  return if res == PicoErrorGeneric.int8: 1 else: 0

proc bme68xWriteBytes(regAddr: uint8; regData: ptr uint8; length: uint32; intfPtr: pointer): int8 {.cdecl.} =
  let i2c = cast[ptr I2cIntf](intfPtr)

  let res = i2c.i2c.writeBytes(i2c.address, regAddr, regData, length)

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

proc fetchData*(self: var Bme68x): uint8 =
  self.nFields = 0
  self.status = bme68x_get_data(self.lastOpMode, self.sensorData[0].addr, self.nFields.addr, self.device.addr)
  self.iFields = 0

  return self.nFields

proc getData*(self: var Bme68x; data: var Bme68xData): uint8 =
  if self.lastOpMode == BME68X_FORCED_MODE:
    data = self.sensorData[0]
  else:
    if self.nFields > 0:
      # iFields spans from 0-2 while nFields spans from
      # 0-3, where 0 means that there is no new data
      data = self.sensorData[self.iFields]
      inc(self.iFields)

      # Limit reading continuously to the last fields read
      if self.iFields >= self.nFields:
        self.iFields = self.nFields - 1
        return 0

      # Indicate if there is something left to read
      return self.nFields - self.iFields;

  return 0

proc begin*(self: var Bme68x; i2c: var I2c; address: I2cAddress = Bme68xI2cAddrHigh; interrupt: GpioOptional = GpioUnused): bool =
  self.i2c = i2c.addr
  self.address = address
  self.interrupt = interrupt

  var res: int8 = 0

  if self.interrupt != GpioUnused:
    self.interrupt.Gpio.setFunction(Sio)
    self.interrupt.Gpio.setDir(In)
    self.interrupt.Gpio.pullUp()

  self.i2cInterface.i2c = self.i2c
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



