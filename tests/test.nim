import todo

proc test =
  priority("Implement test proc", "Description of proc")

proc main =
  todo("Hello from todo!", "This todo has additional context")
  echo "Hello World!"
  test()
  priority("This is a high priority task")

when isMainModule:
  main()

todo("Hello from global scope!")
