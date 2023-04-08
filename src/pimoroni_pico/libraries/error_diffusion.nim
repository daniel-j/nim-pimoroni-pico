import ./pico_graphics
when not defined(mock):
  import ../drivers/psram_display
  import ../drivers/fatfs
  export psram_display
else:
  import ../drivers/psram_display_mock
  export psram_display_mock

type
  ErrorDiffusionBackend* = enum
    BackendMemory, BackendPsram, BackendFile

  ErrorDiffusion* = object
    x*, y*: int
    width*, height*: int
    orientation*: int
    graphics*: ptr PicoGraphics
    case backend*: ErrorDiffusionBackend:
    of BackendMemory: fbMemory*: seq[RgbLinear]
    of BackendPsram: psramAddress*: PsramAddress
    of BackendFile:
      when not defined(mock):
        fbFile*: FIL
      else:
        fbFile*: File

proc init*(self: var ErrorDiffusion; x, y, width, height: int; graphics: ptr PicoGraphics) =
  echo "Initializing ErrorDiffusion with backend ", self.backend
  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.graphics = graphics
  case self.backend:
  of BackendMemory: self.fbMemory = newSeq[RgbLinear](self.width * self.height)
  of BackendPsram: discard
  of BackendFile:
    when not defined(mock):
      discard f_open(self.fbFile.addr, "/error_diffusion.bin", FA_CREATE_ALWAYS or FA_READ or FA_WRITE)
      discard f_expand(self.fbFile.addr, FSIZE_t self.width * self.height * sizeof(RgbLinear), 1)
    else:
      discard self.fbFile.open("error_diffusion.bin", fmReadWrite)

proc autobackend*(self: var ErrorDiffusion) =
  when defined(mock):
    self.backend = ErrorDiffusionBackend.BackendMemory
    # can also be BackendFile in mock mode
  else:
    self.backend = if self.graphics.backend == PicoGraphicsBackend.BackendPsram:
      ErrorDiffusionBackend.BackendPsram
    else:
      ErrorDiffusionBackend.BackendFile

proc deinit*(self: var ErrorDiffusion) =
  case self.backend:
  of BackendMemory: self.fbMemory = @[]
  of BackendPsram: discard
  of BackendFile:
    when not defined(mock):
      discard f_close(self.fbFile.addr)
    else:
      self.fbFile.close()

proc rowToAddress(self: ErrorDiffusion; x, y: int; offset: uint32 = 0; stride: uint32 = sizeof(RgbLinear).uint32): PsramAddress =
  return offset + ((y.uint32 * self.width.uint32) + x.uint32) * stride

proc readRow*(self: var ErrorDiffusion; y: int): seq[RgbLinear] =
  case self.backend:
  of BackendMemory:
    let pos1 = self.rowToAddress(0, y, stride = 1)
    let pos2 = self.rowToAddress(0, y + 1, stride = 1) - 1
    return self.fbMemory[pos1 .. pos2]
  of BackendPsram:
    var rgb = newSeq[RgbLinear](self.width)
    self.graphics[].fbPsram.read(self.rowToAddress(0, y, offset = self.psramAddress), cuint sizeof(RgbLinear) * self.width, cast[ptr uint8](rgb[0].addr))
    return rgb
  of BackendFile:
    var rgb = newSeq[RgbLinear](self.width)
    when not defined(mock):
      discard f_lseek(self.fbFile.addr, FSIZE_t self.rowToAddress(0, y))
      var br: cuint
      discard f_read(self.fbFile.addr, rgb[0].addr, cuint sizeof(RgbLinear) * self.width, br.addr)
    else:
      self.fbFile.setFilePos(self.rowToAddress(0, y).int)
      discard self.fbFile.readBuffer(rgb[0].addr, sizeof(RgbLinear) * self.width)
    return rgb

proc write*(self: var ErrorDiffusion; x, y: int; rgb: seq[RgbLinear]) =
  # echo "writing ", (x, y), " ", rgb.len, " ", rgb[0]
  case self.backend:
  of BackendMemory:
    let pos = self.rowToAddress(x, y, stride = 1)
    copyMem(self.fbMemory[pos].addr, rgb[0].unsafeAddr, sizeof(RgbLinear) * rgb.len)
  of BackendPsram:
    self.graphics[].fbPsram.write(self.rowToAddress(x, y, self.psramAddress), uint sizeof(RgbLinear) * rgb.len, cast[ptr uint8](rgb[0].unsafeAddr))
  of BackendFile:
    when not defined(mock):
      discard f_lseek(self.fbFile.addr, FSIZE_t self.rowToAddress(x, y))
      var bw: cuint
      discard f_write(self.fbFile.addr, rgb[0].unsafeAddr, cuint sizeof(RgbLinear) * rgb.len, bw.addr)
    else:
      self.fbFile.setFilePos(self.rowToAddress(x, y).int)
      discard self.fbFile.writeBuffer(rgb[0].unsafeAddr, sizeof(RgbLinear) * rgb.len)

proc process*(self: var ErrorDiffusion) =
  # echo "processing errorMatrix ", drawY
  let imgW = self.width
  let imgH = self.height

  let ox = self.x
  let oy = self.y
  let dx = 0
  let dy = 0 # drawY * jpegDecodeOptions.h div jpegDecodeOptions.jpegH

  echo "Processing error matrix ", (imgW, imgH)

  var rowCurrent: seq[RgbLinear]
  var rowNext: seq[RgbLinear]

  var lastProgress = -1

  for y in 0 ..< imgH:
    if y == 0:
      rowCurrent = self.readRow(y)
    else:
      swap(rowCurrent, rowNext)
    if y < imgH - 1:
      rowNext = self.readRow(y + 1)
    for x in 0 ..< imgW:
      let pos = case self.orientation:
      of 3: Point(x: ox + imgW - (dx + x), y: oy + imgH - (dy + y))
      of 6: Point(x: ox + imgH - (dy + y), y: oy + (dx + x))
      of 8: Point(x: ox + (dy + y), y: oy + imgW - (dx + x))
      else: Point(x: ox + dx + x, y: oy + dy + y)

      let oldPixel = rowCurrent[x].clamp()

      # find closest color using distance function
      let color = self.graphics[].createPenNearest(oldPixel)
      self.graphics[].setPen(color)
      self.graphics[].setPixel(pos)

      let newPixel = self.graphics[].getPenColor(color)

      let quantError = oldPixel - newPixel

      if x + 1 < imgW:
        rowCurrent[x + 1] += (quantError * 7) shr 4  # 7/16

      if y + 1 < imgH:
        if x > 0:
          rowNext[x - 1] += (quantError * 3) shr 4  # 3/16
        rowNext[x] += (quantError * 5) shr 4  # 5/16
        if x + 1 < imgW:
          rowNext[x + 1] += (quantError) shr 4  # 1/16

    # self.write(0, y, rowCurrent)
    # if y == imgH - 1:
    #   self.write(0, imgH - 1, rowNext)

    let currentProgress = y * 100 div imgH
    if lastProgress != currentProgress:
      stdout.write($currentProgress & "%\r")
      stdout.flushFile()
      lastProgress = currentProgress
