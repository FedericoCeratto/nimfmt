# Nim code formatter
#
# Copyright 2016 Federico Ceratto <federico.ceratto@gmail.com>

import
  os,
  parsecfg,
  parseopt,
  strformat,
  strutils,
  tables

const version = "0.2.0"

from compiler/ast import PNode, nkImportStmt, nkExportStmt, nkCharLit, nkUInt64Lit, nkFloatLit, nkFloat128Lit, nkStrLit, nkTripleStrLit, nkSym, nkIdent

import
  compiler/ast,
  compiler/idents,
  compiler/layouter,
  compiler/syntaxes,
  compiler/options

from compiler/msgs import fileInfoIdx
from compiler/pathutils import RelativeFile, AbsoluteFile, toAbsoluteDir
from compiler/syntaxes import setupParsers, TParsers, closeParsers


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


type NameInstance = tuple[name, filename: string, linenum, colnum: int]

var naming_styles_tracker = initTable[string, seq[NameInstance]]()


proc collect_node_naming_style(n: PNode, input_fname: string) =
  ## Collect intances
  let name = n.ident.s
  let normalized = normalize(name)
  # normalized --> (name, input_fname, n.info.line.int, n.info.col.int)
  if not naming_styles_tracker.contains(normalized):
    naming_styles_tracker[normalized] = @[]

  naming_styles_tracker[normalized].add( (name, input_fname, n.info.line.int, n.info.col.int) )

proc check_node_naming_style(n: PNode, input_fname: string) =
  ## Check naming style
  let name = n.ident.s
  let normalized = normalize(name)

  let instances = naming_styles_tracker[normalized]
  if instances.len == 1:
    return

  let old = instances[^2]

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
  # TODO: switch to scanning over tokens?
  #let normalized = normalize(n.ident.s)

  case n.kind
  of nkImportStmt, nkExportStmt, nkCharLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit, nkSym, nkCommentStmt: discard
  of nkIdent:
    collect_node_naming_style(n, input_fname)
    check_node_naming_style(n, input_fname)
  else:
    for s in n.sons:
      check_naming_style(nfconf, s, input_fname)

proc fix_naming_style(nfconf: Config, em: var Emitter, input_fname: string) =
  ## Check and fix names in AST
  for i in 0..em.tokens.high:
    let name = em.tokens[i]
    let k = em.kinds[i]
    if k != ltIdent:
      continue
    let normalized = normalize(name)
    if not naming_styles_tracker.contains normalized:
      continue
    let instances = naming_styles_tracker[normalized]
    if instances.len < 2:
      continue
    #echo normalized
    #echo naming_styles_tracker[normalized].len
    #for i in instances:
    #  echo i
    #assert naming_styles_tracker.contains normalized, normalized
    #echo naming_styles_tracker[normalized]
    #em.tokens[i] = normalized


type
  PrettyOptions = object
    indWidth: int
    maxLineLen: int


proc prettyPrint(nfconf: Config, input_fname, output_fname: string, opt: PrettyOptions): string =
  var conf = newConfigRef()
  let fileIdx = fileInfoIdx(conf, AbsoluteFile input_fname)
  let f = splitFile(output_fname.expandTilde)
  conf.outFile = RelativeFile f.name & f.ext
  conf.outDir = toAbsoluteDir f.dir
  var p: TParsers
  p.parser.em.indWidth = opt.indWidth
  if setupParsers(p, fileIdx, newIdentCache(), conf):
    p.parser.em.maxLineLen = opt.maxLineLen
    var n = parseAll(p)
    check_naming_style(nfconf, n, input_fname)
    fix_naming_style(nfconf, p.parser.em, input_fname)
    # do not call closeParsers(p), instead call directly renderTokens
    result = p.parser.em.renderTokens()

proc nimfmt*(nfconf: Config, input_fname, output_fname: string): string =
  ## Format file
  let cache = newIdentCache()
  var pconf = newConfigRef()
  #let ast = parseString(input, cache, pconf)
  let opts = PrettyOptions(maxLineLen: 80, indWidth: 2)
  return prettyPrint(nfconf, input_fname, output_fname, opts)

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
      output = nimfmt(conf, input_fn, output_fn)

    # FIXME https://github.com/nim-lang/Nim/pull/12365
    if output.len == 0:
      echo "Nothing to write"
      return

    if write_to_stdout:
      echo output

    else:
      if not allow_overwrite and (output_fn.fileExists or output_fn.dirExists):
        echo "Not overwriting $#" % output_fn
      else:
        echo "writing $#" % output_fn
        output_fn.writeFile(output)


if isMainModule:
  main()
