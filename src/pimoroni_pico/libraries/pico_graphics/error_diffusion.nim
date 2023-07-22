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
    s*: int # stride/width
    m*: seq[RgbLinearComponent] # matrix
    d*: RgbLinearComponent # divider

  ErrorDiffusion*[PGT: PicoGraphics] = object
    x*, y*, width*, height*: int
    orientation*: int
    graphics*: ptr PGT
    matrix*: ErrorDiffusionMatrix
    alternateRow*: bool
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

const
  Simple2D* = ErrorDiffusionMatrix(
    s: 2,
    m: @[
      0, 1,
      1, 0
    ],
    d: 2
  )

  JarvisJudiceNinke* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 7, 5,
      3, 5, 7, 5, 3,
      1, 3, 5, 3, 1
    ],
    d: 48
  )

  Stucki* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 8, 4,
      2, 4, 8, 4, 2,
      1, 2, 4, 2, 1
    ],
    d: 42
  )

  Burkes* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 8, 4,
      2, 4, 8, 4, 2
    ],
    d: 32
  )

  Sierra* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 5, 3,
      2, 4, 5, 4, 2,
      0, 2, 3, 2, 0
    ],
    d: 32
  )

  TwoRowSierra* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 4, 3,
      1, 2, 3, 2, 1
    ],
    d: 16
  )

  SierraLite* = ErrorDiffusionMatrix(
    s: 3,
    m: @[
      0, 0, 2,
      1, 1, 0
    ],
    d: 4
  )

  FloydSteinberg* = ErrorDiffusionMatrix(
    s: 3,
    m: @[
      0, 0, 7,
      3, 5, 1
    ],
    d: 16
  )

  FalseFloydSteinberg* = ErrorDiffusionMatrix(
    s: 2,
    m: @[
      0, 3,
      3, 2
    ],
    d: 8
  )

  Atkinson* = ErrorDiffusionMatrix(
    s: 4,
    m: @[
      0, 0, 1, 1,
      1, 1, 1, 0,
      0, 1, 0, 0
    ],
    d: 8
  )

  StevenPigeon* = ErrorDiffusionMatrix(
    s: 5,
    m: @[
      0, 0, 0, 2, 1,
      0, 2, 2, 2, 0,
      1, 0, 1, 0, 1
    ],
    d: 14
  )

  ErrorDiffusionMatrices* = [
    Simple2D,
    JarvisJudiceNinke, Stucki, Burkes,
    Sierra, TwoRowSierra, SierraLite,
    FloydSteinberg, FalseFloydSteinberg,
    Atkinson, StevenPigeon
  ]

proc init*(self: var ErrorDiffusion; graphics: var PicoGraphics; x, y, width, height: int; matrix: ErrorDiffusionMatrix = FloydSteinberg; alternateRow: bool = false) =
  echo "Initializing ErrorDiffusion with backend ", self.backend
  self.graphics = graphics.addr
  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.matrix = matrix
  self.alternateRow = alternateRow

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

proc write*(self: var ErrorDiffusion; x, y: int; rgb: openArray[RgbLinear]; length: int = -1) =
  # echo "writing ", (x, y), " ", rgb.len, " ", rgb[0]
  let length = if length < 0: rgb.len else: min(rgb.len, length)
  case self.backend:
  of BackendMemory:
    let pos = self.rowToAddress(x, y, stride = 1)
    copyMem(self.fbMemory[pos].addr, rgb[0].unsafeAddr, sizeof(RgbLinear) * length)
  of BackendPsram:
    self.graphics[].fbPsram.write(self.rowToAddress(x, y, self.psramAddress), uint sizeof(RgbLinear) * length, cast[ptr uint8](rgb[0].unsafeAddr))
  of BackendFile:
    when not defined(mock):
      if f_tell(self.fbFile.addr) != self.rowToAddress(x, y):
        discard f_lseek(self.fbFile.addr, FSIZE_t self.rowToAddress(x, y))
      var bw: cuint
      discard f_write(self.fbFile.addr, rgb[0].unsafeAddr, cuint sizeof(RgbLinear) * length, bw.addr)
    else:
      self.fbFile.setFilePos(self.rowToAddress(x, y).int)
      discard self.fbFile.writeBuffer(rgb[0].unsafeAddr, sizeof(RgbLinear) * length)

proc rowPos(y, rowCount: int): int {.inline.} = y mod rowCount

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

  var rows = newSeq[seq[RgbLinear]](matrixRows)

  var lastProgress = -1

  for y in 0 ..< imgH:
    if y > 0:
      rows[rowPos(y - 1, matrixRows)].setLen(0)

    for i in 0..<matrixRows:
      let ry = rowPos(y + i, matrixRows)
      if y + i < imgH and rows[ry].len == 0:
        rows[ry] = self.readRow(y + i)

    for xraw in 0 ..< imgW:
      let x = if self.alternateRow and y mod 2 == 0: xraw else: imgW - 1 - xraw
      let pos = case self.orientation:
      of 3: Point(x: ox + imgW - 1 - (dx + x), y: oy + imgH - 1 - (dy + y))
      of 6: Point(x: ox + imgH - 1 - (dy + y), y: oy + (dx + x))
      of 8: Point(x: ox + (dy + y), y: oy + imgW - 1 - (dx + x))
      else: Point(x: ox + dx + x, y: oy + dy + y)

      let oldPixel = rows[rowPos(y, matrixRows)][x].clamp()

      # find closest color using distance function
      let color = self.graphics[].createPenNearest(oldPixel)
      # self.graphics[].setPixelImpl(pos, color)
      self.graphics[].setPen(color)
      self.graphics[].setPixel(pos)

      let newPixel = self.graphics[].getPenColor(color)

      let quantError = oldPixel - newPixel

      for i, m in self.matrix.m:
        if m == 0: continue
        # Get the coords of the pixel the error is being applied to
        let mx = if self.alternateRow and y mod 2 == 0: x + (i mod self.matrix.s) - curPix else: x - (i mod self.matrix.s) + curPix
        let my = y + (i div self.matrix.s)
        if mx < 0 or mx >= imgW or my < 0 or my >= imgH:
          continue
        rows[rowPos(my, matrixRows)][mx] += (quantError * m) div self.matrix.d

    let currentProgress = y * 100 div imgH
    if lastProgress != currentProgress:
      stdout.write($currentProgress & "%\r")
      stdout.flushFile()
      lastProgress = currentProgress
