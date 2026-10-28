import Lake
open Lake DSL

package «cardano-keri-lean»

require singular from git
  "https://github.com/lambdasistemi/singular.git" @
  "a84b253730003c9b0a8961b80e2e5449ba480a62"

@[default_target]
lean_lib CardanoKeri

/-- The ACDC, TEL and delegation statements with their proofs and probes.
Not a default target; `lake build CardanoKeriStatements` builds it. -/
lean_lib CardanoKeriStatements where
  roots := #[`CardanoKeri.Statements]
