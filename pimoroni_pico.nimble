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
requires "picostdlib >= 0.4.0"
requires "pixie >= 5.0.4"

include picostdlib/build_utils/tasks

before install:
  exec "nimble c -c -d:useFuthark -d:futharkRebuild -d:opirRebuild src/pimoroni_pico/futhark_gen"

task test, "Runs the test suite":

  # exec "piconim configure --project tests --source tests --board pico"

  # exec "piconim configure --project tests --source tests --board pico_w"

  # build and run mock tests
  exec "nim c -r --skipParentCfg:on --hints:off tests/mock/tinky_frame resources/sample.jpg"

task examples, "Build the examples":
  const examples = [
    # Galaxy Unicorn
    "galactic_unicorn/lightmeter",
    "galactic_unicorn/rainbow",
    "galactic_unicorn/simple",

    # Inky Frame
    "inky_frame/slideshow",
  ]

  # exec "piconim configure --project examples --source examples --board pico"
  # exec "cmake --build build/examples -- -j4"

  exec "piconim configure --project examples --source examples --board pico_w"

  for ex in examples:
    let splitpath = ex.split("/")
    let (product, base) = (splitpath[0], splitpath[^1])
    exec "piconim build --project examples examples/" & ex & " --target " & product & "_" & base & " --compileOnly"

  exec "cmake --build build/examples -- -j4"
