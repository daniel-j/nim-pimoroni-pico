import ../pico_graphics
import ../jpegdec
when not defined(mock):
  import ../../drivers/fatfs

import ../pico_graphics/error_diffusion

var jpeg: JPEGDEC

type
  DrawMode* = enum
    Default, OrderedDither, ErrorDiffusion

  JpegColorModifier* = proc (color: var Rgb)

  JpegDecoder*[PGT: PicoGraphics] = object
    coords: Point
    w, h: int
    drawArea: Rect
    cropArea: Rect
    jpegW, jpegH: int
    progress: int
    lastY: int
    chunkHeight: int
    graphics: ptr PGT
    drawMode: DrawMode
    errDiff*: ErrorDiffusion[PGT]
    errDiffRow: seq[RgbLinear]
    colorModifier*: JpegColorModifier

proc jpegdecOpenCallback(filename: cstring, size: ptr int32): pointer {.cdecl.} =
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

proc jpegdecCloseCallback(handle: pointer) {.cdecl.} =
  when not defined(mock):
    discard f_close(cast[ptr FIL](handle))
    dealloc(cast[ptr FIL](handle))
  else:
    let file = cast[ref File](handle)
    file[].close()
    GC_unref(file)

proc jpegdecReadCallback(jpeg: ptr JPEGFILE; p: ptr uint8, c: int32): int32 {.cdecl.} =
  when not defined(mock):
    var br: cuint
    discard f_read(cast[ptr FIL](jpeg.fHandle), p, c.cuint, br.addr)
    return br.int32
  else:
    let file = cast[ref File](jpeg.fHandle)
    return file[].readBuffer(p, c).int32

proc jpegdecSeekCallback(jpeg: ptr JPEGFILE, p: int32): int32 {.cdecl.} =
  when not defined(mock):
    (f_lseek(cast[ptr FIL](jpeg.fHandle), p.FSIZE_t) == FR_OK).int32
  else:
    let file = cast[ref File](jpeg.fHandle)
    file[].setFilePos(p)
    return 1

proc drawScaled(self: var JpegDecoder; draw: ptr JPEGDRAW): int =
  let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)

  let dx = (draw.x * self.w div self.jpegW)
  let dy = (draw.y * self.h div self.jpegH)
  let dw = ((draw.x + draw.iWidth) * self.w div self.jpegW) - dx
  let dh = ((draw.y + draw.iHeight) * self.h div self.jpegH) - dy
  let startx = max(self.cropArea.x - dx, 0)
  let starty = max(self.cropArea.y - dy, 0)
  let realdw = min(dx + dw, self.cropArea.w + self.cropArea.x) - dx
  let realdh = min(dy + dh, self.cropArea.h + self.cropArea.y) - dy

  # echo (dw, realdw), (dh, realdh)

  let lastProgress = (self.progress * 100) div (self.drawArea.area())

  if self.drawMode == ErrorDiffusion and dw > self.errDiffRow.len:
    self.errDiffRow.setLen(dw + 1)

  var pos = Point()

  for y in starty ..< realdh:
    let symin = y * self.jpegH div self.h
    # if symin >= draw.iHeight: continue

    case jpeg.getOrientation():
    of 3: pos.y = self.coords.y + self.h - 1 - (dy + y)
    of 6: pos.x = self.coords.x + self.h - 1 - (dy + y)
    of 8: pos.x = self.coords.x + (dy + y)
    else: pos.y = self.coords.y + dy + y

    let poffset = symin * draw.iWidth

    for x in startx ..< realdw:
      let sxmin = x * self.jpegW div self.w
      # if sxmin >= draw.iWidth: continue

      var color = constructRgb(Rgb565(p[poffset + sxmin]))
      # color = color.getCacheKey().getCacheColor()

      case jpeg.getOrientation():
      of 3: pos.x = self.coords.x + self.w - 1 - (dx + x)
      of 6: pos.y = self.coords.y + (dx + x)
      of 8: pos.y = self.coords.y + self.w - 1 - (dx + x)
      else: pos.x = self.coords.x + dx + x

      # if not self.drawArea.contains(pos):
      #   self.graphics[].setPen(7)
      #   self.graphics[].setPixel(pos)
      #   continue

      if not self.colorModifier.isNil:
        self.colorModifier(color)

      case self.drawMode:
      of Default:
        let pen = self.graphics[].createPenNearest(color.toLinear())
        self.graphics[].setPen(pen)
        self.graphics[].setPixel(pos)
      of OrderedDither:
        self.graphics[].setPixelDither(pos, color.toLinear())
      of ErrorDiffusion:
        self.errDiffRow[x] = color.toLinear()

      self.progress.inc()

    if self.drawMode == ErrorDiffusion and realdw > 0 and startx < realdw:
      # echo (dx + startx - self.cropArea.x, dy + y - self.cropArea.y, startx, self.errDiffRow.len, realdw, dw)
      self.errDiff.write(dx + startx - self.cropArea.x, dy + y - self.cropArea.y, self.errDiffRow[startx ..< realdw])

  let currentProgress = (self.progress * 100) div (self.drawArea.area())
  if lastProgress != currentProgress:
    stdout.write($currentProgress & "%\r")
    stdout.flushFile()

  return 1

