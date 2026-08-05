import PlutusCore.Default

/-!
This file is a deliberately invalid compatibility-audit input.  Variant E is
the target named by Milestone 8, but it is absent from the currently pinned
PlutusCoreBlaster package.  The audit must scan this artefact through the same
reference path as the tracked bridge sources, report the reference unresolved,
and convert that expected failure into the seeded-retired-reference control.

It is not imported by the bridge and changes no bridge semantics.
-/

#check PlutusCore.Default.BuiltinSemanticsVariant.defaultFunSemanticsVariantE
