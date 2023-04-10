import std/math
import ../pico_graphics
import ../jpegdec
when not defined(mock):
  import ../../drivers/fatfs

import ../pico_graphics/error_diffusion

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
    errDiff: ErrorDiffusion

var jpegDecodeOptions: JpegDecodeOptions

# var errorMatrix: seq[seq[RgbLinear]]

# proc processErrorMatrix(drawY: int) =
#   # echo "processing errorMatrix ", drawY
#   let imgW = jpegDecodeOptions.w
#   let imgH = jpegDecodeOptions.chunkHeight + 1

#   let graphics = jpegDecodeOptions.graphics

#   let ox = jpegDecodeOptions.x
#   let oy = jpegDecodeOptions.y
#   let dx = 0
#   let dy = drawY * jpegDecodeOptions.h div jpegDecodeOptions.jpegH

#   let jpegOrientation = jpeg.getOrientation()

#   for y in 0 ..< imgH - 1:
#     for x in 0 ..< imgW:
#       let pos = case jpegOrientation:
#       of 3: Point(x: ox + jpegDecodeOptions.w - (dx + x), y: oy + jpegDecodeOptions.h - (dy + y))
#       of 6: Point(x: ox + jpegDecodeOptions.h - (dy + y), y: oy + (dx + x))
#       of 8: Point(x: ox + (dy + y), y: oy + jpegDecodeOptions.w - (dx + x))
#       else: Point(x: ox + dx + x, y: oy + dy + y)

#       let oldPixel = errorMatrix[y][x].clamp()

#       # find closest color using distance function
#       let color = graphics[].createPenNearest(oldPixel)
#       graphics[].setPen(color)
#       graphics[].setPixel(pos)

#       let newPixel = graphics[].getPenColor(color)

#       let quantError = oldPixel - newPixel

#       if x + 1 < imgW:
#         errorMatrix[y][x + 1] += (quantError * 7) shr 4  # 7/16

