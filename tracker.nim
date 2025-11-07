import std/[os, osproc, streams, unicode]
import std/[strutils, sequtils, strtabs, tables]
import illwill, scan, todo

todo("simple ui mode", "no special unicode symbols")
todo("FILE_EXPLORE", "expand FILE_SELECT into dired territory")
todo("FILE_PIN / BOOKMARK", "FILE_RECENT but user-defined files")

type
  STATE = enum
    FILE_SELECT, FILE_VIEW, ISSUE_VIEW, DIRECT_VIEW, FILE_RECENT
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
  files, recentFiles : seq[string]
  config = newStringTable()
  line = 3
  fileIndex = 1
  selection = 1
  issueSelection = 1
  current : string
  flash = 32
  historyFile = "history.txt"

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
  config["scanDir"] = getAppDir()   # ./ | /usr/user/home/
  config["editor"] = "hx"           # hx | vi | vim | emacs | {any editor that supports +x}
  config["controls"] = "true"       # true | false
  config["extensions"] = ".nim,.py" # .ext,.ext,... | {empty for *}
  config["arrow"] = "false"         # true | false
  config["flash"] = "false"         # true | false
  config["history"] = "10"          # 0 .. maxInt
  config["ui"] = "nerd"             # nerd | simple
  config["return"] = "file"         # file | select | recent
  if fileExists("./config.ini"):
    let configFile = newFileStream("./config.ini")
    let options = configFile.readAll()
    let lines = options.split('\n')
    var option : seq[string]
    for line in lines:
      if line != "":
        option = line.split('=')
        config[option[0].strip] = option[1].strip
  if not fileExists(historyFile):
    writeFile(historyFile, "")

proc loadFilesFromScanDir =
  for file in walkDirRec(config["scanDir"], relative=true, checkDir=true):
    for extension in config["extensions"].split(","):
      if file.endsWith(extension):
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

proc displayIssues(issues : seq[Issue], filename : string) : int =
  var
    line = yMargin
    issues = scan(filename)
    count = 1
  fileIssues = initTable[int, (int, int)]() # [issueIndex, (terminalLine, fileLine)]
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
  return line
  
proc displayControls(offset : int = 0) =
  if config["controls"] == "true":
    tb.write(xMargin-1, line+offset, styleBright, fgGreen, "[Enter] ", resetStyle, fgCyan, "Goto")
    tb.write(xMargin-1+14, line+offset, styleBright, fgYellow, "[\u2191/\u2193/\u2190/\u2192] ", resetStyle, fgCyan, "Select")
    tb.write(xMargin-1+14+18, line+offset, styleBright, fgMagenta, "[Esc] ", resetStyle, fgCyan, "Back")
    tb.write(xMargin-1+14+18+12, line+offset, styleBright, fgRed, "[Q] ", resetStyle, fgCyan, "Quit")
      
proc displayArrows =
  if config["arrow"] == "true":
    case config["flash"]:
    of "true":
      if flash > 16:
        tb.write(borderXMargin, toInt(line / 2), fgYellow, "\u25c1")
        tb.write(tb.width()-borderXMargin-1, toInt(line / 2), fgYellow, "\u25b7")
      flash -= 1
      if flash == 0: flash = 32
    of "false":
      tb.write(borderXMargin, toInt(line / 2), fgYellow, "\u25c1")
      tb.write(tb.width()-borderXMargin-1, toInt(line / 2), fgYellow, "\u25b7")
  
proc fileSelect : void =
  tb.write(xMargin, 1, styleBright, fgCyan, "\u{f0969} Scan Directory: ", fgYellow, config["scanDir"], resetStyle)
  line = 3
  fileIndex = 1
  for file in files:
    if fileIndex == selection:
      tb.write(xMargin, line, resetStyle, styleBright, fgGreen, "  ", $fileIndex, ". ", file, resetStyle)
      current = config["scanDir"] & file
    else:
      tb.write(xMargin, line, resetStyle, "  ", $fileIndex, ". ", file, resetStyle)
    fileIndex+=1
    line+=1
  tb.write(tb.width()-11, 1, styleBright, fgCyan, "[TRACKER]")
  displayControls(1)

proc truncateRecentFiles : void =
  if recentFiles.len > config["history"].parseInt():
    recentFiles.delete(config["history"].parseInt() .. recentFiles.len-1)

proc enterFileAndReturn : void =
  var fileArgs : seq[string]
  if fileIssues.len == 0:
    fileArgs = @[current]
  else:
    fileArgs = @["+" & $fileIssues[issueSelection][1], current]
  let p = startProcess(config["editor"], args=fileArgs, options=Opt)
  discard p.waitForExit()
  closeNoQuit()
  p.close()

proc recordToRecentFilesInMemory : void =
  let history = readFile(historyFile)
  recentFiles = history.split('\n')
  recentFiles.insert(current, 0)
  recentFiles = recentFiles.deduplicate()

proc writeHistoryToDisk : void =
  let f = open(historyFile, fmWrite)
  defer: f.close()
  for file in recentFiles:
    f.writeLine(file)

proc updateHistory : void =
  recordToRecentFilesInMemory()
  truncateRecentFiles()
  writeHistoryToDisk()
    
