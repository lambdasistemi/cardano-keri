import Lake
open Lake DSL

package «cardano-keri-lean»

@[default_target]
lean_lib CardanoKeri

/-- Unproven statements (STATEMENTS mode): the ACDC, TEL and delegation
surface. Not a default target; `lake build CardanoKeriStatements` builds it
and reports its intentional `sorry`s. -/
lean_lib CardanoKeriStatements where
  roots := #[`CardanoKeri.Statements]
