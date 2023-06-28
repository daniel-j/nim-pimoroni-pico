
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

import picostdlib/hardware/timer
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
    extTempOffset: float
    ovfCounter: uint32
    lastMillis: uint32
    bsecInstance: ptr uint8

  BsecOutputs* = object
    output*: array[BSEC_NUMBER_OUTPUTS, BsecOutputT]
    nOutputs*: uint8

  BsecCallback* = proc (data: Bme68xData; outputs: BsecOutputs; bsec: var Bsec2)

proc BSEC_CHECK_INPUT(x: uint32; shift: BsecPhysicalSensorT): bool =
  (x.int and (1 shl (shift.int-1))) != 0

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
  discard

proc begin*(self: var Bsec2; i2c: var I2c; i2cAddr: I2cAddress; idleTask: Bme68xDelayUsFptrT = bme68xDelayUs): bool =
  ## Function to initialize the sensor based on the I2c library
  ## @param i2cAddr  : The I2C address the sensor is at
  ## @param i2c      : The I2c object
  ## @param idleTask : Delay or Idle function
  ## @return True if everything initialized correctly
  if not self.sensor.begin(i2c, i2cAddr):
    return false
  return self.beginCommon()

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

proc updateSubscription*(self: var Bsec2; sensorList: openArray[BsecVirtualSensorT]; sampleRate: float = BSEC_SAMPLE_RATE_ULP): bool =
  ## Function that sets the desired sensors and the sample rates
  ## @param sensorList	: The list of output sensors
  ## @param nSensors		: Number of outputs requested
  ## @param sampleRate	: The sample rate of requested sensors
  ## @return	true for success, false otherwise
  var virtualSensors: array[BSEC_NUMBER_OUTPUTS, BsecSensorConfigurationT]
  var sensorSettings: array[BSEC_MAX_PHYSICAL_SENSOR, BsecSensorConfigurationT]
  var nSensorSettings: uint8 = BSEC_MAX_PHYSICAL_SENSOR

  for i in 0 ..< sensorList.len:
    virtualSensors[i].sensor_id = sensorList[i].uint8
    virtualSensors[i].sample_rate = sampleRate

  # Subscribe to library virtual sensors outputs
  self.status = bsec_update_subscription_m(self.bsecInstance, virtualSensors[0].addr, sensorList.len.uint8, sensorSettings[0].addr, nSensorSettings.addr)
  if self.status != BSEC_OK:
    return false

  return true

