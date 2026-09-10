module

public import Lean

import LeanFmt.Tests.PrivateModuleDependency

public section

syntax (name := exportedModuleSyntax) "exported_module_syntax" : term

macro (name := exportedKeywordSyntax) "exported_keyword%" value:term : term => `($value)
