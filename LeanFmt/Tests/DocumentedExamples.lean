import LeanFmt

namespace LeanFmt.Tests.DocumentedExamples

private def marker : String :=
  "<!-- leanfmt-test -->"

private def expectedExampleCount : Nat :=
  16

private partial def takeFenceBody (lines body : List String)
    : Except String (List String × List String) :=
  match lines with
  | [] => .error "documented example has no closing fence"
  | "```" :: rest => .ok (body.reverse, rest)
  | line :: rest => takeFenceBody rest (line :: body)

private partial def extractMarkedExamples : List String -> Except String (List String)
  | [] => .ok []
  | line :: rest => do
      if line = marker then
        match rest with
        | "```lean" :: fenced =>
            let (body, following) <- takeFenceBody fenced []
            let examples <- extractMarkedExamples following
            pure ((String.intercalate "\n" body ++ "\n") :: examples)
        | _ =>
            throw "documented example marker must be followed by a Lean fence"
      else
        extractMarkedExamples rest

def run (env : Lean.Environment) : IO Unit := do
  let contents <- IO.FS.readFile "docs/design.md"
  let examples <- match extractMarkedExamples (contents.splitOn "\n") with
                  | .ok examples => pure examples
                  | .error message => throw <| IO.userError message
  unless examples.length = expectedExampleCount do
    let message :=
      s!"expected {expectedExampleCount} documented examples, found {examples.length}"
    throw <| IO.userError message
  for (source, index) in examples.zipIdx do
    let fileName := s!"docs/design-example-{index + 1}.lean"
    let result <- Formatter.formatSourceWithEnvDetailed env source fileName
    if result.fellBack then
      throw <| IO.userError s!"documented example {index + 1} fell back"
    unless result.formatted = source do
      let message :=
        s!"documented example {index + 1} is not formatted\nexpected:\n{source}\nactual:\n{result.formatted}"
      throw <| IO.userError message

end LeanFmt.Tests.DocumentedExamples
