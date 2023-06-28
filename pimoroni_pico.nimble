# Package

version       = "0.1.0"
author        = "djazz"
description   = "Pimoroni Pico drivers and libraries for Nim"
license       = "MIT"
srcDir        = "src"
skipFiles     = @["futhark_gen.nim"]
backend       = "c"

# Dependencies

requires "nim >= 1.6.0"
requires "picostdlib >= 0.3.2"
requires "pixie >= 5.0.4"

include picostdlib/build_utils/tasks

before install:
  exec "nimble c -c -d:useFuthark -d:futharkRebuild -d:opirRebuild src/pimoroni_pico/futhark_gen"
