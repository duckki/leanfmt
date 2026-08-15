import LeanFmt.Tests.Suite

def main (args : List String) : IO UInt32 := do
  Lean.initSearchPath (← Lean.findSysroot)
  let env ← LeanFmt.Formatter.defaultEnvironment
  LeanFmt.Tests.runTestGroups env args
  pure 0
