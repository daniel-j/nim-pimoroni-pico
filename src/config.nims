switch("cpu", "arm")
switch("os", "freertos")

switch("define", "release")
switch("define", "NDEBUG")
switch("opt", "size")
switch("mm", "orc") # use "arc", "orc" or "none"
switch("deepcopy", "on")
switch("threads", "off")

switch("compileOnly", "on")
switch("nimcache", "build/" & projectName() & "/nimcache")

switch("define", "checkAbi")
switch("define", "nimMemAlignTiny")
switch("define", "useMalloc")
# switch("define", "nimAllocPagesViaMalloc")
# switch("define", "nimPage256")

# when using cpp backend
# see for similar issue: https://github.com/nim-lang/Nim/issues/17040
switch("d", "nimEmulateOverflowChecks")

# for futhark to work
switch("maxLoopIterationsVM", "1000000000")

# switch("d", "PICO_SDK_PATH:/path/to/pico-sdk")
switch("d", "CMAKE_BINARY_DIR:" & getCurrentDir() & "/build/" & projectName())
switch("d", "CMAKE_SOURCE_DIR:" & getCurrentDir() & "/csource")
