import std/os
import std/math
import std/bitops
import picostdlib/hardware/adc
import picostdlib/hardware/base
import picostdlib/hardware/dma
import picostdlib/hardware/gpio
import picostdlib/hardware/pio
import picostdlib/pico/platform
import picostdlib/pico/time
import ../common/pimoroni_common
import ./pico_graphics

pioInclude(currentSourcePath.parentDir / ".." / "pio" / "galactic_unicorn.pio")

{.push header: "galactic_unicorn.pio.h".}

# Import program and config the C header file that is generated  at
# compile-time.
var galacticUnicornProgram {.importc: "galactic_unicorn_program".}: PioProgram

proc galacticUnicornProgramGetDefaultConfig(offset: uint): PioSmConfig
  {.importc: "galactic_unicorn_program_get_default_config".}

{.pop.}

const
  GalacticUnicornWidth* = 53
  GalacticUnicornHeight* = 11

  SwitchAPin* = 0.Gpio
  SwitchBPin * = 1.Gpio
  SwitchCPin* = 3.Gpio
  SwitchDPin* = 6.Gpio
  SwitchVolumeUpPin* = 7.Gpio
  SwitchVolumeDownPin* = 8.Gpio
  SwitchBrightnessUpPin* = 21.Gpio
  SwitchBrightnessDownPin* = 26.Gpio
  SwitchSleepPin* = 27.Gpio

  I2cSdaPin = 4.Gpio
  I2cSclPin = 5.Gpio

  I2sDataPin = 9.Gpio
  I2sBclkPin = 10.Gpio
  I2sLrclkPin = 11.Gpio

  ColumnClockPin = 13.Gpio
  ColumnDataPin = 14.Gpio
  ColumnLatchPin = 15.Gpio
  ColumnBlankPin = 16.Gpio

  RowBit0Pin = 17.Gpio
  RowBit1Pin = 18.Gpio
  RowBit2Pin = 19.Gpio
  RowBit3Pin = 20.Gpio

  MutePin = 22.Gpio
  LightSensorPin = 28.Gpio

  RowCount = GalacticUnicornHeight
  BcdFrameCount = 14
  BcdFrameBytes = 60
  RowBytes = BcdFrameCount * BcdFrameBytes
  BitstreamLength = RowCount * RowBytes
  SystemFreq = 22050


type
  GalacticUnicorn* = object
    brightness: uint16
    volume: uint16
    bitstream* {.align: 4.}: array[BitstreamLength, uint8]
    bitstreamAddr*: uint32

  Button* = enum
    ButtonA = SwitchAPin
    ButtonB = SwitchBPin
    ButtonC = SwitchCPin
    ButtonD = SwitchDPin
    ButtonVolumeUp = SwitchVolumeUpPin
    ButtonVolumeDown = SwitchVolumeDownPin
    ButtonBrightnessUp = SwitchBrightnessUpPin
    ButtonBrightnessDown = SwitchBrightnessDownPin
    ButtonSleep = SwitchSleepPin

var
  unicorn: ptr GalacticUnicorn = nil

  dmaChannel: uint32
  dmaCtrlChannel: uint32
  audioDmaChannel: uint32

  bitstreamPio = pio0
  bitstreamSm = 0.PioStateMachine
  bitstreamSmOffset = 0'u

