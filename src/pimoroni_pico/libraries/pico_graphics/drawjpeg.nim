import std/math
import ../pico_graphics
import ../jpegdec
when not defined(mock):
  import ../../drivers/fatfs

var jpeg: JPEGDEC

type
  DrawMode* = enum
    Default, OrderedDither, ErrorDiffusion

  JpegDecodeOptions = object
    x, y, w, h: int
    jpegW, jpegH: int
    progress: int
    lastY: int
    chunkHeight: int
    graphics: ptr PicoGraphics
    drawMode: DrawMode

var jpegDecodeOptions: JpegDecodeOptions
var errorMatrix: seq[seq[RgbLinear]]

proc processErrorMatrix(drawY: int) =
  # echo "processing errorMatrix ", drawY
  let imgW = jpegDecodeOptions.w
  let imgH = jpegDecodeOptions.chunkHeight + 1

  let graphics = jpegDecodeOptions.graphics

  let ox = jpegDecodeOptions.x
  let oy = jpegDecodeOptions.y
  let dx = 0
  let dy = drawY * jpegDecodeOptions.h div jpegDecodeOptions.jpegH

  for y in 0 ..< imgH - 1:
    for x in 0 ..< imgW:

      let pos = case jpeg.getOrientation():
      of 3: Point(x: ox + jpegDecodeOptions.w - (dx + x), y: oy + jpegDecodeOptions.h - (dy + y))
      of 6: Point(x: ox + jpegDecodeOptions.h - (dy + y), y: oy + (dx + x))
      of 8: Point(x: ox + (dy + y), y: oy + jpegDecodeOptions.w - (dx + x))
      else: Point(x: ox + dx + x, y: oy + dy + y)

      let oldPixel = errorMatrix[y][x]

      # find closest color using distance function
      let color = graphics[].createPenNearest(oldPixel)
      graphics[].setPen(color)
      graphics[].setPixel(pos)

      let newPixel = graphics[].getPenColor(color)

      let quantError = oldPixel.clamp() - newPixel

      if x + 1 < imgW:
        errorMatrix[y][x + 1] += (quantError * 7) shr 4  # 7/16

      if y + 1 < imgH:
        if x > 0:
          errorMatrix[y + 1][x - 1] += (quantError * 3) shr 4  # 3/16
        errorMatrix[y + 1][x] += (quantError * 5) shr 4  # 5/16
        if x + 1 < imgW:
          errorMatrix[y + 1][x + 1] += (quantError) shr 4  # 1/16

proc jpegdec_open_callback(filename: cstring, size: ptr int32): pointer {.cdecl.} =
  when not defined(mock):
    let fil = create(FIL)
    if f_open(fil, filename, FA_READ) != FR_OK:
      return nil
    size[] = f_size(fil).int32
    return fil
  else:
    let file = new File
    if not file[].open($filename, fmRead):
      return nil
    size[] = file[].getFileSize().int32
    GC_ref(file)
    return cast[pointer](file)

proc jpegdec_close_callback(handle: pointer) {.cdecl.} =
  when not defined(mock):
    discard f_close(cast[ptr FIL](handle))
    dealloc(cast[ptr FIL](handle))
  else:
    let file = cast[ref File](handle)
    file[].close()
    GC_unref(file)

proc jpegdec_read_callback(jpeg: ptr JPEGFILE; p: ptr uint8, c: int32): int32 {.cdecl.} =
  when not defined(mock):
    var br: cuint
    discard f_read(cast[ptr FIL](jpeg.fHandle), cast[pointer](p), c.cuint, br.addr)
    return br.int32
  else:
    let file = cast[ref File](jpeg.fHandle)
    return file[].readBuffer(p, c).int32

proc jpegdec_seek_callback(jpeg: ptr JPEGFILE, p: int32): int32 {.cdecl.} =
  when not defined(mock):
    (f_lseek(cast[ptr FIL](jpeg.fHandle), p.FSIZE_t) == FR_OK).int32
  else:
    let file = cast[ref File](jpeg.fHandle)
    file[].setFilePos(p)
    return 1

