import ../drivers/display_st7789
import ../drivers/rgbled
import ../drivers/button

export display_st7789, rgbled, button

type
  PicoDisplayKind* = enum
    PicoDisplay1_1
    PicoDisplay2_0
    PicoDisplay2_8

  PicoDisplayInfo* = object
    width*: uint16
    height*: uint16
    ledRed*: Gpio
    ledGreen*: Gpio
    ledBlue*: Gpio
    btnA*: Gpio
    btnB*: Gpio
    btnX*: Gpio
    btnY*: Gpio

const picoDisplay1_1* = PicoDisplayInfo(
  width: 240,
  height: 135,
  ledRed: Gpio(6),
  ledGreen: Gpio(7),
  ledBlue: Gpio(8),
  btnA: Gpio(12),
  btnB: Gpio(13),
  btnX: Gpio(14),
  btnY: Gpio(15)
)

const picoDisplay2_0* = PicoDisplayInfo(
  width: 320,
  height: 240,
  ledRed: picoDisplay1_1.ledRed,
  ledGreen: picoDisplay1_1.ledGreen,
  ledBlue: picoDisplay1_1.ledBlue,
  btnA: picoDisplay1_1.btnA,
  btnB: picoDisplay1_1.btnB,
  btnX: picoDisplay1_1.btnX,
  btnY: picoDisplay1_1.btnY
)

const picoDisplay2_8* = PicoDisplayInfo(
  width: picoDisplay2_0.width,
  height: picoDisplay2_0.height,
  ledRed: Gpio(26),
  ledGreen: Gpio(27),
  ledBlue: Gpio(28),
  btnA: picoDisplay2_0.btnA,
  btnB: picoDisplay2_0.btnB,
  btnX: picoDisplay2_0.btnX,
  btnY: picoDisplay2_0.btnY
)

func getPicoDisplayInfo(kind: PicoDisplayKind): PicoDisplayInfo =
  return case kind:
  of PicoDisplay1_1: picoDisplay1_1
  of PicoDisplay2_0: picoDisplay2_0
  of PicoDisplay2_8: picoDisplay2_8

type
  PicoDisplay*[kind: static[PicoDisplayKind]] = object of PicoGraphicsPenRgb565
    display*: St7789
    led*: RgbLed
    fb: array[getPicoDisplayInfo(kind).width.int * getPicoDisplayInfo(kind).height.int, Rgb565]
    btnA*: Button
    btnB*: Button
    btnX*: Button
    btnY*: Button


proc createPicoDisplay*(kind: static[PicoDisplayKind]): PicoDisplay[kind] =
  const picoDisplayInfo = case kind:
  of PicoDisplay1_1: picoDisplay1_1
  of PicoDisplay2_0: picoDisplay2_0
  of PicoDisplay2_8: picoDisplay2_8
  result.display.init(picoDisplayInfo.width, picoDisplayInfo.height, Rotate_0, false, getSpiPins(Front))

  result.init(result.display.width, result.display.height, frameBuffer = result.fb[0].addr)

  result.led = createRgbLed(picoDisplayInfo.ledRed, picoDisplayInfo.ledGreen, picoDisplayInfo.ledBlue)

  result.btnA = createButton(picoDisplayInfo.btnA)
  result.btnB = createButton(picoDisplayInfo.btnB)
  result.btnX = createButton(picoDisplayInfo.btnX)
  result.btnY = createButton(picoDisplayInfo.btnY)

proc update*(self: var PicoDisplay) =
  self.display.update(PicoGraphicsPenRgb565(self))

proc setBacklight*(self: PicoDisplay; level: uint8) =
  self.display.setBacklight(level)
