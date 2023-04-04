import pimoroni_pico/libraries/inky_frame_mock
import pimoroni_pico/libraries/pico_graphics/drawjpeg

var inky = InkyFrame(kind: InkyFrame7_3)
inky.init()

proc drawFile(filename: string) =
  inky.setPen(Clean)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  if inky.drawJpeg(filename, x, y, w, h, gravity=(0.5, 0.5)) == 1:
    echo "writing image..."

    inky.update()
    inky.image.writeFile("inky.png")
  else:
    echo "jpeg error"
  #  inky.led(LedActivity, 0)

proc inkyProc() =
  echo "Starting..."

  drawFile("image.jpg")


inkyProc()
