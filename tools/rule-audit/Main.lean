import LeanFmt.Driver.Environment
import LeanFmt.Driver.Files
import LeanFmt.Formatter.LineBreakRules
import LeanFmt.RegisteredFormatAudit

open Lean System LeanFmt

namespace LeanFmt.RuleAudit

structure Options where
  maxFilesPerRoot : Nat := 100
  maxSamples : Nat := 3
  roots : List FilePath := []
deriving Repr

inductive ParseResult where
  | run (options : Options)
  | help
  | error (message : String)

def usage : String :=
  String.intercalate "\n"
    [
      "Usage: ruleAudit [--max-files-per-root N] [--max-samples N] PATH...",
      "",
      "Inspect registered Lean formatters and compare their stable symbolic layout",
      "with leanfmt's current structural owner for the same source span. Directories",
      "are searched recursively and sampled evenly in sorted path order."
    ]

def parseNatOption (name value : String) : Except String Nat := do
  let some number := value.toNat?
  | throw s!"{name} requires a natural number"
  pure number

def parseArgs (args : List String) : ParseResult :=
  let rec loop (options : Options) : List String -> ParseResult
    | [] =>
        if options.roots.isEmpty then
          .error "no input paths"
        else if options.maxSamples < 2 then
          .error "--max-samples must be at least 2"
        else
          .run { options with roots := options.roots.reverse }
    | "-h" :: _ | "--help" :: _ => .help
    | "--max-files-per-root" :: value :: rest =>
        match parseNatOption "--max-files-per-root" value with
        | .ok number => loop { options with maxFilesPerRoot := number } rest
        | .error message => .error message
    | "--max-samples" :: value :: rest =>
        match parseNatOption "--max-samples" value with
        | .ok number => loop { options with maxSamples := number } rest
        | .error message => .error message
    | option :: rest =>
        if option.startsWith "-" then
          .error s!"unknown or incomplete option: {option}"
        else
          loop { options with roots := FilePath.mk option :: options.roots } rest
  loop {} args

structure Boundary where
  offset : Nat
  indentLevels : Nat
deriving BEq, Repr

structure ProductionProfile where
  nodeKind : String
  ruleName : String
  breaks : Array Boundary
deriving BEq, Repr

structure Sample where
  file : String
  byteOffset : Nat
  sourceText : String
  audit : RegisteredFormatAudit.Audit
  childBoundaryOffsets : Array Nat
  candidateBreaks : Array Boundary
  production : Array ProductionProfile
  exactProduction : Array ProductionProfile
deriving Repr

structure Group where
  key : RegisteredFormatAudit.StructuralKey
  occurrences : Nat := 0
  attempts : Nat := 0
  samples : Array Sample := #[]
  rejections : Array RegisteredFormatAudit.Rejection := #[]
deriving Repr

structure State where
  files : Nat := 0
  parseFailures : Array (String × String) := #[]
  registeredOccurrences : Nat := 0
  groups : Array Group := #[]

partial def syntaxNodes (stx : Syntax) : Array Syntax :=
  match stx with
  | .node _ _ children =>
      children.foldl (fun nodes child => nodes ++ syntaxNodes child) #[stx]
  | _ => #[]

def treeSpan? (tree : SyntaxTree.Tree) : Option (String.Pos.Raw × String.Pos.Raw) := do
  let first <- tree.firstToken?
  let last <- tree.lastToken?
  pure (first.span.start, last.span.stop)

def profileFor
    (targetStart : String.Pos.Raw) (context : Formatter.LineBreakRules.RuleContext)
    (tree : SyntaxTree.Tree)
    : ProductionProfile :=
  let segment := Formatter.LineBreakRules.Segment.ofTree tree
  let rule := Formatter.LineBreakRules.formattingRuleFor tree
  let breaks :=
    (rule.breakPoints context segment).filterMap
      fun point => do
        let child <- segment.child? point.index
        let token <- child.firstToken?
        if targetStart <= token.span.start then
          some
            {
              offset := token.span.start.byteIdx - targetStart.byteIdx
              indentLevels := point.indentLevels
            }
        else
          none
  {
    nodeKind :=
      match tree with
      | .node kind _ => SyntaxTree.nodeKindName kind
      | .missing => "missing"
      | .leaf _ => "leaf"
    ruleName := rule.name
    breaks := breaks.toArray
  }

