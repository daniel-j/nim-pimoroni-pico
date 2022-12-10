# Package

version       = "0.1.0"
author        = "djazz"
description   = "Pimoroni Pico drivers and libraries Nim port"
license       = "MIT"
srcDir        = "src"
bin           = @["example"]
backend       = "c"

# Dependencies

requires "nim >= 1.6.0"
requires "picostdlib >= 0.3.2"

include picostdlib/build_utils/tasks
