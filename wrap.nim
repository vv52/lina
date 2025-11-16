proc wrap*(str : string, len : int) : seq[string] =
  var src = str
  while src.len > len:
    result.add(src[0..len-1])
    src = src[len..src.len-1]
  if src.len < len:
    result.add(src)

if isMainModule:
  echo """----- wrap("test test test test test", 3)"""
  for line in wrap("test test test test test", 3):
    echo line
  echo """----- wrap("really long sentence, definitely clipping over screen edge... how does this look?", 25)"""
  for line in wrap("really long sentence, definitely clipping over screen edge... how does this look?", 25):
    echo line