partial def exactProductionProfiles
    (targetStart targetStop : String.Pos.Raw)
    (context : Formatter.LineBreakRules.RuleContext)
    (tree : SyntaxTree.Tree)
    : Array ProductionProfile :=
  let own :=
    if treeSpan? tree == some (targetStart, targetStop) then
      #[profileFor targetStart context tree]
    else
      #[]
  match tree with
  | .node _ children =>
      let segment := Formatter.LineBreakRules.Segment.ofTree tree
      (List.range children.size).foldl
        (fun profiles index =>
          match children[index]? with
          | some child =>
              profiles
              ++ exactProductionProfiles targetStart targetStop
                  (context.push segment index) child
          | none => profiles)
        own
  | _ => own

partial def productionProfilesWithin
    (targetStart targetStop : String.Pos.Raw)
    (context : Formatter.LineBreakRules.RuleContext)
    (tree : SyntaxTree.Tree)
    : Array ProductionProfile :=
  let span := treeSpan? tree
  let own :=
    match span with
    | some (start, stop) =>
        if targetStart <= start && stop <= targetStop then
          #[profileFor targetStart context tree]
        else
          #[]
    | none => #[]
  let overlapsTarget :=
    match span with
    | some (start, stop) => start < targetStop && targetStart < stop
    | none => true
  if !overlapsTarget then
    #[]
  else
    match tree with
    | .node _ children =>
        let segment := Formatter.LineBreakRules.Segment.ofTree tree
        (List.range children.size).foldl
          (fun profiles index =>
            match children[index]? with
            | some child =>
                profiles
                ++ productionProfilesWithin targetStart targetStop
                    (context.push segment index) child
            | none => profiles)
          own
    | _ => own

def candidateBoundaries (stx : Syntax) (candidate : RegisteredFormatAudit.RuleCandidate)
    : Array Boundary :=
  match stx.getPos? (canonicalOnly := true) with
  | none => #[]
  | some start =>
      let children := RegisteredFormatAudit.normalizedChildren stx
      candidate.breaks.filterMap
        fun point => do
          let child <- children[point.childIndex]?
          let childStart <- child.getPos? (canonicalOnly := true)
          if start <= childStart then
            some
              {
                offset := childStart.byteIdx - start.byteIdx
                indentLevels := point.indentLevels
              }
          else
            none

def childBoundaryOffsets (stx : Syntax) : Array Nat :=
  match stx.getPos? (canonicalOnly := true) with
  | none => #[]
  | some start =>
      (RegisteredFormatAudit.normalizedChildren stx).filterMap
        fun child => do
          let childStart <- child.getPos? (canonicalOnly := true)
          if start < childStart then
            some (childStart.byteIdx - start.byteIdx)
          else
            none

def findGroupIndex? (groups : Array Group) (key : RegisteredFormatAudit.StructuralKey)
    : Option Nat :=
  (List.range groups.size).find?
    fun index => groups[index]?.any (fun group => group.key == key)

def rejectionName : RegisteredFormatAudit.Rejection -> String
  | .notRegistered => "not registered"
  | .missingSourceSpan => "missing source span"
  | .incompleteSourceCoverage => "incomplete source coverage"
  | .sourceComment => "source comment"
  | .formatterFailure _ => "formatter failure"
  | .leadingWhitespace => "leading whitespace"
  | .multilineToken _ => "multiline token"
  | .tokenMismatch .. => "token rewriting"
  | .layoutInsideToken .. => "layout inside token"
  | .unsupportedWhitespace _ => "unsupported whitespace"
  | .unsupportedIndentation .. => "unsupported indentation"
  | .columnAlignment .. => "column-relative alignment"
  | .trailingOutput _ => "trailing output"
  | .incompleteOutput _ => "incomplete output"