proc dmaSafeAbort(self: var GalacticUnicorn; channel: uint) =
  # Tear down the DMA channel.
  # This is copied from: https://github.com/raspberrypi/pico-sdk/pull/744/commits/5e0e8004dd790f0155426e6689a66e08a83cd9fc

  let irq0Save = dmaHw.inte0 and (1'u32 shl channel)
  hwClearBits(cast[IoRw32](dmaHw.inte0.addr), irq0Save)

  dmaHw.abort = 1'u32 shl channel

  # To fence off on in-flight transfers, the BUSY bit should be polled
  # rather than the ABORT bit, because the ABORT bit can clear prematurely.
  while (dmaHw.ch[channel].ctrlTrig and DMA_CH0_CTRL_TRIG_BUSY_BITS) != 0:
    tightLoopContents()

  # Clear the interrupt (if any) and restore the interrupt masks.
  dmaHw.ints0 = 1'u32 shl channel
  hwSetBits(cast[IoRw32](dmaHw.inte0.addr), irq0Save)

proc partialTeardown(self: var GalacticUnicorn) =
  # Stop the bitstream SM
  bitstreamPio.disable(bitstreamSm)

  # Make sure the display is off and switch it to an invisible row, to be safe
  const pinsToSet = 1 shl ColumnBlankPin.int or 0b1111 shl RowBit0Pin.int
  pioSmSetPinsWithMask(bitstreamPio, bitstreamSm, pinsToSet, pinsToSet)

  dmaHw.ch[dmaCtrlChannel].al1_ctrl = uint32 (dmaHw.ch[dmaCtrlChannel].al1_ctrl and not DMA_CH0_CTRL_TRIG_CHAIN_TO_BITS) or (dmaCtrlChannel shl DMA_CH0_CTRL_TRIG_CHAIN_TO_LSB)
  dmaHw.ch[dmaChannel].al1_ctrl = uint32 (dmaHw.ch[dmaChannel].al1_ctrl and not DMA_CH0_CTRL_TRIG_CHAIN_TO_BITS) or (dmaChannel shl DMA_CH0_CTRL_TRIG_CHAIN_TO_LSB)

  # Abort any in-progress DMA transfer
  self.dmaSafeAbort(dmaCtrlChannel)
  self.dmaSafeAbort(dmaChannel)

  # // Stop the audio SM
  # pio_sm_set_enabled(audio_pio, audio_sm, false);

  # // Reset the I2S pins to avoid popping when audio is suddenly stopped
  # const uint pins_to_clear = 1 << I2S_DATA | 1 << I2S_BCLK | 1 << I2S_LRCLK;
  # pio_sm_set_pins_with_mask(audio_pio, audio_sm, 0, pins_to_clear);

  # // Abort any in-progress DMA transfer
  # dma_safe_abort(audio_dma_channel);

proc nextAudioSequence(self: var GalacticUnicorn) =
  discard

proc dmaComplete() {.cdecl.} =
  if unicorn != nil and dmaChannelGetIrq0Status(audioDmaChannel):
    unicorn[].nextAudioSequence()

proc init*(self: var GalacticUnicorn) =
  self.brightness = 255
  self.bitstreamAddr = cast[uint32](self.bitstream[0].addr)

  if not unicorn.isNil:
    # Tear down the old GU instance's hardware resources
    self.partialTeardown()

  # for each row:
  #   for each bcd frame:
  #            0: 00110110                           # row pixel count (minus one)
  #      1  - 53: xxxxxbgr, xxxxxbgr, xxxxxbgr, ...  # pixel data
  #      54 - 55: xxxxxxxx, xxxxxxxx                 # dummy bytes to dword align
  #           56: xxxxrrrr                           # row select bits
  #      57 - 59: tttttttt, tttttttt, tttttttt       # bcd tick count (0-65536)
  #
  #  .. and back to the start

  # initialise the bcd timing values and row selects in the bitstream
  for row in 0..<GalacticUnicornHeight:
    for frame in 0..<BcdFrameCount:
      # find the offset of this row and frame in the bitstream
      let offset = row * RowBytes + (BcdFrameBytes * frame)

      self.bitstream[offset + 0] = GalacticUnicornWidth - 1  # row pixel count
      self.bitstream[offset + 1] = row.uint8                 # row select

      # set the number of bcd ticks for this frame
      let bcdTicks = uint32 1 shl frame
      self.bitstream[offset + 56] = uint8 (bcdTicks and       0xff'u32) shr  0
      self.bitstream[offset + 57] = uint8 (bcdTicks and     0xff00'u32) shr  8
      self.bitstream[offset + 58] = uint8 (bcdTicks and   0xff0000'u32) shr 16
      self.bitstream[offset + 59] = uint8 (bcdTicks and 0xff000000'u32) shr 24

  # echo "bitstream:"
  # for i, val in self.bitstream:
  #   if i mod 30 == 0: stdout.write("\n")
  #   stdout.write(val.BiggestUint.toHex(2) & " ")
  # stdout.flushFile()
  # echo ""

  # setup light sensor adc
  if (adcHw.cs and ADC_CS_EN_BITS) == 0:
    adcInit()
  
  adcGpioInit(LightSensorPin)
  
  const columnPinMask = {ColumnClockPin, ColumnDataPin, ColumnLatchPin, ColumnBlankPin}
  gpioInitMask(columnPinMask)
  gpioSetDirOutMasked(columnPinMask)
  gpioPut(ColumnClockPin, Low)
  gpioPut(ColumnDataPin, Low)
  gpioPut(ColumnLatchPin, Low)
  gpioPut(ColumnBlankPin, High)

  # initialise the row select, and set them to a non-visible row to avoid flashes during setup
  const rowBitPinMask = {RowBit0Pin, RowBit1Pin, RowBit2Pin, RowBit3Pin}
  gpioInitMask(rowBitPinMask)
  gpioSetDirOutMasked(rowBitPinMask)
  gpioPutMasked(rowBitPinMask, uint32.high)

  sleepMs(100)

  # configure full output current in register 2

  const reg1: uint16 = 0b1111111111001110

  # clock the register value to the first 9 driver chips
  for j in 0..<9:
    for i in 0..<16:
      gpioPut(ColumnDataPin, reg1.testBit(15 - i).Value)

      sleepUs(10)
      gpioPut(ColumnClockPin, High)
      sleepUs(10)
      gpioPut(ColumnClockPin, Low)

  # clock the last chip and latch the value
  for i in 0..<16:
    gpioPut(ColumnDataPin, reg1.testBit(15 - i).Value)

    sleepUs(10)
    gpioPut(ColumnClockPin, High)
    sleepUs(10)
    gpioPut(ColumnClockPin, Low)

    if i == 4:
      gpioPut(ColumnLatchPin, High)
  
  gpioPut(ColumnLatchPin, Low)

  # reapply the blank as the above seems to cause a slight glow.
  # Note, this will produce a brief flash if a visible row is selected (which it shouldn't be)
  gpioPut(ColumnBlankPin, Low)
  sleepUs(10)
  gpioPut(ColumnBlankPin, High)

  gpioInit(MutePin)
  gpioSetDir(MutePin, Out)
  gpioPut(MutePin, High)

  # setup button inputs
  const buttonPinMask = {SwitchAPin, SwitchBPin, SwitchCPin, SwitchDPin, SwitchSleepPin, SwitchBrightnessUpPin, SwitchBrightnessDownPin, SwitchVolumeUpPin, SwitchVolumeDownPin}
  gpioInitMask(buttonPinMask)
  for pin in buttonPinMask:
    gpioPullUp(pin)

  bitstreamPio = pio0

  if unicorn.isNil:
    bitstreamSm = bitstreamPio.claimUnusedSm()
    bitstreamSmOffset = bitstreamPio.addProgram(galacticUnicornProgram)

  for pin in columnPinMask + rowBitPinMask:
    bitstreamPio.gpioInit(pin)

  # set the blank and row pins to be high, then set all led driving pins as outputs.
  # This order is important to avoid a momentary flash
  # const pinsToSet = 1 shl ColumnBlankPin.uint or 0b1111 shl RowBit0Pin.uint
  # pioSmSetPinsWithMask(bitstreamPio, bitstreamSm, pinsToSet, pinsToSet)
  # pioSmSetConsecutivePindirs(bitstreamPio, bitstreamSm, ColumnClockPin.cuint, 8, true)
  bitstreamPio.setPins(bitstreamSm, {ColumnBlankPin} + rowBitPinMask, High)
  bitstreamPio.setPinDirs(bitstreamSm, columnPinMask + rowBitPinMask, Out)

  var c = galacticUnicornProgramGetDefaultConfig(bitstreamSmOffset)

  # osr shifts right, autopull on, autopull threshold 8
  c.setOutShift(true, true, 32)

  # configure out, set, and sideset pins
  c.setOutPins(RowBit0Pin..RowBit3Pin)
  c.setSetPins(ColumnDataPin..ColumnBlankPin)
  c.setSidesetPins(ColumnClockPin)

  # join fifos as only tx needed (gives 8 deep fifo instead of 4)
  c.setFifoJoin(JoinTx)

  # setup dma transfer for pixel data to the pio
  dmaChannel = dmaClaimUnusedChannel(true).uint32
  dmaCtrlChannel = dmaClaimUnusedChannel(true).uint32

  var ctrlConfig = dmaChannelGetDefaultConfig(dmaCtrlChannel)
  ctrlConfig.setTransferDataSize(DmaSize32)
  ctrlConfig.setReadIncrement(false)
  ctrlConfig.setWriteIncrement(false)
  ctrlConfig.setChainTo(dmaChannel)

  dmaChannelConfigure(
    dmaCtrlChannel,
    ctrlConfig.addr,
    dmaHw.ch[dmaChannel].readAddr.addr,
    self.bitstreamAddr.addr,
    1,
    false
  )

  var config = dmaChannelGetDefaultConfig(dmaChannel)
  config.setTransferDataSize(DmaSize32)
  config.setBswap(false) # byte swap to reverse little endian
  config.setDreq(bitstreamPio.getDreq(bitstreamSm, true))
  config.setChainTo(dmaCtrlChannel)

  dmaChannelConfigure(
    dmaChannel,
    config.addr,
    bitstreamPio.txf[bitstreamSm].addr,
    nil,
    BitstreamLength div 4,
    false
  )


  bitstreamPio.init(bitstreamSm, bitstreamSmOffset, c)

  bitstreamPio.enable(bitstreamSm)

  # start the control channel
  dmaStartChannelMask(1'u32 shl dmaCtrlChannel)

  # // setup audio pio program
  # audio_pio = pio0;
  # if(unicorn == nullptr) {
  #   audio_sm = pio_claim_unused_sm(audio_pio, true);
  #   audio_sm_offset = pio_add_program(audio_pio, &audio_i2s_program);
  # }

  # pio_gpio_init(audio_pio, I2S_DATA);
  # pio_gpio_init(audio_pio, I2S_BCLK);
  # pio_gpio_init(audio_pio, I2S_LRCLK);

  # audio_i2s_program_init(audio_pio, audio_sm, audio_sm_offset, I2S_DATA, I2S_BCLK);
  # uint32_t system_clock_frequency = clock_get_hz(clk_sys);
  # uint32_t divider = system_clock_frequency * 4 / SYSTEM_FREQ; // avoid arithmetic overflow
  # pio_sm_set_clkdiv_int_frac(audio_pio, audio_sm, divider >> 8u, divider & 0xffu);

  # audio_dma_channel = dma_claim_unused_channel(true);
  # dma_channel_config audio_config = dma_channel_get_default_config(audio_dma_channel);
  # channel_config_set_transfer_data_size(&audio_config, DMA_SIZE_16);
  # //channel_config_set_bswap(&audio_config, false); // byte swap to reverse little endian
  # channel_config_set_dreq(&audio_config, pio_get_dreq(audio_pio, audio_sm, true));
  # dma_channel_configure(audio_dma_channel, &audio_config, &audio_pio->txf[audio_sm], NULL, 0, false);

  # dma_channel_set_irq0_enabled(audio_dma_channel, true);

  if unicorn == nil:
    irqAddSharedHandler(DmaIrq0, dmaComplete, PICO_SHARED_IRQ_HANDLER_DEFAULT_ORDER_PRIORITY)
    irqSetEnabled(DmaIrq0, true)

  unicorn = self.addr


proc setPixel*(self: var GalacticUnicorn; x, y: int; r, g, b: uint8) =
  if x < 0 or x >= GalacticUnicornWidth or y < 0 or y >= GalacticUnicornHeight:
    return

  # make those coordinates sane
  let x2 = (GalacticUnicornWidth - 1) - x
  let y2 = (GalacticUnicornHeight - 1) - y

  var gammaR = Gamma14Bit[(r * self.brightness) shr 8].int
  var gammaG = Gamma14Bit[(g * self.brightness) shr 8].int
  var gammaB = Gamma14Bit[(b * self.brightness) shr 8].int

  # for each row:
  #   for each bcd frame:
  #            0: 00110110                           # row pixel count (minus one)
  #      1  - 53: xxxxxbgr, xxxxxbgr, xxxxxbgr, ...  # pixel data
  #      54 - 55: xxxxxxxx, xxxxxxxx                 # dummy bytes to dword align
  #           56: xxxxrrrr                           # row select bits
  #      57 - 59: tttttttt, tttttttt, tttttttt       # bcd tick count (0-65536)
  #
  #  .. and back to the start

  let offsetBase = y2 * RowBytes + 2 + x2

  # set the appropriate bits in the separate bcd frames
  for frame in 0 ..< BcdFrameCount:

    let redBit = gammaR and 0b1
    let greenBit = gammaG and 0b1
    let blueBit = gammaB and 0b1

    let offset = offsetBase + (BcdFrameBytes * frame)

    self.bitstream[offset] = uint8 blueBit or (greenBit shl 1) or (redBit shl 2)

    gammaR = gammaR shr 1
    gammaG = gammaG shr 1
    gammaB = gammaB shr 1

proc clear*(self: var GalacticUnicorn) =
  if unicorn == self.addr:
    for y in 0..<GalacticUnicornHeight:
      for x in 0..<GalacticUnicornWidth:
        self.setPixel(x, y, 0, 0, 0)

# proc pioProgramInit(pio: PioInstance; sm: PioStateMachine; offset: uint) =
#   discard

proc light*(self: var GalacticUnicorn): uint16 =
  adcSelectInput(Adc28)
  return adcRead()

proc setBrightness*(self: var GalacticUnicorn; value: float) =
  self.brightness = uint16 floor(value.clamp(0.0, 1.0) * 255.0)

proc getBrightness*(self: var GalacticUnicorn): float =
  self.brightness.float / 255.0

proc adjustBrightness*(self: var GalacticUnicorn; delta: float) =
  self.setBrightness(self.getBrightness() + delta)

proc isPressed*(self: var GalacticUnicorn; button: Button): bool =
  button.Gpio.gpioGet() == Low

proc update*(self: var GalacticUnicorn; graphics: var PicoGraphics) =
  discard
