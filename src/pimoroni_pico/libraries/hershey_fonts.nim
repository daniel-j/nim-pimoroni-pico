import std/math

type
  HersheyFontGlyph* {.byref.} = object
    width*: uint
    vertexCount*: uint
    vertices*: ptr int8

  HersheyFont* {.byref.} = object
    name*: string
    chars*: array[95, HersheyFontGlyph]

  LineFunc* = proc(x1, y1, x2, y2: int32)

proc glyphData*(font: HersheyFont; c: char): ptr HersheyFontGlyph =
  if c.uint8 < 32 or c.uint8 > 127 + 64: # + 64 char remappings defined in unicode_sorta.hpp
    return nil

  # if c > 127:
  #   c = unicode_sorta::char_base_195[c - 128]

  return font.chars[c.uint8 - 32].unsafeAddr

proc measureGlyph*(font: HersheyFont; c: char; s: float32): int32 =
  let gd = font.glyphData(c)

  # if glyph data not found (id too great) then skip
  if gd.isNil:
    return 0

  return int32 gd.width.float32 * s

proc measureText*(font: HersheyFont; message: string; s: float): int32 =
  for c in message:
    result += font.measureGlyph(c, s)

proc glyph*(font: HersheyFont; line: LineFunc; c: char; x, y: int32; s: float32; angle: float32): int32 =
  let gd = font.glyphData(c)

  # if glyph data not found (id too great) then skip
  if gd.isNil:
    return 0

  let a = degToRad(angle)
  let asin: float32 = sin(a)
  let acos: float32 = cos(a)

  let v = cast[ptr UncheckedArray[int8]](gd.vertices)

  var pv = 0
  var cx = int8 v[pv].float32 * s
  inc(pv)
  var cy = int8 v[pv].float32 * s
  inc(pv)
  var penDown = true

  for i in 1'u32 ..< gd.vertex_count:
    if v[pv] == -128 and v[pv + 1] == -128:
      penDown = false
      pv += 2
    else:
      let nx = int8 v[pv].float32 * s
      inc(pv)
      let ny = int8 v[pv].float32 * s
      inc(pv)

      let rcx = int32 (cx.float32 * acos - cy.float32 * asin) + 0.5f
      let rcy = int32 (cx.float32 * asin + cy.float32 * acos) + 0.5f

      let rnx = int32 (nx.float32 * acos - ny.float32 * asin) + 0.5f
      let rny = int32 (nx.float32 * asin + ny.float32 * acos) + 0.5f

      if penDown:
        line(rcx + x, rcy + y, rnx + x, rny + y)

      cx = nx
      cy = ny
      penDown = true

  return int32 gd.width.float32 * s

proc text*(font: HersheyFont; line: LineFunc; message: string; x, y: int32; s: float32; angle: float32) =
  let cx = x
  let cy = y

  var ox: int32 = 0

  let a = degToRad(angle)
  let asin: float32 = sin(degToRad(a))
  let acos: float32 = cos(degToRad(a))

  for c in message:
    let rcx = int32 (ox.float32 * acos) + 0.5f
    let rcy = int32 (ox.float32 * asin) + 0.5f

    ox += font.glyph(line, c, cx + rcx, cy + rcy, s, angle)
