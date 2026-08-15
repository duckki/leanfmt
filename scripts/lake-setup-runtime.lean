import Lean

open System

namespace LeanFmt.Validation

def listedPaths (path : FilePath) : IO (Array String) := do
  let contents ← IO.FS.readFile path
  let paths : Array String :=
    (contents.splitOn "\n").foldl
      (fun paths path => if path.isEmpty then paths else paths.push path)
      #[]
  return paths

def setupHasNoRuntime (path : FilePath) : IO Bool :=
  IO.FS.withFile path .read
    fun handle => do
      let bytes ← handle.read 32
      return (String.fromUTF8? bytes).any (·.startsWith "{\"plugins\": []")

structure SetupRuntime where
  dynlibs : Array String := #[]
  plugins : Array String := #[]

def uniquePaths (paths : Array String) : Array String :=
  paths.foldl
    (fun unique path => if unique.contains path then unique else unique.push path)
    #[]

def jsonStringArray (json : Lean.Json) (field : String) : Array String :=
  match json.getObjVal? field with
  | .ok (.arr values) =>
      values.filterMap fun value => if let .str path := value then some path else none
  | _ => #[]

def jsonPluginPaths (json : Lean.Json) : Array String :=
  match json.getObjVal? "plugins" with
  | .ok (.arr plugins) =>
      plugins.filterMap fun plugin =>
        if let .ok (.str path) := plugin.getObjVal? "path" then some path else none
  | _ => #[]

def setupRuntime (setupPath : String) : IO SetupRuntime := do
  if !(← FilePath.pathExists setupPath) then
    return {}
  if ← setupHasNoRuntime setupPath then
    return {}
  let json ← IO.FS.readFile setupPath
  match Lean.Json.parse json with
  | .ok json =>
      return {
        dynlibs := uniquePaths (jsonStringArray json "dynlibs")
        plugins := uniquePaths (jsonPluginPaths json)
      }
  | .error _ => return {}

def projectRuntime (setupPaths : Array String) : IO SetupRuntime := do
  let mut runtime : SetupRuntime := {}
  for setupPath in setupPaths do
    let setup ← setupRuntime setupPath
    runtime :=
      {
        dynlibs := uniquePaths (runtime.dynlibs ++ setup.dynlibs)
        plugins := uniquePaths (runtime.plugins ++ setup.plugins)
      }
  return runtime

def runtimeLine (setupPaths : Array String) : IO String := do
  let separator := if System.Platform.isWindows then ";" else ":"
  let runtime ← projectRuntime setupPaths
  return String.intercalate separator runtime.dynlibs.toList
    ++ "\t"
    ++ String.intercalate separator runtime.plugins.toList

def main (args : List String) : IO UInt32 := do
  let [setupList, output] := args
  |
    IO.eprintln "usage: lake-setup-runtime.lean SETUP_LIST OUTPUT"
    return 2
  let line ← runtimeLine (← listedPaths setupList)
  IO.FS.writeFile output (line ++ "\n")
  return 0

end LeanFmt.Validation

def main := LeanFmt.Validation.main