def updateGroup
    (state : State) (key : RegisteredFormatAudit.StructuralKey)
    (update : Group -> Group)
    : State :=
  match findGroupIndex? state.groups key with
  | some index =>
      match state.groups[index]? with
      | some group => { state with groups := state.groups.set! index (update group) }
      | none => state
  | none => { state with groups := state.groups.push (update { key }) }

def processSyntax
    (options : Options) (environment : Environment) (moduleTree : SyntaxTree.Module)
    (file : FilePath) (state : State) (stx : Syntax)
    : IO State := do
  if ParserLayout.metadataSourceForKind environment stx.getKind != .registered then
    pure state
  else
    let key := RegisteredFormatAudit.structuralKey stx
    let state :=
      {
        updateGroup state key
            fun group => { group with occurrences := group.occurrences + 1 } with
          registeredOccurrences := state.registeredOccurrences + 1
      }
    let some groupIndex := findGroupIndex? state.groups key
    | pure state
    let some group := state.groups[groupIndex]?
    | pure state
    if options.maxSamples <= group.samples.size
        || options.maxSamples * 6 <= group.attempts then
      pure state
    else
      let state :=
        updateGroup state key fun group => { group with attempts := group.attempts + 1 }
      let result <- RegisteredFormatAudit.auditSyntax environment moduleTree stx
                      file.toString
      match result with
      | .rejected reason =>
          pure
          <| updateGroup state key
              fun group =>
                { group with rejections := group.rejections.push reason }
      | .inferred audit =>
          let some start := stx.getPos? (canonicalOnly := true)
          | pure state
          let some stop := stx.getTailPos? (canonicalOnly := true)
          | pure state
          let sample : Sample :=
            {
              file := file.toString
              byteOffset := start.byteIdx
              sourceText := SyntaxTree.sourceText moduleTree.source start stop
              audit
              childBoundaryOffsets := childBoundaryOffsets stx
              candidateBreaks := candidateBoundaries stx audit.candidate
              production := productionProfilesWithin start stop {} moduleTree.tree
              exactProduction := exactProductionProfiles start stop {} moduleTree.tree
            }
          pure
          <| updateGroup state key
              fun group =>
                { group with samples := group.samples.push sample }

def processFile
    (options : Options) (loader : Driver.EnvironmentLoader) (state : State)
    (file : FilePath)
    : IO State := do
  try
    let source <- IO.FS.readFile file
    let driverOptions : Driver.Options := { importEnvFirst := true }
    let environment <- loader.environmentForSource driverOptions source file.toString
    let moduleTree <- SyntaxTree.parseModuleStringWithEnv environment source file.toString
    let mut state := { state with files := state.files + 1 }
    for stx in syntaxNodes moduleTree.rawSyntax do
      state <- processSyntax options environment moduleTree file state stx
    pure state
  catch exception =>
    pure
      {
        state with
          files := state.files + 1
          parseFailures := state.parseFailures.push (file.toString, toString exception)
      }

def evenlySample (limit : Nat) (files : List FilePath) : List FilePath :=
  if limit == 0 || files.length <= limit then
    files
  else if limit == 1 then
    files.take 1
  else
    (List.range limit).filterMap
      fun index => files[(index * (files.length - 1)) / (limit - 1)]?

def filesForRoot (options : Options) (root : FilePath) : IO (List FilePath) := do
  let driverOptions : Driver.Options := { recursive := true, files := [root] }
  let files <- Driver.expandInputPaths driverOptions
  pure
  <| evenlySample options.maxFilesPerRoot
      (files.mergeSort fun a b => a.toString <= b.toString)

def childRoleName : RegisteredFormatAudit.ChildRole -> String
  | .missing => "missing"
  | .atom => "atom"
  | .operand => "operand"

