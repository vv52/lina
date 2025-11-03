import std/[os, osproc, strutils, strformat]
import illwill, scan

const
  xMargin = 2
  yMargin = 2

proc close() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)
 
illwillInit(fullscreen=true)
setControlCHook(close)
hideCursor()

var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

proc displayIssue(i : Issue, line : int, filename : string) : int =
  case i.level:
  of PRIORITY:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, border, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+2
    else:
      tb.write(xMargin, line, resetStyle, fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, border, " ", fgMagenta, i.description)
      tb.write(xMargin, line+2, resetStyle, fgCyan, border, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
  of TODO:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, border, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+2
    else:
      tb.write(xMargin, line, resetStyle, fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, border, " ", fgYellow, i.description)
      tb.write(xMargin, line+2, resetStyle, fgCyan, border, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3

proc displayIssues(issues : seq[Issue], filename : string) : void =
  var
    line = yMargin
    length = terminalWidth() - 10 - filename.len
    spacer = "_".repeat(length)
    issues = scan(filename)
  tb.write(xMargin, line, styleBright, fgCyan, "//_FILE_[", fgYellow, filename, fgCyan, "]", spacer)
  tb.write(xMargin, line+1, fgCyan, border)
  line+=2
  for i in issues:
    line = displayIssue(i, line, filename)
  length = terminalWidth() - 12
  spacer = "_".repeat(length)
  tb.write(xMargin, line, styleBright, fgCyan, "\\\\_", spacer, "_TRACKER_")

proc main =
  var filename = "./test.nim"
  var issues = scan(filename)
  displayIssues(issues, filename)
  tb.display()
  # while true:
  #   var key = getKey()
  #   case key
  #   of Key.None: discard
  #   # of Key.Enter: displayIssue(issues[0], filename)
  #   of Key.Escape, Key.Q: close()
  #   else:
  #     discard
  #   tb.display()
  #   sleep(20)

when isMainModule:
  main()
