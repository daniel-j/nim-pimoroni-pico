import ../pico_graphics
import ../jpegdec
when not defined(mock):
  import ../../drivers/fatfs

import ../pico_graphics/error_diffusion

var jpeg: JPEGDEC

type
  DrawMode* = enum
    Default, OrderedDither, ErrorDiffusion

  JpegDecoder*[PGT: PicoGraphics] = object
    x, y, w, h: int
    jpegW, jpegH: int
    progress: int
    lastY: int
    chunkHeight: int
    graphics: ptr PGT
    drawMode: DrawMode
    errDiff: ErrorDiffusion[PGT]

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

proc getJpegdecDrawCallback(jpegDecoder: var JpegDecoder): auto =
  return proc (draw: ptr JPEGDRAW): cint {.cdecl.} =
    let self = cast[ptr typeof(jpegDecoder)](draw.pUser)
    let p = cast[ptr UncheckedArray[uint16]](draw.pPixels)

    let imgW = self.w
    let imgH = self.h

    let dx = (draw.x * imgW div self.jpegW)
    let dy = (draw.y * imgH div self.jpegH)
    let dw = ((draw.x + draw.iWidth) * imgW div self.jpegW) - dx
    let dh = ((draw.y + draw.iHeight) * imgH div self.jpegH) - dy

    # if self.drawMode == ErrorDiffusion and false:
    #   if draw.x == 0 and draw.y == 0:
    #     # echo "Free heap before errorMatrix: ", getFreeHeap()
    #     echo draw[]
    #     self.chunkHeight = dh

    #     errorMatrix.setLen(self.chunkHeight + 1)

    #     for i in 0 .. self.chunkHeight:
    #       errorMatrix[i] = newSeq[RgbLinear](imgW)
    #     # echo "Free heap after errorMatrix alloc: ", getFreeHeap()

    #   if self.lastY != draw.y:
    #     processErrorMatrix(self.lastY)
    #     swap(errorMatrix[0], errorMatrix[self.chunkHeight])

    #     self.chunkHeight = dh
    #     errorMatrix.setLen(self.chunkHeight + 1)

    #     for i in 1 .. self.chunkHeight:
    #       errorMatrix[i] = newSeq[RgbLinear](imgW)

    #   self.lastY = draw.y

    let lastProgress = (self.progress * 100) div (imgW * imgH)

    var row: seq[RgbLinear]

    let realdw = min(dx + dw, imgW) - dx
    if self.drawMode == ErrorDiffusion:
      row = newSeq[RgbLinear](realdw)

    for y in 0 ..< dh:
      # if dy + y < 0 or dy + y >= imgH: continue
      let symin = y * self.jpegH div imgH
      if symin >= draw.iHeight: continue
      let symax = min((y + 1) * self.jpegH div imgH, draw.iHeight)

      for x in 0 ..< realdw:
        # if dx + x < 0 or dx + x >= imgW: continue
        let sxmin = x * self.jpegW div imgW
        if sxmin >= draw.iWidth: continue
        let sxmax = min((x + 1) * self.jpegW div imgW, draw.iWidth)

        let pos = case jpeg.getOrientation():
        of 3: Point(x: self.x + imgW - (dx + x), y: self.y + imgH - (dy + y))
        of 6: Point(x: self.x + imgH - (dy + y), y: self.y + (dx + x))
        of 8: Point(x: self.x + (dy + y), y: self.y + imgW - (dx + x))
        else: Point(x: self.x + dx + x, y: self.y + dy + y)

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

        color = color.level(black=0.00f, white=0.97f) #.saturate(1.00)

        case self.drawMode:
        of Default:
          let pen = self.graphics[].createPenNearest(color.toLinear())
          self.graphics[].setPen(pen)
          self.graphics[].setPixel(pos)
        of OrderedDither:
          color = color.saturate(1.50f) #.level(black=0.04, white=0.97)
          self.graphics[].setPixelDither(pos, color.toLinear())
        of ErrorDiffusion:
          color = color.saturate(1.30f).level(gamma=1.6f)
          # errorMatrix[y][dx + x] += color.toLinear()
          row[x] = color.toLinear()

        self.progress.inc()
      if self.drawMode == ErrorDiffusion:
        self.errDiff.write(dx, dy + y, row)

    let currentProgress = (self.progress * 100) div (imgW * imgH)
    if lastProgress != currentProgress:
      stdout.write($currentProgress & "%\r")
      stdout.flushFile()

    return 1

proc drawJpeg*(self: var JpegDecoder; graphics: var PicoGraphics; filename: string; x, y: int = 0; w, h: int; gravity: tuple[x, y: float32] = (0.0f, 0.0f); drawMode: DrawMode = Default; matrix: ErrorDiffusionMatrix = FloydSteinberg): int =
  self.x = x
  self.y = y
  self.w = w
  self.h = h
  self.progress = 0
  self.lastY = 0
  self.drawMode = drawMode
  self.graphics = graphics.addr

  echo "- opening jpeg file ", filename

  var jpegErr = jpeg.open(
    filename,
    jpegdecOpenCallback,
    jpegdecCloseCallback,
    jpegdecReadCallback,
    jpegdecSeekCallback,
    self.getJpegdecDrawCallback()
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
    let contains = true
    let boxRatio = self.w / self.h
    let imgRatio = self.jpegW / self.jpegH
    if (if contains: imgRatio > boxRatio else: imgRatio <= boxRatio):
      self.h = (self.w.float32 / imgRatio).int
    else:
      self.w = (self.h.float32 * imgRatio).int

    case jpeg.getOrientation():
      of 6, 8: # vertical
        self.x = ((w - self.h).float32 * gravity.x).int + x
        self.y = ((h - self.w).float32 * gravity.y).int + y
      else: # horizontal
        self.x = ((w - self.w).float32 * gravity.x).int + x
        self.y = ((h - self.h).float32 * gravity.y).int + y

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
    echo "- drawing jpeg at ", (self.x, self.y)
    echo "- drawing size ", (self.w, self.h)

    jpeg.setPixelType(RGB565_LITTLE_ENDIAN)

    if self.drawMode == ErrorDiffusion:
      self.errDiff.autobackend(graphics)
      self.errDiff.init(self.x, self.y, self.w, self.h, graphics, matrix)
      self.errDiff.orientation = jpeg.getOrientation()
      if self.errDiff.backend == ErrorDiffusionBackend.BackendPsram:
        self.errDiff.psramAddress = PsramAddress graphics.bounds.w * graphics.bounds.h

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
