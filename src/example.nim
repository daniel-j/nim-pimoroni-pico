
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
    x, y, w, h: int

var jpegDecodeOptions: JpegDecodeOptions

proc jpegdec_open_callback(filename: cstring, size: ptr int32): pointer {.noconv.} =
  let fil = create(FIL)
  if f_open(fil, filename, FA_READ).bool:
    return nil
  size[] = f_size(fil).int32
  return fil

proc jpegdec_close_callback(handle: pointer) {.noconv.} =
  discard f_close(cast[ptr FIL](handle))
  dealloc(cast[ptr FIL](handle))

proc jpegdec_read_callback(jpeg: ptr JPEGFILE; p: ptr uint8, c: int32): int32 {.noconv.} =
  var br: cuint
  discard f_read(cast[ptr FIL](jpeg.fHandle), cast[pointer](p), c.cuint, br.addr)
  return br.int32

proc jpegdec_seek_callback(jpeg: ptr JPEGFILE, p: int32): int32 {.noconv.} =
  (f_lseek(cast[ptr FIL](jpeg.fHandle), p.FSIZE_t) == FR_OK).int32

proc jpegdec_draw_callback(draw: ptr JPEGDRAW): cint {.noconv.} =
  let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)
  var i = 0
  let xo = jpegDecodeOptions.x
  let yo = jpegDecodeOptions.y

  # echo "drawing at ", draw.x, "x", draw.y, "  size ", draw.iWidth, "x", draw.iHeight
  for y in 0 ..< draw.iHeight:
    for x in 0 ..< draw.iWidth:
      let sx = ((draw.x + x + xo) * jpegDecodeOptions.w) div jpeg.getWidth()
      let sy = ((draw.y + y + yo) * jpegDecodeOptions.h) div jpeg.getHeight()

      if xo + sx >= 0 and xo + sx < inky.bounds.w and yo + sy >= 0 and yo + sy < inky.bounds.h:
        let pos = Point(x: xo + sx, y: yo + sy)
        let c = constructRgb(RGB565(p[i]))
        #inky.setPen(c)
        #inky.setPixel(pos)
        inky.setPixelDither(pos, c)

      inc(i)

  return 1


proc drawJpeg(filename: string; x, y, w, h: int) =
  jpegDecodeOptions.x = x
  jpegDecodeOptions.y = y
  jpegDecodeOptions.w = w
  jpegDecodeOptions.h = h

  echo "- opening jpeg file ", filename
  echo jpeg.open(
    filename,
    jpegdec_open_callback,
    jpegdec_close_callback,
    jpegdec_read_callback,
    jpegdec_seek_callback,
    jpegdec_draw_callback
  )

  jpeg.setPixelType(RGB565_LITTLE_ENDIAN)

  echo "- starting jpeg decode.."
  echo jpeg.decode(0, 0, 0)

  jpeg.close()

if cyw43_arch_init() != 0:
  echo "Wifi init failed!"
else:

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)

  discard stdioUsbInit()
  blockUntilUsbConnected()

  cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)

  echo "Starting..."

  inky.init()

  echo "Cleaning..."

  inky.setPen(Colour.Clean)
  inky.clear()
  #inky.setPen(Colour.Red)
  #inky.rectangle(Rect(x: 0, y: 0, w: 100, h: 100))
  #inky.setPen(Colour.Green)
  #inky.polygon([P(200, 400), P(300, 100), P(120, 120)])
  inky.update()

  echo "Mounting SD card..."

  fr = f_mount(fs.addr, "", 1)
  if fr != FR_OK:
    echo "Failed to mount SD card, error: ", fr
  else:
    echo "Listing SD card contents.."
    var file: FILINFO
    var dir: DIR
    discard f_opendir(dir.addr, "/")
    while f_readdir(dir.addr, file.addr) == FR_OK and file.fname[0].bool:
      echo "- ", file.getFname(), " ", file.fsize, " ", file.getFname().len

    let filename = "a.jpg"
    drawJpeg(filename, 0, 0, 600, 448)
    inky.update()

  echo "Wake Up Event: ", inky.getWakeUpEvent()

  while true:
    inky.led(Led.Activity, 0)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, true)
    sleepMs(250)
    inky.led(Led.Activity, 100)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, false)
    sleepMs(250)

