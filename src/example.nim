
import picostdlib/[
  pico/stdio,
  pico/time,
  pico/platform,
  pico/cyw43_arch
]

import pimoroni_pico/libraries/jpegdec
import pimoroni_pico/libraries/inky_frame

import std/math


discard stdioUsbInit()
blockUntilUsbConnected()

echo "USB connected"


var fs: FATFS
var fr: FRESULT
var jpeg: JPEGDEC
var inky: InkyFrame

type
  JpegDecodeOptions = object
    x, y, w, h: int
    jpegW, jpegH: int
    progress: int
    dither: bool
    lastY: int
    chunkHeight: int

var jpegDecodeOptions: JpegDecodeOptions

var errorMatrix: seq[seq[Rgb]]

proc processErrorMatrix(drawY: int) =
  # echo "processing errorMatrix ", drawY
  let imgW = jpegDecodeOptions.w
  let imgH = jpegDecodeOptions.chunkHeight + 1

  let ox = jpegDecodeOptions.x
  let oy = jpegDecodeOptions.y
  let dx = 0
  let dy = drawY * jpegDecodeOptions.h div jpegDecodeOptions.jpegH

  for y in 0 ..< imgH - 1:
    for x in 0 ..< imgW:
      let pos = Point(x: ox + dx + x, y: oy + dy + y)

      let oldPixel = errorMatrix[y][x].clamp()

      inky.setPixel(pos, oldPixel)  ##  find closest color using a LUT

      # echo pos, " ", oldPixel

      ## inky.setPen(oldPixel.closest(inky.palette).uint8)  ##  find closest color using distance function
      ## inky.setPixel(pos)

      let newPixel = inky.palette[inky.color.uint8]

      let quantError = oldPixel - newPixel

      if x + 1 < imgW:
        errorMatrix[y][x + 1] = (errorMatrix[y][x + 1] + quantError * 7 div 16)

      if y + 1 < imgH:
        if x > 0:
          errorMatrix[y + 1][x - 1] = (errorMatrix[y + 1][x - 1] + quantError * 3 div 16)
        errorMatrix[y + 1][x] = (errorMatrix[y + 1][x] + quantError * 5 div 16)
        if x + 1 < imgW:
          errorMatrix[y + 1][x + 1] = (errorMatrix[y + 1][x + 1] + quantError * 1 div 16)

  echo (jpegDecodeOptions.progress * 100) div (jpegDecodeOptions.w * jpegDecodeOptions.h), "%"

proc jpegdec_open_callback(filename: cstring, size: ptr int32): pointer {.cdecl.} =
  let fil = create(FIL)
  if f_open(fil, filename, FA_READ).bool:
    return nil
  size[] = f_size(fil).int32
  return fil

proc jpegdec_close_callback(handle: pointer) {.cdecl.} =
  discard f_close(cast[ptr FIL](handle))
  dealloc(cast[ptr FIL](handle))

proc jpegdec_read_callback(jpeg: ptr JPEGFILE; p: ptr uint8, c: int32): int32 {.cdecl.} =
  var br: cuint
  discard f_read(cast[ptr FIL](jpeg.fHandle), cast[pointer](p), c.cuint, br.addr)
  return br.int32

proc jpegdec_seek_callback(jpeg: ptr JPEGFILE, p: int32): int32 {.cdecl.} =
  (f_lseek(cast[ptr FIL](jpeg.fHandle), p.FSIZE_t) == FR_OK).int32

