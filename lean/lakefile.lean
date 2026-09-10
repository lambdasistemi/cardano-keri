import Lake
open Lake DSL

package «cardano-keri-lean»

@[default_target]
lean_lib CardanoKeri

/-- The ACDC, TEL and delegation statements with their proofs and probes.
Not a default target; `lake build CardanoKeriStatements` builds it. -/
lean_lib CardanoKeriStatements where
  roots := #[`CardanoKeri.Statements]
