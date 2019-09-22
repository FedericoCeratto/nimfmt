# Nim code formatter
#
# Copyright 2016 Federico Ceratto <federico.ceratto@gmail.com>

import
  compiler/idents,
  compiler/options,
  compiler/renderer,
  os,
  parsecfg,
  parseopt,
  strutils

const version = "0.2.0"

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
  let name = n.ident.s
  let normalized = normalize(name)
  let old = naming_styles_tracker.mgetOrPut(
    normalized,
    (name, input_fname, n.info.line.int, n.info.col.int)
  )
  if name == old.name:
    return  # already seen or just inserted by mgetOrPut

  let msg =
    if input_fname == "":
      # Only one file (or stdin) is being processed
      "Warning: $# at $#:$# also appears as $# at $#:$#" % [
        name, $n.info.line, $n.info.col,
        old.name, $old.linenum, $old.colnum
      ]
    else:
      "Warning: $# at $#:$#:$# also appears as $# at $#:$#:$#" % [
        name, input_fname, $n.info.line, $n.info.col,
        old.name, $old.filename, $old.linenum, $old.colnum
      ]

  stderr.writeLine msg

proc check_naming_style(nfconf: Config, n: PNode, input_fname: string) =
  ## Recursively check names in AST
  case n.kind
  of nkImportStmt, nkExportStmt, nkCharLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit, nkSym, nkCommentStmt: discard
  of nkIdent:
    check_node_naming_style(n, input_fname)
  else:
    for s in n.sons:
      check_naming_style(nfconf, s, input_fname)

from compiler/msgs import fileInfoIdx
from compiler/pathutils import RelativeFile, AbsoluteFile, toAbsoluteDir
from compiler/syntaxes import setupParsers, TParsers, closeParsers
import compiler/syntaxes

type
  PrettyOptions = object
    indWidth: int
    maxLineLen: int

proc prettyPrint(nfconf: Config, infile, outFile: string, opt: PrettyOptions) =
  var conf = newConfigRef()
  let fileIdx = fileInfoIdx(conf, AbsoluteFile infile)
  let f = splitFile(outfile.expandTilde)
  conf.outFile = RelativeFile f.name & f.ext
  conf.outDir = toAbsoluteDir f.dir
  var p: TParsers
  p.parser.em.indWidth = opt.indWidth
  if setupParsers(p, fileIdx, newIdentCache(), conf):
    p.parser.em.maxLineLen = opt.maxLineLen
    var n = parseAll(p)
    check_naming_style(nfconf, n, infile)
    closeParsers(p)

proc nimfmt*(nfconf: Config, input_fname, output_fname: string): seq[string] =
  ## Format file
  result = @[]
  let cache = newIdentCache()
  var pconf = newConfigRef()
  #let ast = parseString(input, cache, pconf)
  let opts = PrettyOptions(maxLineLen: 80, indWidth: 2)
  prettyPrint(nfconf, input_fname, output_fname, opts)

  var formatted: seq[string] = @[]

  return formatted

proc load_config_file(fnames: seq[string]): Config =
  ## Load config file
  for rel_fn in fnames:
    let fn = expandTilde(rel_fn)
    if fileExists(fn):
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
      output_lines = nimfmt(conf, input_fn, output_fn)

    if output_lines.len == 0:
      echo "Nothing to write"
      return

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
