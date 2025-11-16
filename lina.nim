import std/[os, osproc]
import std/[streams, times, unicode]
import std/[strutils, sequtils, strtabs, tables]
import illwill, stacks, simple_parseopt
import scan, wrap, todo

todo("FILE_PIN", "FILE_RECENT but user-defined files, Key.Asterisk, star ascii, from anywhere")

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
  historyFile = "./history.txt"
  configFile = "./config.ini"
  currentPath : string
  currentDirPaths : seq[(PathComponent, string)]
  lastPath = Stack[string]()
  selectedItems : seq[(PathComponent, string)]
  copiedItems : seq[(PathComponent, string)]
  top = 0
  bottom = tb.height - 2 - 1
  pos = 0
  posMax = 0
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
  config["shell"] = "fish"          # fish | bash | sh | {any shell}
  config["controls"] = "true"       # true | false
  config["extensions"] = ".nim,.py" # .ext,.ext,... | {empty for *}
  config["arrow"] = "false"         # true | false
  config["flash"] = "false"         # true | false
  config["history"] = "10"          # 0 .. maxInt
  config["ui"] = "nerd"             # nerd | simple
  config["return"] = "file"         # file | select | recent
  config["default"] = "select"      # file | select | recent | explore (not implemented)
  config["splash"] = "true"         # true | false
  config["clock"] = "true"          # true | false
  config["todoOnly"] = "false"      # true | false
  var returnPath = currentPath
  discard existsOrCreateDir(getConfigDir() / "lina/")
  setCurrentDir(getConfigDir() / "lina/")
  if fileExists(configFile):
    let configFile = newFileStream("./config.ini")
    let options = configFile.readAll()
    let lines = options.split('\n')
    var option : seq[string]
    for line in lines:
      if line != "":
        option = line.split('=')
        config[option[0].strip] = option[1].strip
    todo("refactor all the filename expand calls")
    # config["scanDir"] = config["scanDir"].expandTilde.expandFilename
  discard existsOrCreateDir(getDataDir() / "lina/")
  setCurrentDir(getDataDir() / "lina/")
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
    separator = " -- "
    arrowLeft = "<"
    arrowRight = ">"
    arrowUp = "^"
    arrowDown = "v"
    inFileIcon = "--> "
    symlinkArrow = " -> "
    verticalDots = "|"
  if not returnPath.isEmptyOrWhitespace:
    setCurrentDir(returnPath)
  else: setCurrentDir(getAppDir())
    