def familyName : RegisteredFormatAudit.RuleFamily -> String
  | .atomic => "atomic"
  | .application => "application"
  | .prefix => "prefix"
  | .postfix => "postfix"
  | .infix => "infix"
  | .delimited => "delimited"
  | .suffixBody => "suffix-body"
  | .sequence => "sequence"
  | .structural => "structural"

def shapeName (key : RegisteredFormatAudit.StructuralKey) : String :=
  ",".intercalate (key.children.toList.map childRoleName)

def boundaryName (breaks : Array Boundary) : String :=
  if breaks.isEmpty then
    "none"
  else
    ", ".intercalate
      (breaks.toList.map fun point => s!"{point.offset}:+{point.indentLevels}")

def markdownCode (text : String) : String :=
  "`" ++ (text.replace "|" "\\|").replace "`" "'" ++ "`"

def sourceSummary (text : String) : String :=
  let compact := (text.replace "\r" "").replace "\n" "\\n"
  if compact.length <= 100 then compact else (compact.take 97).toString ++ "..."

def stableCandidate? (group : Group) : Option RegisteredFormatAudit.RuleCandidate :=
  RegisteredFormatAudit.stableRuleCandidate?
    (group.samples.map (fun sample => sample.audit))

def effectiveProductionBreaks (sample : Sample) : Array Boundary :=
  sample.production.foldl
    (fun breaks profile =>
      profile.breaks.foldl
        (fun breaks point =>
          if !sample.childBoundaryOffsets.contains point.offset
              || breaks.any (fun current => current.offset == point.offset) then
            breaks
          else
            breaks.push point)
        breaks)
    #[]

def sampleAgrees (sample : Sample) : Bool :=
  effectiveProductionBreaks sample == sample.candidateBreaks

def productionDescriptions (group : Group) : String :=
  let descriptions :=
    group.samples.foldl
      (fun descriptions sample =>
        (sample.exactProduction ++ sample.production).foldl
          (fun descriptions profile =>
            let relevantBreaks :=
              profile.breaks.filter
                fun point => sample.childBoundaryOffsets.contains point.offset
            if relevantBreaks.isEmpty && !sample.exactProduction.contains profile then
              descriptions
            else
              let description :=
                profile.nodeKind
                ++ "/"
                ++ profile.ruleName
                ++ " ["
                ++ boundaryName relevantBreaks
                ++ "]"
              if descriptions.contains description then
                descriptions
              else
                descriptions.push description)
          descriptions)
      #[]
  if descriptions.isEmpty then
    "none"
  else
    ", ".intercalate descriptions.toList

def reportGroupRow (group : Group) (candidate : RegisteredFormatAudit.RuleCandidate)
    : String :=
  let agreement :=
    if group.samples.all sampleAgrees then
      "agrees"
    else if group.samples.all fun sample => sample.exactProduction.isEmpty then
      "no exact owner"
    else
      "differs"
  let candidateBreaks :=
    group.samples[0]?.map (fun sample => boundaryName sample.candidateBreaks)
    |>.getD "none"
  let location :=
    group.samples[0]?.map (fun sample => s!"{sample.file}:{sample.byteOffset}")
    |>.getD "unknown"
  let source :=
    group.samples[0]?.map (fun sample => sourceSummary sample.sourceText)
    |>.getD "unknown"
  s!"| {markdownCode (toString group.key.kind)} | {markdownCode (shapeName group.key)} | {familyName candidate.family} | {candidateBreaks} | {markdownCode (productionDescriptions group)} | {agreement} | {group.samples.size}/{group.occurrences} | {markdownCode source} | {markdownCode location} |"

def rejectionSummary (groups : Array Group) : Array (String × Nat) :=
  groups.foldl
    (fun counts group =>
      group.rejections.foldl
        (fun counts rejection =>
          let name := rejectionName rejection
          match (List.range counts.size).find?
                  fun index => counts[index]?.any (fun entry => entry.1 == name) with
          | some index =>
              match counts[index]? with
              | some entry => counts.set! index (entry.1, entry.2 + 1)
              | none => counts
          | none => counts.push (name, 1))
        counts)
    #[]

