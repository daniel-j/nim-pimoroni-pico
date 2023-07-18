import std/os
import pimoroni_pico/libraries/inky_frame_mock
import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/pico_graphics/error_diffusion


proc drawHslChart(kind: InkyFrameKind) =
  echo "Drawing HSL chart..."

  var inky = InkyFrame(kind: kind)
  inky.init()

  var errDiff: ErrorDiffusion[PicoGraphicsPen3Bit]
  errDiff.autobackend(inky)
  errDiff.init(0, 0, inky.width, inky.height, inky)
  errDiff.orientation = 0
  if errDiff.backend == ErrorDiffusionBackend.BackendPsram:
    errDiff.psramAddress = PsramAddress inky.width * inky.height

  inky.setPen(White)
  inky.clear()
  var p = Point()
  var row = newSeq[RgbLinear](inky.width)
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
      let color = inky.createPenHsl(hue, 1.0, 1.02 - l * 1.04)
      #let color = LChToLab(1 - l, 0.15, hue).fromLab()
      # inky.setPen(color)
      # inky.setPixel(p)
      row[x] = color.level(gamma=1.5).toLinear()
    errDiff.write(0, y, row)

  errDiff.process()
  errDiff.deinit()

  echo "Converting image..."
  inky.update()
  echo "Writing image to tinky_frame_" & $kind & "_hsl.png..."
  inky.image.writeFile("tinky_frame_" & $kind & "_hsl.png")

proc drawFile(filename: string; kind: InkyFrameKind; drawMode: DrawMode): bool =
  var inky = InkyFrame(kind: kind)
  var jpegDecoder: JpegDecoder[PicoGraphicsPen3Bit]
  inky.init()

  inky.setPen(White)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  echo "Decoding jpeg file ", filename, "..."

  if jpegDecoder.drawJpeg(inky, filename, x, y, w, h, gravity=(0.5, 0.5), drawMode) == 1:
    echo "Converting image..."
    inky.update()
    echo "Writing image to tinky_frame_" & $kind & "_image_" & $drawMode & ".png..."
    inky.image.writeFile("tinky_frame_" & $kind & "_image_" & $drawMode & ".png")
    return true
  else:
    echo "JPEGDEC error"
    return false


for kind in InkyFrameKind:
  for drawMode in DrawMode:
    doAssert drawFile(paramStr(1), kind, drawMode)
  drawHslChart(kind)
