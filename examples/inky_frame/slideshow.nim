import std/random
import std/typetraits
import std/strutils

import picostdlib
import picostdlib/pico/rand
import picostdlib/hardware/watchdog

import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/inky_frame
import pimoroni_pico/libraries/pico_graphics/error_diffusion


const pictureDelay = 5

discard stdioInitAll()

var inky: InkyFrame[InkyFrame5_7]

inky.boot()

var jpegDecoder: JpegDecoder[PicoGraphicsPen3Bit]

echo "Detected Inky Frame model: ", inky.kind

inky.init()

inky.led(Led.LedActivity, 100)

echo "Wake Up Events: ", inky.getWakeUpEvents()

# if cyw43ArchInit() == PicoOk:
#   echo "Initialized Cyw43"
#   if inky.isBatteryPowered():
#     echo "Running on battery!"
#     echo "VSYS voltage: ", inky.getBatteryVoltage(), " V"
#   else:
#     echo "Powered by VBUS. Voltage: ", inky.getBatteryVoltage(), " V"
# else:
#   echo "Could not initialize Cyw43"

jpegDecoder.init(inky)

jpegDecoder.errDiff.matrix = FloydSteinberg
jpegDecoder.errDiff.alternateRow = true
jpegDecoder.errDiff.variableDither = true
jpegDecoder.errDiff.hybridDither = false

jpegDecoder.colorModifier = proc (color: var Rgb) =
  color = color.level(gamma=1.3, black=0.05, white=1.02)

proc drawFile(filename: string) =
  inky.led(LedActivity, 50)
  let startTime = getAbsoluteTime()
  inky.setPen(White)
  inky.setBorder(White)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)
    of InkyFrame13_3: (0, 0, 1600, 1200)

  # let (x, y, w, h) = (0, 0, inky.width, inky.height)

  if jpegDecoder.drawJpeg(filename, x, y, w, h, gravity=(0.5f, 0.5f), contains = false, DrawMode.ErrorDiffusion) == 1:
    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    inky.led(LedActivity, 100)
    echo "Updating... (" & filename & ")"
    inky.update()
    echo "Update complete. Sleeping..."
    inky.led(LedActivity, 0)
    # inky.sleep(pictureDelay, true)
    sleepMs(pictureDelay * 60 * 1000)
  else:
    inky.led(LedActivity, 0)

proc getFileN(directory: string; n: Natural): string =
  var i = 0
  for file in fsWalkDir(directory):
    if file.kind != DtReg: continue
    if i == n:
      return file.name
    inc(i)

