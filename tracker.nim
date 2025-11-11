import std/[os, osproc, streams, times, unicode]
import std/[strutils, sequtils, strtabs, tables]
import illwill, stacks, scan, todo

todo("FILE_PIN / BOOKMARK", "FILE_RECENT but user-defined files")

type
  STATE = enum
    FILE_SELECT, FILE_VIEW, ISSUE_VIEW, FILE_EXPLORE, DIRECT_VIEW, FILE_RECENT
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
  dirIcon = "\ueaf7 "
  codeIcon = "\ueae9 " 
  symbolicIcon = "\ueb15 "
  folderIcon = "\uea83 "
  fileIcon = "\uea7b "
  notifIcon = "\uf444"
  nextDirIcon = " \uf101"
  fileSelectIcon = "\u{f0969} "
  fileRecentIcon = "\u{f0abb} "
  cursor = "⩺"
  separator = " \ueb3b "
  arrowLeft = "\u25c1"
  arrowRight = "\u25b7"
  arrowUp = "\u25b3"
  arrowDown = "\u25bd"
  # verticalDots = "\u22ee"
  verticalDots = "\u250a"
  inFileIcon = " \u21b3 "
  symlinkArrow = " \u27f6 "
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
  itemSelection = 1
  current : string
  flash = 32
  historyFile = "history.txt"
  currentPath : string
  currentDirPaths : seq[(PathComponent, string)]
  lastPath = Stack[string]()
  selectedItems : seq[(PathComponent, string)]
  copiedItems : seq[(PathComponent, string)]
  top = 0
  bottom = tb.height - 2 - 1
  pos = 0
  posMax = 0
let
  bottomReset = tb.height - 2 - 1
  scrollStartUp = (tb.height / 3).toInt + 1
  scrollStartDown = ((tb.height / 3) * 2).toInt
  verticalDotsOffset = ((tb.height - 2) / 2).toInt + 2

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
  setCurrentDir(getAppDir())
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
  config["default"] = "select"      # file | select | recent | explore (not implemented)
  var returnPath = currentPath
  setCurrentDir(getAppDir())
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
  if config["ui"] == "simple":
    dirIcon = "dir  "
    codeIcon = "code " 
    symbolicIcon = "*"
    folderIcon = "dir  "
    fileIcon = "file "
    notifIcon = "'"
    nextDirIcon = " >>"
    fileSelectIcon = ""
    fileRecentIcon = ""
    cursor = ">"
    separator = "--"
    arrowLeft = "<"
    arrowRight = ">"
    arrowUp = "^"
    arrowDown = "v"
    inFileIcon = "-->"
    verticalDots = "|"
  if not returnPath.isEmptyOrWhitespace:
    setCurrentDir(returnPath)
    
proc loadFilesFromScanDir =
  files.setLen(0)
  for file in walkDirRec(config["scanDir"].expandTilde.expandFilename, relative=true, checkDir=true):
    for extension in config["extensions"].split(","):
      if file.endsWith(extension):
        files.add(file)

proc resetProgram =
  loadConfig()
  loadFilesFromScanDir()
  tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  
proc formatPermissions(p : set[FilePermission]) : string =
  var output = "---------"
  if p.contains(fpUserRead):
    output[0] = 'r'
  if p.contains(fpUserWrite):
    output[1] = 'w'
  if p.contains(fpUserExec):
    output[2] = 'x'
  if p.contains(fpGroupRead):
    output[3] = 'r'
  if p.contains(fpGroupWrite):
    output[4] = 'w'
  if p.contains(fpGroupExec):
    output[5] = 'x'
  if p.contains(fpOthersRead):
    output[6] = 'r'
  if p.contains(fpOthersWrite):
    output[7] = 'w'
  if p.contains(fpOthersExec):
    output[8] = 'x'
  return output

proc formatKind(k : PathComponent) : string =
  case k:
  of pcFile:
    return "File"
  of pcLinkToFile:
    return "*File"
  of pcDir:
    return "Directory"
  of pcLinkToDir:
    return "*Directory"

