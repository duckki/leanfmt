# Registered formatter ruleset audit

This audit uses registered Lean formatters only as development-time evidence. It does
not require leanfmt to match Lean's printer, and it does not generate production rules.

## Corpus

The September 2026 review sampled 20 evenly distributed files from each of Lean Core,
Std, and Mathlib `v4.33.0`. Three accepted examples were requested for each normalized
syntax shape.

- 60 files parsed without failure.
- 58,116 registered-syntax occurrences covered 499 normalized structural groups.
- 115 groups produced stable candidates from at least two examples.
- 59 stable candidates had the same direct child boundaries and indentation as leanfmt.
- 54 differed from leanfmt, and 2 had no exact regrouped owner.
- 99 groups varied across accepted samples; 285 did not yield two accepted samples.

The difference count is not a defect count. Registered formatters and leanfmt make
different style choices, and the audit rejects comments, token rewriting, multiline
tokens, column alignment, and other layouts that cannot be translated safely.

## Reviewed differences

Most stable differences are intentional:

- leanfmt indents application and ordinary prefix continuations by one level; many Lean
  formatters use zero-level continuations;
- leanfmt normally breaks before an infix operator, while some registered formatters
  break after it;
- tuples and anonymous constructors use leanfmt's balanced delimiter rules;
- import paths remain unbroken, and `open` and `attribute` lists use their existing
  reviewed peer-flow rules;
- unary prefixes and parser-declaration fragments may retain source-protected layout.

Atomic-looking differences such as double-quoted names, `?_`, `?name`, `:60`,
`ns:ident`, and `atomic(...)` did not produce internal breaks in focused narrow-width probes. Their
explicit compatibility entries may be inventory cleanup candidates, but they are not
formatting defects.

## Open findings

### Parser-described peer applications

`Lean.Parser.Term.matchExprPat` is application-shaped, but its current default rule can
break before the first argument and leave the remaining argument tail overflowing:

```lean
match_expr e with
| VeryLongNamespace.veryLongConstructorName
    _ _ first second third fourth fifth sixth =>
  pure e
```

`Lean.Parser.Level.max` has the same peer-operand shape. The clean fix is to extend the
existing parser-described application classification to these nonordinary term shapes,
not to add syntax-kind rules.

### Command peer sequences

The `universe` command exposes only its first continuation boundary. A long list becomes
one overflowing continuation line:

```lean
universe
  u v w veryLongUniverseName anotherLongUniverseName
```

Its identifier tail should use the existing peer-sequence vocabulary. The change should
be based on the parser shape and should be checked against `variable`, `include`, `omit`,
and other command lists before promotion.

The missing exact owner for `doForDecl` was reviewed as expected regrouping: the
declaration is represented by surrounding `do` ownership, so it does not justify a new
rule.

## Reproduction

Build the development-only tool:

```sh
cd tools/rule-audit
lake build
```

Run it under Mathlib's Lake environment so project parser extensions are available:

```sh
lake env /path/to/leanfmt/tools/rule-audit/.lake/build/bin/ruleAudit \
  --max-files-per-root 20 --max-samples 3 \
  "$(lean --print-prefix)/src/lean/Lean" \
  "$(lean --print-prefix)/src/lean/Std" \
  Mathlib
```

The report compares only normalized direct-child boundaries. Production boundaries may
be owned by any regrouped descendant inside the same source span; nested boundaries
inside one logical child and leading boundaries before the syntax node are excluded.
