# comment 1

#
# comment 2
#


import
  strutils

# unsorted imports
import strutils
import os

# comment

import times, tables

let camelCase = 3

proc myFoo(a: string, b: string, c: int, ): string =
  ## I'm a doc comment
  # I'm a regular comment
  var messyVar = 3
  messy_var = 4
  messyvar = 5
  return "string to return"
  raise newException(Exception,
  "foo")
  yield "string to yield"
  discard "string to discard" # boring comment
#

  break



  continue




proc myFoo(a: string) =
  # proc after 4 white lines
  discard


discard myFoo("a", "b", 1)
discard myFoo("a", "b", 2)
discard myFoo("a", "b", 1)

# Extra white line at the end

