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
* `W3a_contribution_keeps_pending` — the close request carrying the reached
  key state stays pending across a competing contribution, before the close
  fold (INV408-05);
* `W3b_revival_fold_refused` / `W3b_refused_revival_keeps_leaf` — the
  connected close/fold/post/refused-revival journey: with only the pre-close
  rotation witnessed, the posted revival fold is refused and the leaf keeps
  the dormant key state with no checkpoint, instantiating
  `refused_revival_keeps_leaf` (INV408-05/06);
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

/-- W3a: the close request remains pending across a competing contribution,
BEFORE the close fold. Journey: register, fold, close under the premise, then
a competing revive contribution — the go-request carrying the reached key
state 1 is still pending. Boundary: posting only; no fold is attempted here. -/
def traceClosePosted : List (Slot × Action) :=
  traceRegister ++ [(2, .reap 6 11 6), (4, .contribute 11 4 4 .revive)]

theorem W3a_contribution_keeps_pending :
    pendingGo (run auth6 traceClosePosted (Sys.init 7)) 11 = some (.goDormant 1) := by rfl

/-- W3b, the connected journey: register, fold, close, the close fold landing
dormant 1, the posted revival request, the attempted revival fold. Its first
FIVE steps are exactly `preRefusedRevival`'s; the sixth is the refused action
below. -/
def traceRefusedRevival : List (Slot × Action) :=
  traceRegister ++ [(2, .reap 6 11 6), (3, .fold 3 1 7 [(1, .process)]),
                    (4, .contribute 11 1 4 .revive), (5, .fold 3 2 7 [(2, .process)])]

/-- W3b, the exact prestate: the connected close/fold/post prefix — register,
fold, close under the premise, the close fold landing dormant 1, then the
posted revival request — under the environment witnessing only the pre-close
rotation. Both W3b statements below are bound to THIS state, so the refusal
cannot be stale-metadata (wrong generation) or a missing request. -/
def preRefusedRevival : Sys :=
  run preOnly
    (traceRegister ++ [(2, .reap 6 11 6), (3, .fold 3 1 7 [(1, .process)]),
                       (4, .contribute 11 1 4 .revive)])
    (Sys.init 7)

/-- The prefix is `ReachFar` (every step succeeds, all slots strictly before
the horizon) — the generic refused-revival theorem's assumed domain is
inhabited by this exact prestate. -/
theorem preRefusedRevival_reachFar : ReachFar p408 preOnly preRefusedRevival := by
  have h0 : ReachFar p408 preOnly (Sys.init 7) := .init 7
  have h1 := h0.step (a := .contribute 11 1 0 .register) (now := 0) (by decide) (by rfl)
  have h2 := h1.step (a := .fold 3 0 7 [(0, .process)]) (now := 1) (by decide) (by rfl)
  have h3 := h2.step (a := .reap 6 11 6) (now := 2) (by decide) (by rfl)
  have h4 := h3.step (a := .fold 3 1 7 [(1, .process)]) (now := 3) (by decide) (by rfl)
  exact h4.step (a := .contribute 11 1 4 .revive) (now := 4) (by decide) (by rfl)

/-- W3b, the refused action: the final fold of the journey — processing the
posted revival of dormant 1 at generation 2, exactly the prestate above — is
refused: the environment witnesses no rotation from the retained key state. -/
theorem W3b_revival_fold_refused :
    stepFn p408 preOnly (.fold 3 2 7 [(2, .process)]) 5 preRefusedRevival = none := by rfl

/-- W3b, the retained state: applying exactly that refused action from exactly
that prestate (definitional with the full journey `run preOnly
traceRefusedRevival (Sys.init 7)`) leaves the leaf at dormant 1 with no
checkpoint. The generic theorem `refused_revival_keeps_leaf`
(CardanoKeri.Registry.Agreement) states this boundary in general; these
witnesses compute the concrete journey directly and do not formally bind its
preconditions — its current type concludes facts about the retained input
state, its proof using only the retained-leaf hypothesis and R1c. -/
theorem W3b_refused_revival_keeps_leaf :
    lookup (run preOnly [(5, .fold 3 2 7 [(2, .process)])] preRefusedRevival).leaves 11 = some (.dormant 1) ∧
    lookup (run preOnly [(5, .fold 3 2 7 [(2, .process)])] preRefusedRevival).ckpts 11 = none :=
  ⟨rfl, rfl⟩

/-- W3b, positive fixture control (not a production semantic mutation kill):
from the SAME `preRefusedRevival` with the SAME action, rotation evidence
from the retained key state 1 (env `auth6`) lets the fold succeed — leaf
active 1, live checkpoint at key state 2 — so the refusal is attributable to
the missing witness, not to stale generation or a missing request.
Supplementary: the full auth6 journey computes the same post-state
(`W3b_positive_rotation_revives_journey`). -/
theorem W3b_positive_rotation_revives :
    ∃ f s', stepFn p408 auth6 (.fold 3 2 7 [(2, .process)]) 5 preRefusedRevival = some (f, s') ∧
      lookup s'.leaves 11 = some (.active 1) ∧ lookup s'.ckpts 11 = some ⟨1, 2, .live⟩ :=
  ⟨_, _, rfl, rfl, rfl⟩

