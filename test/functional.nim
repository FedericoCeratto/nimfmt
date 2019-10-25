
import unittest
import strutils, streams, osproc


proc exec(cmd: string, echo = false): string {.discardable.} =
  let (output, exit_code) = execCmdEx(cmd)
  if exit_code != 0:
    echo "Unexpected failure: $#\n----$#\n----" % [$exit_code, output]
    raise newException(Exception, "error while executing '$#'" % cmd)

  return output


suite "Functional test":

  var last_cmd = ""
  var last_output = ""

  proc nimfmt(cmd: string) =
    last_cmd = "./nimfmt " & cmd
    last_output = exec(last_cmd)

  proc diff(new, exp: string): bool =
    let cmd = "diff --color=always test/data/expected/$#.nim test/data/generated_$#.nim" %
        [exp, new]
    let (output, exit_code) = execCmdEx(cmd)
    if exit_code != 0:
      echo "--output--"
      echo last_output
      echo "---diff---"
      echo output
      echo "----------"
      return false

    return true

  teardown:
    exec "rm test/data/generated_*.nim -f"

  test "Help":
    nimfmt("-h")

  test "Debug custom conf":
    nimfmt("-d -c=test/data/sample1_fix_naming_snake_case.cfg test/data/empty.nim")
    check last_output.contains("Reading")

  test "Basic":
    nimfmt("-c:test/data/sample1.cfg test/data/sample1.nim -p:generated_")
    check diff("sample1", "sample1")

  test "Warnings":
    #nimfmt("-c:test/data/sample1.cfg test/data/sample1.nim -p:output_ -c:test/data/variable_naming_warnings.ini")
    nimfmt("test/data/sample1.nim -p:generated_ -c:test/data/variable_naming_warnings.ini")
    check last_output.contains("Warning") # TODO improve

  test "Fix naming style: most popular":
    # Automatically pick most popular name
    nimfmt("-c:test/data/sample1_fix_naming_most_popular.cfg test/data/sample1.nim -p:generated_")
    check diff("sample1", "sample1_fix_naming_most_popular")

  test "Fix naming style: snake_case":
    # Automatically pick snake_case if possible
    nimfmt("-c:test/data/sample1_fix_naming_snake_case.cfg test/data/sample1.nim -p:generated_")
    check diff("sample1", "sample1_fix_naming_snake_case")

#  test "Fix package directory naming style: most popular":
#    # Automatically pick most popular name
#    nimfmt("-c:test/data/sample1_fix_naming_most_popular.cfg test/data/package_directory.nim -p:generated_")
#    check diff("package_directory", "package_directory")

  test "Fix naming style 2: most popular":
    # Automatically pick most popular name
    nimfmt("-c:test/data/sample1_fix_naming_most_popular.cfg test/data/sample2.nim -p:generated_")
    check diff("sample2", "sample2_fix_naming_most_popular")

