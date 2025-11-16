import std/[terminal, strutils]

# var icon = " \u2937\ueae9 "
var icon = " \u21b3 \ueae9 "
var border = "|| "

proc todo*(message : string) =
  when defined(todo):
    var e = new CatchableError
    try:
      raise e
    except:
      let filepath = $e.trace[e.trace.len-2].filename
      let dirs = filepath.split('/')
      let filename = dirs[dirs.high]
      styledEcho fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, message
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $e.trace[e.trace.len-2].line
  else: discard

proc todo*(message : string, description : string) =
  when defined(todo):
    var e = new CatchableError
    try:
      raise e
    except:
      let filepath = $e.trace[e.trace.len-2].filename
      let dirs = filepath.split('/')
      let filename = dirs[dirs.high]
      styledEcho fgCyan, border, styleBright, fgYellow, "[TODO] ", resetStyle, message
      styledEcho fgCyan, border, fgYellow, description
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $e.trace[e.trace.len-2].line
  else: discard

proc priority*(message : string) =
  when defined(todo):
    var e = new CatchableError
    try:
      raise e
    except:
      let filepath = $e.trace[e.trace.len-2].filename
      let dirs = filepath.split('/')
      let filename = dirs[dirs.high]
      styledEcho fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, message
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $e.trace[e.trace.len-2].line
  else: discard

proc priority*(message : string, description : string) =
  when defined(todo):
    var e = new CatchableError
    try:
      raise e
    except:
      let filepath = $e.trace[e.trace.len-2].filename
      let dirs = filepath.split('/')
      let filename = dirs[dirs.high]
      styledEcho fgCyan, border, styleBright, fgRed, "[HIGH PRIORITY] ", resetStyle, bgYellow, fgBlack, message
      styledEcho fgCyan, border, fgMagenta, description
      styledEcho fgCyan, border, fgWhite, icon, styleUnderscore, fgCyan, filename, resetStyle, styleBright, fgCyan, ":", $e.trace[e.trace.len-2].line
  else: discard
