import std/os, std/macros
import picostdlib/helpers

when defined(useFuthark) or defined(useFutharkForPimoroniPico):
  import futhark
  const bsec2Include = currentSourcePath.parentDir / ".." / "vendor" / "bme68x" / "Bosch-BSEC2-Library" / "src" / "inc"

  importc:
    outputPath currentSourcePath.parentDir / "futhark_bsec2.nim"

    compilerArg "--target=arm-none-eabi"
    compilerArg "-mthumb"
    compilerArg "-mcpu=cortex-m0plus"
    compilerArg "-fsigned-char"
    compilerArg "-fshort-enums" # needed to get the right struct size

    sysPath armSysrootInclude
    sysPath armInstallInclude
    path bsec2Include

    renameCallback futharkRenameCallback

    "bsec_interface.h"
    "bsec_interface_multi.h"
else:
  include ./futhark_bsec2

##  Nim helpers

import picostdlib
import ../common/pimoroni_i2c
import ../drivers/bme68x

const
  BSEC_TOTAL_HEAT_DUR* = 140.uint16
  BSEC_INSTANCE_SIZE* = 3272
  BSEC_E_INSUFFICIENT_INSTANCE_SIZE* =  -105.BsecLibraryReturnT

type
  Bsec2* = object
    version*: BsecVersionT
    status*: BsecLibraryReturnT
    bmeConf: BsecBmeSettingsT
    newDataCallback: BsecCallback
    outputs: BsecOutputs
    opMode: uint8
    extTempOffset: cfloat
    ovfCounter: uint32
    lastMillis: uint32
    bsecInstance: ptr uint8

  BsecData* = BsecOutputT
  BsecSensor* = BsecVirtualSensorT

  BsecOutputs* = object
    output*: array[BSEC_NUMBER_OUTPUTS, BsecData]
    nOutputs*: uint8

  BsecCallback* = proc (data: Bme68xData; outputs: BsecOutputs; bsec: Bsec2)

proc BSEC_CHECK_INPUT(x, shift: int): int =
  (x and (1 shl (shift-1)))

proc begin*(self: var Bsec2; intf: Bme68xIntf; read: Bme68xReadFptrT; write: Bme68xWriteFptrT; idleTask: Bme68xDelayUsFptrT; intfPtr: pointer): bool =
  ## Function to initialize the sensor based on custom callbacks
  ## @param intf     : BME68X_SPI_INTF or BME68X_I2C_INTF interface
  ## @param read     : Read callback
  ## @param write    : Write callback
  ## @param idleTask : Delay or Idle function
  ## @param intfPtr : Pointer to the interface descriptor
  ## @return True if everything initialized correctly
  discard

proc begin*(self: var Bsec2; i2cAddr: I2cAddress; i2c: var I2c; idleTask: Bme68xDelayUsFptrT = bme68xDelayUs): bool =
  ## Function to initialize the sensor based on the I2c library
  ## @param i2cAddr  : The I2C address the sensor is at
  ## @param i2c      : The I2c object
  ## @param idleTask : Delay or Idle function
  ## @return True if everything initialized correctly
  discard

proc updateSubscription*(self: var Bsec2; sensorList: openArray[BsecSensor], sampleRate: float = BSEC_SAMPLE_RATE_ULP): bool =
  ## Function that sets the desired sensors and the sample rates
  ## @param sensorList	: The list of output sensors
  ## @param nSensors		: Number of outputs requested
  ## @param sampleRate	: The sample rate of requested sensors
  ## @return	true for success, false otherwise
  discard

proc run*(self: var Bsec2): bool =
  ## Callback from the user to read data from the BME68x using parallel/forced mode, process and store outputs
  ## @return	true for success, false otherwise
  discard

proc setCallback*(self: var Bsec2; callback: BsecCallback) =
  self.newDataCallback = callback

proc getOutputs*(self: var Bsec2): ptr BsecOutputs =
  ## Function to get the BSEC outputs
  ## @return	pointer to BSEC outputs if available else nil
  if self.outputs.nOutputs > 0:
    return self.outputs.addr
  else:
    return nil

proc getData*(self: var Bsec2; id: BsecSensor): ptr BsecData =
  ## Function to get the BSEC output by sensor id
  ## @return	pointer to BSEC output, nil otherwise
  for i in 0..<self.outputs.nOutputs.int:
    if id.uint8 == self.outputs.output[i].sensor_id:
      return self.outputs.output[i].addr
  return nil

# WIP