proc drawFast(self: var JpegDecoder; draw: ptr JPEGDRAW): int =
  let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)
  let lastProgress = (self.progress * 100) div (self.jpegW * self.jpegH)

  for y in 0 ..< draw.iHeight:
    for x in 0 ..< draw.iWidth:
      if x >= draw.iWidthUsed: break  # Clip to the used width
      let i = y * draw.iWidth + x
      if draw.iBpp == 16:
        var color = constructRgb(Rgb565(p[i]))
        let pos = Point(x: draw.x + x, y: draw.y + y)
        case self.drawMode:
        of Default:
          let pen = self.graphics[].createPenNearest(color.toLinear())
          self.graphics[].setPen(pen)
          self.graphics[].setPixel(pos)
        of OrderedDither:
          self.graphics[].setPixelDither(pos, color.toLinear())
        of ErrorDiffusion:
          discard
      self.progress.inc()

  let currentProgress = (self.progress * 100) div (self.jpegW * self.jpegH)
  if lastProgress != currentProgress:
    stdout.write($currentProgress & "%\r")
    stdout.flushFile()

  return 1

proc jpegdecDrawCallback[T](draw: ptr JPEGDRAW): cint {.cdecl.} =
  return cast[ptr T](draw.pUser)[].drawScaled(draw).cint


proc init*(self: var JpegDecoder; graphics: var PicoGraphics) =
  self.graphics = graphics.addr
  self.errDiff = typeof(self.errDiff)(backend: autobackend(graphics))

