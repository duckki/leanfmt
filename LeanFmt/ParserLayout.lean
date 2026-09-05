import Lean

namespace LeanFmt.ParserLayout

open Lean

/-!
`ParserLayout` is the adapter between Lean's imported parser/formatter metadata and
leanfmt's lossless syntax tree. It evaluates a parser description once per syntax kind
and exposes conservative structural facts. The syntax tree may use these facts to
regroup source tokens, but this module never emits text or chooses a rendered layout.
-/

inductive MetadataSource where
  | registered
  | parserDescription
  | unavailable
deriving BEq, Inhabited, Repr

def MetadataSource.description : MetadataSource -> String
  | .registered => "registered formatter"
  | .parserDescription => "parser description"
  | .unavailable => "no formatter metadata"

structure PrintingAnnotations where
  softBreak : Bool := false
  hardBreak : Bool := false
  indent : Bool := false
  dedent : Bool := false
  group : Bool := false
  fill : Bool := false
deriving BEq, Inhabited, Repr

def PrintingAnnotations.merge (left right : PrintingAnnotations) : PrintingAnnotations :=
  {
    softBreak := left.softBreak || right.softBreak
    hardBreak := left.hardBreak || right.hardBreak
    indent := left.indent || right.indent
    dedent := left.dedent || right.dedent
    group := left.group || right.group
    fill := left.fill || right.fill
  }

structure OwnedBodyPolicy where
  suffixes : List String := []
  headerClauseKeywords : List String := []
  suffixOwnsBody : Bool := false
deriving BEq, Inhabited, Repr

structure KindFacts where
  metadataSource : MetadataSource := .unavailable
  annotations : PrintingAnnotations := {}
  infixPrecedence? : Option (Nat × Nat) := none
  spacedApplication : Bool := false
  ownedBody? : Option OwnedBodyPolicy := none
deriving Inhabited, Repr

abbrev Facts := NameMap KindFacts

def Facts.infixPrecedence? (facts : Facts) (kind : SyntaxNodeKind) : Option (Nat × Nat) :=
  (facts.find? kind) >>= (·.infixPrecedence?)

def Facts.isSpacedApplication (facts : Facts) (kind : SyntaxNodeKind) : Bool :=
  (facts.find? kind).any (·.spacedApplication)

def Facts.ownedBody? (facts : Facts) (kind : SyntaxNodeKind) : Option OwnedBodyPolicy :=
  (facts.find? kind) >>= (·.ownedBody?)

private def hasRegisteredFormatter (env : Environment) (kind : SyntaxNodeKind) : Bool :=
  !(KeyedDeclsAttribute.getValues PrettyPrinter.formatterAttribute env kind).isEmpty

private inductive DescriptionKind where
  | leading
  | trailing
deriving BEq, Inhabited, Repr

private def parserDescriptionKind? (env : Environment) (kind : SyntaxNodeKind)
    : Option DescriptionKind := do
  let info <- env.find? kind
  if info.type.isConstOf ``TrailingParserDescr then
    some .trailing
  else if info.type.isConstOf ``ParserDescr then
    some .leading
  else
    none

def metadataSourceForKind (env : Environment) (kind : SyntaxNodeKind) : MetadataSource :=
  if hasRegisteredFormatter env kind then
    .registered
  else if (parserDescriptionKind? env kind).isSome then
    .parserDescription
  else
    .unavailable

private partial def parserDescrPrecedence? (kind : SyntaxNodeKind)
    : ParserDescr -> Option (Nat × Nat)
  | .trailingNode nodeKind precedence leftPrecedence parser =>
      if nodeKind == kind then
        some (precedence, leftPrecedence)
      else
        parserDescrPrecedence? kind parser
  | .node _ _ parser
  | .unary _ parser =>
      parserDescrPrecedence? kind parser
  | .binary _ left right =>
      parserDescrPrecedence? kind left <|> parserDescrPrecedence? kind right
  | _ => none

