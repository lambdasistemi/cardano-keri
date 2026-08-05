import PlutusCore.UPLC

/-!
This file is a deliberately invalid compatibility-audit input.  It names the
retired plural spelling of the pinned CEK entry point; the current package owns
`cekExecuteProgramWithSemanticVariant` (singular).  The audit must scan this
artefact through the same reference path as the tracked bridge sources, report
the reference unresolved, and convert that expected failure into the
seeded-retired-reference control.

It is not imported by the bridge and changes no bridge semantics.
-/

#check PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticsVariant
