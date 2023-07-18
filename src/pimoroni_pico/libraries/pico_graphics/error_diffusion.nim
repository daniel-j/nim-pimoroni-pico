import ../pico_graphics
export pico_graphics
when not defined(mock):
  import ../../drivers/psram_display
  import ../../drivers/fatfs
  export psram_display
else:
  import ../../drivers/psram_display_mock
  export psram_display_mock

when defined(mock):
  type FIL* = File

type
  ErrorDiffusionBackend* = enum
    BackendMemory, BackendPsram, BackendFile

  ErrorDiffusionMatrix* = object
    s*: int # stride
    m*: seq[float32] # matrix

  ErrorDiffusion*[PGT: PicoGraphics] = object
    x*, y*: int
    width*, height*: int
    orientation*: int
    graphics*: ptr PGT
    matrix*: ErrorDiffusionMatrix
    case backend*: ErrorDiffusionBackend:
    of BackendMemory: fbMemory*: seq[RgbLinear]
    of BackendPsram: psramAddress*: PsramAddress
    of BackendFile:
      fbFile*: FIL

# Inspired by https://github.com/makew0rld/dither/blob/master/error_diffusers.go
func currentPixel(matrix: ErrorDiffusionMatrix): int =
  # The current pixel is assumed to be the right-most zero value in the top row.
  for i, m in matrix.m[0..<matrix.s]:
    if m != 0: return i - 1
  # The whole first line is zeros, which doesn't make sense
  # Just default to returning the middle of the row.
  return matrix.s div 2

func strength*(matrix: ErrorDiffusionMatrix; strength: float32): ErrorDiffusionMatrix =
  ## matrix.strength(x) modifies an existing error diffusion matrix so that it will
  ## be applied with the specified strength.
  ##
  ## strength is usually a value from 0 to 1.0, where 1.0 means 100% strength, and will
  ## not modify the matrix at all. It is inversely proportional to contrast - reducing the
  ## strength increases the contrast. It can be useful at values like 0.8 for reducing
  ## noise in the dithered image.
  if strength == 1.0: return matrix

  result.s = matrix.s
  result.m.setLen(matrix.m.len)
  for i, m in matrix.m:
    result.m[i] = m * strength

const
  Simple2D* = ErrorDiffusionMatrix(
    s: 2,
    m: @[
      0.0, 0.5,
      0.5, 0.0
    ]
  )

  FloydSteinberg* = ErrorDiffusionMatrix(
    s: 3,
    m: @[
      0.0,      0.0,      7.0 / 16,
      3.0 / 16, 5.0 / 16, 1.0 / 16
    ]
  )

  FalseFloydSteinberg* = ErrorDiffusionMatrix(
    s: 2,
    m: @[
      0.0,     3.0 / 8,
      3.0 / 8, 2.0 / 8
    ]
  )

  JarvisJudiceNinke* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      7.0 / 48, 5.0 / 48,
      3.0 / 48, 5.0 / 48, 7.0 / 48, 5.0 / 48, 3.0 / 48,
      1.0 / 48, 3.0 / 48, 5.0 / 48, 3.0 / 48, 1.0 / 48
    ]
  )

  Stucki* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      8.0 / 42, 4.0 / 42,
      2.0 / 42, 4.0 / 42, 8.0 / 42, 4.0 / 42, 2.0 / 42,
      1.0 / 42, 2.0 / 42, 4.0 / 42, 2.0 / 42, 1.0 / 42
    ]
  )

  Burkes* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      8.0 / 32, 4.0 / 32,
      2.0 / 32, 4.0 / 32, 8.0 / 32, 4.0 / 32, 2.0 / 32
    ]
  )

  Sierra* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      5.0 / 32, 3.0 / 32,
      2.0 / 32, 4.0 / 32, 5.0 / 32, 4.0 / 32, 2.0 / 32,
      0.0,      2.0 / 32, 3.0 / 32, 2.0 / 32, 0.0
    ]
  )

  TwoRowSierra* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      4.0 / 16, 3.0 / 16,
      1.0 / 16, 2.0 / 16, 3.0 / 16, 2.0 / 16, 1.0 / 16
    ]
  )

  SierraLite* = ErrorDiffusionMatrix(
    s: 3,
    m: @[
      0.0,     0.0,     2.0 / 4,
      1.0 / 4, 1.0 / 4, 0.0
    ]
  )

  Atkinson* = ErrorDiffusionMatrix(
    s: 4,
    m: @[
      0.0,     0.0,     1.0 / 8, 1.0 / 8,
      1.0 / 8, 1.0 / 8, 1.0 / 8, 0.0,
      0.0,     1.0 / 8, 0.0,     0.0
    ]
  )

  StevenPigeon* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0.0,      0.0,      0.0,      2.0 / 14, 1.0 / 14,
      0.0,      2.0 / 14, 2.0 / 14, 2.0 / 14, 0.0,
      1.0 / 14, 0.0,      1.0 / 14, 0.0,      1.0 / 14
    ]
  )

  ErrorDiffusionMatrices* = [
    Simple2D,
    FloydSteinberg, FalseFloydSteinberg,
    JarvisJudiceNinke, Stucki, Burkes,
    Sierra, TwoRowSierra, SierraLite,
    Atkinson, StevenPigeon
  ]

