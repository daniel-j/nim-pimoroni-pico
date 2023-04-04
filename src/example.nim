import std/strutils
import std/random

import picostdlib
import picostdlib/pico/rand

import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/inky_frame

discard stdioInitAll()
# blockUntilUsbConnected()

echo "USB connected"

var fs: FATFS

let m = detectInkyFrameModel()
if m.isSome:
  echo "Detected Inky Frame model: ", m.get()
else:
  echo "Unknown Inky Frame model"

assert(m.isSome)

const inkyKind {.strdefine.} = "Unknown inkyKind"
let inkyKindEnum = parseEnum[InkyFrameKind](inkyKind, m.get())
var inky = InkyFrame(kind: inkyKindEnum)

inky.init()
echo "Wake Up Events: ", inky.getWakeUpEvents()


proc drawFile(filename: string) =
  inky.led(LedActivity, 50)
  inky.setPen(White)
  inky.setBorder(White)
  inky.clear()

  # inky.setPen(Black)
  # inky.rectangle(constructRect(0, 0, 600 div 8, 448))
  # inky.setPen(White)
  # inky.rectangle(constructRect((600 div 8) * 1, 0, 600 div 8, 448))
  # inky.setPen(Green)
  # inky.rectangle(constructRect((600 div 8) * 2, 0, 600 div 8, 448))
  # inky.setPen(Blue)
  # inky.rectangle(constructRect((600 div 8) * 3, 0, 600 div 8, 448))
  # inky.setPen(Red)
  # inky.rectangle(constructRect((600 div 8) * 4, 0, 600 div 8, 448))
  # inky.setPen(Yellow)
  # inky.rectangle(constructRect((600 div 8) * 5, 0, 600 div 8, 448))
  # inky.setPen(Orange)
  # inky.rectangle(constructRect((600 div 8) * 6, 0, 600 div 8, 448))
  # inky.setPen(Clean)
  # inky.rectangle(constructRect((600 div 8) * 7, 0, 600 div 8, 448))

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  if inky.drawJpeg(filename, x, y, w, h, gravity=(0.5, 0.5)) == 1:
    inky.led(LedActivity, 100)
    inky.update()
    inky.led(LedActivity, 0)
    sleepMs(1 * 60 * 1000)
  else:
    inky.led(LedActivity, 0)

iterator walkDir(directory: string): FILINFO =
  var file: FILINFO
  var dir: DIR
  discard f_opendir(dir.addr, directory.cstring)
  while f_readdir(dir.addr, file.addr) == FR_OK and file.fname[0].bool:
    yield file

proc getFileN(directory: string; n: Natural): FILINFO =
  var i = 0
  for file in walkDir(directory):
    if i == n:
      return file
    inc(i)

proc inkyProc() =
  echo "Starting..."

  if EvtBtnA in inky.getWakeUpEvents():
    echo "Drawing HSL chart..."
    let startTime = getAbsoluteTime()
    inky.setPen(White)
    inky.clear()
    var p = Point()
    for y in 0..<inky.height:
      echo y, " of ", inky.height
      p.y = y
      let yd = y / inky.height
      let l = yd
      for x in 0..<inky.width:
        p.x = x
        let xd = x / inky.width
        let hue = xd
        inky.setPen(inky.createPenHsl(hue, 1.0, 1.0 - l))
        # let col = constructRgb(int16 hue * 255, 255, int16 255 - l / 255)
        # let hslCacheKey = (((col.r and 0xE0) shl 1) or ((col.g and 0xE0) shr 2) or ((col.b and 0xE0) shr 5))
        # inky.setPen(hslCache[hslCacheKey].rgb565ToRgb())
        inky.setPixel(p)

    let endTime = getAbsoluteTime()
    echo "Time: ", absoluteTimeDiffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.update()

  elif EvtBtnB in inky.getWakeUpEvents():
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

      inky.setPen(inky.createPenHsl(rand(1.0), 0.5 + rand(0.5), 0.25 + rand(0.5)))
      # inky.setPen(uint 2 + rand(4))
      inky.circle(p, size - 2)

    let endTime = getAbsoluteTime()
    echo "Time: ", absoluteTimeDiffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.update()

  elif EvtBtnC in inky.getWakeUpEvents():
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
    echo "Time: ", absoluteTimeDiffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.update()

  elif EvtBtnD in inky.getWakeUpEvents():
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

      inky.setPen(inky.createPenHsl(rand(1.0), 0.5 + rand(0.5), 0.25 + rand(0.5)))
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

      inky.setPen(inky.createPenHsl(rand(1.0), 0.5 + rand(0.5), 0.25 + rand(0.5)))
      # inky.setPen(uint 2 + rand(4))
      inky.thickLine(p1, p2, thickness)

    let endTime = getAbsoluteTime()
    echo "Time: ", absoluteTimeDiffUs(startTime, endTime) div 1000, "ms"
    echo "Updating..."
    inky.update()

  elif EvtBtnE in inky.getWakeUpEvents():
    echo "Cleaning..."
    inky.setPen(Clean)
    inky.setBorder(Orange)
    let startTime = getAbsoluteTime()
    inky.clear()
    let endTime = getAbsoluteTime()
    echo "Time to clear: ", absoluteTimeDiffUs(startTime, endTime) div 1000, "ms"
    echo "First update..."
    inky.update()
    inky.setBorder(White)
    echo "Second update..."
    inky.update()

  echo "Mounting SD card..."

  let fr = f_mount(fs.addr, "".cstring, 1)
  if fr != FR_OK:
    echo "Failed to mount SD card, error: ", fr
  else:
    echo "Listing SD card contents.."
    let directory = "/images"
    var fileCount = 0
    for i in walkDir(directory):
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
      echo "- ", file.getFname()

    echo "starting main image loop"

    for i in fileOrder:
      let file = getFileN(directory, i)
      echo "- ", file.getFname(), " ", file.fsize
      if file.fsize == 0:
        continue

      echo "- file timestamp: ", $file.getFileDate(), " ", $file.getFileTime()

      let filename = directory & "/" & file.getFname()

      drawFile(filename)

    discard f_unmount("")

inkyProc()

while true:
  inky.led(LedActivity, 0)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
  sleepMs(250)
  inky.led(LedActivity, 100)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
  sleepMs(250)
  tightLoopContents()
