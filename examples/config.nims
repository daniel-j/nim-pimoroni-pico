switch("path", "$projectDir/../src")
switch("path", getCurrentDir() & "/src")

include "../src/config.nims"

switch("d", "cmakeBinaryDir:" & getCurrentDir() & "/build/examples")
switch("d", "piconimCsourceDir:" & getCurrentDir() & "/csource")
switch("d", "futharkgen")
