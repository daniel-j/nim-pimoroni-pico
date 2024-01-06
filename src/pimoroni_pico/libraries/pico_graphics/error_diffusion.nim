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
    hybridDither*: bool
    variableDither*: bool
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

type
  ThreeCoefs {.packed.} = tuple
    r: int16      # right
    dl: int16     # down-left
    d: int16      # down
    sum: int16    # sum

const coefsArr: array[256, ThreeCoefs] = [
  (  13,     0,     5,    18),     #    0
  (  13,     0,     5,    18),     #    1
  (  21,     0,    10,    31),     #    2
  (   7,     0,     4,    11),     #    3
  (   8,     0,     5,    13),     #    4
  (  47,     3,    28,    78),     #    5
  (  23,     3,    13,    39),     #    6
  (  15,     3,     8,    26),     #    7
  (  22,     6,    11,    39),     #    8
  (  43,    15,    20,    78),     #    9
  (   7,     3,     3,    13),     #   10
  ( 501,   224,   211,   936),     #   11
  ( 249,   116,   103,   468),     #   12
  ( 165,    80,    67,   312),     #   13
  ( 123,    62,    49,   234),     #   14
  ( 489,   256,   191,   936),     #   15
  (  81,    44,    31,   156),     #   16
  ( 483,   272,   181,   936),     #   17
  (  60,    35,    22,   117),     #   18
  (  53,    32,    19,   104),     #   19
  ( 237,   148,    83,   468),     #   20
  ( 471,   304,   161,   936),     #   21
  (   3,     2,     1,     6),     #   22
  ( 459,   304,   161,   924),     #   23
  (  38,    25,    14,    77),     #   24
  ( 453,   296,   175,   924),     #   25
  ( 225,   146,    91,   462),     #   26
  ( 149,    96,    63,   308),     #   27
  ( 111,    71,    49,   231),     #   28
  (  63,    40,    29,   132),     #   29
  (  73,    46,    35,   154),     #   30
  ( 435,   272,   217,   924),     #   31
  ( 108,    67,    56,   231),     #   32
  (  13,     8,     7,    28),     #   33
  ( 213,   130,   119,   462),     #   34
  ( 423,   256,   245,   924),     #   35
  (   5,     3,     3,    11),     #   36
  ( 281,   173,   162,   616),     #   37
  ( 141,    89,    78,   308),     #   38
  ( 283,   183,   150,   616),     #   39
  (  71,    47,    36,   154),     #   40
  ( 285,   193,   138,   616),     #   41
  (  13,     9,     6,    28),     #   42
  (  41,    29,    18,    88),     #   43
  (  36,    26,    15,    77),     #   44
  ( 289,   213,   114,   616),     #   45
  ( 145,   109,    54,   308),     #   46
  ( 291,   223,   102,   616),     #   47
  (  73,    57,    24,   154),     #   48
  ( 293,   233,    90,   616),     #   49
  (  21,    17,     6,    44),     #   50
  ( 295,   243,    78,   616),     #   51
  (  37,    31,     9,    77),     #   52
  (  27,    23,     6,    56),     #   53
  ( 149,   129,    30,   308),     #   54
  ( 299,   263,    54,   616),     #   55
  (  75,    67,    12,   154),     #   56
  (  43,    39,     6,    88),     #   57
  ( 151,   139,    18,   308),     #   58
  ( 303,   283,    30,   616),     #   59
  (  38,    36,     3,    77),     #   60
  ( 305,   293,    18,   616),     #   61
  ( 153,   149,     6,   308),     #   62
  ( 307,   303,     6,   616),     #   63
  (   1,     1,     0,     2),     #   64
  ( 101,   105,     2,   208),     #   65
  (  49,    53,     2,   104),     #   66
  (  95,   107,     6,   208),     #   67
  (  23,    27,     2,    52),     #   68
  (  89,   109,    10,   208),     #   69
  (  43,    55,     6,   104),     #   70
  (  83,   111,    14,   208),     #   71
  (   5,     7,     1,    13),     #   72
  ( 172,   181,    37,   390),     #   73
  (  97,    76,    22,   195),     #   74
  (  72,    41,    17,   130),     #   75
  ( 119,    47,    29,   195),     #   76
  (   4,     1,     1,     6),     #   77
  (   4,     1,     1,     6),     #   78
  (   4,     1,     1,     6),     #   79
  (   4,     1,     1,     6),     #   80
  (   4,     1,     1,     6),     #   81
  (   4,     1,     1,     6),     #   82
  (   4,     1,     1,     6),     #   83
  (   4,     1,     1,     6),     #   84
  (   4,     1,     1,     6),     #   85
  (  65,    18,    17,   100),     #   86
  (  95,    29,    26,   150),     #   87
  ( 185,    62,    53,   300),     #   88
  (  30,    11,     9,    50),     #   89
  (  35,    14,    11,    60),     #   90
  (  85,    37,    28,   150),     #   91
  (  55,    26,    19,   100),     #   92
  (  80,    41,    29,   150),     #   93
  ( 155,    86,    59,   300),     #   94
  (   5,     3,     2,    10),     #   95
  (   5,     3,     2,    10),     #   96
  (   5,     3,     2,    10),     #   97
  (   5,     3,     2,    10),     #   98
  (   5,     3,     2,    10),     #   99
  (   5,     3,     2,    10),     #  100
  (   5,     3,     2,    10),     #  101
  (   5,     3,     2,    10),     #  102
  (   5,     3,     2,    10),     #  103
  (   5,     3,     2,    10),     #  104
  (   5,     3,     2,    10),     #  105
  (   5,     3,     2,    10),     #  106
  (   5,     3,     2,    10),     #  107
  ( 305,   176,   119,   600),     #  108
  ( 155,    86,    59,   300),     #  109
  ( 105,    56,    39,   200),     #  110
  (  80,    41,    29,   150),     #  111
  (  65,    32,    23,   120),     #  112
  (  55,    26,    19,   100),     #  113
  ( 335,   152,   113,   600),     #  114
  (  85,    37,    28,   150),     #  115
  ( 115,    48,    37,   200),     #  116
  (  35,    14,    11,    60),     #  117
  ( 355,   136,   109,   600),     #  118
  (  30,    11,     9,    50),     #  119
  ( 365,   128,   107,   600),     #  120
  ( 185,    62,    53,   300),     #  121
  (  25,     8,     7,    40),     #  122
  (  95,    29,    26,   150),     #  123
  ( 385,   112,   103,   600),     #  124
  (  65,    18,    17,   100),     #  125
  ( 395,   104,   101,   600),     #  126
  (   4,     1,     1,     6),     #  127
  (   4,     1,     1,     6),     #  128
  ( 395,   104,   101,   600),     #  129
  (  65,    18,    17,   100),     #  130
  ( 385,   112,   103,   600),     #  131
  (  95,    29,    26,   150),     #  132
  (  25,     8,     7,    40),     #  133
  ( 185,    62,    53,   300),     #  134
  ( 365,   128,   107,   600),     #  135
  (  30,    11,     9,    50),     #  136
  ( 355,   136,   109,   600),     #  137
  (  35,    14,    11,    60),     #  138
  ( 115,    48,    37,   200),     #  139
  (  85,    37,    28,   150),     #  140
  ( 335,   152,   113,   600),     #  141
  (  55,    26,    19,   100),     #  142
  (  65,    32,    23,   120),     #  143
  (  80,    41,    29,   150),     #  144
  ( 105,    56,    39,   200),     #  145
  ( 155,    86,    59,   300),     #  146
  ( 305,   176,   119,   600),     #  147
  (   5,     3,     2,    10),     #  148
  (   5,     3,     2,    10),     #  149
  (   5,     3,     2,    10),     #  150
  (   5,     3,     2,    10),     #  151
  (   5,     3,     2,    10),     #  152
  (   5,     3,     2,    10),     #  153
  (   5,     3,     2,    10),     #  154
  (   5,     3,     2,    10),     #  155
  (   5,     3,     2,    10),     #  156
  (   5,     3,     2,    10),     #  157
  (   5,     3,     2,    10),     #  158
  (   5,     3,     2,    10),     #  159
  (   5,     3,     2,    10),     #  160
  ( 155,    86,    59,   300),     #  161
  (  80,    41,    29,   150),     #  162
  (  55,    26,    19,   100),     #  163
  (  85,    37,    28,   150),     #  164
  (  35,    14,    11,    60),     #  165
  (  30,    11,     9,    50),     #  166
  ( 185,    62,    53,   300),     #  167
  (  95,    29,    26,   150),     #  168
  (  65,    18,    17,   100),     #  169
  (   4,     1,     1,     6),     #  170
  (   4,     1,     1,     6),     #  171
  (   4,     1,     1,     6),     #  172
  (   4,     1,     1,     6),     #  173
  (   4,     1,     1,     6),     #  174
  (   4,     1,     1,     6),     #  175
  (   4,     1,     1,     6),     #  176
  (   4,     1,     1,     6),     #  177
  (   4,     1,     1,     6),     #  178
  ( 119,    47,    29,   195),     #  179
  (  72,    41,    17,   130),     #  180
  (  97,    76,    22,   195),     #  181
  ( 172,   181,    37,   390),     #  182
  (   5,     7,     1,    13),     #  183
  (  83,   111,    14,   208),     #  184
  (  43,    55,     6,   104),     #  185
  (  89,   109,    10,   208),     #  186
  (  23,    27,     2,    52),     #  187
  (  95,   107,     6,   208),     #  188
  (  49,    53,     2,   104),     #  189
  ( 101,   105,     2,   208),     #  190
  (   1,     1,     0,     2),     #  191
  ( 307,   303,     6,   616),     #  192
  ( 153,   149,     6,   308),     #  193
  ( 305,   293,    18,   616),     #  194
  (  38,    36,     3,    77),     #  195
  ( 303,   283,    30,   616),     #  196
  ( 151,   139,    18,   308),     #  197
  (  43,    39,     6,    88),     #  198
  (  75,    67,    12,   154),     #  199
  ( 299,   263,    54,   616),     #  200
  ( 149,   129,    30,   308),     #  201
  (  27,    23,     6,    56),     #  202
  (  37,    31,     9,    77),     #  203
  ( 295,   243,    78,   616),     #  204
  (  21,    17,     6,    44),     #  205
  ( 293,   233,    90,   616),     #  206
  (  73,    57,    24,   154),     #  207
  ( 291,   223,   102,   616),     #  208
  ( 145,   109,    54,   308),     #  209
  ( 289,   213,   114,   616),     #  210
  (  36,    26,    15,    77),     #  211
  (  41,    29,    18,    88),     #  212
  (  13,     9,     6,    28),     #  213
  ( 285,   193,   138,   616),     #  214
  (  71,    47,    36,   154),     #  215
  ( 283,   183,   150,   616),     #  216
  ( 141,    89,    78,   308),     #  217
  ( 281,   173,   162,   616),     #  218
  (   5,     3,     3,    11),     #  219
  ( 423,   256,   245,   924),     #  220
  ( 213,   130,   119,   462),     #  221
  (  13,     8,     7,    28),     #  222
  ( 108,    67,    56,   231),     #  223
  ( 435,   272,   217,   924),     #  224
  (  73,    46,    35,   154),     #  225
  (  63,    40,    29,   132),     #  226
  ( 111,    71,    49,   231),     #  227
  ( 149,    96,    63,   308),     #  228
  ( 225,   146,    91,   462),     #  229
  ( 453,   296,   175,   924),     #  230
  (  38,    25,    14,    77),     #  231
  ( 459,   304,   161,   924),     #  232
  (   3,     2,     1,     6),     #  233
  ( 471,   304,   161,   936),     #  234
  ( 237,   148,    83,   468),     #  235
  (  53,    32,    19,   104),     #  236
  (  60,    35,    22,   117),     #  237
  ( 483,   272,   181,   936),     #  238
  (  81,    44,    31,   156),     #  239
  ( 489,   256,   191,   936),     #  240
  ( 123,    62,    49,   234),     #  241
  ( 165,    80,    67,   312),     #  242
  ( 249,   116,   103,   468),     #  243
  ( 501,   224,   211,   936),     #  244
  (   7,     3,     3,    13),     #  245
  (  43,    15,    20,    78),     #  246
  (  22,     6,    11,    39),     #  247
  (  15,     3,     8,    26),     #  248
  (  23,     3,    13,    39),     #  249
  (  47,     3,    28,    78),     #  250
  (   8,     0,     5,    13),     #  251
  (   7,     0,     4,    11),     #  252
  (  21,     0,    10,    31),     #  253
  (  13,     0,     5,    18),     #  254
  (  13,     0,     5,    18),     #  255
]