private partial def parserDescrAnnotations : ParserDescr -> PrintingAnnotations
  | .const name =>
      {
        softBreak := name == `ppSpace || name == `ppHardLineUnlessUngrouped
        hardBreak := name == `ppLine
      }
  | .unary name parser =>
      let annotations := parserDescrAnnotations parser
      {
        annotations with
          indent := annotations.indent || name == `ppIndent || name == `ppGroup
          dedent :=
            annotations.dedent || name == `ppDedent || name == `ppDedentIfGrouped
          group := annotations.group || name == `ppRealGroup
          fill := annotations.fill || name == `ppRealFill || name == `ppGroup
      }
  | .binary _ left right =>
      (parserDescrAnnotations left).merge (parserDescrAnnotations right)
  | .node _ _ parser
  | .trailingNode _ _ _ parser
  | .nodeWithAntiquot _ _ parser =>
      parserDescrAnnotations parser
  | .sepBy parser _ separator _
  | .sepBy1 parser _ separator _ =>
      (parserDescrAnnotations parser).merge (parserDescrAnnotations separator)
  | .symbol symbol
  | .nonReservedSymbol symbol _ =>
      {
        softBreak := symbol.startsWith " " || symbol.endsWith " "
        hardBreak := symbol.contains '\n'
      }
  | .unicodeSymbol unicode ascii _ =>
      {
        softBreak :=
          unicode.startsWith " "
          || unicode.endsWith " "
          || ascii.startsWith " "
          || ascii.endsWith " "
        hardBreak := unicode.contains '\n' || ascii.contains '\n'
      }
  | .cat .. | .parser .. => {}

private partial def parserDescrSequence : ParserDescr -> List ParserDescr
  | .binary combinator left right =>
      if combinator == `andthen then
        parserDescrSequence left ++ parserDescrSequence right
      else
        [.binary combinator left right]
  | parser => [parser]

private def isNullaryPrintingAnnotation (name : Name) : Bool :=
  name == `ppHardSpace
  || name == `ppSpace
  || name == `ppLine
  || name == `ppAllowUngrouped
  || name == `ppHardLineUnlessUngrouped

private def isUnaryPrintingAnnotation (name : Name) : Bool :=
  name == `ppRealFill
  || name == `ppRealGroup
  || name == `ppIndent
  || name == `ppGroup
  || name == `ppDedent
  || name == `ppDedentIfGrouped

private partial def parserDescrApplicationSequence : ParserDescr -> List ParserDescr
  | .binary combinator left right =>
      if combinator == `andthen then
        parserDescrApplicationSequence left ++ parserDescrApplicationSequence right
      else
        [.binary combinator left right]
  | .const name =>
      if isNullaryPrintingAnnotation name then [] else [.const name]
  | .unary name parser =>
      if isUnaryPrintingAnnotation name then
        parserDescrApplicationSequence parser
      else
        [.unary name parser]
  | parser => [parser]

private def parserDescrSymbolIsTight (symbol : String) : Bool :=
  symbol.toList.all
    fun char => char != ' ' && char != '\t' && char != '\n' && char != '\r'

private def parserDescrSymbolIsApplicationHead (symbol : String) : Bool :=
  let symbol := symbol.trimAscii.toString
  parserDescrSymbolIsTight symbol && symbol.toList.any (·.isAlphanum)

private def parserDescrIsApplicationHead : ParserDescr -> Bool
  | .symbol symbol
  | .nonReservedSymbol symbol _ => parserDescrSymbolIsApplicationHead symbol
  | .unicodeSymbol ascii unicode _ =>
      let ascii := ascii.trimAscii.toString
      let unicode := unicode.trimAscii.toString
      parserDescrSymbolIsTight ascii
      && parserDescrSymbolIsTight unicode
      && (ascii.toList.any (·.isAlphanum) || unicode.toList.any (·.isAlphanum))
  | _ => false

private def parserDescrIsOptional : ParserDescr -> Bool
  | .unary combinator _ => combinator == `optional
  | _ => false

