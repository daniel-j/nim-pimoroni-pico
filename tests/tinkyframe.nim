import pimoroni_pico/libraries/inky_frame_mock
import pimoroni_pico/libraries/pico_graphics/drawjpeg

var inky = InkyFrame(kind: InkyFrame7_3)
inky.init()

proc drawHslChart() =
  echo "Drawing HSL chart..."
  inky.setPen(White)
  inky.clear()
  var p = Point()
  for y in 0..<inky.height:
    # echo y, " of ", inky.height
    p.y = y
    let yd = y / inky.height
    let l = yd
    for x in 0..<inky.width:
      p.x = x
      let xd = x / inky.width
      let hue = xd
      inky.setPen(inky.createPenHsl(hue, 1.0, 1.02 - l * 1.04))
      # let col = constructRgb(int16 hue * 255, 255, int16 255 - l * 255)
      # let hslCacheKey = getCacheKey(col)
      # inky.setPen(hslCache[hslCacheKey].rgb565ToRgb())
      inky.setPixel(p)

  echo "Converting image..."
  inky.update()
  echo "Writing image to inkyhsl.png..."
  inky.image.writeFile("inkyhsl.png")

proc drawFile(filename: string) =
  inky.setPen(Clean)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  echo "Decoding jpeg file ", filename, "..."

  if inky.drawJpeg(filename, x, y, w, h, gravity=(0.5, 0.5), OrderedDither) == 1:
    echo "Converting image..."
    inky.update()
    echo "Writing image to inky.png..."
    inky.image.writeFile("inky.png")
  else:
    echo "JPEGDEC error"

proc inkyProc() =
  echo "Starting..."

  drawFile("image.jpg")


  drawHslChart()

inkyProc()
