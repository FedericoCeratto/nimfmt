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

from sequtils import toSeq
from algorithm import reversed

const version = "0.2.0"

from compiler/ast import PNode, nkImportStmt, nkExportStmt, nkCharLit,
    nkUInt64Lit, nkFloatLit, nkFloat128Lit, nkStrLit, nkTripleStrLit, nkSym, nkIdent

import
  compiler/ast,
  compiler/idents,
  compiler/layouter,
  compiler/syntaxes,
  compiler/options

from compiler/msgs import fileInfoIdx
from compiler/pathutils import RelativeFile, AbsoluteFile, toAbsoluteDir
from compiler/syntaxes import setupParser, Parser, closeParser

const default_conf_search_fns = "./.nimfmt.cfg ~/.config/nimfmt.cfg ~/.nimfmt.cfg /etc/nimfmt.cfg"


proc writeHelp(exit_val = 0) =
  ## Write help and quit
  let name = getAppFilename().extractFilename()
  echo "nimfmt v. $#  -  Nim style tool" % version
  echo """
  Usage: $# <filename.nim> [<filename.nim> ... ]
  [ -p=<prefix> ]        output file prefix
  [ -s=<suffix> ]        output file suffix
  [ -c=<filename>,... ]  configuration file search locations (default: )
  [ -i ]                 update files in-place (dangerous!)
  [ -w ]                 overwrite existing files (automatically enabled when using -i)
  [-d]                   debug
  [-v]                   version
  [-h]                   this help

  If any of -p ..., -s ... or -i are specified the output will be written to disk,
  otherwise to stdout
  """ % [name]
  quit(exit_val)


type
  NameInstance = tuple[filename: string, linenum, colnum: int]
  NameInstances = seq[NameInstance]
  Tracker = OrderedTable[string, NameInstances]

var naming_styles_tracker = initTable[string, Tracker]()
## normalized name -> name -> NameInstance

proc nimnormalize(name: string): string =
  ## Normalize identifier removing underscores and preserving the first char
  result = newString(name.len)
  var o = 1
  result[0] = name[0]
  for c in name[1..^1]:
    if c.isUpperAscii():
      result[o] = c.toLowerAscii()
      inc o
    elif c == '_':
      discard # skip without increasing o
    else:
      result[o] = c
      inc o
  result.set_len(o)

proc collect_node_naming_style(n: PNode, input_fname: string) =
  ## Collect intances
  let name = n.ident.s
  let normalized = nimnormalize(name)
  # normalized --> (name, input_fname, n.info.line.int, n.info.col.int)
  if not naming_styles_tracker.contains(normalized):
    naming_styles_tracker[normalized] = initOrderedTable[string, NameInstances]()
  if not naming_styles_tracker[normalized].contains(name):
    naming_styles_tracker[normalized][name] = @[]

  let n: NameInstance = (input_fname, n.info.line.int, n.info.col.int)
  # naming_styles_tracker[normalized].mgetOrPut(name, @[]).add(n)
  naming_styles_tracker[normalized][name].add(n)

proc check_node_naming_style(n: PNode, input_fname: string) =
  ## Check naming style for one leaf node
  let name = n.ident.s
  let normalized = nimnormalize(name)

  let instances: Tracker = naming_styles_tracker[normalized]
  if instances.len == 1:
    return

  var names = ""
  var old: NameInstance
  for n, o in instances.pairs:
    if n != name:
      if names == "":
        names.add n
        old = o[0]
      else:
        names.add(", " & n)

  let msg =
    if input_fname == "":
      # Only one file (or stdin) is being processed
      "Warning: $# at $#:$# also appears as $# at $#:$#" % [
        name, $n.info.line, $n.info.col,
        names, $old.linenum, $old.colnum
      ]
    else:
      "Warning: $# at $#:$#:$# also appears as $# at $#:$#:$#" % [
        name, input_fname, $n.info.line, $n.info.col,
        names, $old.filename, $old.linenum, $old.colnum
      ]

  stderr.writeLine msg

proc collect_naming_style(nfconf: Config, n: PNode, input_fname: string) =
  ## Recursively collect names in AST
  # TODO: switch to scanning over tokens?
  case n.kind
  of nkImportStmt, nkExportStmt, nkCharLit..nkUInt64Lit,
      nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit, nkSym,
      nkCommentStmt: discard
  of nkIdent:
    collect_node_naming_style(n, input_fname)
  else:
    for s in n.sons:
      collect_naming_style(nfconf, s, input_fname)

