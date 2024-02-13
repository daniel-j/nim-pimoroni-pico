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

task futharkgen, "Generate futhark cache":
  exec "nimble c -c src/pimoroni_pico/futharkgen"

before install:
  futharkgenTask()

task test, "Runs the test suite":

  # exec "piconim configure --project tests --source tests --board pico"

  # exec "piconim configure --project tests --source tests --board pico_w"

  # build and run mock tests
  selfExec "c -r -d:release --opt:speed --skipParentCfg:on tests/mock/tinky_frame resources/sample.jpg"

task examples, "Build the examples":
  const examples = [
    # Badger 2040
    "badger2040/hello",

    # Galaxy Unicorn
    "galactic_unicorn/lightmeter",
    "galactic_unicorn/rainbow",
    "galactic_unicorn/simple",

    # Inky Frame
    "inky_frame/slideshow",
    "inky_frame/slideshow_gphotos",
    "inky_frame/sleepy_head"
  ]

  # exec "piconim configure --project examples --source examples --board pico"
  # exec "cmake --build build/examples -- -j4"

  exec "piconim configure --project examples --source examples --board pico_w"

  for ex in examples:
    let splitpath = ex.split("/")
    let (product, base) = (splitpath[0], splitpath[^1])
    exec "piconim build --project examples examples/" & ex & " --target " & product & "_" & base & " --compileOnly"

  exec "cmake --build build/examples -- -j4"