proc jpegdec_draw_callback(draw: ptr JPEGDRAW): cint {.cdecl.} =
  let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)

  let dx = (draw.x * jpegDecodeOptions.w div jpegDecodeOptions.jpegW)
  let dy = (draw.y * jpegDecodeOptions.h div jpegDecodeOptions.jpegH)
  let dw = ((draw.x + draw.iWidth) * jpegDecodeOptions.w div jpegDecodeOptions.jpegW) - dx
  let dh = ((draw.y + draw.iHeight) * jpegDecodeOptions.h div jpegDecodeOptions.jpegH) - dy

  if draw.x == 0 and draw.y == 0:
    echo draw[]
    jpegDecodeOptions.chunkHeight = dh

    errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

    for i in 0 .. jpegDecodeOptions.chunkHeight:
      errorMatrix[i] = newSeq[Rgb](jpegDecodeOptions.w)

  if jpegDecodeOptions.lastY != draw.y:
    processErrorMatrix(jpegDecodeOptions.lastY)
    swap(errorMatrix[0], errorMatrix[jpegDecodeOptions.chunkHeight])

    jpegDecodeOptions.chunkHeight = dh
    errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

    for i in 1 .. jpegDecodeOptions.chunkHeight:
      errorMatrix[i] = newSeq[Rgb](jpegDecodeOptions.w)

  jpegDecodeOptions.lastY = draw.y

  # var lastDx = -1
  # var lastDy = -1
  # for y in 0 ..< draw.iHeight:
  #   let dy = y # (y * jpegDecodeOptions.h) div jpegDecodeOptions.jpegH
  #   if lastDy == dy: continue
  #   lastDy = dy
  #   for x in 0 ..< draw.iWidth:
  #     let dx = ((draw.x + x) * jpegDecodeOptions.w) div jpegDecodeOptions.jpegW
  #     if lastDx == dx: continue
  #     lastDx = dx
  #     if dx >= 0 and dx < jpegDecodeOptions.w and dy >= 0 and dy < jpegDecodeOptions.chunkHeight:
  #       inc(errorMatrix[dy][dx], constructRgb(RGB565(p[x + y * draw.iWidth])))
  #       # echo "set pixel ", Point(x: dx + jpegDecodeOptions.x, y: dy + draw.y + jpegDecodeOptions.y)
  #       #inky.setPixel(Point(x: dx + jpegDecodeOptions.x, y: dy + jpegDecodeOptions.y), constructRgb(RGB565(p[x + y * draw.iWidth])))  ##  find closest color using a LUT

  # echo "dest: ", (dx, dy), " size: ", (dw, dh)

  for y in 0 ..< dh:
    if dy + y < 0 or dy + y >= jpegDecodeOptions.h: continue
    let symin = floor(y * jpegDecodeOptions.jpegH / jpegDecodeOptions.h).int
    if symin >= draw.iHeight: continue
    let symax = ceil(y * jpegDecodeOptions.jpegH / jpegDecodeOptions.h).int
    for x in 0 ..< dw:
      if dx + x < 0 or dx + x >= jpegDecodeOptions.w: continue
      let sxmin = floor(x * jpegDecodeOptions.jpegW / jpegDecodeOptions.w).int
      if sxmin >= draw.iWidth: continue
      let sxmax = ceil(x * jpegDecodeOptions.jpegW / jpegDecodeOptions.w).int
      # echo "pixel", (dx + x, dy + y), " from ", (sx, sy)
      var color = constructRgb(RGB565(p[sxmin + symin * draw.iWidth]))
      if sxmax < draw.iWidth and symax < draw.iHeight and sxmin != sxmax and symin != sxmax:
        inc(color, constructRgb(RGB565(p[sxmin + symax * draw.iWidth])))
        inc(color, constructRgb(RGB565(p[sxmax + symin * draw.iWidth])))
        inc(color, constructRgb(RGB565(p[sxmax + symax * draw.iWidth])))
        color = color div 4

      color = color.saturate(1.2).level(black=0.00, white=0.92, gamma=0.92)

      # inky.setPixel(Point(x: jpegDecodeOptions.x + dx + x, y: jpegDecodeOptions.y + dy + y), color)
      inc(errorMatrix[y][dx + x], color)
      jpegDecodeOptions.progress.inc()

  return 1