#       if y + 1 < imgH:
#         if x > 0:
#           errorMatrix[y + 1][x - 1] += (quantError * 3) shr 4  # 3/16
#         errorMatrix[y + 1][x] += (quantError * 5) shr 4  # 5/16
#         if x + 1 < imgW:
#           errorMatrix[y + 1][x + 1] += (quantError) shr 4  # 1/16

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
    discard f_read(cast[ptr FIL](jpeg.fHandle), p, c.cuint, br.addr)
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

  let imgW = jpegDecodeOptions.w
  let imgH = jpegDecodeOptions.h

  let dx = (draw.x * imgW div jpegDecodeOptions.jpegW)
  let dy = (draw.y * imgH div jpegDecodeOptions.jpegH)
  let dw = ((draw.x + draw.iWidth) * imgW div jpegDecodeOptions.jpegW) - dx
  let dh = ((draw.y + draw.iHeight) * imgH div jpegDecodeOptions.jpegH) - dy

  # if jpegDecodeOptions.drawMode == ErrorDiffusion and false:
  #   if draw.x == 0 and draw.y == 0:
  #     # echo "Free heap before errorMatrix: ", getFreeHeap()
  #     echo draw[]
  #     jpegDecodeOptions.chunkHeight = dh

  #     errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

  #     for i in 0 .. jpegDecodeOptions.chunkHeight:
  #       errorMatrix[i] = newSeq[RgbLinear](imgW)
  #     # echo "Free heap after errorMatrix alloc: ", getFreeHeap()

  #   if jpegDecodeOptions.lastY != draw.y:
  #     processErrorMatrix(jpegDecodeOptions.lastY)
  #     swap(errorMatrix[0], errorMatrix[jpegDecodeOptions.chunkHeight])

  #     jpegDecodeOptions.chunkHeight = dh
  #     errorMatrix.setLen(jpegDecodeOptions.chunkHeight + 1)

  #     for i in 1 .. jpegDecodeOptions.chunkHeight:
  #       errorMatrix[i] = newSeq[RgbLinear](imgW)

  #   jpegDecodeOptions.lastY = draw.y

  let lastProgress = (jpegDecodeOptions.progress * 100) div (imgW * imgH)

  var row: seq[RgbLinear]

  let realdw = min(dx + dw, imgW) - dx
  if jpegDecodeOptions.drawMode == ErrorDiffusion:
    row = newSeq[RgbLinear](realdw)

  for y in 0 ..< dh:
    # if dy + y < 0 or dy + y >= imgH: continue
    let symin = floor(y * jpegDecodeOptions.jpegH / imgH).int
    if symin >= draw.iHeight: continue
    let symax = min(floor((y + 1) * jpegDecodeOptions.jpegH / imgH).int, draw.iHeight)

    for x in 0 ..< realdw:
      # if dx + x < 0 or dx + x >= imgW: continue
      let sxmin = floor(x * jpegDecodeOptions.jpegW / imgW).int
      if sxmin >= draw.iWidth: continue
      let sxmax = min(floor((x + 1) * jpegDecodeOptions.jpegW / imgW).int, draw.iWidth)

      let pos = case jpeg.getOrientation():
      of 3: Point(x: jpegDecodeOptions.x + imgW - (dx + x), y: jpegDecodeOptions.y + imgH - (dy + y))
      of 6: Point(x: jpegDecodeOptions.x + imgH - (dy + y), y: jpegDecodeOptions.y + (dx + x))
      of 8: Point(x: jpegDecodeOptions.x + (dy + y), y: jpegDecodeOptions.y + imgW - (dx + x))
      else: Point(x: jpegDecodeOptions.x + dx + x, y: jpegDecodeOptions.y + dy + y)

      var color = Rgb()

      # linear interpolation
      # var colorv = RgbLinear()
      # var divider: RgbLinearComponent = 0
      # for sx in sxmin..<sxmax:
      #   for sy in symin..<symax:
      #     colorv += constructRgb(Rgb565(p[sx + sy * draw.iWidth])).toLinear()
      #     inc(divider)
      # if divider > 0:
      #   color = (colorv div divider).fromLinear()
      # else:
      #   # fallback
      #   color = constructRgb(Rgb565(p[sxmin + symin * draw.iWidth]))
      color = constructRgb(Rgb565(p[sxmin + symin * draw.iWidth]))

      color = color.level(black=0.00, white=0.97) #.saturate(1.00)

      case jpegDecodeOptions.drawMode:
      of Default:
        let pen = graphics[].createPenNearest(color.toLinear())
        graphics[].setPen(pen)
        graphics[].setPixel(pos)
      of OrderedDither:
        color = color.saturate(1.30) #.level(black=0.04, white=0.97)
        graphics[].setPixelDither(pos, color.toLinear())
      of ErrorDiffusion:
        color = color.saturate(1.30).level(gamma=1.5)
        # errorMatrix[y][dx + x] += color.toLinear()
        row[x] = color.toLinear()

      jpegDecodeOptions.progress.inc()
    if jpegDecodeOptions.drawMode == ErrorDiffusion:
     jpegDecodeOptions.errDiff.write(dx, dy + y, row)

  let currentProgress = (jpegDecodeOptions.progress * 100) div (imgW * imgH)
  if lastProgress != currentProgress:
    stdout.write($currentProgress & "%\r")
    stdout.flushFile()

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

    if jpegDecodeOptions.drawMode == ErrorDiffusion:
      jpegDecodeOptions.errDiff.autobackend(self.addr)
      jpegDecodeOptions.errDiff.init(jpegDecodeOptions.x, jpegDecodeOptions.y, jpegDecodeOptions.w, jpegDecodeOptions.h, self.addr)
      jpegDecodeOptions.errDiff.orientation = jpeg.getOrientation()
      if jpegDecodeOptions.errDiff.backend == ErrorDiffusionBackend.BackendPsram:
        jpegDecodeOptions.errDiff.psramAddress = PsramAddress self.bounds.w * self.bounds.h

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
      jpegDecodeOptions.errDiff.process()
      jpegDecodeOptions.errDiff.deinit()
    
    # if jpegDecodeOptions.drawMode == ErrorDiffusion and false:
    #   processErrorMatrix(jpegDecodeOptions.lastY)
    # errorMatrix.setLen(0)

  else:
    echo "- couldnt decode jpeg! error: ", jpeg.getLastError()
    return jpegErr

  return 1