proc init*(self: var ErrorDiffusion; graphics: var PicoGraphics; x, y, width, height: int; matrix: ErrorDiffusionMatrix = FloydSteinberg) =
  echo "Initializing ErrorDiffusion with backend ", self.backend
  self.graphics = graphics.addr
  self.x = x
  self.y = y
  self.width = width
  self.height = height
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

proc autobackend*(graphics: PicoGraphics): ErrorDiffusionBackend =
  when defined(mock):
    ErrorDiffusionBackend.BackendMemory
    # can also be BackendFile in mock mode
  else:
    if graphics.backend == PicoGraphicsBackend.BackendPsram:
      ErrorDiffusionBackend.BackendPsram
    else:
      ErrorDiffusionBackend.BackendFile

proc deinit*(self: var ErrorDiffusion) =
  case self.backend:
  of BackendMemory: self.fbMemory.reset()
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
  let dy = 0

  if self.variableDither:
    self.matrix = FloydSteinberg # it has same amount of rows

  echo "Processing error matrix ", (imgW, imgH), " ", self.matrix

  let matrixRows = self.matrix.m.len div self.matrix.s
  let curPix = self.matrix.currentPixel()
  let palette = self.graphics[].getPalette()

  var rows = newSeq[seq[RgbLinear]](matrixRows)
  var lumRows = newSeq[seq[uint8]](matrixRows)
  var lastProgress = -1

  for y in 0 ..< imgH:
    if y > 0:
      rows[rowPos(y - 1, matrixRows)].setLen(0)
      if self.variableDither:
        lumRows[rowPos(y - 1, matrixRows)].setLen(0)

    for i in 0..<matrixRows:
      let ry = rowPos(y + i, matrixRows)
      if y + i < imgH and rows[ry].len == 0:
        rows[ry] = self.readRow(y + i)
        if self.variableDither:
          lumRows[ry] = newSeq[uint8](imgW)
          for i in 0..<imgW:
            let L = rows[ry][i].toLab().L #.fromLinear().toHsl().l
            lumRows[ry][i] = (L * 255.0).clamp(0, 255).uint8

    for xraw in 0 ..< imgW:
      let x = if self.alternateRow and y mod 2 == 0: xraw else: imgW - 1 - xraw
      let pos = case self.orientation:
      of 3: Point(x: ox + imgW - 1 - (dx + x), y: oy + imgH - 1 - (dy + y))
      of 6: Point(x: ox + imgH - 1 - (dy + y), y: oy + (dx + x))
      of 8: Point(x: ox + (dy + y), y: oy + imgW - 1 - (dx + x))
      else: Point(x: ox + dx + x, y: oy + dy + y)

      if self.variableDither:
        let coefIndex = lumRows[rowPos(y, matrixRows)][x]
        let coefs = coefsArr[coefIndex]
        self.matrix.m[2] = coefs.r
        self.matrix.m[3] = coefs.dl
        self.matrix.m[4] = coefs.d
        self.matrix.m[5] = 0
        self.matrix.d = coefs.sum

      let oldPixel = rows[rowPos(y, matrixRows)][x].clamp(-rgbMultiplier div 10, rgbMultiplier + rgbMultiplier div 10)

      # find closest color using distance function
      var color: uint8
      if not self.hybridDither:
        color = self.graphics[].createPenNearest(oldPixel)
        # color = oldPixel.toLab().closest(paletteLab).uint8
        self.graphics[].setPixelImpl(pos, color)
      else:
        color = self.graphics[].setPixelDither(pos, oldPixel)

      let newPixel = palette[color]

      let quantError = oldPixel - newPixel

      for i, m in self.matrix.m:
        if m == 0: continue
        # Get the coords of the pixel the error is being applied to
        let mx = if self.alternateRow and y mod 2 == 0: x + (i mod self.matrix.s) - curPix else: x - (i mod self.matrix.s) + curPix
        if mx >= 0 and mx < imgW:
          let my = y + (i div self.matrix.s)
          if my >= 0 and my < imgH:
            let rgbl = RgbLinear(
              r: RgbLinearComponent (quantError.r.int * m) div self.matrix.d,
              g: RgbLinearComponent (quantError.g.int * m) div self.matrix.d,
              b: RgbLinearComponent (quantError.b.int * m) div self.matrix.d
            )
            rows[rowPos(my, matrixRows)][mx] += rgbl

    let currentProgress = y * 100 div imgH
    if lastProgress != currentProgress:
      stdout.write($currentProgress & "%\r")
      stdout.flushFile()
      lastProgress = currentProgress