proc init*(self: var ErrorDiffusion; x, y, width, height: int; graphics: var PicoGraphics; matrix: ErrorDiffusionMatrix = FloydSteinberg) =
  echo "Initializing ErrorDiffusion with backend ", self.backend
  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.graphics = graphics.addr
  self.matrix = matrix
  case self.backend:
  of BackendMemory: self.fbMemory = newSeq[RgbLinear](self.width * self.height)
  of BackendPsram: discard
  of BackendFile:
    when not defined(mock):
      discard f_open(self.fbFile.addr, "/error_diffusion.bin", FA_CREATE_ALWAYS or FA_READ or FA_WRITE)
      discard f_expand(self.fbFile.addr, FSIZE_t self.width * self.height * sizeof(RgbLinear), 1)
    else:
      discard self.fbFile.open("error_diffusion.bin", fmReadWrite)

proc autobackend*(self: var ErrorDiffusion; graphics: var PicoGraphics) =
  when defined(mock):
    self.backend = ErrorDiffusionBackend.BackendMemory
    # can also be BackendFile in mock mode
  else:
    self.backend = if graphics.backend == PicoGraphicsBackend.BackendPsram:
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
      if f_tell(self.fbFile.addr) != self.rowToAddress(0, y):
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
      if f_tell(self.fbFile.addr) != self.rowToAddress(x, y):
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

  echo "Processing error matrix ", (imgW, imgH), " ", self.matrix

  let matrixRows = self.matrix.m.len div self.matrix.s
  let curPix = self.matrix.currentPixel()

  var rows = newSeq[seq[RgbLinear]](imgH)

  var lastProgress = -1

  for y in 0 ..< imgH:
    if y > 0:
      rows[y - 1] = @[] # destroy row

    for i in 0..<matrixRows:
      if y + i < imgH and rows[y + i].len == 0:
        rows[y + i] = self.readRow(y + i)

    for x in 0 ..< imgW:
      let pos = case self.orientation:
      of 3: Point(x: ox + imgW - (dx + x), y: oy + imgH - (dy + y))
      of 6: Point(x: ox + imgH - (dy + y), y: oy + (dx + x))
      of 8: Point(x: ox + (dy + y), y: oy + imgW - (dx + x))
      else: Point(x: ox + dx + x, y: oy + dy + y)

      let oldPixel = rows[y][x].clamp()

      # find closest color using distance function
      let color = self.graphics[].createPenNearest(oldPixel)
      self.graphics[].setPen(color)
      self.graphics[].setPixel(pos)

      let newPixel = self.graphics[].getPenColor(color)

      let quantError = oldPixel - newPixel

      for i, m in self.matrix.m:
        if m == 0: continue
        # Get the coords of the pixel the error is being applied to
        let mx = x + (i mod self.matrix.s) - curPix
        let my = y + (i div self.matrix.s)
        if mx < 0 or mx >= imgW or my < 0 or my >= imgH:
          continue
        rows[my][mx] += quantError * m

    let currentProgress = y * 100 div imgH
    if lastProgress != currentProgress:
      stdout.write($currentProgress & "%\r")
      stdout.flushFile()
      lastProgress = currentProgress
