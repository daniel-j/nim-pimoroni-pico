switch("path", "$projectDir/../src")

# switch("define", "release")
# switch("opt", "size")

switch("mm", "orc") # use "arc", "orc" or "none"
switch("deepcopy", "on")
switch("threads", "off")

switch("define", "checkAbi")
switch("define", "useMalloc")
switch("define", "nimAllocPagesViaMalloc")
switch("define", "nimPage256")

# when using cpp backend
# see for similar issue: https://github.com/nim-lang/Nim/issues/17040
switch("d", "nimEmulateOverflowChecks")

# for futhark to work
switch("maxLoopIterationsVM", "1000000000")
