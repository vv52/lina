import std/[os, strutils]
import illwill, scan

proc close() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

illwillInit(fullscreen=true)
setControlCHook(close)
hideCursor()

var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

tb.setForegroundColor(fgBlue, true)
tb.drawRect(0, 0, terminalWidth(), 5)
tb.drawHorizLine(2, 38, 3, doubleStyle=true)

# tb.write(2, 1, fgWhite, "Press any key to display its name")
# tb.write(2, 2, "Press ", fgYellow, "ESC", fgWhite,
#                " or ", fgYellow, "Q", fgWhite, " to quit")
proc main =
  scan("../todo/src/todo.nim")
  while true:
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Escape, Key.Q: close()
    else:
      discard
    tb.display()
    sleep(20)

when isMainModule:
  main()
