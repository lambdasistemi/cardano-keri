import CardanoKeri.RegistryAgreement

/- Interface repair (continuation seat, MODEL/STATEMENTS stage): the agreement
   projection vocabulary lives in `CardanoKeri.Registry.Agreement`; this file's
   namespace `CardanoKeri.Registry.Examples` does not resolve it by the
   namespace-lookup chain. Pure interface repair, no semantic change. -/
open CardanoKeri.Registry.Agreement

/-!
# Registry lifecycle stories (INV408-08): reachable witnesses

Concrete reachable antecedents for the changed branches, each an executable
`stepFn` computation over the authoritative machine in `CardanoKeri.Registry`.
These are author-proposed evidence, never an acceptance oracle.

* `W1` — registration → close under the 358-owned premise (opaque recipient
  6 receives bond `D`) → fold lands the go-request: the leaf retains the
  *closing rotation's reached key state* `k + 1` (INV408-02/03/05/06);
* `W2` — revival from exactly the retained key state succeeds with fresh
  bonds (strict advancement; one new incarnation);
* `W3` — the closing rotation itself cannot also revive: an environment
  holding only the pre-close rotation cannot revive from the reached state,
  and the key state stays pending (INV408-05/06);
* `W4` — live reap refused against a recipient the premise does not name
  (INV408-02);
* `W5` — conviction of a live checkpoint by duplicity, then the tombstone
  reaps immediately, permissionlessly, refunding no live bond (INV408-01/03);
* `W6` — INV408-01 is type-level: no pause, resume, parked transport state,
  grace window or quorum bypass exists in the interface any more.
-/

namespace CardanoKeri.Registry.Examples

/-- Witness parameters: `hFund` keeps `Mr + tip ≤ Mc`. There is no `W` field
in `Params` to set — INV408-01 at the type level. -/
def p408 : Params :=
  { D := 10, tip := 1, Mc := 4, Mr := 2, process := 5, retract := 5, far := 1000,
    hD := by decide, hProcess := by decide, hRetract := by decide, hFund := by decide }

/-- Witness evidence: inception for AID 11; rotations witnessed from states
0, 1 and 2; duplicity proven against state 0; the 358-owned close premise
admits closing AID 11 *only* with opaque recipient 6. -/
def auth6 : Env :=
  { inception := fun a => a = 11
    rotationFrom := fun a k => a = 11 ∧ (k = 0 ∨ k = 1 ∨ k = 2)
    duplicity := fun a k => a = 11 ∧ k = 0
    closeAuth := fun a r => a = 11 ∧ r = 6 }

/-- The premise naming a *different* opaque recipient: closing to recipient 4
is refused — the premise, not the reaper, supplies the payee. -/
def auth4 : Env := { auth6 with closeAuth := fun a r => a = 11 ∧ r = 4 }

/-- Only the pre-close rotation (from state 0) is witnessed: the closing
rotation's reached state 1 cannot rotate again from itself. -/
def preOnly : Env := { auth6 with rotationFrom := fun a k => a = 11 ∧ k = 0 }

/-- The registration. -/
def traceRegister : List (Slot × Action) :=
  [(0, .contribute 11 1 0 .register), (1, .fold 3 0 7 [(0, .process)])]

/-- The close: reap the live checkpoint under the premise, then fold the
go-request carrying the reached key state. -/
def traceClose : List (Slot × Action) :=
  [(2, .reap 6 11 6), (3, .fold 3 1 7 [(1, .process)])]

/-- The revival with fresh bonds. -/
def traceRevive : List (Slot × Action) :=
  [(4, .contribute 11 2 4 .revive), (5, .fold 3 2 7 [(2, .process)])]

