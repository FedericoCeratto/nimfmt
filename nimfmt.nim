# Nim code formatter
#
# Copyright 2016 Federico Ceratto <federico.ceratto@gmail.com>

import
  compiler/parser,
  compiler/renderer,
  os,
  parsecfg,
  parseopt,
  pegs,
  strutils

import
  options, lists

const version = "0.1.0"

from compiler/ast import PNode, nkImportStmt, nkExportStmt, nkCharLit, nkUInt64Lit, nkFloatLit, nkFloat128Lit, nkStrLit, nkTripleStrLit, nkSym, nkIdent

import compiler/ast

proc writeHelp(exit_val=0) =
  ## Write help and quit
  let name = getAppFilename().extractFilename()
  echo """
  Usage: $# <filename.nim> [<filename.nim> ... ]
  [ -p <prefix> ]     output file prefix
  [ -s <suffix> ]     output file suffix
  [ -c <filename>, ]  configuration file location(s) (default: ./.nimfmt.cfg ~/.nimfmt.cfg)
  [ -i ]              update files in-place (dangerous!)
  [ -w ]              overwrite existing files (automatically enabled when using -i)
  [-v]                version
  [-h]                this help

  If any of -p ..., -s ... or -i are specified the output will be written to disk,
  otherwise to stdout
  """ % [name]
  quit(exit_val)




import tables

type NameInstance = tuple[name, filename: string, linenum, colnum: int]

var naming_styles_tracker = initTable[string, NameInstance]()


proc check_node_naming_style(n: PNode, input_fname: string) =
  ## Check naming style
  let normalized = normalize($n)
  let old = naming_styles_tracker.mgetOrPut(
    normalized,
    ($n, input_fname, n.info.line.int, n.info.col.int)
  )
  if $n == old.name:
    return  # already seen or just inserted by mgetOrPut

  let msg =
    if input_fname == "":
      # Only one file (or stdin) is being processed
      "Warning: $# at $#:$# also appears as $# at $#:$#" % [
        $n, $n.info.line, $n.info.col,
        old.name, $old.linenum, $old.colnum
      ]
    else:
      "Warning: $# at $#:$#:$# also appears as $# at $#:$#:$#" % [
        $n, input_fname, $n.info.line, $n.info.col,
        old.name, $old.filename, $old.linenum, $old.colnum
      ]

  stderr.writeln msg

proc check_naming_style(conf: Config, n: PNode, input_fname: string) =
  ## Recursively check names in AST
  case n.kind
  of nkImportStmt: discard
  of nkExportStmt: discard
  of nkCharLit..nkUInt64Lit: discard
  of nkFloatLit..nkFloat128Lit: discard
  of nkStrLit..nkTripleStrLit: discard
  of nkSym: discard
  of nkCommentStmt: discard
  of nkIdent:
    check_node_naming_style(n, input_fname)
  else:
    for s in n.sons:
      check_naming_style(conf, s, input_fname)

proc nimfmt*(input: string, conf: Config, input_fname: string): seq[string] =
  ## Format file
  result = @[]
  let ast = parseString input

  echo "kind ", ast.kind
  echo "comment ", ast.comment
  echo "info ", ast.info
  #echo "sym ", repr ast.sym
  #echo "typ ", ast.typ
  #echo "ident ", repr ast.ident

  var formatted: seq[string] = @[]
  for line in ast.renderTree({renderDocComments}).splitLines():
    formatted.add line[2..^1].strip(leading = false)

  check_naming_style(conf, ast, input_fname)

  return formatted

proc load_config_file(fnames: seq[string]): Config =
  ## Load config file
  for rel_fn in fnames:
    let fn = expandTilde(rel_fn)
    echo "TRY ", fn
    if fileExists(fn):
      echo "FOUND ", fn
      return loadConfig(fn)

  return newConfig()


proc main() =
  ## Run nimfmt from CLI
  var
    input_fnames: seq[string] = @[]
    in_place = false
    suffix = ""
    prefix = ""
    allow_overwrite = false
    config_filenames: seq[string] = @["./.nimfmt.cfg", "~/.nimfmt.cfg"]

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      if key.endswith(".nim"):
        input_fnames.add key
      else:
        echo "Ignoring $#" % key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        echo "nimfmt v. $#  -  Nim style tool" % version
        writeHelp()
      of "version", "v":
        echo version
      of "prefix", "p":
        prefix = val
      of "suffix", "s":
        suffix = val
      of "configfiles", "c":
        config_filenames = val.split(",")
      of "i":
        in_place = true
      of "w":
        allow_overwrite = true
      else:
        writeHelp(1)

    of cmdEnd:
      quit(1)

  if input_fnames.len == 0:
    echo "Please specify at least an input file. Only files ending with .nim are parsed.\n"
    writeHelp(1)

  let conf = load_config_file(config_filenames)

  for input_fn in input_fnames:
    let
      (dirname, i_fn, _) = input_fn.splitFile()
      output_fn = dirname / "$#$#$#.nim" % [prefix, i_fn, suffix]
      write_to_stdout = (prefix == "" and suffix == "" and not in_place)
      input_str = readFile(input_fn)
      output_lines = nimfmt(input_str, conf, input_fn)

    if write_to_stdout:
      for line in output_lines:
        echo line

    else:
      if not allow_overwrite and (output_fn.fileExists or output_fn.dirExists):
        echo "Not overwriting $#" % output_fn
      else:
        echo "writing $#" % output_fn
        output_fn.writeFile(output_lines.join("\n"))


if isMainModule:
  main()
