import ../libraries/pico_graphics
import ../common/pimoroni_common
export pico_graphics, pimoroni_common

##
## Display Driver
##

type
  DisplayDriver* = object of RootObj
    width*: uint16
    height*: uint16
    rotation*: Rotation

proc init*(self: var DisplayDriver; width: uint16; height: uint16; rotation: Rotation = Rotate_0) =
  self.width = width
  self.height = height
  self.rotation = rotation

method update*(self: var DisplayDriver; display: var PicoGraphicsBase) {.base.} =
  discard

method partialUpdate*(self: var DisplayDriver; display: var PicoGraphicsBase; region: Rect) {.base.} =
  discard

method setUpdateSpeed*(self: var DisplayDriver; updateSpeed: int): bool {.base.} =
  return false

method setBacklight*(self: var DisplayDriver; brightness: uint8) {.base.} =
  discard

method isBusy*(self: var DisplayDriver): bool {.base.} =
  return false

method powerOff*(self: var DisplayDriver) {.base.} =
  discard

method cleanup*(self: var DisplayDriver) {.base.} =
  discard
