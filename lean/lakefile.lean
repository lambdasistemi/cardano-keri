import Lake
open Lake DSL

package «cardano-keri-lean»

require singular from git
  "https://github.com/lambdasistemi/singular.git" @
  "f844a8f423eaf65009c587b9d7dd9ad3e00d21af"

@[default_target]
lean_lib CardanoKeri

/-- The ACDC, TEL and delegation statements with their proofs and probes.
Not a default target; `lake build CardanoKeriStatements` builds it. -/
lean_lib CardanoKeriStatements where
  roots := #[`CardanoKeri.Statements]
