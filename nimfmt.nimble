# Package

version       = "0.1.0"
author        = "Federico Ceratto"
description   = "Nim restyling tool"
license       = "LGPLv3"

bin           = @["nimfmt"]

# Dependencies

requires "nim >= 0.14.2"

# Cmds

task release, "Build a release":
  exec "nim c -d:release nimfmt.nim"

task b, "Build":
  exec "nim c nimfmt.nim"

task test, "Basic test":
  exec "nim c -r test/unit.nim"

task test_functional, "Basic functional test":
  exec "nim c nimfmt.nim"
  exec "nim c -r test/functional.nim"


task loop, "loop":
  exec "nim c -p:../Nim nimfmt.nim"
  exec "./nimfmt test/data/sample.nim -p:output_"
  exec "cat test/data/output_sample.nim"
  #exec "diff test/data/sample_expected_output.nim test/data/output_sample.nim"
  exec "rm test/data/output_sample.nim"