private def parserDescrIsSpacedOperand : ParserDescr -> Bool
  | .cat category _ => category == `term || category == `ident
  | .const category => category == `ident
  | _ => false

private partial def parserDescrIsSpacedApplication (kind : SyntaxNodeKind)
    : ParserDescr -> Bool
  | .node nodeKind _ parser
  | .nodeWithAntiquot _ nodeKind parser =>
      if nodeKind == kind then
        match parserDescrApplicationSequence parser with
        | [] | [_] => false
        | head :: rest =>
            parserDescrIsApplicationHead head
            && rest.getLast?.any parserDescrIsSpacedOperand
            && rest.dropLast.all parserDescrIsOptional
      else
        parserDescrIsSpacedApplication kind parser
  | .unary _ parser => parserDescrIsSpacedApplication kind parser
  | .binary _ left right =>
      parserDescrIsSpacedApplication kind left
      || parserDescrIsSpacedApplication kind right
  | _ => false

private def parserDescrIsBodyLayoutConstraint : ParserDescr -> Bool
  | .const parser => [`colGt, `colGe].contains parser
  | .unary _ parser => parserDescrIsBodyLayoutConstraint parser
  | .binary combinator left right =>
      combinator == `andthen
      && parserDescrIsBodyLayoutConstraint left
      && parserDescrIsBodyLayoutConstraint right
  | _ => false

private partial def parserDescrIsOwnedTacticBody : ParserDescr -> Bool
  | .const parser =>
      parser == `tacticSeq
      || parser == `tacticSeqIndentGt
      || parser == `Lean.Parser.Tactic.tacticSeq
      || parser == `Lean.Parser.Tactic.tacticSeqIndentGt
  | .unary _ parser => parserDescrIsOwnedTacticBody parser
  | .binary combinator constraint body =>
      combinator == `andthen
      && parserDescrIsBodyLayoutConstraint constraint
      && parserDescrIsOwnedTacticBody body
  | _ => false

private partial def parserDescrIsOwnedBody : ParserDescr -> Bool
  | .cat category _ => category == `term
  | .const parser =>
      parser == `tacticSeq
      || parser == `tacticSeqIndentGt
      || parser == `Lean.Parser.Tactic.tacticSeq
      || parser == `Lean.Parser.Tactic.tacticSeqIndentGt
  | .unary combinator parser =>
      combinator != `optional && parserDescrIsOwnedBody parser
  | _ => false

private def parserDescrKeywordSuffixes : ParserDescr -> List String
  | .symbol symbol
  | .nonReservedSymbol symbol _ =>
      let symbol := symbol.trimAscii.toString
      if symbol.toList.any (·.isAlphanum) then [symbol] else []
  | .unicodeSymbol ascii unicode _ =>
      [ascii, unicode].filterMap
        fun symbol =>
          let symbol := symbol.trimAscii.toString
          if symbol.toList.any (·.isAlphanum) then some symbol else none
  | _ => []

private def parserDescrSuffixOwnedBodyClauseSuffixes (parser : ParserDescr)
    : List String :=
  match parserDescrSequence parser with
  | [suffix, body] =>
      if parserDescrIsOwnedBody body then parserDescrKeywordSuffixes suffix else []
  | _ => []

private def parserDescrTrailingTacticBodySuffixes (parser : ParserDescr) : List String :=
  match parserDescrSequence parser |>.reverse with
  | body :: suffix :: _ =>
      if parserDescrIsOwnedTacticBody body then
        parserDescrKeywordSuffixes suffix
      else
        []
  | _ => []

private def parserDescrTrailingBodySuffixes (parser : ParserDescr) : List String :=
  match parserDescrSequence parser with
  | [] | [_] => []
  | sequence =>
      match sequence.reverse with
      | body :: suffix :: preceding =>
          if !preceding.isEmpty && parserDescrIsOwnedBody body then
            parserDescrKeywordSuffixes suffix
          else
            match body with
            | .unary combinator clause =>
                if combinator == `optional && !sequence.dropLast.isEmpty then
                  parserDescrSuffixOwnedBodyClauseSuffixes clause
                else
                  []
            | _ => []
      | _ => []

private def parserDescrIsRepeatedSpacedOperands : ParserDescr -> Bool
  | .unary combinator parser =>
      (combinator == `many || combinator == `many1)
      && match (parserDescrApplicationSequence parser).reverse with
          | operand :: constraints =>
              parserDescrIsSpacedOperand operand
              && constraints.all parserDescrIsBodyLayoutConstraint
          | _ => false
  | _ => false