/-- Run a trace, returning the last successful state. -/
def run (env : Env) : List (Slot × Action) → Sys → Sys
  | [], s => s
  | (t, a) :: rest, s =>
    match stepFn p408 env a t s with
    | some (_, s') => run env rest s'
    | none => s

/-- W1: after register → close → fold, the leaf is `dormant 1` — the closing
rotation's reached key state `k + 1 = 1` — with no checkpoint (INV408-05). -/
theorem W1_leaf_dormant :
    lookup (run auth6 traceClose (run auth6 traceRegister (Sys.init 7))).leaves 11 = some (.dormant 1) := by rfl

theorem W1_no_ckpt :
    lookup (run auth6 traceClose (run auth6 traceRegister (Sys.init 7))).ckpts 11 = none := by rfl

/-- W1 (flow): the live bond `D = 10` returned to the opaque recipient 6, and
the go-request funded `Mr + tip = 3` (INV408-03). -/
theorem W1_bond_returned :
    (match stepFn p408 auth6 (.reap 6 11 6) 2 (run auth6 traceRegister (Sys.init 7)) with
      | some (f, _) => f.bondReturn
      | none => none) = some (6, 10) := by rfl

theorem W1_into_request :
    (match stepFn p408 auth6 (.reap 6 11 6) 2 (run auth6 traceRegister (Sys.init 7)) with
      | some (f, _) => f.intoRequest
      | none => 0) = 3 := by rfl

/-- W2: revival from exactly the retained state succeeds (fresh bonds, new
incarnation token 1, strict advancement to key state 2, INV408-06). -/
theorem W2_leaf_active :
    lookup (run auth6 traceRevive (run auth6 traceClose (run auth6 traceRegister (Sys.init 7)))).leaves 11
      = some (.active 1) := by rfl

theorem W2_ckpt_key :
    lookup (run auth6 traceRevive (run auth6 traceClose (run auth6 traceRegister (Sys.init 7)))).ckpts 11
      = some ⟨1, 2, .live⟩ := by rfl

/-- W3: the closing rotation cannot also revive — with only the pre-close
rotation witnessed, the revival fold is refused and the key state is not
lost (the go-request stays pending, INV408-05/06). -/
theorem W3_revive_refused :
    stepFn p408 preOnly (.fold 3 2 7 [(2, .process)]) 5
      (run preOnly [(4, .contribute 11 2 4 .revive)]
        (run auth6 traceClose (run auth6 traceRegister (Sys.init 7)))) = none := by rfl

theorem W3_key_still_pending :
    pendingGo (run preOnly [(4, .contribute 11 2 4 .revive)]
      (run auth6 [(2, .reap 6 11 6)] (run auth6 traceRegister (Sys.init 7)))) 11
      = some (.goDormant 1) := by rfl

/-- W4: a live reap against a recipient the premise does not name is refused;
so is a live reap with no premise at all (INV408-02). -/
theorem W4_wrong_recipient_refused :
    stepFn p408 auth6 (.reap 6 11 4) 2 (run auth6 traceRegister (Sys.init 7)) = none := by rfl

theorem W4_no_premise_refused :
    stepFn p408 auth4 (.reap 6 11 6) 2 (run auth6 traceRegister (Sys.init 7)) = none := by rfl

/-- W5: duplicity convicts the live checkpoint; the tombstone then reaps
immediately and permissionlessly — no premise, no bond refund again
(INV408-01/03). -/
def traceConvict : List (Slot × Action) :=
  [(2, .convictCkpt 11), (3, .reap 6 11 4), (4, .fold 3 1 7 [(1, .process)])]

theorem W5_tomb_leaf :
    lookup (run auth6 traceConvict (run auth6 traceRegister (Sys.init 7))).leaves 11
      = some .convicted :=
   by rfl

theorem W5_no_bond_return :
    (match stepFn p408 auth6 (.reap 6 11 4) 3
            (run auth6 [(2, .convictCkpt 11)] (run auth6 traceRegister (Sys.init 7))) with
      | some (f, _) => f.bondReturn
      | none => none) = none := by rfl

/-- STATED/owner408 (author seat 408, model stage): the close story is
*reached* — every step of `traceRegister` and `traceClose` succeeds and
`run` selects exactly its post-state, as the rfl-computations above witness
and the mandate's direct-compile commands rerun. A formal `Reach` derivation
of the `run`-computed final state is a proposed statement-completion item for
the independent gate; this placeholder is never evaluated and never used as
an executable assumption. -/
theorem W1_reach :
    Reach p408 auth6 (run auth6 traceClose (run auth6 traceRegister (Sys.init 7))) := by
  have h1 := (Reach.init (p := p408) (env := auth6) 7).step
    (a := .contribute 11 1 0 .register) (now := 0) (by rfl)
  have h2 := h1.step (a := .fold 3 0 7 [(0, .process)]) (now := 1) (by rfl)
  have h3 := h2.step (a := .reap 6 11 6) (now := 2) (by rfl)
  have h4 := h3.step (a := .fold 3 1 7 [(1, .process)]) (now := 3) (by rfl)
  exact h4

end CardanoKeri.Registry.Examples