def renderReport (options : Options) (state : State) : String :=
  let stable :=
    state.groups.filterMap
      fun group => (stableCandidate? group).map fun candidate => (group, candidate)
  let agreements := stable.filter fun entry => entry.1.samples.all sampleAgrees
  let noOwners :=
    stable.filter
      fun entry => entry.1.samples.all fun sample => sample.exactProduction.isEmpty
  let differences :=
    stable.filter
      fun entry =>
        !entry.1.samples.all sampleAgrees
        && !entry.1.samples.all (fun sample => sample.exactProduction.isEmpty)
  let unstable :=
    state.groups.filter
      fun group => 2 <= group.samples.size && (stableCandidate? group).isNone
  let insufficient := state.groups.filter fun group => group.samples.size < 2
  let header :=
    [
      "# Registered formatter ruleset audit",
      "",
      s!"- Files sampled: {state.files}",
      s!"- Parse failures: {state.parseFailures.size}",
      s!"- Registered syntax occurrences: {state.registeredOccurrences}",
      s!"- Normalized structural groups: {state.groups.size}",
      s!"- Stable groups: {stable.size}",
      s!"- Stable agreements: {agreements.size}",
      s!"- Stable differences: {differences.size}",
      s!"- Stable groups without an exact production owner: {noOwners.size}",
      s!"- Unstable registered layouts: {unstable.size}",
      s!"- Groups with fewer than two accepted samples: {insufficient.size}",
      s!"- Sampling limits: {options.maxFilesPerRoot} files per root, {options.maxSamples} accepted samples per shape",
      ""
    ]
  let table
      (title : String)
      (entries : Array (Group × RegisteredFormatAudit.RuleCandidate)) :=
    [
      s!"## {title}",
      "",
      "| Syntax kind | Normalized children | Registered family | Registered breaks | Production owners/rules and breaks | Result | Samples/occurrences | Source | Location |",
      "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    ]
    ++ (entries.toList.map fun entry => reportGroupRow entry.1 entry.2)
    ++ [""]
  let rejectionLines :=
    ["## Rejections", ""]
    ++ ((rejectionSummary state.groups).toList.map
          fun entry => s!"- {entry.1}: {entry.2}")
    ++ [""]
  let unstableLines :=
    ["## Unstable or undersampled", ""]
    ++ (unstable.toList.map
          fun group =>
            s!"- {markdownCode (toString group.key.kind)} ({group.samples.size}/{group.occurrences} samples)")
    ++ (insufficient.toList.map
          fun group =>
            s!"- {markdownCode (toString group.key.kind)} ({group.samples.size}/{group.occurrences} samples)")
    ++ [""]
  let failureLines :=
    if state.parseFailures.isEmpty then
      []
    else
      ["## Parse failures", ""]
      ++ (state.parseFailures.toList.map
            fun failure => s!"- {markdownCode failure.1}: {failure.2}")
      ++ [""]
  "\n".intercalate
  <| header
      ++ table "Stable differences" differences
      ++ table "Stable agreements" agreements
      ++ table "Stable groups without an exact owner" noOwners
      ++ rejectionLines
      ++ unstableLines
      ++ failureLines

def run (options : Options) : IO UInt32 := do
  let loader <- Driver.loadEnvironmentLoader { importEnvFirst := true }
  let mut state : State := {}
  for root in options.roots do
    for file in (← filesForRoot options root) do
      state <- processFile options loader state file
  IO.println (renderReport options state)
  pure 0

end LeanFmt.RuleAudit

def main (args : List String) : IO UInt32 :=
  match LeanFmt.RuleAudit.parseArgs args with
  | .run options => LeanFmt.RuleAudit.run options
  | .help => IO.println LeanFmt.RuleAudit.usage *> pure 0
  | .error message => do
      IO.eprintln s!"error: {message}\n\n{LeanFmt.RuleAudit.usage}"
      pure 2