proc loadFilesFromScanDir =
  files.setLen(0)
  for file in walkDirRec(config["scanDir"].expandTilde.expandFilename, relative=false, checkDir=true):
    for extension in config["extensions"].split(","):
      if file.endsWith(extension):
        if config["todoOnly"].parseBool:
          if file.hasTodo:
            files.add(file)
        else:
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
  var add = 0
  case i.level:
  of PRIORITY:
    if i.description == "":
      tb.write(xMargin, line, resetStyle, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      tb.write(xMargin, line+1, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
      result = line+3
    else:
      tb.write(xMargin, line, resetStyle, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, i.message)
      if i.description.len + xMargin + 1 > tb.width:
        var multi = wrap(i.description, tb.width - xMargin - 3)
        for l in multi:
          tb.write(xMargin, line+1+add, resetStyle, " ", fgMagenta, l)
          add += 1
        tb.write(xMargin, line+1+add, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, fgCyan, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
        result = line+3+add
      else:
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
      if i.description.len + xMargin + 1 > tb.width:
        var multi = wrap(i.description, tb.width - xMargin - 3)
        for l in multi:
          tb.write(xMargin, line+1+add, resetStyle, " ", fgYellow, l)
          add += 1
        tb.write(xMargin, line+1+add, resetStyle, " ", inFileIcon, fgCyan, codeIcon, styleUnderscore, fgCyan, filename.relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle, styleBright, fgCyan, ":", $i.line)
        result = line+3+add
      else:
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
  if config["controls"].parseBool:
    tb.write(xMargin-1, line+offset, styleBright, fgGreen, "[Enter] ", resetStyle, fgCyan, "Goto")
    tb.write(xMargin-1+14, line+offset, styleBright, fgYellow, "[\u2191/\u2193/\u2190/\u2192] ", resetStyle, fgCyan, "Select")
    tb.write(xMargin-1+14+18, line+offset, styleBright, fgMagenta, "[Esc] ", resetStyle, fgCyan, "Back")
    tb.write(xMargin-1+14+18+12, line+offset, styleBright, fgRed, "[Q] ", resetStyle, fgCyan, "Quit")
      
proc displayArrows =
  if config["arrow"].parseBool and currentState != DIRECT_VIEW:
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
      tb.write(xMargin, 3 + pos, resetStyle, styleBright, fgGreen, "  ", $(top + pos + 1), ". ", files[top + pos].relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle)
      current = files[top + pos]
      # current = config["scanDir"].expandTilde.expandFilename / files[top + pos]
    else:
      tb.write(xMargin, 3 + pos, resetStyle, "  ", $(top + pos + 1), ". ", files[top + pos].relativePath(config["scanDir"].expandTilde.expandFilename), resetStyle)
    pos += 1
  posMax = pos
  if top > 0:
    tb.write(2, 3, fgYellow, arrowUp)
  if bottom < files.len:
    tb.write(2, tb.height - 1, fgYellow, arrowDown)
  if top > 0 or bottom < files.len:
    tb.write(2, verticalDotsOffset, fgCyan, verticalDots)

proc truncateRecentFiles : void =
  var keep : seq[string]
  for file in recentFiles:
    if fileExists(file):
      keep.add(file)
  if keep.len > config["history"].parseInt():
    keep.delete(config["history"].parseInt() .. keep.len-1)
  recentFiles.setLen(0)
  recentFiles = keep

proc enterShellAndReturn : void =
  if currentState == FILE_EXPLORE:
    let p = startProcess(config["shell"], options=Opt)
    discard p.waitForExit()
    closeNoQuit()
    p.close()

proc editConfig : void =
  var fileArgs = @[getConfigDir() / "lina" / configFile.lastPathPart]
  let p = startProcess(config["editor"], args=fileArgs, options=Opt)
  discard p.waitForExit()
  closeNoQuit()
  p.close()

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
  # setCurrentDir(getConfigDir() / "lina/")
  setCurrentDir(getDataDir() / "lina/")
  let history = readFile(historyFile)
  recentFiles = history.split('\n')
  recentFiles.insert(current.expandTilde.expandFilename, 0)
  recentFiles = recentFiles.deduplicate()
  if not returnPath.isEmptyOrWhitespace:
    setCurrentDir(returnPath)
  else: setCurrentDir(getAppDir())

proc writeHistoryToDisk : void =
  var returnPath = currentPath
  # setCurrentDir(getConfigDir() / "lina/")
  setCurrentDir(getDataDir() / "lina/")
  let f = open(historyFile, fmWrite)
  for file in recentFiles:
    f.writeLine(file)
  f.close()
  if not returnPath.isEmptyOrWhitespace:
    setCurrentDir(returnPath)
  else: setCurrentDir(getAppDir())

proc updateHistory : void =
  recordToRecentFilesInMemory()
  truncateRecentFiles()
  writeHistoryToDisk()
    
proc fileRecent : void =
  tb.write(xMargin, 1, styleBright, fgCyan, fileRecentIcon, "Recent Files", resetStyle)
  line = 3
  fileIndex = 1
  setCurrentDir(getDataDir() / "lina/")
  # setCurrentDir(getConfigDir() / "lina/")
  let history = readFile(historyFile)
  recentFiles.setLen(0)
  recentFiles = history.split('\n')
  recentFiles = recentFiles.deduplicate
  setCurrentDir(getAppDir())
  truncateRecentFiles()
  for file in recentFiles:
    if not file.isEmptyOrWhitespace and fileExists(file):
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
  while not currentPath.dirExists:
    currentPath = currentPath.parentDir
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
    tb.setBackgroundColor(bgNone)
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
    var count = 0
    var size = 0
    for file in walkDir(f[1].expandTilde.expandFilename):
      size += getFilesize(file[1].expandTilde.expandFilename)
      count += 1
    tb.setBackgroundColor(bgNone)
    tb.fill(0, 0, tb.width, tb.height, " ")
    tb.write(2, 1, fgYellow, f[1])
    if f[0] == pcDir:
      tb.write(4, 2, fgCyan, f[0].formatKind, fgWhite, separator, fgGreen, f[1].relativePath(currentPath))
    else:
      tb.write(4, 2, fgMagenta, f[0].formatKind, fgWhite, separator, fgGreen, f[1].relativePath(currentPath), fgMagenta, symlinkArrow, fgCyan, styleUnderscore, f[1].expandSymlink, resetStyle)
    tb.write(4, 2 + 1, fgBlue, "       Size: ", fgWhite, size.formatSize(includeSpace=true))
    tb.write(4, 2 + 2, fgBlue, "Permissions: ", fgWhite, f[1].getFilePermissions.formatPermissions)
    tb.write(4, 2 + 3, fgBlue, "      Items: ", fgWhite, $count)
    tb.write(4, 2 + 4, fgBlue, "Last Access: ", fgWhite, f[1].getLastAccessTime.format("d MMM yyyy h:mm:ss tt"))
    tb.write(4, 2 + 5, fgBlue, " Last Write: ", fgWhite, f[1].getLastModificationTime.format("d MMM yyyy h:mm:ss tt"))
    tb.write(4, 2 + 6, fgBlue, "    Created: ", fgWhite, f[1].getCreationTime.format("d MMM yyyy h:mm:ss tt"))
  var key = Key.None
  while not @[Key.I, Key.Escape].contains(key):
    tb.display()
    sleep(20)
    key = getKey()
    if key == Key.Q: close()
 
proc displayFileContents(f: (PathComponent, string)) : void =
  todo("wordwrap", "OR screen scroll with line[x..tb.width]")
  case f[0]:
  of pcDir, pcLinkToDir:
    discard
  of pcFile, pcLinkToFile:
    let
      fileContents = readFile(f[1])
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
    tb.setBackgroundColor(bgNone)
    tb.fill(0, 0, tb.width, tb.height, " ")
    tb.write(2, 1, fgYellow, f[1].relativePath(currentPath))
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
          tb.setBackgroundColor(bgNone)
          tb.fill(0, 0, tb.width, tb.height, " ")
          tb.write(2, 1, fgYellow, f[1].relativePath(currentPath))
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
          tb.setBackgroundColor(bgNone)
          tb.fill(0, 0, tb.width, tb.height, " ")
          tb.write(2, 1, fgYellow, f[1].relativePath(currentPath))
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
      if tb.height - 1 < fileLines.len:
        tb.write(2, verticalDotsOffset, fgCyan, verticalDots)
      lineCount = "[" & $fcTop & "-" & $fcBottom & "/" & $(fileLines.len - 1) & "]"
      tb.write(lineCountOffset, 1, fgCyan, lineCount.align(maxLen))
      if update:
        tb.display()
        sleep(10)
        update = false

proc writeZero(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "█▀▀█ ")
  tb.write(xPos, yPos + 1, fgCyan, "█▄▀█ ")
  tb.write(xPos, yPos + 2, fgCyan, "█▄▄█ ")

proc writeOne(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, " ▄█  ")
  tb.write(xPos, yPos + 1, fgCyan, "  █  ")
  tb.write(xPos, yPos + 2, fgCyan, "▄▄█▄ ")

proc writeTwo(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "▄▀▀▄ ")
  tb.write(xPos, yPos + 1, fgCyan, "  ▄▀ ")
  tb.write(xPos, yPos + 2, fgCyan, "▄█▄▄ ")

proc writeThree(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "█▀▀█ ")
  tb.write(xPos, yPos + 1, fgCyan, "  ▀▄ ")
  tb.write(xPos, yPos + 2, fgCyan, "█▄▄█ ")

proc writeFour(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "█  █ ") 
  tb.write(xPos, yPos + 1, fgCyan, "█▄▄█ ")
  tb.write(xPos, yPos + 2, fgCyan, "   █ ")

proc writeFive(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "█▀▀▀ ")
  tb.write(xPos, yPos + 1, fgCyan, "▀▀▀▄ ")
  tb.write(xPos, yPos + 2, fgCyan, "▄▄▄▀ ")

proc writeSix(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "▄▀▀▄ ")
  tb.write(xPos, yPos + 1, fgCyan, "█▄▄▄ ")
  tb.write(xPos, yPos + 2, fgCyan, "▀▄▄▀ ")

proc writeSeven(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "▀▀▀█ ")
  tb.write(xPos, yPos + 1, fgCyan, "  █  ")
  tb.write(xPos, yPos + 2, fgCyan, " ▐▌  ")

proc writeEight(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "▄▀▀▄ ")
  tb.write(xPos, yPos + 1, fgCyan, "▄▀▀▄ ")
  tb.write(xPos, yPos + 2, fgCyan, "▀▄▄▀ ")

proc writeNine(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgCyan, "▄▀▀▄ ")
  tb.write(xPos, yPos + 1, fgCyan, "▀▄▄█ ")
  tb.write(xPos, yPos + 2, fgCyan, " ▄▄▀ ")

proc writeColon(xPos : int, yPos : int) : void =
  tb.write(xPos, yPos + 0, fgYellow, "▄ ")
  tb.write(xPos, yPos + 1, fgYellow, "  ")
  tb.write(xPos, yPos + 2, fgYellow, "▀ ")

proc displayTime : void =
  let digit0 = ((tb.width / 2).toInt - 10, (tb.height / 2).toInt - 1)
  let digit1 = ((tb.width / 2).toInt - 5, (tb.height / 2).toInt - 1)
  let digitColon = ((tb.width / 2).toInt , (tb.height / 2).toInt - 1)
  let digit2 = ((tb.width / 2).toInt + 2, (tb.height / 2).toInt - 1)
  let digit3 = ((tb.width / 2).toInt + 7, (tb.height / 2).toInt - 1)
  var key = Key.None
  while key == Key.None:
    let currentTime = now().format("HHmm")
    tb.setForegroundColor(fgMagenta)
    tb.setBackgroundColor(bgBlack)
    tb.fill((tb.width / 2).toInt - 12, (tb.height / 2).toInt - 2, (tb.width / 2).toInt + 12, (tb.height / 2).toInt + 2, " ")
    tb.drawRect((tb.width / 2).toInt - 12, (tb.height / 2).toInt - 2, (tb.width / 2).toInt + 12, (tb.height / 2).toInt + 2, doubleStyle=true)
    case currentTime[0]:
    of '0': writeZero(digit0[0], digit0[1])
    of '1': writeOne(digit0[0], digit0[1])
    of '2': writeTwo(digit0[0], digit0[1])
    of '3': writeThree(digit0[0], digit0[1])
    of '4': writeFour(digit0[0], digit0[1])
    of '5': writeFive(digit0[0], digit0[1])
    of '6': writeSix(digit0[0], digit0[1])
    of '7': writeSeven(digit0[0], digit0[1])
    of '8': writeEight(digit0[0], digit0[1])
    of '9': writeNine(digit0[0], digit0[1])
    else: discard
    case currentTime[1]:
    of '0': writeZero(digit1[0], digit1[1])
    of '1': writeOne(digit1[0], digit1[1])
    of '2': writeTwo(digit1[0], digit1[1])
    of '3': writeThree(digit1[0], digit1[1])
    of '4': writeFour(digit1[0], digit1[1])
    of '5': writeFive(digit1[0], digit1[1])
    of '6': writeSix(digit1[0], digit1[1])
    of '7': writeSeven(digit1[0], digit1[1])
    of '8': writeEight(digit1[0], digit1[1])
    of '9': writeNine(digit1[0], digit1[1])
    else: discard
    writeColon(digitColon[0], digitColon[1])
    case currentTime[2]:
    of '0': writeZero(digit2[0], digit2[1])
    of '1': writeOne(digit2[0], digit2[1])
    of '2': writeTwo(digit2[0], digit2[1])
    of '3': writeThree(digit2[0], digit2[1])
    of '4': writeFour(digit2[0], digit2[1])
    of '5': writeFive(digit2[0], digit2[1])
    of '6': writeSix(digit2[0], digit2[1])
    of '7': writeSeven(digit2[0], digit2[1])
    of '8': writeEight(digit2[0], digit2[1])
    of '9': writeNine(digit2[0], digit2[1])
    else: discard
    case currentTime[3]:
    of '0': writeZero(digit3[0], digit3[1])
    of '1': writeOne(digit3[0], digit3[1])
    of '2': writeTwo(digit3[0], digit3[1])
    of '3': writeThree(digit3[0], digit3[1])
    of '4': writeFour(digit3[0], digit3[1])
    of '5': writeFive(digit3[0], digit3[1])
    of '6': writeSix(digit3[0], digit3[1])
    of '7': writeSeven(digit3[0], digit3[1])
    of '8': writeEight(digit3[0], digit3[1])
    of '9': writeNine(digit3[0], digit3[1])
    else: discard
    tb.display()
    sleep(20)
    key = getKey()
    if key == Key.Q: close()

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

proc displaySplash : void =
  if config["splash"].parseBool:
    var ticks = 100
    tb.setForegroundColor(fgCyan)
    tb.drawRect((tb.width / 2).toInt - 27, (tb.height / 2).toInt - 5, (tb.width / 2).toInt + 26, (tb.height / 2).toInt + 5)
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt - 3, fgYellow, "     _", fgCyan, """/\/\""", fgYellow, "________", fgCyan, """/\/\""", fgYellow, "___________________________")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt - 2, fgYellow, "    _", fgCyan, """/\/\""", fgYellow, "________________", fgCyan, """/\/\/\/\""", fgYellow, "____", fgCyan, """/\/\/\""", fgYellow, "_____ ")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt - 1, fgYellow, "   _", fgCyan, """/\/\""", fgYellow, "________", fgCyan, """/\/\""", fgYellow, "____", fgCyan, """/\/\""", fgYellow, "__", fgCyan, """/\/\""", fgYellow, "______", fgCyan, """/\/\""", fgYellow, "___  ")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt + 0, fgYellow, "  _", fgCyan, """/\/\""", fgYellow, "________", fgCyan, """/\/\""", fgYellow, "____", fgCyan, """/\/\""", fgYellow, "__", fgCyan, """/\/\""", fgYellow, "__", fgCyan, """/\/\/\/\""", fgYellow, "___   ")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt + 1, fgYellow, " _", fgCyan, """/\/\/\/\/\""", fgYellow, "__", fgCyan, """/\/\/\""", fgYellow, "__", fgCyan, """/\/\""", fgYellow, "__", fgCyan, """/\/\""", fgYellow, "__", fgCyan, """/\/\/\/\/\""", fgYellow, "_    ")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt + 2, fgYellow, "____________________________________________     ")
    tb.write((tb.width / 2).toInt - 25, (tb.height / 2).toInt + 3, fgCyan, "                                    by vv52      ")
    tb.display()
    while ticks > 0:
      var key = getKey()
      if key != Key.None:
        ticks = 0
      else:
        ticks -= 1
        sleep(20)

proc confirm(message : string) : bool =
  let
    messageLines = message.wrap((tb.width/2).toInt)
    popUpWidth = (tb.width/2).toInt + 4
    puX1 = (tb.width/2).toInt - (popUpWidth/2).toInt
    puX2 = (tb.width/2).toInt + (popUpWidth/2).toInt
    puY1 = (tb.height/2).toInt - ((messageLines.len+5)/2).toInt
    puY2 = (tb.height/2).toInt + ((messageLines.len+5)/2).toInt
  var
    i = 0
  tb.setForegroundColor(fgRed)
  tb.setBackgroundColor(bgBlack)
  tb.fill(puX1, puY1, puX2, puY2, " ")
  tb.drawRect(puX1, puY1, puX2, puY2, doubleStyle=true)
  tb.setForegroundColor(fgYellow)
  while i < messageLines.len:
    tb.write(puX1+2, puY1+2 + i, messageLines[i].center((tb.width/2).toInt))
    i += 1
  tb.write((tb.width/2).toInt-7, puY1+2 + i+1, fgRed, styleBright, "[Y]es")
  tb.write((tb.width/2).toInt+4, puY1+2 + i+1, fgGreen, styleBright, "[N]o", resetStyle)
  tb.display()
  var key = Key.None
  while key == Key.None:
    key = getKey()
    case key:
    of Key.Y:
      return true
    of Key.N, Key.Escape:
      return false
    else:
      discard
    sleep(20)

proc main(filename : string) : void =
  var timer = 0
  while true:
    tb.clear()
    var key = getKey()
    if config["clock"].parseBool:
      if currentState in @[FILE_SELECT, FILE_EXPLORE, FILE_RECENT]:
        if key == Key.None:
          timer += 1
        else: timer = 0
    case currentState:
    of FILE_SELECT:
      fileSelect()
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
      of Key.Dot:
        editConfig()
        initProgram()
        loadConfig()
      of Key.Up, Key.K:
        if selection == 1:
          selection = files.len
          while bottom < files.len:
            top += 1
            bottom += 1
        elif selection < scrollStartUp and top > 0:
          top -= 1
          bottom -= 1
          selection -= 1
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
        itemSelection = 1
      of Key.C: displayCalendar()
      of Key.ShiftC: displayTime()
      of Key.Escape: discard
      of Key.Q: close()
      else:
        discard
    of FILE_RECENT:
      fileRecent()
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
      of Key.Dot:
        editConfig()
        initProgram()
        loadConfig()
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
      of Key.ShiftC: displayTime()
      of Key.E:
        currentState = FILE_EXPLORE
        currentPath = config["scanDir"].expandTilde.expandFilename
        itemSelection = 1
      of Key.Escape: discard
      of Key.Q: close()
      else:
        discard
    of FILE_VIEW:
      fileView(current)
      case key
      of Key.None: discard
      of Key.CtrlR:
        resetProgram()
      of Key.Dot:
        editConfig()
        initProgram()
        loadConfig()
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
        current = files[selection-1]
      of Key.Right, Key.L:
        if selection == files.len:
          selection = 1
        else:
          selection += 1
        issueSelection = 1
        current = files[selection-1]
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
      of Key.ShiftC: displayTime()
      of Key.E:
        currentState = FILE_EXPLORE
        currentPath = config["scanDir"].expandTilde.expandFilename
        itemSelection = 1
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
      of Key.Dot:
        editConfig()
        initProgram()
        loadConfig()
        currentState = FILE_EXPLORE
        setCurrentDir(currentPath)
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
      of Key.Right, Key.L, Key.Enter:
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
                current = currentDirPaths[itemSelection - 1][1]
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
        displayFileContents(currentDirPaths[itemSelection - 1])
      of Key.ShiftC: displayTime()
      of Key.X:
        if currentDirPaths[itemSelection - 1] in selectedItems:
          selectedItems.keepIf(proc(x: (PathComponent, string)): bool = x != currentDirPaths[itemSelection - 1])
        else:
          selectedItems.add(currentDirPaths[itemSelection - 1])
      of Key.D:
        if confirm("Really delete " & $(selectedItems.len) & " items?"):
          for item in selectedItems:
            case item[0]:
            of pcLinkToFile:
              removeFile(item[1])
            of pcFile, pcDir, pcLinkToDir:
              discard
          for item in selectedItems:
            case item[0]:
            of pcFile:
              removeFile(item[1].expandTilde.expandFilename)
            of pcLinkToFile, pcDir, pcLinkToDir:
              discard
          for item in selectedItems:
            case item[0]:
            of pcLinkToDir:
              removeFile(item[1])
            of pcDir, pcFile, pcLinkToFile:
              discard
          for item in selectedItems:
            case item[0]:
            of pcDir:
              removeDir(item[1].expandTilde.expandFilename)
            of pcLinkToDir, pcFile, pcLinkToFile:
              discard
          selectedItems.setLen(0)
          itemSelection = 1
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
      of Key.Tab:
        enterShellAndReturn()
        initProgram()
        currentState = FILE_EXPLORE
        setCurrentDir(currentPath)
      of Key.Space:
        discard
      of Key.Escape:
        if copiedItems.len > 0:
          copiedItems.setLen(0)
        elif selectedItems.len > 0:
          selectedItems.setLen(0)
        else:
          currentState = FILE_RECENT
          selection = 1
          setCurrentDir(getAppDir())
      of Key.Q: close()
      else:
        discard
    of DIRECT_VIEW:
      fileView(filename)
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
      of Key.Enter, Key.Space:
        enterFileAndReturn()
        updateHistory()
        initProgram()
        currentState = DIRECT_VIEW
      of Key.Escape: discard
      of Key.Q: close()
      else:
        discard
    tb.display()
    if config["clock"].parseBool:
      if timer > 1000:
        displayTime()
        timer = 0
    sleep(20)

when isMainModule:
  initProgram()
  loadConfig()
  loadFilesFromScanDir()
  simple_parseopt.config: noSlash.dashDashParameters
  let options = getOptions:
    explore   = false       {. alias("e") .}
    view      : string      {. alias("v") .}
    arguments : seq[string]
  if not options.view.isEmptyOrWhitespace:
    currentState = DIRECT_VIEW
    current = options.view
    main(current)
  elif options.explore:
    currentState = FILE_EXPLORE
    currentPath = config["scanDir"].expandTilde.expandFilename
    setCurrentDir(currentPath)
    main("")
  else:
    displaySplash()
    case config["default"]:
    of "select":
      currentState = FILE_SELECT
    of "recent":
      currentState = FILE_RECENT
    of "explore":
      currentState = FILE_EXPLORE
      currentPath = config["scanDir"].expandTilde.expandFilename
      setCurrentDir(currentPath)
    else:
      echo """CONFIG ERROR: 'default' must be 'select', 'recent', or 'explore'"""
    main("")