proc jpegdec_draw_callback(draw: ptr JPEGDRAW): cint {.cdecl.} =
  let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)
  let graphics = jpegDecodeOptions.graphics

  let dx = (draw.x * jpegDecodeOptions.w div jpegDecodeOptions.jpegW)
  let dy = (draw.y * jpegDecodeOptions.h div jpegDecodeOptions.jpegH)
  let dw = ((draw.x + draw.iWidth) * jpegDecodeOptions.w div jpegDecodeOptions.jpegW) - dx
  let dh = ((draw.y + draw.iHeight) * jpegDecodeOptions.h div jpegDecodeOptions.jpegH) - dy

  if jpegDecodeOptions.drawMode == ErrorDiffusion:
    if draw.x == 0 and draw.y == 0:
      # echo "Free heap before errorMatrix: ", getFreeHeap()
      echo draw[]
      jpegDecodeOptions.chunkHeight = dh

      errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

      for i in 0 .. jpegDecodeOptions.chunkHeight:
        errorMatrix[i] = newSeq[RgbLinear](jpegDecodeOptions.w)
      # echo "Free heap after errorMatrix alloc: ", getFreeHeap()

    if jpegDecodeOptions.lastY != draw.y:
      processErrorMatrix(jpegDecodeOptions.lastY)
      swap(errorMatrix[0], errorMatrix[jpegDecodeOptions.chunkHeight])

      jpegDecodeOptions.chunkHeight = dh
      errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

      for i in 1 .. jpegDecodeOptions.chunkHeight:
        errorMatrix[i] = newSeq[RgbLinear](jpegDecodeOptions.w)

    jpegDecodeOptions.lastY = draw.y

  let lastProgress = (jpegDecodeOptions.progress * 100) div (jpegDecodeOptions.w * jpegDecodeOptions.h)

  for y in 0 ..< dh:
    if dy + y < 0 or dy + y >= jpegDecodeOptions.h: continue
    let symin = floor(y * jpegDecodeOptions.jpegH / jpegDecodeOptions.h).int
    if symin >= draw.iHeight: continue
    let symax = min(floor((y + 1) * jpegDecodeOptions.jpegH / jpegDecodeOptions.h).int, draw.iHeight)
    for x in 0 ..< dw:
      if dx + x < 0 or dx + x >= jpegDecodeOptions.w: continue
      let sxmin = floor(x * jpegDecodeOptions.jpegW / jpegDecodeOptions.w).int
      if sxmin >= draw.iWidth: continue
      let sxmax = min(floor((x + 1) * jpegDecodeOptions.jpegW / jpegDecodeOptions.w).int, draw.iWidth)

      let pos = case jpeg.getOrientation():
      of 3: Point(x: jpegDecodeOptions.x + jpegDecodeOptions.w - (dx + x), y: jpegDecodeOptions.y + jpegDecodeOptions.h - (dy + y))
      of 6: Point(x: jpegDecodeOptions.x + jpegDecodeOptions.h - (dy + y), y: jpegDecodeOptions.y + (dx + x))
      of 8: Point(x: jpegDecodeOptions.x + (dy + y), y: jpegDecodeOptions.y + jpegDecodeOptions.w - (dx + x))
      else: Point(x: jpegDecodeOptions.x + dx + x, y: jpegDecodeOptions.y + dy + y)

      var color = Rgb()

      # linear interpolation
      # var colorv = Vec3()
      # var divider = 0
      # for sx in sxmin..<sxmax:
      #   for sy in symin..<symax:
      #     colorv += constructRgb(Rgb565(p[sx + sy * draw.iWidth])).rgbToVec3().srgbToLinear()
      #     inc(divider)
      # if divider > 0:
      #   color = (colorv / divider.float).linearToSRGB().vec3ToRgb()
      # else:
      #   # fallback
      #   color = constructRgb(Rgb565(p[sxmin + symin * draw.iWidth]))
      color = constructRgb(Rgb565(p[sxmin + symin * draw.iWidth]))

      color = color.level(black=0.00, white=0.97, gamma=1.0).saturate(1.15)

      case jpegDecodeOptions.drawMode:
      of Default:
        let pen = graphics[].createPenNearest(color.toLinear())
        graphics[].setPen(pen)
        graphics[].setPixel(pos)
      of OrderedDither:
        graphics[].setPixelDither(pos, color.toLinear())
      of ErrorDiffusion:
        errorMatrix[y][dx + x] += color.toLinear()

      # errorMatrix[y][dx + x] = (((errorMatrix[y][dx + x].rgbToVec3() / errorMultiplier) + color.rgbToVec3().srgbToLinear(gamma=2.1)) * errorMultiplier).vec3ToRgb()
      jpegDecodeOptions.progress.inc()

  let currentProgress = (jpegDecodeOptions.progress * 100) div (jpegDecodeOptions.w * jpegDecodeOptions.h)
  if lastProgress != currentProgress:
    echo currentProgress, "%"

  return 1


