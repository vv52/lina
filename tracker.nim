import std/[os, osproc, streams, unicode]
import std/[strutils, strtabs, tables]
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
  tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  currentState : STATE = FILE_SELECT
  issueBuffer = initTable[string, seq[Issue]]()
  fileIssues = initTable[int, (int, int)]() # [issueIndex, (terminalLine, fileLine)]
  files : seq[string]
  config = newStringTable()
  line = 3
  fileIndex = 1
  selection = 1
  issueSelection = 1
  current : string

proc close() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc closeNoQuit() {.noconv.} =
  illwillDeinit()
  showCursor()

proc initProgram =
  illwillInit(fullscreen=true)
  setControlCHook(close)
  hideCursor()
  tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  tb.clear()
  fileIssues = initTable[int, (int, int)]()
  selection = 1
  issueSelection = 1


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
    count = 1
  for i in issues:
    fileIssues[count] = (line, i.line)
    line = displayIssue(i, line, filename)
    count+=1
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
  tb.setForegroundColor(fgCyan)
  tb.drawRect(borderXMargin, borderYMargin+1, tb.width()-borderXMargin-1, line+1, doubleStyle=true)
  tb.write(tb.width()-11, line+1, styleBright, fgCyan, "[TRACKER]")


proc displayCursor : void =
  if fileIssues.len > 1:
    tb[xMargin-1, fileIssues[issueSelection][0]] = TerminalChar(ch: "⩺".runeAt(0), fg: fgGreen, bg: bgNone, style: {styleBright})

proc fileView(filename : string) : void =
  if not issueBuffer.hasKey(filename):
    issueBuffer[filename] = scan(filename)
  displayIssues(issueBuffer[filename], filename)
  displayCursor()

proc main(filename : string) : void =
  initProgram()
  loadConfig()
  loadFilesFromScanDir()
  while true:
    tb.clear()
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
      case currentState:
      of FILE_SELECT:
        if selection == 1:
          selection = files.len
        else:
          selection -= 1
      of FILE_VIEW:
        if issueSelection == 1:
          issueSelection = fileIssues.len
        else:
          issueSelection -= 1
      of ISSUE_VIEW:
        discard
      of DIRECT_VIEW:
        discard
    of Key.Down, Key.J:
      case currentState:
      of FILE_SELECT:
        if selection == files.len:
          selection = 1
        else:
          selection += 1
      of FILE_VIEW:
        if issueSelection == fileIssues.len:
          issueSelection = 1
        else:
          issueSelection += 1
      of ISSUE_VIEW:
        discard
      of DIRECT_VIEW:
        discard
    of Key.Enter:
      case currentState:
      of FILE_SELECT:
        currentState = FILE_VIEW
      of FILE_VIEW:
        let p = startProcess("hx", args=["+" & $fileIssues[issueSelection][1], current], options=Opt)
        discard p.waitForExit()
        closeNoQuit()
        p.close()
        initProgram()
        currentState = FILE_SELECT
      of ISSUE_VIEW:
        discard
      of DIRECT_VIEW:
        let p = startProcess("hx", args=[current], options=Opt)
        discard p.waitForExit()
        closeNoQuit()
        p.close()
        quit(0)
    of Key.Escape, Key.Q: close()
    else:
      discard
    tb.display()
    sleep(20)

when isMainModule:
  let params = commandLineParams()
  if params.len == 1:
    currentState = DIRECT_VIEW
    current = params[0]
    main(current)
  else:
    main("./test.nim")
