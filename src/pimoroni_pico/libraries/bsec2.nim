
when defined(useFuthark) or defined(useFutharkForPimoroniPico):
  import std/os, std/macros
  import picostdlib/helpers
  import futhark
  const bsec2Include = currentSourcePath.parentDir / ".." / "vendor" / "Bosch-BSEC2-Library" / "src" / "inc"

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

import ../common/pimoroni_i2c
import ../drivers/bme68x

const
  BSEC_TOTAL_HEAT_DUR* = 140.uint16
  BSEC_INSTANCE_SIZE* = 3272
  BSEC_E_INSUFFICIENT_INSTANCE_SIZE* =  -105.BsecLibraryReturnT

type
  Bsec2* = object
    sensor*: Bme68x
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

proc createBsec2*(): Bsec2 =
  ## Constructor of Bsec2 class
  result.ovfCounter = 0
  result.lastMillis = 0
  result.status = BSEC_OK
  result.extTempOffset = 0.0f
  result.opMode = BME68X_SLEEP_MODE
  result.newDataCallback = nil
  result.bsecInstance = nil

proc beginCommon(self: var Bsec2): bool =
  let instanceSize = bsec_get_instance_size_m()
  ## Common code for the begin function
  if self.bsecInstance.isNil:
    self.bsecInstance = cast[ptr uint8](alloc0(instanceSize))
    # why not use BSEC_INSTANCE_SIZE ?

  if BSEC_INSTANCE_SIZE < instanceSize:
    self.status = BSEC_E_INSUFFICIENT_INSTANCE_SIZE
    return false

  self.status = bsec_init_m(self.bsecInstance)
  if self.status != BSEC_OK:
    return false

  self.status = bsec_get_version_m(self.bsecInstance, self.version.addr)
  if self.status != BSEC_OK:
    return false

  zeroMem(self.bmeConf.addr, sizeof(self.bmeConf))
  zeroMem(self.outputs.addr, sizeof(self.outputs))

  return true

proc begin*(self: var Bsec2; intf: Bme68xIntf; read: Bme68xReadFptrT; write: Bme68xWriteFptrT; idleTask: Bme68xDelayUsFptrT; intfPtr: pointer): bool =
  ## Function to initialize the sensor based on custom callbacks
  ## @param intf     : BME68X_SPI_INTF or BME68X_I2C_INTF interface
  ## @param read     : Read callback
  ## @param write    : Write callback
  ## @param idleTask : Delay or Idle function
  ## @param intfPtr : Pointer to the interface descriptor
  ## @return True if everything initialized correctly

proc begin*(self: var Bsec2; i2c: var I2c; i2cAddr: I2cAddress; idleTask: Bme68xDelayUsFptrT = bme68xDelayUs): bool =
  ## Function to initialize the sensor based on the I2c library
  ## @param i2cAddr  : The I2C address the sensor is at
  ## @param i2c      : The I2c object
  ## @param idleTask : Delay or Idle function
  ## @return True if everything initialized correctly
  if not self.sensor.begin(i2c, i2cAddr):
    return false
  return self.beginCommon()

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

proc getState*(self: Bsec2; state: ptr uint8): bool =
  ## Function to get the state of the algorithm to save to non-volatile memory
  ## @param state			: Pointer to a memory location, to hold the state
  ## @return	true for success, false otherwise
  discard

proc setState*(self: var Bsec2; state: ptr uint8): bool =
  ## Function to set the state of the algorithm from non-volatile memory
  ## @param state			: Pointer to a memory location that contains the state
  ## @return	true for success, false otherwise
  discard

proc getConfig*(self: Bsec2; config: ptr uint8): bool =
  ## Function to retrieve the current library configuration
  ## @param config    : Pointer to a memory location, to hold the serialized config blob
  ## @return	true for success, false otherwise
  discard

proc setConfig*(self: var Bsec2; config: ptr uint8): bool =
  ## Function to set the configuration of the algorithm from memory
  ## @param state			: Pointer to a memory location that contains the configuration
  ## @return	true for success, false otherwise
  discard

proc setTemperatureOffset*(self: var Bsec2; tempOffset: float) =
  ## Function to set the temperature offset
  ## @param tempOffset	: Temperature offset in degree Celsius
  self.extTempOffset = tempOffset

proc getTimeMs*(self: Bsec2): int64 =
  ## Function to calculate an int64_t timestamp in milliseconds
  discard

proc allocateMemory*(self: var Bsec2; memBlock: var array[BSEC_INSTANCE_SIZE, uint8]) =
  ## Function to assign the memory block to the bsec instance
  ## @param[in] memBlock : reference to the memory block
  # self.bsecInstance = memBlock[0].addr

proc clearMemory*(self: var Bsec2) =
  ## Function to de-allocate the dynamically allocated memory
  # dealloc(self.bsecInstance)

proc processData(self: var Bsec2; currTimeNs: int64; data: ptr Bme68xData): bool =
  ## Reads the data from the BME68x sensor and process it
  ## @param currTimeNs: Current time in ns
  ## @return true if there are new outputs. false otherwise
  discard

proc setBme68xConfigForced(self: var Bsec2) =
  # Set the BME68x sensor configuration to forced mode
  self.sensor.setTPH(self.bmeConf.temperature_oversampling, self.bmeConf.pressure_oversampling, self.bmeConf.humidity_oversampling)
  if self.sensor.status != BME68X_OK:
    return

  self.sensor.setHeaterProf(self.bmeConf.heater_temperature, self.bmeConf.heater_duration)
  if self.sensor.status != BME68X_OK:
    return

  self.sensor.setOpMode(BME68X_FORCED_MODE)
  if self.sensor.status != BME68X_OK:
    return

  self.opMode = BME68X_FORCED_MODE


proc setBme68xConfigParallel(self: var Bsec2) =
  # Set the BME68X sensor configuration to parallel mode

  self.sensor.setTPH(self.bmeConf.temperature_oversampling, self.bmeConf.pressure_oversampling, self.bmeConf.humidity_oversampling)
  if self.sensor.status != BME68X_OK:
    return

  let sharedHeaterDur = uint16 BSEC_TOTAL_HEAT_DUR - (self.sensor.getMeasDur(BME68X_PARALLEL_MODE) div 1000)

  self.sensor.setHeaterProf(self.bmeConf.heater_temperature_profile[0].addr, self.bmeConf.heater_duration_profile[0].addr, sharedHeaterDur, self.bmeConf.heater_profile_len)
  if self.sensor.status != BME68X_OK:
    return

  self.sensor.setOpMode(BME68X_PARALLEL_MODE)
  if self.sensor.status != BME68X_OK:
    return

  self.opMode = BME68X_PARALLEL_MODE

# WIP
