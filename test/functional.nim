
import unittest
import strutils, streams, osproc


proc exec(cmd: string) =
  if execCmd(cmd) != 0:
    raise newException(Exception, "error while executing '$#'" % cmd)


proc exec2*(command: string, timeout: int = - 1): tuple[output: string, stderr: string, exitCode: int] {.tags: [ExecIOEffect, ReadIOEffect], gcsafe, discardable.} =
  var p = startProcess(command, options={poEvalCommand})
  let exit_code = p.waitForExit(timeout)
  if p.peekExitCode() == -1:
    raise newException(Exception, "timeout")

  result = (p.outputStream().readAll(), p.errorStream().readAll(), exit_code)
  #close(p)


suite "Functional test":

  teardown:
    exec "rm test/data/output_*.nim"

  test "Basic test":
    exec("./nimfmt test/data/sample.nim -p:output_")
    exec("diff --color=always test/data/sample_expected_output.nim test/data/output_sample.nim")

  test "Warnings test":
    #exec("./nimfmt test/data/sample.nim -p:output_ -c:test/data/variable_naming_warnings.ini")
    let (outp, errC) = execCmdEx("./nimfmt test/data/sample.nim -p:output_ -c:test/data/variable_naming_warnings.ini")
    if errC != 0:
      echo "Unexpected failure: $#\n----$#\n----" % [$errC, outp]

    check errC == 0
    check outp.contains("Warning")

    #var e = exec2("./nimfmt test/data/sample.nim -p:output_ -c:test/data/variable_naming_warnings.ini")
    #if e.exitCode != 0:
    #  echo "Unexpected failure: $#\n----$#\n----$#\n----" % [$e.exitCode, e.stderr, e.stderr]
    #  fail()
    #else:
    #  check e.exitCode == 0
    #  check e.stderr.contains "Warning"
    #  #e = exec2("diff --color=always test/data/sample_expected_output.nim test/data/output_sample.nim")
