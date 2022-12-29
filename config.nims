switch("cpu", "arm")
switch("os", "freertos")

switch("define", "release")
# switch("define", "NDEBUG")
switch("opt", "size")
switch("mm", "orc") # use "arc", "orc" or "none"
switch("deepcopy", "on")

switch("compileOnly", "on")
switch("nimcache", "build/nimcache")

switch("define", "checkAbi")
switch("define", "useMalloc")
switch("define", "nimAllocPagesViaMalloc")
switch("define", "nimPage256")

# when using cpp backend
# see for similar issue: https://github.com/nim-lang/Nim/issues/17040
switch("d", "nimEmulateOverflowChecks")
