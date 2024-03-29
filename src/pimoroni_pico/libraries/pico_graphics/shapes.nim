
##
## Point
##

type
  Point* = object
    x*: int
    y*: int

func constructPoint*(x, y: int32): Point =
  result.x = x
  result.y = y

func `-=`*(self: var Point; a: Point) {.inline.} =
  dec(self.x, a.x)
  dec(self.y, a.y)

func `+=`*(self: var Point; a: Point) {.inline.} =
  inc(self.x, a.x)
  inc(self.y, a.y)

func `/=`*(lhs: var Point; rhs: int32) {.inline.} =
  lhs.x = lhs.x div rhs
  lhs.y = lhs.y div rhs

func `==`*(lhs, rhs: Point): bool {.inline.} =
  return lhs.x == rhs.x and lhs.y == rhs.y

func `-`*(lhs, rhs: Point): Point {.inline.} = Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
func `-`*(rhs: Point): Point {.inline.} = Point(x: -rhs.x, y: -rhs.y)
func `+`*(lhs, rhs: Point): Point {.inline.} = Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
func `div`*(lhs: Point; rhs: int32): Point {.inline.} = Point(x: lhs.x div rhs, y: lhs.y div rhs)


##
## Rect
##

type
  Rect* = object
    x*: int
    y*: int
    w*: int
    h*: int

func constructRect*(x, y, w, h: int): Rect =
  result.x = x
  result.y = y
  result.w = w
  result.h = h

func constructRect*(tl: Point; br: Point): Rect =
  result.x = tl.x
  result.y = tl.y
  result.w = br.x - tl.x
  result.h = br.y - tl.y

func clamp*(self: Point; r: Rect): Point =
  result.x = min(max(self.x, r.x), r.x + r.w)
  result.y = min(max(self.y, r.y), r.y + r.h)

func empty*(self: Rect): bool =
  return self.w <= 0 or self.h <= 0

func contains*(self: Rect; p: Point): bool =
  return p.x >= self.x and p.y >= self.y and p.x < self.x + self.w and p.y < self.y + self.h

func contains*(self: Rect; p: Rect): bool =
  return p.x >= self.x and p.y >= self.y and p.x + p.w < self.x + self.w and p.y + p.h < self.y + self.h

func intersects*(self: Rect; r: Rect): bool =
  return not (self.x > r.x + r.w or self.x + self.w < r.x or self.y > r.y + r.h or self.y + self.h < r.y)

func intersection*(self: Rect; r: Rect): Rect =
  result.x = max(self.x, r.x)
  result.y = max(self.y, r.y)
  result.w = min(self.x + self.w, r.x + r.w) - max(self.x, r.x)
  result.h = min(self.y + self.h, r.y + r.h) - max(self.y, r.y)

proc inflate*(self: var Rect; v: int32) =
  dec(self.x, v)
  dec(self.y, v)
  inc(self.w, v * 2)
  inc(self.h, v * 2)

proc deflate*(self: var Rect; v: int32) =
  inc(self.x, v)
  inc(self.y, v)
  dec(self.w, v * 2)
  dec(self.h, v * 2)

func area*(self: Rect): int {.inline.} = self.w * self.h
