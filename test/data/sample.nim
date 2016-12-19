# comment 1

#
# comment 2
#


import strutils
import os

# n

import times, tables

proc my_foo( a: string,  b:string,c:int, ): string  =
  ## I'm a doc comment
  # I'm a regular comment
  var messyVar = 3
  messy_var = 4
  messyvar = 5
  return  "string to return"
  raise newException( Exception , 
  "foo" )
  yield   "string to yield"
  discard   "string to discard"  # boring comment
#

  break



  continue

discard myFoo("a", "b", 1)
discard my_foo("a", "b", 1)

# Extra white line at the end