proc inkyProc() =
  inky.led(Led.LedActivity, 0)
  echo "Starting..."

  echo "Mounting SD card..."

  let fsAvailable = fsInit()
  if not fsAvailable:
    echo "Failed to mount SD card"

  if EvtBtnA in inky.getWakeUpEvents():
    inky.led(LedA, 50)
    echo "Drawing HSL/LCh chart..."
    let startTime = getAbsoluteTime()

    var errDiff = ErrorDiffusion[inky](backend: autobackend(inky))
    errDiff.init(inky, 0, 0, inky.width, inky.height, FloydSteinberg)
    errDiff.alternateRow = true
    errDiff.hybridDither = false
    errDiff.orientation = 0
    if errDiff.backend == ErrorDiffusionBackend.BackendPsram:
      errDiff.psramAddress = PsramAddress inky.width * inky.height

    inky.setPen(White)
    inky.clear()
    var p = Point()
    var row = newSeq[RgbLinear](inky.width)
    for y in 0..<inky.height:
      stdout.write $(y+1) & " of " & $inky.height & "\r"
      stdout.flushFile()
      p.y = y
      let yd = y.float32 / inky.height.float32
      let l = yd
      for x in 0..<inky.width:
        p.x = x
        let xd = x / inky.width
        let hue = xd * 2
        var color = if xd < 0.5:
          inky.createPenHsl(hue, 1.0, 1.02 - l * 1.04)
        else:
          LChToLab(1 - l, 0.5, hue * 360).fromLab()
        # inky.setPen(color)
        # inky.setPixel(p)
        row[x] = color
      errDiff.write(0, y, row)

    errDiff.process()
    errDiff.deinit()

    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.led(LedA, 100)
    inky.update()
    inky.led(LedA, 0)

  elif EvtBtnB in inky.getWakeUpEvents():
    inky.led(LedB, 50)
    echo "Drawing bubbles..."
    let startTime = getAbsoluteTime()
    inky.setPen(White)
    inky.clear()
    const bubbleCount = 100

    for i in 0..<bubbleCount:
      echo i, " of ", bubbleCount
      let size = 25 + rand(50)
      let x = rand(inky.bounds.w)
      let y = rand(inky.bounds.h)
      let p = Point(x: x, y: y)

      inky.setPen(Black)
      inky.circle(p, size)
      var color = inky.createPenHsl(rand(1.0f).float32, 0.5f + rand(0.5f).float32, 0.25f + rand(0.5f).float32).fromLinear()
      color = color.saturate(1.50f).level(black=0.05f, white=0.97f, gamma=1.8f)
      inky.setPen(color)
      # inky.setPen(uint 2 + rand(4))
      inky.circle(p, size - 2)

    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.led(LedB, 100)
    inky.update()
    inky.led(LedB, 0)

  elif EvtBtnC in inky.getWakeUpEvents():
    inky.led(LedC, 50)
    echo "Drawing palette stripes..."
    let startTime = getAbsoluteTime()

    inky.setPen(Black)
    inky.rectangle(constructRect(0, 0, inky.width div 8, inky.height))
    inky.setPen(White)
    inky.rectangle(constructRect((inky.width div 8) * 1, 0, inky.width div 8, inky.height))
    inky.setPen(Green)
    inky.rectangle(constructRect((inky.width div 8) * 2, 0, inky.width div 8, inky.height))
    inky.setPen(Blue)
    inky.rectangle(constructRect((inky.width div 8) * 3, 0, inky.width div 8, inky.height))
    inky.setPen(Red)
    inky.rectangle(constructRect((inky.width div 8) * 4, 0, inky.width div 8, inky.height))
    inky.setPen(Yellow)
    inky.rectangle(constructRect((inky.width div 8) * 5, 0, inky.width div 8, inky.height))
    inky.setPen(Orange)
    inky.rectangle(constructRect((inky.width div 8) * 6, 0, inky.width div 8, inky.height))
    inky.setPen(Clean)
    inky.rectangle(constructRect((inky.width div 8) * 7, 0, inky.width div 8, inky.height))
    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.led(LedC, 100)
    inky.update()
    inky.led(LedC, 0)

  elif EvtBtnD in inky.getWakeUpEvents():
    inky.led(LedD, 50)
    echo "Drawing triangles and lines..."
    let startTime = getAbsoluteTime()
    inky.setPen(White)
    inky.clear()
    const triCount = 50

    for i in 0..<triCount:
      echo i, " of ", triCount
      let size = 50 + rand(50)
      let x = rand(inky.bounds.w)
      let y = rand(inky.bounds.h)
      var p1 = Point(x: x, y: y)
      var p2 = p1 + Point(x: size, y: size)
      var p3 = p1 + Point(x: -size, y: size)

      inky.setPen(inky.createPenHsl(rand(1.0f).float32, 0.5f + rand(0.5f).float32, 0.25f + rand(0.5f).float32).fromLinear())
      # inky.setPen(uint 2 + rand(4))
      inky.triangle(p1, p2, p3)

    const lineCount = 30
    for i in 0..<lineCount:
      echo i, " of ", lineCount
      let x = rand(inky.bounds.w)
      let y = rand(inky.bounds.h)
      let size = 50 + rand(50)
      let thickness = 5 + rand(8)
      var p1 = Point(x: x - rand(size), y: y - rand(size))
      var p2 = Point(x: x + rand(size), y: y + rand(size))

      inky.setPen(inky.createPenHsl(rand(1.0f).float32, 0.5f + rand(0.5f).float32, 0.25f + rand(0.5).float32).fromLinear())
      # inky.setPen(uint 2 + rand(4))
      inky.thickLine(p1, p2, thickness)

    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.led(LedD, 100)
    inky.update()
    inky.led(LedD, 0)

  elif EvtBtnE in inky.getWakeUpEvents():
    inky.led(LedE, 50)
    echo "Cleaning..."
    inky.setPen(Clean)
    inky.setBorder(Orange)
    let startTime = getAbsoluteTime()
    inky.clear()
    let endTime = getAbsoluteTime()
    echo "Time to clear: ", diffUs(startTime, endTime) div 1000, "ms"
    echo "First update..."
    inky.led(LedE, 100)
    inky.update()
    inky.setBorder(White)
    echo "Second update..."
    inky.update()
    inky.led(LedE, 0)

  if fsAvailable:
    echo "Listing SD card contents.."
    let directory = "/sd/images"
    var fileCount = 0
    for f in fsWalkDir(directory):
      if f.kind == DtReg:
        inc(fileCount)
    echo "number of files: ", fileCount
    var fileOrder = newSeq[int](fileCount)
    for i in 0..<fileCount:
      fileOrder[i] = i
    let seed = cast[int64](getRand64())
    echo "rand seed: ", seed
    randomize(seed)
    fileOrder.shuffle()
    echo "shuffled file order:"
    for i in fileOrder:
      let file = getFileN(directory, i)
      echo "- ", file

    echo "starting main image loop"

    for i in fileOrder:
      let fname = getFileN(directory, i)
      let file = directory / fname
      let fsize = getFileSize(file)
      if fsize == 0 or not (file.toLower().endsWith(".jpg") or file.toLower().endsWith(".jpeg")):
        continue

      echo "- ", file, " ", fsize
      echo "- file timestamp: ", getLastModificationTime(file).utc

      drawFile(file)

    discard fsUnmount("/sd")
    sleepMs(30 * 1000)
    watchdogReboot(0, 0, 0)

inkyProc()

while true:
  inky.led(LedActivity, 0)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
  sleepMs(250)
  inky.led(LedActivity, 100)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
  sleepMs(250)
  tightLoopContents()