proc drawJpeg*(self: var PicoGraphics; filename: string; x, y: int = 0; w, h: int; gravity: tuple[x, y: float] = (0.0, 0.0); drawMode: DrawMode = Default): int =
  jpegDecodeOptions.x = x
  jpegDecodeOptions.y = y
  jpegDecodeOptions.w = w
  jpegDecodeOptions.h = h
  jpegDecodeOptions.progress = 0
  jpegDecodeOptions.lastY = 0
  jpegDecodeOptions.graphics = self.addr
  jpegDecodeOptions.drawMode = drawMode

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
    echo "- jpeg orientation: ", jpeg.getOrientation()

    jpegDecodeOptions.jpegW = jpeg.getWidth()
    jpegDecodeOptions.jpegH = jpeg.getHeight()

    case jpeg.getOrientation():
      of 6, 8: # vertical
        jpegDecodeOptions.w = h
        jpegDecodeOptions.h = w
      else: discard # horizontal

    # https://stackoverflow.com/questions/21961839/simulation-background-size-cover-in-canvas/45894506#45894506
    let contains = true
    let boxRatio = jpegDecodeOptions.w / jpegDecodeOptions.h
    let imgRatio = jpegDecodeOptions.jpegW / jpegDecodeOptions.jpegH
    if (if contains: imgRatio > boxRatio else: imgRatio <= boxRatio):
      jpegDecodeOptions.h = (jpegDecodeOptions.w.float / imgRatio).int
    else:
      jpegDecodeOptions.w = (jpegDecodeOptions.h.float * imgRatio).int

    case jpeg.getOrientation():
      of 6, 8: # vertical
        jpegDecodeOptions.x = ((w - jpegDecodeOptions.h).float * gravity.x).int + x
        jpegDecodeOptions.y = ((h - jpegDecodeOptions.w).float * gravity.y).int + y
      else: # horizontal
        jpegDecodeOptions.x = ((w - jpegDecodeOptions.w).float * gravity.x).int + x
        jpegDecodeOptions.y = ((h - jpegDecodeOptions.h).float * gravity.y).int + y

    var jpegScaleFactor = 0
    if jpegDecodeOptions.jpegW > jpegDecodeOptions.w * 8 and jpegDecodeOptions.jpegH > jpegDecodeOptions.h * 8:
      jpegScaleFactor = JPEG_SCALE_EIGHTH
      jpegDecodeOptions.jpegW = jpegDecodeOptions.jpegW div 8
      jpegDecodeOptions.jpegH = jpegDecodeOptions.jpegH div 8
    elif jpegDecodeOptions.jpegW > jpegDecodeOptions.w * 4 and jpegDecodeOptions.jpegH > jpegDecodeOptions.h * 4:
      jpegScaleFactor = JPEG_SCALE_QUARTER
      jpegDecodeOptions.jpegW = jpegDecodeOptions.jpegW div 4
      jpegDecodeOptions.jpegH = jpegDecodeOptions.jpegH div 4
    elif jpegDecodeOptions.jpegW > jpegDecodeOptions.w * 2 and jpegDecodeOptions.jpegH > jpegDecodeOptions.h * 2:
      jpegScaleFactor = JPEG_SCALE_HALF
      jpegDecodeOptions.jpegW = jpegDecodeOptions.jpegW div 2
      jpegDecodeOptions.jpegH = jpegDecodeOptions.jpegH div 2

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
    if jpegDecodeOptions.drawMode == ErrorDiffusion:
      processErrorMatrix(jpegDecodeOptions.lastY)
    errorMatrix.setLen(0)

  else:
    echo "- couldnt decode jpeg! error: ", jpeg.getLastError()
    return jpegErr

  return 1
