import CardanoKeri.Cage

open CardanoKeri.Cage
open CardanoKeri.Registry

namespace CardanoKeri.Mutants

/-- CG-03 (A-001 additive): `authorized.ownerAndHook` requires plugin
withdrawal — an owner-signed request whose hook did not run refuses. The
frozen `ownerAndHook_trivial_breaks_inv` exercises only the both-true case,
so this pins the missing conjunct directly. -/
theorem CG03_ownerAndHook_requires_hook : authorized .ownerAndHook ⟨true, false⟩ = false := by decide

end CardanoKeri.Mutants

-- Premise: owner-signed with hook run authorizes (reachable allow-path).
example : authorized .ownerAndHook ⟨true, true⟩ = true := by decide
-- Premise: owner-signed without hook run refuses (concrete sensor input).
example : authorized .ownerAndHook ⟨true, false⟩ = false := by decide
-- The additive assertion applied to its sensor input.
example : authorized .ownerAndHook ⟨true, false⟩ = false :=
  CardanoKeri.Mutants.CG03_ownerAndHook_requires_hook