private partial def parserDescrHeaderClauseKeywords : ParserDescr -> List String
  | .unary combinator parser =>
      let current :=
        if combinator == `optional then
          match parserDescrSequence parser with
          | [keyword, arguments] =>
              if parserDescrIsRepeatedSpacedOperands arguments then
                parserDescrKeywordSuffixes keyword
              else
                []
          | _ => []
        else
          []
      current ++ parserDescrHeaderClauseKeywords parser
  | .node _ _ parser
  | .trailingNode _ _ _ parser
  | .nodeWithAntiquot _ _ parser =>
      parserDescrHeaderClauseKeywords parser
  | .binary _ left right =>
      parserDescrHeaderClauseKeywords left ++ parserDescrHeaderClauseKeywords right
  | _ => []

private partial def parserDescrOwnedTrailingBodySuffixes (parser : ParserDescr)
    : List String :=
  match parser with
  | .node _ _ parser
  | .nodeWithAntiquot _ _ parser =>
      parserDescrTrailingBodySuffixes parser
      ++ parserDescrOwnedTrailingBodySuffixes parser
  | .trailingNode _ _ _ parser =>
      parserDescrTrailingTacticBodySuffixes parser
  | .unary _ parser => parserDescrOwnedTrailingBodySuffixes parser
  | .binary _ left right =>
      parserDescrOwnedTrailingBodySuffixes left
      ++ parserDescrOwnedTrailingBodySuffixes right
  | _ => []

private def parserKindOwnsCategory (env : Environment) (category kind : SyntaxNodeKind)
    : Bool :=
  (Parser.getParserCategory? env category).any
    fun parserCategory => parserCategory.kinds.contains kind

private def parserKindOwnsCommandOrTacticLayout
    (env : Environment) (kind : SyntaxNodeKind)
    : Bool :=
  [`command, `tactic].any fun category => parserKindOwnsCategory env category kind

private def ownedBodyPolicy? (env : Environment) (kind : SyntaxNodeKind)
    (descriptionKind : DescriptionKind) (hasFormatter : Bool) (parser : ParserDescr)
    : Option OwnedBodyPolicy :=
  if !parserKindOwnsCommandOrTacticLayout env kind
      || (descriptionKind == .trailing && hasFormatter) then
    none
  else
    let suffixes := parserDescrOwnedTrailingBodySuffixes parser
    if suffixes.isEmpty then
      none
    else
      some
        {
          suffixes
          headerClauseKeywords := parserDescrHeaderClauseKeywords parser
          suffixOwnsBody := parserKindOwnsCategory env `tactic kind
        }

unsafe def kindFactsUnsafe (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : KindFacts :=
  let hasFormatter := hasRegisteredFormatter env kind
  let metadataSource := metadataSourceForKind env kind
  match parserDescriptionKind? env kind with
  | none =>
      { metadataSource }
  | some descriptionKind =>
      match env.evalConst ParserDescr options kind with
      | .error _ => { metadataSource }
      | .ok parser =>
          {
            metadataSource
            annotations := parserDescrAnnotations parser
            infixPrecedence? :=
              if descriptionKind == .trailing then
                parserDescrPrecedence? kind parser
              else
                none
            spacedApplication := parserDescrIsSpacedApplication kind parser
            ownedBody? :=
              ownedBodyPolicy? env kind descriptionKind hasFormatter parser
          }

@[implemented_by kindFactsUnsafe]
opaque kindFacts
    (env : Environment) (options : Options) (kind : SyntaxNodeKind) : KindFacts

partial def collect
    (env : Environment) (options : Options)
    (stx : Syntax) (facts : Facts := {})
    : Facts :=
  match stx with
  | .missing | .atom .. | .ident .. => facts
  | .node _ kind children =>
      let facts :=
        if facts.contains kind then
          facts
        else
          facts.insert kind (kindFacts env options kind)
      children.foldl (fun facts child => collect env options child facts) facts

end LeanFmt.ParserLayout