proc drawJpeg(filename: string; x, y: int = 0; w, h: int; dither: bool = false; gravity: tuple[x, y: float] = (0.0, 0.0)): int =
  jpegDecodeOptions.x = x
  jpegDecodeOptions.y = y
  jpegDecodeOptions.w = w
  jpegDecodeOptions.h = h
  jpegDecodeOptions.progress = 0
  jpegDecodeOptions.dither = dither
  jpegDecodeOptions.lastY = 0

  echo "- opening jpeg file ", filename
  var jpegErr = jpeg.open(
    filename,
    jpegdec_open_callback,
    jpegdec_close_callback,
    jpegdec_read_callback,
    jpegdec_seek_callback,
    jpegdec_draw_callback
  )
  if jpegErr == 1:
    echo "- jpeg dimensions: ", jpeg.getWidth(), "x", jpeg.getHeight()

    # https://stackoverflow.com/questions/21961839/simulation-background-size-cover-in-canvas/45894506#45894506
    let contains = true
    let boxRatio = w / h
    let imgRatio = jpeg.getWidth() / jpeg.getHeight()

    if (if contains: imgRatio > boxRatio else: imgRatio < boxRatio):
      jpegDecodeOptions.h = (w.float / imgRatio).int
    else:
      jpegDecodeOptions.w = (h.float * imgRatio).int

    jpegDecodeOptions.x = ((w - jpegDecodeOptions.w).float * gravity.x).int + x
    jpegDecodeOptions.y = ((h - jpegDecodeOptions.h).float * gravity.y).int + y

    jpegDecodeOptions.jpegW = jpeg.getWidth()
    jpegDecodeOptions.jpegH = jpeg.getHeight()

    var jpegScaleFactor = 0
    if jpeg.getWidth() > jpegDecodeOptions.w * 8 and jpeg.getHeight() > jpegDecodeOptions.h * 8:
      jpegScaleFactor = JPEG_SCALE_EIGHTH
      jpegDecodeOptions.jpegW = jpeg.getWidth() div 8
      jpegDecodeOptions.jpegH = jpeg.getHeight() div 8
    elif jpeg.getWidth() > jpegDecodeOptions.w * 4 and jpeg.getHeight() > jpegDecodeOptions.h * 4:
      jpegScaleFactor = JPEG_SCALE_QUARTER
      jpegDecodeOptions.jpegW = jpeg.getWidth() div 4
      jpegDecodeOptions.jpegH = jpeg.getHeight() div 4
    elif jpeg.getWidth() > jpegDecodeOptions.w * 2 and jpeg.getHeight() > jpegDecodeOptions.h * 2:
      jpegScaleFactor = JPEG_SCALE_HALF
      jpegDecodeOptions.jpegW = jpeg.getWidth() div 2
      jpegDecodeOptions.jpegH = jpeg.getHeight() div 2

    echo "- jpeg scale factor: ", jpegScaleFactor
    echo "- jpeg scaled dimensions: ", jpegDecodeOptions.jpegW, "x", jpegDecodeOptions.jpegH
    echo "- drawing jpeg at ", (jpegDecodeOptions.x, jpegDecodeOptions.y)
    echo "- drawing size ", (jpegDecodeOptions.w, jpegDecodeOptions.h)

    jpeg.setPixelType(RGB565_LITTLE_ENDIAN)

    echo "- starting jpeg decode.."
    try:
      jpegErr = jpeg.decode(0, 0, jpegScaleFactor.cint)
    except CatchableError:
      echo "error: ", system.getCurrentException().msg, system.getCurrentException().getStackTrace()
      echo jpeg.getLastError()
      jpegErr = 0
    if jpegErr != 1:
      echo "- jpeg decoding error: ", jpeg.getLastError()
      return jpegErr

    jpeg.close()
    processErrorMatrix(jpegDecodeOptions.lastY)
    errorMatrix.setLen(0)

  else:
    echo "- couldnt decode jpeg! error: ", jpeg.getLastError()
    return jpegErr

  return 1


proc inkyProc() =
  echo "Starting..."

  inky.init()

  echo "Wake Up Event: ", inky.getWakeUpEvent()


  # inky.setPen(Pen.Black)
  # inky.rectangle(constructRect(0, 0, 600 div 8, 448))
  # inky.setPen(Pen.White)
  # inky.rectangle(constructRect((600 div 8) * 1, 0, 600 div 8, 448))
  # inky.setPen(Pen.Green)
  # inky.rectangle(constructRect((600 div 8) * 2, 0, 600 div 8, 448))
  # inky.setPen(Pen.Blue)
  # inky.rectangle(constructRect((600 div 8) * 3, 0, 600 div 8, 448))
  # inky.setPen(Pen.Red)
  # inky.rectangle(constructRect((600 div 8) * 4, 0, 600 div 8, 448))
  # inky.setPen(Pen.Yellow)
  # inky.rectangle(constructRect((600 div 8) * 5, 0, 600 div 8, 448))
  # inky.setPen(Pen.Orange)
  # inky.rectangle(constructRect((600 div 8) * 6, 0, 600 div 8, 448))
  # inky.setPen(Pen.Clean)
  # inky.rectangle(constructRect((600 div 8) * 7, 0, 600 div 8, 448))
  # inky.update()

  echo "Cleaning..."
  inky.setPen(Pen.Clean)
  inky.setBorder(Pen.Red)
  inky.clear()
  inky.update()

  echo "Mounting SD card..."

  fr = f_mount(fs.addr, "", 1)
  if fr != FR_OK:
    echo "Failed to mount SD card, error: ", fr
  else:
    echo "Listing SD card contents.."
    var file: FILINFO
    var dir: DIR
    discard f_opendir(dir.addr, "/hidden/")
    while f_readdir(dir.addr, file.addr) == FR_OK and file.fname[0].bool:
      echo "- ", file.getFname(), " ", file.fsize
      if file.fsize == 0:
        continue

      echo "- file timestamp: ", $file.getFileDate(), " ", $file.getFileTime()

      let filename = "/hidden/" & file.getFname()

      inky.led(Led.Activity, 50)
      inky.setPen(Pen.White)
      inky.setBorder(Pen.White)
      inky.clear()
      if drawJpeg(filename, 0, 0, 600, 448, dither=false, gravity=(0.5, 0.5)) == 1:
        inky.led(Led.Activity, 100)
        inky.update()
        inky.led(Led.Activity, 0)
        sleepMs(1 * 60 * 1000)
      else:
        inky.led(Led.Activity, 0)

    discard f_unmount("")

inkyProc()

while true:
  inky.led(Led.Activity, 0)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
  sleepMs(250)
  inky.led(Led.Activity, 100)
  # cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
  sleepMs(250)
  tightLoopContents()
