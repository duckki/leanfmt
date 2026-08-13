import LeanFmt.Formatter.SpaceRules

namespace LeanFmt
namespace Formatter
namespace SourceBoundary

/-- Source trivia between two emitted tokens. The syntax tree remains unchanged;
this value centralizes the physical boundary facts needed by layout planning and
emission. -/
structure Boundary where
  text : String
  normalized : String
deriving Repr

def ofText (text : String) : Boundary :=
  { text, normalized := SpaceRules.normalizeLineEndings text }

def betweenTokens (source : String) (left right : SyntaxTree.Token) : Boundary :=
  ofText <| SyntaxTree.sourceText source left.span.stop right.span.start

def beforeToken (token : SyntaxTree.Token) : Boundary :=
  ofText token.leading.text

def Boundary.hasComment (boundary : Boundary) : Bool :=
  SpaceRules.hasCommentStart boundary.normalized

def Boundary.hasLineStructure (boundary : Boundary) : Bool :=
  SpaceRules.hasLineStructure boundary.normalized

def Boundary.commentForcesBreak (boundary : Boundary) : Bool :=
  SpaceRules.commentForcesLineBreak boundary.normalized

def Boundary.hasLineComment (boundary : Boundary) : Bool :=
  boundary.normalized.splitOn "\n"
  |>.any fun line => (SpaceRules.stripLeadingHorizontalWhitespace line).startsWith "--"

def Boundary.startsOnNewLine (boundary : Boundary) : Bool :=
  match boundary.normalized.toList.dropWhile SpaceRules.isHorizontalWhitespace with
  | '\n' :: _ => true
  | _ => false

def Boundary.startsAfterBlankLine (boundary : Boundary) : Bool :=
  let leadingWhitespace :=
    boundary.normalized.toList.takeWhile
      fun char => char == '\n' || SpaceRules.isHorizontalWhitespace char
  2 <= leadingWhitespace.count '\n'

def Boundary.endsBeforeBlankLine (boundary : Boundary) : Bool :=
  let trailingWhitespace :=
    boundary.normalized.toList.reverse.takeWhile
      fun char => char == '\n' || SpaceRules.isHorizontalWhitespace char
  2 <= trailingWhitespace.count '\n'

def Boundary.hasSeparatedCommentGroups (boundary : Boundary) : Bool :=
  SpaceRules.commentTriviaHasSeparatedGroups boundary.normalized

def Boundary.standaloneCommentIndent? (boundary : Boundary) : Option Nat :=
  SpaceRules.standaloneSourceCommentIndent? boundary.normalized

def Boundary.standaloneLineCommentIndent? (boundary : Boundary) : Option Nat :=
  match boundary.normalized.splitOn "\n" with
  | [] | [_] => none
  | _ :: rest =>
      rest.findSome?
        fun line =>
          let stripped := SpaceRules.stripLeadingHorizontalWhitespace line
          if stripped.startsWith "--" then
            some (line.length - stripped.length)
          else
            none

def Boundary.firstCommentColumn? (boundary : Boundary) (firstLineColumn : Nat)
    : Option Nat :=
  SpaceRules.firstCommentColumn? boundary.normalized firstLineColumn

def Boundary.beginsMultilineBlockComment (boundary : Boundary) : Bool :=
  let firstLine := boundary.normalized.splitOn "\n" |>.headD ""
  0 < SpaceRules.blockCommentDepthAfterLine 0 firstLine

def Boundary.cleaned (boundary : Boundary) : Boundary :=
  ofText <| SpaceRules.cleanTrivia boundary.normalized

def Boundary.moveLeadingCommentAfterToken? (boundary : Boundary) : Option Boundary :=
  (SpaceRules.moveLeadingCommentAfterToken? boundary.normalized).map ofText

def Boundary.forBreakWithFollowingIndent
    (boundary : Boundary) (commentIndent followingIndent : String)
    : String :=
  SpaceRules.commentTriviaForBreakWithFollowingIndent boundary.normalized
    commentIndent followingIndent

def Boundary.forTreeBoundary
    (boundary : Boundary)
    (sourceCommentColumn targetCommentColumn sourceFollowingIndent : Nat)
    (followingIndent : String)
    : String :=
  SpaceRules.commentTriviaForTreeBoundary boundary.normalized sourceCommentColumn
    targetCommentColumn sourceFollowingIndent followingIndent

end SourceBoundary
end Formatter
end LeanFmt