proc fileRecent : void =
  tb.write(xMargin, 1, styleBright, fgCyan, "\u{f0abb} Recent Files", resetStyle)
  line = 3
  fileIndex = 1
  let history = readFile(historyFile)
  recentFiles = history.split('\n')
  truncateRecentFiles()
  for file in recentFiles:
    if not file.isEmptyOrWhitespace:
      if fileIndex == selection:
        tb.write(xMargin, line, resetStyle, styleBright, fgGreen, "  ", $fileIndex, ". ", file, resetStyle)
        current = file
      else:
        tb.write(xMargin, line, resetStyle, "  ", $fileIndex, ". ", file, resetStyle)
      fileIndex+=1
      line+=1
  tb.write(tb.width()-11, 1, styleBright, fgCyan, "[TRACKER]")
  displayControls(1)

proc displayCursor : void =
  if fileIssues.len > 1:
    tb[xMargin-1, fileIssues[issueSelection][0]] = TerminalChar(ch: "⩺".runeAt(0), fg: fgGreen, bg: bgNone, style: {styleBright})

proc fileView(filename : string) : void =
  if not issueBuffer.hasKey(filename):
    issueBuffer[filename] = scan(filename)
  line = displayIssues(issueBuffer[filename], filename)
  displayCursor()
  displayControls(2)
  displayArrows()

proc fileExplore : void =
  tb.write(tb.width()-11, line, styleBright, fgCyan, "[EXPLORE]")
  todo("implement FILE_EXPLORE mode", "basically DIRED")

proc displayCalendar : void =
  let calOut = execCmdEx("cal --color=always")
  let calLines = calOut[0].split('\n')
  let halfW = (tb.width() / 2).toInt()
  let halfH = (tb.height() / 2).toInt()
  tb.setBackgroundColor(bgBlack)
  tb.fill(halfW - 12, halfH - 5, halfW + 11, halfH + 4, " ")
  tb.setForegroundColor(fgCyan)
  tb.drawRect(halfW - 12, halfH - 5, halfW + 11, halfH + 4, doubleStyle=true)
  var rowNum = 0
  for row in calLines:
    if row.contains("[7m"):
      var splitRow = row.replace("[7m", ",").replace("[0m", ",").split(',')
      tb.write(halfW - 10, halfH - 4 + rowNum, fgYellow, splitRow[0], bgYellow, fgBlack, splitRow[1], bgBlack, fgYellow, splitRow[2])
    else:
      tb.write(halfW - 10, halfH - 4 + rowNum, fgWhite, row)
    rowNum += 1
  var key = Key.None
  while not @[Key.C, Key.Escape].contains(key):
    tb.display()
    sleep(20)
    key = getKey()
    if key == Key.Q: close()

proc main(filename : string) : void =
  while true:
    tb.clear()
    var key = getKey()
    case currentState:
    of FILE_SELECT:
      fileSelect()
      case key
      of Key.None: discard
      of Key.CtrlR: loadConfig()
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
      of Key.Left, Key.H, Key.Right, Key.L:
        currentState = FILE_RECENT
        selection = 1
      of Key.Enter, Key.Space:
        issueSelection = 1
        currentState = FILE_VIEW
      of Key.C: displayCalendar()
      of Key.Escape, Key.Q: close()
      else:
        discard
    of FILE_RECENT:
      fileRecent()
      case key
      of Key.None: discard
      of Key.CtrlR: loadConfig()
      of Key.Up, Key.K:
        if selection == 1:
          selection = recentFiles.len
        else:
          selection -= 1
      of Key.Down, Key.J:
        if selection == recentFiles.len:
          selection = 1
        else:
          selection += 1
      of Key.Left, Key.H, Key.Right, Key.L:
        currentState = FILE_SELECT
        selection = 1
      of Key.Enter, Key.Space:
        issueSelection = 1
        currentState = FILE_VIEW
      of Key.C: displayCalendar()
      of Key.Escape, Key.Q: close()
      else:
        discard
    of FILE_VIEW:
      fileView(current)
      case key
      of Key.None: discard
      of Key.CtrlR: loadConfig()
      of Key.Up, Key.K:
        if issueSelection == 1:
          issueSelection = fileIssues.len
        else:
          issueSelection -= 1
      of Key.Down, Key.J:
        if issueSelection == fileIssues.len:
          issueSelection = 1
        else:
          issueSelection += 1
      of Key.Left, Key.H:
        if selection == 1:
          selection = files.len
        else:
          selection -= 1
        issueSelection = 1
        currentState = FILE_VIEW
        current = config["scanDir"] & files[selection-1]
      of Key.Right, Key.L:
        if selection == files.len:
          selection = 1
        else:
          selection += 1
        issueSelection = 1
        currentState = FILE_VIEW
        current = config["scanDir"] & files[selection-1]
      of Key.Enter, Key.Space:
        enterFileAndReturn()
        updateHistory()
        var temp = selection
        initProgram()
        case config["return"]:
        of "file":
          selection = temp
          currentState = FILE_VIEW
        of "select":
          currentState = FILE_SELECT
        of "recent":
          currentState = FILE_RECENT
        else:
          echo """CONFIG ERROR: 'return' must be 'file', 'select', or 'return'"""
      of Key.C: displayCalendar()
      of Key.Escape:
        currentState = FILE_SELECT
      of Key.Q: close()
      else:
        discard
    of ISSUE_VIEW:
      discard
    of DIRECT_VIEW:
      fileView(filename)
    tb.display()
    sleep(20)

when isMainModule:
  initProgram()
  loadConfig()
  loadFilesFromScanDir()
  let params = commandLineParams()
  if params.len == 1:
    currentState = DIRECT_VIEW
    current = params[0]
    main(current)
  else:
    main("")