/-- Supplementary: the full auth6 journey through `run` reaches the same
successful revival. -/
theorem W3b_positive_rotation_revives_journey :
    lookup (run auth6 traceRefusedRevival (Sys.init 7)).leaves 11 = some (.active 1) ∧
    lookup (run auth6 traceRefusedRevival (Sys.init 7)).ckpts 11 = some ⟨1, 2, .live⟩ :=
  ⟨rfl, rfl⟩

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

/-- W1: the close story is *reached* — a formal `Reach` derivation: every
step of `traceRegister` and `traceClose` succeeds and each `step` links the
`run`-computed post-states, from `Reach.init`. -/
theorem W1_reach :
    Reach p408 auth6 (run auth6 traceClose (run auth6 traceRegister (Sys.init 7))) := by
  have h1 := (Reach.init (p := p408) (env := auth6) 7).step
    (a := .contribute 11 1 0 .register) (now := 0) (by rfl)
  have h2 := h1.step (a := .fold 3 0 7 [(0, .process)]) (now := 1) (by rfl)
  have h3 := h2.step (a := .reap 6 11 6) (now := 2) (by rfl)
  have h4 := h3.step (a := .fold 3 1 7 [(1, .process)]) (now := 3) (by rfl)
  exact h4

/-! ## A-003 antecedent control: pending custody needs the reachable domain

The universal pending-custody theorem (A-002(a), ruled by A-003) assumes
`ReachFar p env s` **and** `now < p.far`. This control shows the
reachable-domain hypothesis is load-bearing: in an arbitrary system whose
inbox holds the same `goDormant` request with an early `submittedAt`, the
retract **succeeds** and the successor's `pendingGo` is `none` — the key
state is lost without any consuming fold. Throughout the control `now <
p.far` holds (`ant408_now_before_far` pins this), so the control alone
demonstrates nothing about the horizon hypothesis, and no separate
horizon-negative control is asserted here. Classification: **antecedent control** for
the theorem's statement domain. It is not a production mutation kill and not
a reachable counterexample: the control system has a go-request pending while
its leaf is absent, so `Inv.goActive` fails there and no `ReachFar`
derivation exists (`ant408_not_reachable` proves this, closing the route back
to the reachable theorem). -/

/-- Control parameters: phase 1 is 10 slots, phase 2 is 10, the end of time
is far away. No premise of any kind is used. -/
def pc408 : Params :=
  { D := 10, tip := 2, Mc := 4, Mr := 1, process := 10, retract := 10,
    far := 1000000000,
    hD := by decide, hProcess := by decide, hRetract := by decide, hFund := by decide }

/-- Empty evidence: the control runs against no premise at all. -/
def ec408 : Env :=
  { inception := fun _ => false, rotationFrom := fun _ _ => false,
    duplicity := fun _ _ => false, closeAuth := fun _ _ => false }

/-- The arbitrary system: one early-dated go-request, nothing else.
Deliberately unreachable — `ant408_not_reachable`. -/
def sc408 : Sys :=
  { gen := 0, plugin := 7, leaves := [], ckpts := [],
    requests := [(0, ⟨11, 1, 0, .goDormant 1⟩)], nextReq := 1, nextToken := 0 }

/-- Antecedent: `pendingGo` sees the request. -/
theorem ant408_pending_before :
    pendingGo sc408 11 = some (.goDormant 1) := by rfl

/-- Antecedent: the clock is inside the horizon. -/
theorem ant408_now_before_far : (10 : Slot) < pc408.far := by decide

/-- The control: the retract succeeds at `now = 10` — phase 2 of the
early-dated request — and the successor's `pendingGo` is `none`. Without the
reachable domain the universal custody statement would be false at `now <
p.far` and with no fold anywhere. -/
theorem ant408_retract_loses_pending :
    ∃ f s', stepFn pc408 ec408 (.retract 0) 10 sc408 = some (f, s') ∧
      pendingGo s' 11 = none :=
  ⟨_, _, rfl, rfl⟩

/-- The domain witness: the control system is not reachable, so this is not a
counterexample to the reachable theorem — it fixes the theorem's statement
domain instead. -/
theorem ant408_not_reachable :
    ¬ ReachFar pc408 ec408 sc408 := by
  intro h
  have hi := reach_inv pc408 ec408 h
  have hgo : goIn sc408.requests 11 :=
    ⟨(0, ⟨11, 1, 0, .goDormant 1⟩), List.mem_cons.2 (Or.inl rfl), rfl, rfl⟩
  obtain ⟨tok, ht⟩ := hi.goActive 11 hgo
  simp [sc408, lookup] at ht

end CardanoKeri.Registry.Examples