proc check_naming_style(nfconf: Config, n: PNode, input_fname: string) =
  ## Recursively check names in AST
  # TODO: switch to scanning over tokens?
  case n.kind
  of nkImportStmt, nkExportStmt, nkCharLit..nkUInt64Lit,
      nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit, nkSym,
      nkCommentStmt: discard
  of nkIdent:
    check_node_naming_style(n, input_fname)
  else:
    for s in n.sons:
      check_naming_style(nfconf, s, input_fname)

proc fix_naming_style(nfconf: Config, em: var Emitter, input_fname: string) =
  ## Check and fix names in AST
  for v in naming_styles_tracker.mvalues:
    v.sort(proc(a, b: tuple[key: string, val: NameInstances]): int = a.val.len - b.val.len)

  for i in 0..em.tokens.high:
    let name = em.tokens[i]
    let k = em.kinds[i]
    if k != ltIdent:
      continue
    let normalized = nimnormalize(name)
    if not naming_styles_tracker.contains normalized:
      continue
    let instances: Tracker = naming_styles_tracker[normalized]
    if true: # pick the most popular
      if instances.len < 2:
        continue

      case nfconf.getSectionValue("", "proc_naming_style")
      of "most_popular", "":
        let choices = toSeq(pairs(naming_styles_tracker[normalized]))
        let last = choices[^1]
        if last[1].len == choices[^2][1].len:
          # the best candidate has the same popularity as the second best
          continue # no point in changing style

        em.tokens[i] = last[0]

      of "snake_case":
        var selected = ""
        for sname, ni in naming_styles_tracker[normalized]:
          if sname != sname.toLowerAscii:
            continue # ignore non snake
          if sname.len > selected.len:
            selected = sname # pick the longest
        if selected.len > 0:
          em.tokens[i] = selected

      else:
        echo "Error: unexpected proc_naming_style"
        quit(1)


type
  PrettyOptions = object
    indWidth: int
    maxLineLen: int


proc nimfmt*(nfconf: Config, input_fname, output_fname: string): string =
  ## Format file
  let cache = newIdentCache()
  var pconf = newConfigRef()
  let opt = PrettyOptions(maxLineLen: 80, indWidth: 2)
  var conf = newConfigRef()
  let fileIdx = fileInfoIdx(conf, AbsoluteFile input_fname)
  let f = splitFile(output_fname.expandTilde)
  conf.outFile = RelativeFile f.name & f.ext
  conf.outDir = toAbsoluteDir f.dir
  var p: Parser
  p.em.indWidth = opt.indWidth
  if setupParser(p, fileIdx, newIdentCache(), conf):
    p.em.maxLineLen = opt.maxLineLen
    var n = parseAll(p)

    collect_naming_style(nfconf, n, input_fname)
    case nfconf.getSectionValue("", "fix_naming_style")
    of "":
      echo "Hint: create a ~/.nimfmt.cfg file to set fix_naming_style"
      check_naming_style(nfconf, n, input_fname)
    of "no":
      check_naming_style(nfconf, n, input_fname)
    of "auto", "ask":
      fix_naming_style(nfconf, p.em, input_fname)

    # do not call closeParsers(p), instead call directly renderTokens
    result = p.em.renderTokens()


proc load_config_file(fnames: seq[string], debug = false): Config =
  ## Load config file
  if fnames.len > 0:
    for rel_fn in fnames:
      let fn = expandTilde(rel_fn)
      if fileExists(fn):
        if debug:
          echo fmt"Reading {fn}"
        return loadConfig(fn)
    echo "Error: configuration file not found"
    quit(1)

  for rel_fn in default_conf_search_fns.splitWhitespace():
    let fn = expandTilde(rel_fn)
    if fileExists(fn):
      if debug:
        echo fmt"Reading {fn}"
      return loadConfig(fn)

  return newConfig()


proc main() =
  ## Run nimfmt from CLI
  var
    debug = false
    input_fnames: seq[string] = @[]
    in_place = false
    suffix = ""
    prefix = ""
    allow_overwrite = false
    conf_search_fns: seq[string] = @[]

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
        writeHelp()
      of "version", "v":
        echo version
      of "prefix", "p":
        prefix = val
      of "suffix", "s":
        suffix = val
      of "configfiles", "c":
        conf_search_fns = val.split(",")
      of "i":
        in_place = true
        allow_overwrite = true
      of "d":
        debug = true
      of "w":
        allow_overwrite = true
      else:
        writeHelp(1)

    of cmdEnd:
      quit(1)

  if input_fnames.len == 0:
    echo "Please specify at least an input file. Only files ending with .nim are parsed.\n"
    writeHelp(1)

  let conf = load_config_file(conf_search_fns, debug)

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
