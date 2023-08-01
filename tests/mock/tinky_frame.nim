import std/os
import pimoroni_pico/libraries/inky_frame_mock
import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/pico_graphics/error_diffusion


proc drawHslChart(kind: InkyFrameKind; drawMode: DrawMode; matrix: ErrorDiffusionMatrix = ErrorDiffusionMatrix()) =
  echo "Drawing HSL chart..."

  var inky = InkyFrame(kind: kind)
  inky.init()

  var errDiff: ErrorDiffusion[inky]
  if drawMode == DrawMode.ErrorDiffusion:
    errDiff = ErrorDiffusion[inky](backend: autobackend(inky))
    errDiff.init(inky, 0, 0, inky.width, inky.height, matrix, alternateRow = true)
    errDiff.orientation = 0
    if errDiff.backend == ErrorDiffusionBackend.BackendPsram:
      errDiff.psramAddress = PsramAddress inky.width * inky.height

  inky.setPen(White)
  inky.clear()
  var p = Point()
  var row: seq[RgbLinear]
  if drawMode == DrawMode.ErrorDiffusion:
    row = newSeq[RgbLinear](inky.width)

  for y in 0..<inky.height:
    stdout.write $(y+1) & " of " & $inky.height & "\r"
    stdout.flushFile()
    p.y = y
    let yd = y / inky.height
    let l = yd
    for x in 0..<inky.width:
      p.x = x
      let xd = x / inky.width
      let hue = xd
      var color = inky.createPenHsl(hue, 1.0, 1.02 - l * 1.04)
      #let color = LChToLab(1 - l, 0.15, hue).fromLab()
      case drawMode:
      of Default:
        let pen = inky.createPenNearest(color.toLinear())
        inky.setPen(pen)
        inky.setPixel(p)
      of OrderedDither:
        color = color.level(black=0.05f, white=0.96f, gamma=1.4f) #.saturate(0.75f).level(black=0.03f, white=1.5f, gamma=defaultGamma)
        inky.setPixelDither(p, color.toLinear())
      of DrawMode.ErrorDiffusion:
        row[x] = color.toLinear()
    if drawMode == DrawMode.ErrorDiffusion:
      errDiff.write(0, y, row)

  if drawMode == DrawMode.ErrorDiffusion:
    errDiff.process()
    errDiff.deinit()

  echo "Converting image..."
  inky.update()
  if drawMode == DrawMode.ErrorDiffusion:
    let filename = "tinky_frame_" & $kind & "_hsl_" & $ErrorDiffusionMatrices.find(matrix) & ".png"
    echo "Writing image to " & filename & "..."
    inky.image.writeFile(filename)
  else:
    let filename = "tinky_frame_" & $kind & "_hsl_" & $drawMode & ".png"
    echo "Writing image to " & filename & "..."
    inky.image.writeFile(filename)

proc drawFile(filename: string; kind: InkyFrameKind; drawMode: DrawMode; matrix: ErrorDiffusionMatrix = ErrorDiffusionMatrix()): bool =
  var inky = InkyFrame(kind: kind)
  var jpegDecoder: JpegDecoder[PicoGraphicsPen3Bit]
  # jpegDecoder.setErrorDiffusionMatrix(Sierra)
  inky.init()

  inky.setPen(White)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  echo "Decoding jpeg file ", filename, "..."

  jpegDecoder.init(inky)

  jpegDecoder.errDiff.matrix = matrix
  jpegDecoder.errDiff.alternateRow = true

  if jpegDecoder.drawJpeg(filename, x, y, w, h, gravity=(0.5f, 0.5f), drawMode) == 1:
    echo "Converting image..."
    inky.update()
    if matrix.s > 0:
      let filename = "tinky_frame_" & $kind & "_image_" & $ErrorDiffusionMatrices.find(matrix) & ".png"
      echo "Writing image to " & filename & "..."
      inky.image.writeFile(filename)
    else:
      let filename = "tinky_frame_" & $kind & "_image_" & $drawMode & ".png"
      echo "Writing image to " & filename & "..."
      inky.image.writeFile(filename)
    return true
  else:
    echo "JPEGDEC error"
    return false

const matrices = [FloydSteinberg]
const drawModes = [OrderedDither, ErrorDiffusion]

for kind in InkyFrameKind:
  for drawMode in drawModes:
    if drawMode == DrawMode.ErrorDiffusion:
      for matrix in matrices:
        drawHslChart(kind, drawMode, matrix)
    else:
      drawHslChart(kind, drawMode)

  for drawMode in drawModes:
    if drawMode == DrawMode.ErrorDiffusion:
      for matrix in matrices:
        doAssert drawFile(paramStr(1), kind, drawMode, matrix)
    else:
      doAssert drawFile(paramStr(1), kind, drawMode)
