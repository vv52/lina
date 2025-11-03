import std/[os, osproc, dirs, tables]
import std/[strtabs, strutils, strformat]
import std/[math, streams]
import illwill, scan, todo

type
  STATE = enum
    FILE_SELECT, FILE_VIEW, ISSUE_VIEW, DIRECT_VIEW
const
  xMargin = 3
  yMargin = 3
  borderXMargin = 0
  borderYMargin = 0
  Opt: set[ProcessOption] = {
    poUsePath,
    poParentStreams
  }

var
  issueBuffer = initTable[string, seq[Issue]]()
  files : seq[string]
  config = newStringTable()
  line = 3
  fileIndex = 1
  selection = 1
  current : string

proc close() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)
 
illwillInit(fullscreen=true)
setControlCHook(close)
hideCursor()

var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

var currentState : STATE = FILE_SELECT

proc loadConfig : void =
  todo("Load file extensions picked up in scan from config.ini")
  if fileExists("./config.ini"):
    let configFile = newFileStream("./config.ini")
    let options = configFile.readAll()
    let lines = options.split('\n')
    var option : seq[string]
    for line in lines:
      if line != "":
        option = line.split('=')
        config[option[0].strip] = option[1].strip
  else:
    config["scanDir"] = getAppDir()

proc loadFilesFromScanDir =
  for file in walkDirRec(config["scanDir"], relative=true, checkDir=true):
    if file.endsWith(".nim"):
      files.add(file)

proc displayIssue(i : Issue, line : int, filename : string) : int =
  todo("Implement wordwrap")
  case i.level:
  of PRIORITY:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, fgCyan, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
    else:
      tb.write(xMargin, line, resetStyle, fgCyan, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, " ", fgMagenta, i.description)
      tb.write(xMargin, line+2, resetStyle, fgCyan, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+4
  of TODO:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, fgCyan, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
    else:
      tb.write(xMargin, line, resetStyle, fgCyan, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, fgCyan, " ", fgYellow, i.description)
      tb.write(xMargin, line+2, resetStyle, fgCyan, " ", fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+4

proc displayIssues(issues : seq[Issue], filename : string) : void =
  var
    line = yMargin
    issues = scan(filename)
  for i in issues:
    line = displayIssue(i, line, filename)
  if line == yMargin:
    tb.write(xMargin, line, resetStyle, styleBright, fgGreen, "[DONE] ", resetStyle, "Nothing to do")
    line+=2
  tb.setForegroundColor(fgCyan)
  tb.drawRect(borderXMargin, borderYMargin+1, tb.width()-borderXMargin-1, line, doubleStyle=true)
  tb.write(0, 1, styleBright, fgCyan, "//[", fgYellow, filename, fgCyan, "]")
  tb.write(tb.width()-11, line, styleBright, fgCyan, "[TRACKER]")

proc fileSelect : void =
  tb.write(xMargin, 1, styleBright, fgCyan, "Scan Directory: ", fgYellow, config["scanDir"], resetStyle)
  line = 3
  fileIndex = 1
  for file in files:
    if fileIndex == selection:
      tb.write(xMargin, line, styleBright, fgGreen, "  ", $fileIndex, ". ", file, resetStyle)
      current = config["scanDir"] & file
    else:
      tb.write(xMargin, line, "  ", $fileIndex, ". ", file, resetStyle)
    fileIndex+=1
    line+=1

proc fileView(filename : string) : void =
  if not issueBuffer.hasKey(filename):
    issueBuffer[filename] = scan(filename)
  displayIssues(issueBuffer[filename], filename)

proc main(filename : string) : void =
  loadConfig()
  loadFilesFromScanDir()
  while true:
    case currentState:
    of FILE_SELECT:
      fileSelect()
    of FILE_VIEW:
      fileView(current)
    of ISSUE_VIEW:
      discard
    of DIRECT_VIEW:
      fileView(filename)
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Up, Key.K:
      if selection == 1:
        selection = files.len
      else:
        selection -= 1
    of Key.Down, Key.J:
      if selection == files.len:
        selection = 1
      else:
        selection += 1
    of Key.Enter:
      case currentState:
      of FILE_SELECT:
        currentState = FILE_VIEW
      of FILE_VIEW:
        let p = startProcess("hx", args=[current], options=Opt)
        discard p.waitForExit()
        p.close()
        currentState = FILE_SELECT
        # close()
        # currentState = FILE_SELECT
      of ISSUE_VIEW:
        discard
      of DIRECT_VIEW:
        discard
    of Key.Escape, Key.Q: close()
    else:
      discard
    tb.display()
    sleep(20)
    tb.clear()

when isMainModule:
  let params = commandLineParams()
  if params.len == 1:
    currentState = DIRECT_VIEW
    main(params[0])
  else:
    main("./test.nim")
