switch("cpu", "arm")
switch("os", "freertos")

switch("define", "release")
switch("opt", "size")
switch("mm", "orc") # use "arc", "orc" or "none"

switch("compileOnly", "on")
switch("nimcache", "build/nimcache")

switch("define", "checkAbi")
switch("define", "useMalloc")
switch("define", "nimAllocPagesViaMalloc")
switch("define", "nimPage256")
switch("define", "NDEBUG")

# when using cpp backend
# see for similar issue: https://github.com/nim-lang/Nim/issues/17040
switch("d", "nimEmulateOverflowChecks")
