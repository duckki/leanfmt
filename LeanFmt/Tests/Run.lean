import LeanFmt.Tests.Suite

def main (args : List String) : IO UInt32 := do
  if let ["--run-group", name] := args then
    let some (_, group) :=
      LeanFmt.Tests.testGroups.find? (fun (groupName, _) => groupName == name)
    | throw <| IO.userError s!"unknown test group: {name}"
    Lean.initSearchPath (← Lean.findSysroot)
    group
    return 0
  let groups ← IO.ofExcept (LeanFmt.Tests.selectedTestGroups args)
  let executable ← IO.appPath
  for (name, _) in groups do
    IO.eprintln s!"test group: {name}"
    let child ←
      IO.Process.spawn
        {
          cmd := executable.toString
          args := #["--run-group", name]
          stdin := .null
          stdout := .inherit
          stderr := .inherit
        }
    let exitCode ← child.wait
    if exitCode != 0 then
      IO.eprintln s!"test group failed: {name} (exit {exitCode})"
      return exitCode
  return 0
