
import picostdlib/[
  pico/stdio,
  pico/time,
  pico/cyw43_arch
]
import pimoroni_pico/libraries/jpegdec
import pimoroni_pico/libraries/inky_frame


var fs: FATFS
var fr: FRESULT
var jpeg: JPEGDEC
var inky: InkyFrame

type
  JpegDecodeOptions = object
    x, y: int
    progress: int
    dither: bool
    lastY: int
    chunkHeight: int

var jpegDecodeOptions: JpegDecodeOptions

var errorMatrix: seq[seq[Rgb]]

proc processErrorMatrix(drawY: int) =
  # echo "processing errorMatrix ", drawY
  let imgW = jpeg.getWidth()
  let imgH = jpegDecodeOptions.chunkHeight + 1

  let xo = jpegDecodeOptions.x
  let yo = jpegDecodeOptions.y

  for y in 0 ..< jpegDecodeOptions.chunkHeight:
    let sy = drawY + y
    for x in 0 ..< imgW:
      let sx = x
      let pos = Point(x: xo + sx, y: yo + sy)

      let oldPixel = errorMatrix[y][x].clamp()

      inky.setPixel(pos, oldPixel)  ##  find closest color using a LUT

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

      jpegDecodeOptions.progress.inc()

  echo (jpegDecodeOptions.progress * 100) div (jpeg.getWidth() * jpeg.getHeight()), "% "

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

  if draw.x == 0 and draw.y == 0:
    echo draw[]
    jpegDecodeOptions.chunkHeight = draw.iHeight

    errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

    for i in 0 .. jpegDecodeOptions.chunkHeight:
      errorMatrix[i] = newSeq[Rgb](jpeg.getWidth())

  if jpegDecodeOptions.lastY != draw.y:
    processErrorMatrix(jpegDecodeOptions.lastY)
    errorMatrix[0] = seq(errorMatrix[jpegDecodeOptions.chunkHeight])
    for i in 1 .. jpegDecodeOptions.chunkHeight:
      errorMatrix[i] = newSeq[Rgb](jpeg.getWidth())

  jpegDecodeOptions.lastY = draw.y

  # echo "decoding ", draw.y

  for y in 0 ..< draw.iHeight:
    for x in 0 ..< draw.iWidth:
      if draw.x + x < jpeg.getWidth():
        inc(errorMatrix[y][draw.x + x], constructRgb(RGB565(p[x + y * draw.iWidth])))

  return 1


proc drawJpeg(filename: string; x, y: int; dither: bool): int =
  jpegDecodeOptions.x = x
  jpegDecodeOptions.y = y
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

    jpeg.setPixelType(RGB565_LITTLE_ENDIAN)

    echo "- starting jpeg decode.."
    try:
      jpegErr = jpeg.decode(0, 0, 0)
    except CatchableError:
      echo "error: ", system.getCurrentException().msg, system.getCurrentException().getStackTrace()
      echo jpeg.getLastError()
      jpegErr = 0
    if jpegErr != 1:
      echo "- jpeg decoding error: ", jpegErr
      return jpegErr


    jpeg.close()
    processErrorMatrix(jpegDecodeOptions.lastY)
    errorMatrix.setLen(0)

  else:
    echo "- couldnt decode jpeg! error: ", jpegErr
    return jpegErr

  return 1

if cyw43_arch_init() != 0:
  echo "Wifi init failed!"
else:

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)

  discard stdioUsbInit()
  blockUntilUsbConnected()

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)

  echo "Starting..."

  inky.init()

  #[
  inky.setPen(Pen.Black)
  inky.rectangle(constructRect(0, 0, 600 div 8, 448))
  inky.setPen(Pen.White)
  inky.rectangle(constructRect((600 div 8) * 1, 0, 600 div 8, 448))
  inky.setPen(Pen.Green)
  inky.rectangle(constructRect((600 div 8) * 2, 0, 600 div 8, 448))
  inky.setPen(Pen.Blue)
  inky.rectangle(constructRect((600 div 8) * 3, 0, 600 div 8, 448))
  inky.setPen(Pen.Red)
  inky.rectangle(constructRect((600 div 8) * 4, 0, 600 div 8, 448))
  inky.setPen(Pen.Yellow)
  inky.rectangle(constructRect((600 div 8) * 5, 0, 600 div 8, 448))
  inky.setPen(Pen.Orange)
  inky.rectangle(constructRect((600 div 8) * 6, 0, 600 div 8, 448))
  inky.setPen(Pen.Clean)
  inky.rectangle(constructRect((600 div 8) * 7, 0, 600 div 8, 448))
  inky.update()
  ]#
  echo "Cleaning..."
  inky.setPen(Pen.Clean)
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

      let filename = "/hidden/" & file.getFname()
      inky.led(Led.Activity, 50)
      if drawJpeg(filename, 0, 0, dither=false) == 1:
        inky.led(Led.Activity, 100)
        inky.update()
      inky.led(Led.Activity, 0)
      sleepMs(30 * 1000)


    discard f_unmount("")

  echo "Wake Up Event: ", inky.getWakeUpEvent()

  while true:
    inky.led(Led.Activity, 0)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
    sleepMs(250)
    inky.led(Led.Activity, 100)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
    sleepMs(250)