proc displayIssue(i : Issue, line : int, filename : string) : int =
  todo("Implement wordwrap")
  case i.level:
  of PRIORITY:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
    else:
      tb.write(xMargin, line, resetStyle, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, " ", fgMagenta, i.description)
      tb.write(xMargin, line+2, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, fgCyan, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+4
  of TODO:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, fgCyan, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
    else:
      tb.write(xMargin, line, resetStyle, styleBright, fgYellow, "[TODO] ", resetStyle, i.message)
      tb.write(xMargin, line+1, resetStyle, " ", fgYellow, i.description)
      tb.write(xMargin, line+2, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, fgCyan, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+4

proc displayIssues(issues : seq[Issue], filename : string) : int =
  todo("Implement pages if longer than screen")
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
        tb.write(borderXMargin, toInt(line / 2), fgYellow, arrowLeft)
        tb.write(tb.width()-borderXMargin-1, toInt(line / 2), fgYellow, arrowRight)
      flash -= 1
      if flash == 0: flash = 32
    of "false":
      tb.write(borderXMargin, toInt(line / 2), fgYellow, arrowLeft)
      tb.write(tb.width()-borderXMargin-1, toInt(line / 2), fgYellow, arrowRight)
  
proc fileSelect : void =
  pos = 0
  tb.write(xMargin, 1, styleBright, fgCyan, fileSelectIcon, "Scan Directory: ", fgYellow, config["scanDir"], resetStyle)
  tb.write(tb.width - 11, 1, styleBright, fgCyan, "[TRACKER]")
  if selection - 1 >= bottom:
    while selection - 1 >= bottom:
      top += 1
      bottom += 1
  elif selection - 1 < top:
    while selection - 1 < top:
      top -= 1
      bottom -= 1  
  while top + pos < bottom and top + pos < files.len:
    if top + pos + 1 == selection:
      tb.write(xMargin, 3 + pos, resetStyle, styleBright, fgGreen, "  ", $(top + pos + 1), ". ", files[top + pos], resetStyle)
      current = config["scanDir"].expandTilde.expandFilename / files[top + pos]
    else:
      tb.write(xMargin, 3 + pos, resetStyle, "  ", $(top + pos + 1), ". ", files[top + pos], resetStyle)
    pos += 1
  posMax = pos
  if top > 0:
    tb.write(2, 3, fgYellow, arrowUp)
  if bottom < files.len:
    tb.write(2, tb.height - 1, fgYellow, arrowDown)
  if top > 0 or bottom < files.len:
    tb.write(2, verticalDotsOffset, fgCyan, verticalDots)

proc truncateRecentFiles : void =
  if recentFiles.len > config["history"].parseInt():
    recentFiles.delete(config["history"].parseInt() .. recentFiles.len-1)

proc enterFileAndReturn : void =
  if currentState == FILE_EXPLORE:
    var fileArgs = @[currentDirPaths[itemSelection - 1][1]]
    let p = startProcess(config["editor"], args=fileArgs, options=Opt)
    discard p.waitForExit()
    closeNoQuit()
    p.close()
  else:
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
  var returnPath = currentPath
  setCurrentDir(getAppDir())
  let history = readFile(historyFile)
  recentFiles = history.split('\n')
  recentFiles.insert(current.expandTilde.expandFilename, 0)
  recentFiles = recentFiles.deduplicate()
  if not returnPath.isEmptyOrWhitespace:
    setCurrentDir(returnPath)

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
  tb.write(xMargin, 1, styleBright, fgCyan, fileRecentIcon, "Recent Files", resetStyle)
  line = 3
  fileIndex = 1
  let history = readFile(historyFile)
  recentFiles = history.split('\n')
  truncateRecentFiles()
  for file in recentFiles:
    if not file.isEmptyOrWhitespace:
      if fileIndex == selection:
        tb.write(xMargin, line, resetStyle, styleBright, fgGreen, "  ", $fileIndex, ". ", file.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle)
        current = file
      else:
        tb.write(xMargin, line, resetStyle, "  ", $fileIndex, ". ", file.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle)
      fileIndex+=1
      line+=1
  tb.write(tb.width()-11, 1, styleBright, fgCyan, "[TRACKER]")
  displayControls(1)

proc displayCursor : void =
  if fileIssues.len > 1:
    tb[xMargin-1, fileIssues[issueSelection][0]] = TerminalChar(ch: cursor.runeAt(0), fg: fgGreen, bg: bgNone, style: {styleBright})

proc fileView(filename : string) : void =
  if not issueBuffer.hasKey(filename):
    issueBuffer[filename] = scan(filename)
  line = displayIssues(issueBuffer[filename], filename)
  tb.setForegroundColor(fgCyan)
  tb.drawRect(borderXMargin, borderYMargin+1, tb.width()-borderXMargin-1, line, doubleStyle=true)
  tb.write(0, 1, styleBright, fgCyan, "//[", fgYellow, config["scanDir"] / filename.relativePath(config["scanDir"].expandTilde.expandFilename), fgCyan, "]")
  tb.write(tb.width()-11, line, styleBright, fgCyan, "[TRACKER]")
  displayCursor()
  displayControls(2)
  displayArrows()

proc fileExplore : void =
  var
    count = 0
    found = false
  tb.write(tb.width()-11, 1, styleBright, fgCyan, "[EXPLORE]")
  tb.write(2, 1, styleBright, fgGreen, currentPath.lastPathPart, resetStyle)
  tb.write(2, 2, styleBright, fgYellow, dirIcon, currentPath, resetStyle)
  setCurrentDir(currentPath)
  currentDirPaths.setLen(0)
  for item in walkDir(currentPath, relative=false):
    currentDirPaths.add(item)
    if item in copiedItems:
      tb.setBackgroundColor(bgYellow)
    elif item in selectedItems:
      tb.setBackgroundColor(bgMagenta)
    else:
      tb.resetAttributes()
    case item.kind:
    of pcFile:
      for extension in config["extensions"].split(","):
        if item.path.endsWith(extension):
          found = true
          if count + 1 == itemSelection:
            tb.write(4, 3 + count, fgCyan, codeIcon, resetStyle, fgGreen, item.path.relativePath(currentPath), nextDirIcon, " ", config["editor"])
          else:
            tb.write(4, 3 + count, fgCyan, codeIcon, resetStyle, item.path.relativePath(currentPath))
      if not found:
        if count + 1 == itemSelection:
          tb.write(4, 3 + count, fgWhite, fileIcon, resetStyle, fgGreen, item.path.relativePath(currentPath))
        else:
          tb.write(4, 3 + count, fgWhite, fileIcon, resetStyle, item.path.relativePath(currentPath))
      found = false
    of pcLinkToFile:
      for extension in config["extensions"].split(","):
        if item.path.endsWith(extension):
          found = true
          if count + 1 == itemSelection:
            tb.write(4, 3 + count, fgCyan, symbolicIcon, fgMagenta, codeIcon, resetStyle, fgGreen, item.path.relativePath(currentPath), nextDirIcon, " ", config["editor"])
          else:
            tb.write(4, 3 + count, fgCyan, symbolicIcon, fgMagenta, codeIcon, resetStyle, item.path.relativePath(currentPath))
      if not found:
        if count + 1 == itemSelection:
          tb.write(4, 3 + count, fgCyan, symbolicIcon, fgYellow, fileIcon, resetStyle, fgGreen, item.path.relativePath(currentPath))
        else:
          tb.write(4, 3 + count, fgCyan, symbolicIcon, fgYellow, fileIcon, resetStyle, item.path.relativePath(currentPath))
      found = false
    of pcDir:
      if count + 1 == itemSelection:
        tb.write(4, 3 + count, fgYellow, folderIcon, resetStyle, fgGreen, item.path.relativePath(currentPath), nextDirIcon)
      else:
        tb.write(4, 3 + count, fgYellow, folderIcon, resetStyle, item.path.relativePath(currentPath))
    of pcLinkToDir:
      if count + 1 == itemSelection:
        tb.write(4, 3 + count, fgCyan, symbolicIcon, fgBlue, folderIcon, resetStyle, fgGreen, item.path.relativePath(currentPath), nextDirIcon)
      else:
        tb.write(4, 3 + count, fgCyan, symbolicIcon, fgBlue, folderIcon, resetStyle, item.path.relativePath(currentPath))
    count += 1

proc displayFileInfo(f: (PathComponent, string)) : void =
  case f[0]:
  of pcFile, pcLinkToFile:
    let info = getFileInfo(f[1], followSymlink=true)
    tb.setBackgroundColor(bgBlack)
    tb.fill(0, 0, tb.width, tb.height, " ")
    tb.write(2, 1, fgYellow, f[1])
    if f[0] == pcFile:
      tb.write(4, 2, fgCyan, info.kind.formatKind, fgWhite, separator, fgGreen, f[1].relativePath(currentPath))
    else:
      tb.write(4, 2, fgMagenta, f[0].formatKind, fgWhite, separator, fgGreen, f[1].relativePath(currentPath), fgMagenta, symlinkArrow, fgCyan, styleUnderscore, f[1].expandSymlink, resetStyle)
    tb.write(4, 2 + 1, fgBlue, "       Size: ", fgWhite, info.size.formatSize(includeSpace=true))
    tb.write(4, 2 + 2, fgBlue, "Permissions: ", fgWhite, info.permissions.formatPermissions)
    tb.write(4, 2 + 3, fgBlue, "Last Access: ", fgWhite, info.lastAccessTime.format("d MMM yyyy h:mm:ss tt"))
    tb.write(4, 2 + 4, fgBlue, " Last Write: ", fgWhite, info.lastWriteTime.format("d MMM yyyy h:mm:ss tt"))
    tb.write(4, 2 + 5, fgBlue, "    Created: ", fgWhite, info.creationTime.format("d MMM yyyy h:mm:ss tt"))
    tb.write(4, 2 + 6, fgBlue, " Block Size: ", fgWhite, info.blockSize.formatSize(includeSpace=true))
    tb.write(4, 2 + 7, fgBlue, "    File ID: ", fgWhite, $info.id.file)  
    tb.write(4, 2 + 8, fgBlue, "  Device ID: ", fgWhite, $info.id.device)  
    tb.write(4, 2 + 9, fgBlue, " Hard Links: ", fgWhite, $info.linkCount)
  of pcDir, pcLinkToDir:
    discard
  var key = Key.None
  while not @[Key.I, Key.Escape].contains(key):
    tb.display()
    sleep(20)
    key = getKey()
    if key == Key.Q: close()

proc displayFileContents(f: string) : void =
  priority("crashes with pcLinkToDir", "pcLinkToFile doesn't crash but is blank like pcDir")
  let
    fileContents = readFile(f)
    fileLines = fileContents.split('\n')
    maxLen = (($fileLines.len).len * 3) + 4
    lineCountOffset = tb.width - maxLen - 2
    verticalDotsOffset = ((tb.height - 2) / 2).toInt + 2
  var
    fcTop = 0
    fcBottom = tb.height() - 2
    fcPos = 0
    update = false
    lineCount : string
  tb.setBackgroundColor(bgBlack)
  tb.fill(0, 0, tb.width, tb.height, " ")
  tb.write(2, 1, fgYellow, f.relativePath(currentPath))
  tb.setForegroundColor(fgWhite)
  while fcPos < fcBottom and fcPos < fileLines.len - 1:
    tb.write(4, 2 + fcPos, fileLines[fcTop + fcPos])
    fcPos += 1
  tb.display()
  var key = Key.None
  while not @[Key.C, Key.Escape].contains(key):
    key = getKey()
    case key:
    of Key.Q: close()
    of Key.Up, Key.K:
      if fcTop > 0:
        fcTop -= 1
        fcBottom -= 1
        tb.setBackgroundColor(bgBlack)
        tb.fill(0, 0, tb.width, tb.height, " ")
        tb.write(2, 1, fgYellow, f.relativePath(currentPath))
        tb.setForegroundColor(fgWhite)
        fcPos = 0
        while fcTop + fcPos < fcBottom and fcTop + fcPos < fileLines.len - 1:
          tb.write(4, 2 + fcPos, fileLines[fcTop + fcPos])
          fcPos += 1
        update = true
    of Key.Down, Key.J:
      if fcBottom < fileLines.len - 1:
        fcTop += 1
        fcBottom += 1
        tb.setBackgroundColor(bgBlack)
        tb.fill(0, 0, tb.width, tb.height, " ")
        tb.write(2, 1, fgYellow, f.relativePath(currentPath))
        tb.setForegroundColor(fgWhite)
        fcPos = 0
        while fcTop + fcPos < fcBottom and fcTop + fcPos < fileLines.len - 1:
          tb.write(4, 2 + fcPos, fileLines[fcTop + fcPos])
          fcPos += 1
        update = true
    else: discard
    if fcTop > 0:
      tb.write(2, 2, fgYellow, arrowUp)
      update = true
    if fcBottom < fileLines.len - 1:
      tb.write(2, tb.height - 1, fgYellow, arrowDown)
      update = true
    if tb.height < fileLines.len:
      tb.write(2, verticalDotsOffset, fgCyan, verticalDots)
    lineCount = "[" & $fcTop & "-" & $fcBottom & "/" & $(fileLines.len - 1) & "]"
    tb.write(lineCountOffset, 1, fgCyan, lineCount.align(maxLen))
    if update:
      tb.display()
      sleep(10)
      update = false

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
      of Key.CtrlR:
        resetProgram()
      of Key.Up, Key.K:
        if selection == 1:
          selection = files.len
          while bottom < files.len:
            top += 1
            bottom += 1
        # scrollStartUp
        elif selection < scrollStartUp and top > 0:
          top -= 1
          bottom -= 1
          selection -= 1
        # /scrollStartUp
        else:
          selection -= 1
      of Key.Down, Key.J:
        if selection == files.len:
          selection = 1
          while top > 0:
            top -= 1
            bottom -= 1
        elif selection > scrollStartDown and bottom < files.len:
          top += 1
          bottom += 1
          selection += 1
        else:
          selection += 1
      of Key.Left, Key.H, Key.Right, Key.L:
        currentState = FILE_RECENT
        selection = 1
      of Key.Enter, Key.Space:
        issueSelection = 1
        currentState = FILE_VIEW
      of Key.E:
        currentState = FILE_EXPLORE
        currentPath = config["scanDir"].expandTilde.expandFilename
      of Key.C: displayCalendar()
      of Key.Escape, Key.Q: close()
      else:
        discard
    of FILE_RECENT:
      fileRecent()
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
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
        top = 0
        bottom = bottomReset
      of Key.Enter, Key.Space:
        issueSelection = 1
        currentState = FILE_VIEW
      of Key.C: displayCalendar()
      of Key.E:
        currentState = FILE_EXPLORE
        currentPath = config["scanDir"].expandTilde.expandFilename
      of Key.Escape, Key.Q: close()
      else:
        discard
    of FILE_VIEW:
      fileView(current)
      todo("config[\"showDone\"] = true", "false: skip files with no tasks")
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
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
        current = config["scanDir"].expandTilde.expandFilename / files[selection-1]
      of Key.Right, Key.L:
        if selection == files.len:
          selection = 1
        else:
          selection += 1
        issueSelection = 1
        current = config["scanDir"].expandTilde.expandFilename / files[selection-1]
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
      of Key.E:
        currentState = FILE_EXPLORE
        currentPath = config["scanDir"].expandTilde.expandFilename
      of Key.Escape:
        case config["default"]:
        of "select":
          currentState = FILE_SELECT
        of "recent":
          currentState = FILE_RECENT
        else:
          echo """CONFIG ERROR: 'default' must be 'select', 'recent', or 'explore'"""
      of Key.Q: close()
      else:
        discard
    of ISSUE_VIEW:
      discard
    of FILE_EXPLORE:
      fileExplore()
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
      of Key.Up, Key.K:
        if itemSelection == 1:
          itemSelection = currentDirPaths.len
        else: itemSelection -= 1
      of Key.Down, Key.J:
        if itemSelection == currentDirPaths.len:
          itemSelection = 1
        else: itemSelection += 1
      of Key.Left, Key.H:
        if not currentPath.isRootDir and not currentPath.isEmptyOrWhitespace:
          lastPath.push(currentPath)
          currentPath = currentPath.parentDir
          itemSelection = 1
          currentDirPaths.setLen(0)
      of Key.Right, Key.L:
        if currentDirPaths.len > 0:
          case currentDirPaths[itemSelection - 1][0]:
          of pcDir, pcLinkToDir:
            lastPath.push(currentPath)
            currentPath = expandFilename(currentDirPaths[itemSelection - 1][1])
            itemSelection = 1
            currentDirPaths.setLen(0)
          of pcFile, pcLinkToFile:
            for extension in config["extensions"].split(","):
              if currentDirPaths[itemSelection - 1][1].endsWith(extension):
                enterFileAndReturn()
                updateHistory()
                initProgram()
                currentState = FILE_EXPLORE
                setCurrentDir(currentPath)
        else:
          currentPath = lastPath.pop
          itemSelection = 1
          currentDirPaths.setLen(0)
      of Key.I:
        displayFileInfo(currentDirPaths[itemSelection - 1])
      of Key.C:
        displayFileContents(currentDirPaths[itemSelection - 1][1])
      of Key.X:
        if currentDirPaths[itemSelection - 1] in selectedItems:
          selectedItems.keepIf(proc(x: (PathComponent, string)): bool = x != currentDirPaths[itemSelection - 1])
        else:
          selectedItems.add(currentDirPaths[itemSelection - 1])
      of Key.D:
        for item in selectedItems:
          case item[0]:
          of pcFile, pcLinkToFile:
            var success = tryRemoveFile(item[1])
            if not success:
              todo("error popup", "cannot delete {file}")
          of pcDir, pcLinkToDir:
            try:
              removeDir(item[1])
            except:
              todo("error popup", "cannot delete {dir}")
        selectedItems.setLen(0)
      of Key.Y:
        for item in selectedItems:
          if not (item in copiedItems):
            copiedItems.add(item)
      of Key.P:
        if copiedItems.len > 0:
          for item in copiedItems:
            case item[0]:
            of pcFile, pcLinkToFile:
              copyFileToDir(item[1], currentPath)
            of pcDir, pcLinkToDir:
              copyDir(item[1], currentPath / item[1].lastPathPart)
          copiedItems.setLen(0)
          selectedItems.setLen(0)
          itemSelection = 1
        elif selectedItems.len > 0:
          for item in selectedItems:
            case item[0]:
            of pcFile, pcLinkToFile:
              moveFile(item[1], currentPath / item[1].lastPathPart)
            of pcDir, pcLinkToDir:
              moveDir(item[1], currentPath / item[1].lastPathPart)
          selectedItems.setLen(0)
          itemSelection = 1
      of Key.ShiftP:
        if copiedItems.len > 0:
          for item in copiedItems:
            case item[0]:
            of pcFile, pcLinkToFile:
              copyFileToDir(item[1], currentPath)
            of pcDir, pcLinkToDir:
              copyDir(item[1], currentPath / item[1].lastPathPart)
          itemSelection = 1
      of Key.R:
        todo("rename file")
        # for item in selectedItems:
        # 	showCursor()
        # 	tb.setForegroundColor(fgCyan)
        # 	var input = readLine()
        # 	hideCursor()
        # 	# sanitize input
        # 	case item[0]:
        # 	of pcFile, pcLinkToFile:
        # 		# pass input to moveFile
        # 	of pcDir, pcLinkToDir:
        # 		# pass input to moveDir
        # selectedItems.setLen(0)
      of Key.Enter, Key.Space:
        discard
      of Key.Escape:
        if copiedItems.len > 0:
          copiedItems.setLen(0)
        elif selectedItems.len > 0:
          selectedItems.setLen(0)
        else:
          currentState = FILE_RECENT
          setCurrentDir(getAppDir())
      of Key.Q: close()
      else:
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
    todo("of \"explore\"")
    case config["default"]:
    of "select":
      currentState = FILE_SELECT
    of "recent":
      currentState = FILE_RECENT
    else:
      echo """CONFIG ERROR: 'default' must be 'select', 'recent', or 'explore'"""
    main("")
