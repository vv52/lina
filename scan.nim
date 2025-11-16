import std/[os, re, streams, strutils]
import std/[sequtils, terminal]

type
  PRIORITY_LEVEL* = enum
    TODO, PRIORITY
  Issue* = object
    line* : int
    message* : string
    description* : string = ""
    level* : PRIORITY_LEVEL = TODO
    # todo("context*: seq[string]", "config-defined lines before/after todo")

const
  todoHead = 6
  todoTail = 2
  priorityHead = 10
  priorityTail = 2
  descSep = """", """" 
  icon* = " \u21b3 \ueae9 "
  border* = "|| "

var
  todoPattern = re"todo\(.+\)"
  priorityPattern = re"priority\(.+\)"
  line : string
  count, i = 0
  matches: array[1, string]
  todos, priorities : string
  contents : seq[string]

proc printIssue(i : Issue, filename : string) : void =
  case i.level:
  of PRIORITY:
    if i.description == "":
      styledEcho fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line
    else:
      styledEcho fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message
      styledEcho fgCyan, border, fgMagenta, i.description
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line
  of TODO:
    if i.description == "":
      styledEcho fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, i.message
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line
    else:          
      styledEcho fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, i.message
      styledEcho fgCyan, border, fgYellow, i.description
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line
  styledEcho fgCyan, border
  
proc scan*(filename : string) : seq[Issue]  =
  var
    fs = newFileStream(filename, fmRead)
    todoIssues, priorityIssues : seq[Issue]
  line = ""
  count = 0
  i = 0
  if not isNil(fs):
    while fs.readLine(line):
      count += 1
      i = find(line, priorityPattern, matches, start=0)
      if i >= 0:
        priorities = line[i+priorityHead .. line.len-1-priorityTail]
        contents = splitLines(replace(priorities, descSep, by="\n"))
        if contents.len > 1:
          priorityIssues.add(Issue(line : count, message : contents[0], description : contents[1], level : PRIORITY))
        else:
          priorityIssues.add(Issue(line : count, message : contents[0], level : PRIORITY))
      i = find(line, todoPattern, matches, start=0)
      if i >= 0:
        todos = line[i+todoHead .. line.len-1-todoTail]
        contents = splitLines(replace(todos, descSep, by="\n"))
        if contents.len > 1:
          todoIssues.add(Issue(line : count, message : contents[0], description : contents[1], level : TODO))
        else:
          todoIssues.add(Issue(line : count, message : contents[0], level : TODO))
    fs.close()
  return concat(priorityIssues, todoIssues)

proc hasTodo*(filename : string) : bool  =
  let
    file = readFile(filename.expandTilde.expandFilename)
    p = find(file, priorityPattern, matches, start=0)
    t = find(file, todoPattern, matches, start=0)
  return (p >= 0) or (t >= 0)
    
proc printFileStatus*(filename : string) : void =
  var length = terminalWidth() - 10 - filename.len
  var spacer = "_".repeat(length)
  styledEcho styleBright, fgCyan, "//_FILE_[", fgYellow, filename, fgCyan, "]", spacer
  styledEcho fgCyan, border
  var issues = scan(filename)
  for i in issues:
    printIssue(i, filename)
  if issues.len == 0:
    styledEcho fgCyan, border, styleBright, fgGreen, "[DONE] ", resetStyle, "Nothing to do"
  length = terminalWidth() - 12
  spacer = "_".repeat(length)
  styledEcho styleBright, fgCyan, "\\\\_", spacer, "_TRACKER_"

# printFileStatus(filename)
