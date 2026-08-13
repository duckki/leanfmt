import Lean

open System

namespace LeanFmt.Version

def unknownVersion : String := "unknown"

def quotedValue? (value : String) : Option String :=
  let value := value.trimAscii.toString
  if value.startsWith "\"" && value.endsWith "\"" then
    some <| (value.drop 1).toString.dropEnd 1 |>.toString
  else
    none

def tomlKeyValue? (line : String) : Option (String × String) := do
  let key :: valueParts := line.splitOn "=" | none
  let value ← quotedValue? (String.intercalate "=" valueParts)
  some (key.trimAscii.toString, value)

def versionFromLakefileToml? (contents : String) : Option String := do
  let pairs := contents.splitOn "\n" |>.filterMap tomlKeyValue?
  let name ← pairs.find? (fun pair => pair.1 == "name") |>.map Prod.snd
  if name != "leanfmt" then
    none
  else
    pairs.find? (fun pair => pair.1 == "version") |>.map Prod.snd

def jsonStringField? (json : Lean.Json) (field : String) : Option String :=
  match json.getObjVal? field with
  | .ok (.str value) => some value
  | _ => none

def normalizeManifestRevision (revision : String) : String :=
  if revision.startsWith "v" then
    (revision.drop 1).toString
  else
    revision

partial def versionFromPackages? (packages : Array Lean.Json) (index : Nat := 0)
    : Option String := do
  let package ← packages[index]?
  match jsonStringField? package "name", jsonStringField? package "rev" with
  | some "leanfmt", some revision => some (normalizeManifestRevision revision)
  | _, _ => versionFromPackages? packages (index + 1)

def versionFromLakeManifest? (contents : String) : Option String := do
  let json ← (Lean.Json.parse contents).toOption
  match json.getObjVal? "packages" with
  | .ok (.arr packages) => versionFromPackages? packages
  | _ => none

partial def findLakeRoot? (candidate : FilePath) : IO (Option FilePath) := do
  if (← (candidate / "lakefile.toml").pathExists)
      || (← (candidate / "lakefile.lean").pathExists)
      || (← (candidate / "lake-manifest.json").pathExists) then
    return some candidate
  else
    match candidate.parent with
    | some parent =>
        if parent == candidate then
          return none
        else
          findLakeRoot? parent
    | none => return none

def versionFromLakefile? (root : FilePath) : IO (Option String) := do
  let lakefile := root / "lakefile.toml"
  if !(← lakefile.pathExists) then
    return none
  return versionFromLakefileToml? (← IO.FS.readFile lakefile)

def versionFromManifest? (root : FilePath) : IO (Option String) := do
  let manifest := root / "lake-manifest.json"
  if !(← manifest.pathExists) then
    return none
  return versionFromLakeManifest? (← IO.FS.readFile manifest)

def versionString : IO String := do
  let root? ← findLakeRoot? (← IO.currentDir)
  match root? with
  | none => return unknownVersion
  | some root =>
      match ← versionFromLakefile? root with
      | some version => return version
      | none =>
          match ← versionFromManifest? root with
          | some version => return version
          | none => return unknownVersion

def fullVersionString : IO String := do
  return s!"leanfmt version {← versionString} (Lean version {Lean.versionString})"

end LeanFmt.Version

namespace LeanFmt

export Version (
  fullVersionString versionFromLakeManifest? versionFromLakefileToml? versionString
)

end LeanFmt
