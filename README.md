# tracker

TUI tool to scan source files for todo("messages") and other similar calls, reporting their contents, line number, and file name. This was built to interact with my todo nimble package for nim projects but could theoretically work with any language supporting the aforementioned call syntax, you would just need to implement todo procs

**File explore mode now focus of dev** -- currently supports navigation, cut/copy/paste/delete, displaying file info, displaying the contents of files, and opening files with tracked extensions in configured editor

## dependencies

```
  nimble install illwave
  nimble install stacks
  nimble install simple_parseopt
  nimble install vv52/todo (optional)
```

NerdFont-compatible font recommended for icon rendering. Otherwise, set "ui" to "simple" in config.ini (default "nerd")
