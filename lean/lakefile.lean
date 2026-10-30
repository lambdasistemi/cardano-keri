import Lake
open Lake DSL

package «cardano-keri-lean»

require singular from git
  "https://github.com/lambdasistemi/singular.git" @
  "d69ab005c3b710aeebf033d3c5cd08c56feb5643"

@[default_target]
lean_lib CardanoKeri

/-- The ACDC, TEL and delegation statements with their proofs and probes.
Not a default target; `lake build CardanoKeriStatements` builds it. -/
lean_lib CardanoKeriStatements where
  roots := #[`CardanoKeri.Statements]

/-- Identity declarations from the same pinned public Singular tree. This
library owns the nested source path without introducing a second revision. -/
lean_lib SingularApplicationHeld where
  srcDir := ".lake/packages/singular/models/singular-application-held/lean"
  roots := #[`SingularApplicationHeld.Assets, `SingularApplicationHeld.Core]
