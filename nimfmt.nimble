# Package

version       = "0.1.0"
author        = "Federico Ceratto"
description   = "Nim restyling tool"
license       = "GPLv3"

bin           = @["nimfmt"]

# Dependencies

requires "nim >= 1.0.0", "compiler#head"

# Cmds

task release, "Build a release":
  exec "nim c -d:nimOldCaseObjects -d:nimpretty -d:release --hints:off nimfmt.nim"

task b, "Build":
  exec "nim c -d:nimOldCaseObjects -d:nimpretty --hints:off nimfmt.nim"

task test, "Basic test":
  exec "nim c -d:nimOldCaseObjects -d:nimpretty --hints:off -r test/unit.nim"

task test_functional, "Basic functional test":
  exec "nim c -d:nimOldCaseObjects -d:nimpretty --hints:off nimfmt.nim"
  exec "nim c --hints:off test/functional.nim"
  exec "./test/functional"

task loop, "loop":
  exec "nim c -p:../Nim nimfmt.nim"
  exec "./nimfmt test/data/sample.nim -p:output_"
  exec "cat test/data/output_sample.nim"
  #exec "diff test/data/sample_expected_output.nim test/data/output_sample.nim"
  exec "rm test/data/output_sample.nim"