proc processData(self: var Bsec2; currTimeNs: int64; data: var Bme68xData): bool =
  ## Reads the data from the BME68x sensor and process it
  ## @param currTimeNs: Current time in ns
  ## @return true if there are new outputs. false otherwise
  var inputs: array[BSEC_MAX_PHYSICAL_SENSOR, BsecInputT] # Temp, Pres, Hum & Gas
  var nInputs: uint8 = 0
  # Checks all the required sensor inputs, required for the BSEC library for the requested outputs
  if BSEC_CHECK_INPUT(self.bmeConf.process_data, BSEC_INPUT_TEMPERATURE):
      inputs[nInputs].sensor_id = BSEC_INPUT_HEATSOURCE.uint8
      inputs[nInputs].signal = self.extTempOffset
      inputs[nInputs].time_stamp = currTimeNs
      inc(nInputs)
      when true or defined(BME68X_USE_FPU):
        inputs[nInputs].signal = data.temperature
      else:
        inputs[nInputs].signal = data.temperature / 100.0f
      inputs[nInputs].sensor_id = BSEC_INPUT_TEMPERATURE.uint8
      inputs[nInputs].time_stamp = currTimeNs
      inc(nInputs)

  if BSEC_CHECK_INPUT(self.bmeConf.process_data, BSEC_INPUT_HUMIDITY):
    when true or defined(BME68X_USE_FPU):
      inputs[nInputs].signal = data.humidity
    else:
      inputs[nInputs].signal = data.humidity / 1000.0f

    inputs[nInputs].sensor_id = BSEC_INPUT_HUMIDITY.uint8
    inputs[nInputs].time_stamp = currTimeNs
    inc(nInputs)

  if BSEC_CHECK_INPUT(self.bmeConf.process_data, BSEC_INPUT_PRESSURE):
    inputs[nInputs].sensor_id = BSEC_INPUT_PRESSURE.uint8
    inputs[nInputs].signal = data.pressure
    inputs[nInputs].time_stamp = currTimeNs
    inc(nInputs)

  if BSEC_CHECK_INPUT(self.bmeConf.process_data, BSEC_INPUT_GASRESISTOR) and (data.status and BME68X_GASM_VALID_MSK) != 0:
    inputs[nInputs].sensor_id = BSEC_INPUT_GASRESISTOR.uint8
    inputs[nInputs].signal = data.gas_resistance
    inputs[nInputs].time_stamp = currTimeNs
    inc(nInputs)

  if BSEC_CHECK_INPUT(self.bmeConf.process_data, BSEC_INPUT_PROFILE_PART) and (data.status and BME68X_GASM_VALID_MSK) != 0:
    inputs[nInputs].sensor_id = BSEC_INPUT_PROFILE_PART.uint8
    inputs[nInputs].signal = if self.opMode == BME68X_FORCED_MODE: 0.0 else: data.gas_index.float
    inputs[nInputs].time_stamp = currTimeNs
    inc(nInputs)

  if nInputs > 0:

    self.outputs.nOutputs = BSEC_NUMBER_OUTPUTS
    zeroMem(self.outputs.output.addr, sizeof(self.outputs.output))

    # Processing of the input signals and returning of output samples is performed by bsec_do_steps()
    self.status = bsec_do_steps_m(self.bsecInstance, inputs[0].addr, nInputs, self.outputs.output[0].addr, self.outputs.nOutputs.addr)

    if self.status != BSEC_OK:
        return false

    if not self.newDataCallback.isNil:
      self.newDataCallback(data, self.outputs, self)

  return true

proc run*(self: var Bsec2): bool =
  ## Callback from the user to read data from the BME68x using parallel/forced mode, process and store outputs
  ## @return	true for success, false otherwise
  var nFieldsLeft: uint8 = 0
  var data: Bme68xData
  let currTimeNs: int64 = int64 timeUs64() * 1000'u64
  self.opMode = self.bmeConf.op_mode

  if currTimeNs >= self.bmeConf.next_call:
    # Provides the information about the current sensor configuration that is
    # necessary to fulfill the input requirements, eg: operation mode, timestamp
    # at which the sensor data shall be fetched etc
    self.status = bsec_sensor_control_m(self.bsecInstance, currTimeNs, self.bmeConf.addr)
    if self.status != BSEC_OK:
      return false

    case self.bmeConf.op_mode:
    of BME68X_FORCED_MODE:
      self.setBme68xConfigForced()
    of BME68X_PARALLEL_MODE:
      if self.opMode != self.bmeConf.op_mode:
        self.setBme68xConfigParallel()
    of BME68X_SLEEP_MODE:
      if self.opMode != self.bmeConf.op_mode:
        self.sensor.setOpMode(BME68X_SLEEP_MODE)
        self.opMode = BME68X_SLEEP_MODE
    else: discard

    if self.sensor.status != BME68X_OK:
      return false

    if self.bmeConf.trigger_measurement != 0 and self.bmeConf.op_mode != BME68X_SLEEP_MODE:
      if self.sensor.fetchData() > 0:
        while true:
          nFieldsLeft = self.sensor.getData(data)
          # check for valid gas data
          if (data.status and BME68X_GASM_VALID_MSK) != 0:
            if not self.processData(currTimeNs, data):
              return false
          if nFieldsLeft <= 0: break

  return true

proc setCallback*(self: var Bsec2; callback: BsecCallback) =
  self.newDataCallback = callback

proc getOutputs*(self: var Bsec2): ptr BsecOutputs =
  ## Function to get the BSEC outputs
  ## @return	pointer to BSEC outputs if available else nil
  if self.outputs.nOutputs > 0:
    return self.outputs.addr
  else:
    return nil

proc getData*(self: var Bsec2; id: BsecVirtualSensorT): ptr BsecOutputT =
  ## Function to get the BSEC output by sensor id
  ## @return	pointer to BSEC output, nil otherwise
  for i in 0'u ..< self.outputs.nOutputs:
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


# WIP