proc drawJpeg*(self: var JpegDecoder; filename: string; x, y, w, h: int; gravity: tuple[x, y: float32] = (0.0f, 0.0f); contains: bool = true; drawMode: DrawMode = Default): int =
  if self.graphics.isNil:
    return 0

  self.coords.x = x
  self.coords.y = y
  self.w = w
  self.h = h
  self.progress = 0
  self.lastY = 0
  self.drawMode = drawMode

  echo "- opening jpeg file ", filename

  var jpegErr = jpeg.open(
    filename,
    jpegdecOpenCallback,
    jpegdecCloseCallback,
    jpegdecReadCallback,
    jpegdecSeekCallback,
    jpegdecDrawCallback[typeof(self)]
  )
  jpeg.setUserPointer(self.addr)

  if jpegErr == 1:
    echo "- jpeg dimensions: ", jpeg.getWidth(), "x", jpeg.getHeight()
    echo "- jpeg orientation: ", jpeg.getOrientation()

    self.jpegW = jpeg.getWidth()
    self.jpegH = jpeg.getHeight()

    case jpeg.getOrientation():
      of 6, 8: # vertical
        self.w = h
        self.h = w
      else: discard # horizontal

    # https://stackoverflow.com/questions/21961839/simulation-background-size-cover-in-canvas/45894506#45894506
    let boxRatio = self.w / self.h
    let imgRatio = self.jpegW / self.jpegH
    if (if contains: imgRatio > boxRatio else: imgRatio <= boxRatio):
      self.h = (self.w.float32 / imgRatio).int
    else:
      self.w = (self.h.float32 * imgRatio).int

    case jpeg.getOrientation():
      of 6, 8: # vertical
        self.coords.x = ((w - self.h).float32 * gravity.x).int + x
        self.coords.y = ((h - self.w).float32 * gravity.y).int + y
        self.drawArea.w = self.h
        self.drawArea.h = self.w
      else: # horizontal
        self.coords.x = ((w - self.w).float32 * gravity.x).int + x
        self.coords.y = ((h - self.h).float32 * gravity.y).int + y
        self.drawArea.w = self.w
        self.drawArea.h = self.h

    self.drawArea.x = self.coords.x
    self.drawArea.y = self.coords.y

    var jpegScaleFactor = 0
    if self.jpegW > self.w * 8 and self.jpegH > self.h * 8:
      jpegScaleFactor = JPEG_SCALE_EIGHTH
      self.jpegW = self.jpegW div 8
      self.jpegH = self.jpegH div 8
    elif self.jpegW > self.w * 4 and self.jpegH > self.h * 4:
      jpegScaleFactor = JPEG_SCALE_QUARTER
      self.jpegW = self.jpegW div 4
      self.jpegH = self.jpegH div 4
    elif self.jpegW > self.w * 2 and self.jpegH > self.h * 2:
      jpegScaleFactor = JPEG_SCALE_HALF
      self.jpegW = self.jpegW div 2
      self.jpegH = self.jpegH div 2

    echo "- jpeg scale factor: ", jpegScaleFactor
    echo "- jpeg scaled dimensions: ", self.jpegW, "x", self.jpegH
    echo "- drawing jpeg at ", (self.coords.x, self.coords.y)
    echo "- drawing size ", (self.w, self.h)

    self.drawArea = self.graphics[].bounds.intersection(self.graphics[].clip.intersection(self.drawArea))

    self.cropArea = case jpeg.getOrientation():
      of 3: constructRect(self.w - self.drawArea.w - self.drawArea.x + self.coords.x, self.h - self.drawArea.h - self.drawArea.y + self.coords.y, self.drawArea.w, self.drawArea.h)
      of 6: constructRect(self.drawArea.y - self.coords.y, self.drawArea.x - self.coords.x, self.drawArea.h, self.drawArea.w)
      of 8: constructRect(self.w - self.drawArea.h - self.drawArea.y + self.coords.y, self.drawArea.x - self.coords.x, self.drawArea.h, self.drawArea.w)
      else: constructRect(self.drawArea.x - self.coords.x, self.drawArea.y - self.coords.y, self.drawArea.w, self.drawArea.h)

    echo (self.drawArea, self.cropArea)

    jpeg.setPixelType(RGB565_LITTLE_ENDIAN)

    if self.drawMode == ErrorDiffusion:
      self.errDiff.init(self.graphics[], self.drawArea.x, self.drawArea.y, self.cropArea.w, self.cropArea.h, self.errDiff.matrix)
      self.errDiff.orientation = jpeg.getOrientation()
      if self.errDiff.backend == ErrorDiffusionBackend.BackendPsram:
        self.errDiff.psramAddress = PsramAddress self.graphics.bounds.w * self.graphics.bounds.h

    echo "- starting jpeg decode.."
    try:
      jpegErr = jpeg.decode(0, 0, jpegScaleFactor.cint)
    except CatchableError:
      echo "error: ", system.getCurrentException().msg, system.getCurrentException().getStackTrace()
      echo jpeg.getLastError()
      jpegErr = 0
    finally:
      self.errDiffRow.reset()
    if jpegErr != 1:
      echo "- jpeg decoding error: ", jpeg.getLastError()
      return jpegErr

    jpeg.close()
    if self.drawMode == ErrorDiffusion:
      self.errDiff.process()
      self.errDiff.deinit()

    # if self.drawMode == ErrorDiffusion and false:
    #   processErrorMatrix(self.lastY)
    # errorMatrix.setLen(0)

  else:
    echo "- couldnt decode jpeg! error: ", jpeg.getLastError()
    return jpegErr

  return 1
