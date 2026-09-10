import CardanoKeri.Statements.Mirror

/-!
# Mirror statements M1 … M13 — unproven

STATEMENTS mode: every theorem ends in `sorry`. Rulings: #392 and
`docs/design/credential-verification.md` ("The revocation mirror").
Mutants named per theorem; the ledger is `STATEMENTS-ATOMS.md`.

Repair 2: M2, M4 and M9 take a reachability premise. Over arbitrary
systems a registry stored under a key other than its own id makes them
false; reachable systems store every registry under its id.
-/

namespace CardanoKeri.Mirror

open CardanoKeri.History

/-- **M1. Only the issuer revokes.** Every SAID in a reachable registry's
set got there by a push whose `rev` walked against the checkpoint of that
registry's issuer at the time (the issuer's own cryptography is the
permission). Mutant: `push` that skips `sealWalk`. -/
theorem M1_only_the_issuer_revokes (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) {said : Said}
    (hrev : r.revoked said = true) :
    ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ stepFn p env s₀ (.push w) = some s₁ ∧
      ReachFrom p env s₁ s ∧ w.tel.kind = .rev ∧ w.tel.i = said ∧ w.tel.ri = rid ∧
      s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧ sealWalk p env c rid w = some v := by
  sorry

/-- **M2. A revocation is permanent, and a registry never closes or changes
hands.** No step removes a SAID from a set, or the registry, or alters its
issuer or id. Over-revocation therefore fails closed. Mutant: an action
that deletes from the set. -/
theorem M2_revocation_is_permanent (p : Params) (env : TelEnv) {s s' : Sys} (h : Reach p env s) {a : Action}
    (hs : stepFn p env s a = some s') {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    ∃ r', s'.reg rid = some r' ∧ r'.issuer = r.issuer ∧ r'.rid = r.rid ∧
      ∀ said, r.revoked said = true → r'.revoked said = true := by
  sorry

/-- **M3. A duplicate push is refused and harmless.** Pushing a SAID already
in the set fails on the insert; nothing else could have changed. Mutant:
`push` that re-inserts and, say, resets the registry. -/
theorem M3_duplicate_push_refused (p : Params) (env : TelEnv) {s : Sys} {w : Walk} {r : Registry}
    (hr : s.reg w.tel.ri = some r) (hin : r.revoked w.tel.i = true) :
    stepFn p env s (.push w) = none := by
  sorry

/-- **M4. Pushes commute.** Two pushes of distinct SAIDs enabled from the
same reachable system land in either order on the same system: the set
converges however it is filled, which is why the mirror needs no
completeness guarantee. Mutant: a push that records its position (an
order-dependent accumulator). -/
theorem M4_pushes_commute (p : Params) (env : TelEnv) {s s₁ s₂ : Sys} (h : Reach p env s) {w₁ w₂ : Walk}
    (hne : w₁.tel.i ≠ w₂.tel.i)
    (h₁ : stepFn p env s (.push w₁) = some s₁) (h₂ : stepFn p env s (.push w₂) = some s₂) :
    ∃ s₁₂ s₂₁, stepFn p env s₁ (.push w₂) = some s₁₂ ∧ stepFn p env s₂ (.push w₁) = some s₂₁ ∧
      s₁₂ = s₂₁ := by
  sorry

/-- **M5. A registry is bound to its issuer by the `vcp` seal.** Every
reachable registry was opened by a walk of a `vcp` naming its id, against
the checkpoint of the AID it records as issuer. Mutant: `open` that trusts
the `issuer` argument without the walk. -/
theorem M5_registry_bound_to_issuer (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    r.rid = rid ∧ ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧
      stepFn p env s₀ (.open r.issuer w) = some s₁ ∧ ReachFrom p env s₁ s ∧
      w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧ c.aid = r.issuer ∧
      sealWalk p env c rid w = some v := by
  sorry

/-- **M6. Push, exactly** (public inversion). A push is enabled iff the
registry exists, its issuer has a checkpoint, the event is a `rev` not
yet in the set, and its seal walks with any verdict — no owner, no current
key, no deadline appears. Mutant: a push guard on the issuer's `cur`. -/
theorem M6_push_iff (p : Params) (env : TelEnv) (s : Sys) (w : Walk) (s' : Sys) :
    stepFn p env s (.push w) = some s' ↔
      ∃ r c, s.reg w.tel.ri = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .rev ∧
        r.revoked w.tel.i = false ∧ (∃ v, sealWalk p env c r.rid w = some v) ∧
        s' = s.setReg r.rid (some (r.insert w.tel.i)) := by
  sorry

/-- **M7. Open, exactly** (public inversion). A registry opens iff no
registry of that id exists, the issuer has a checkpoint, the event is a
`vcp` whose seal walks, and the new registry records the walk's anchor
with an empty set. Mutant: `open` accepting an `iss` as the inception. -/
theorem M7_open_iff (p : Params) (env : TelEnv) (s : Sys) (issuer : AID) (w : Walk) (s' : Sys) :
    stepFn p env s (.open issuer w) = some s' ↔
      ∃ c v a, s.reg w.tel.i = none ∧ s.ckpt issuer = some c ∧ w.tel.kind = .vcp ∧
        sealWalk p env c w.tel.i w = some v ∧ anchorOf c w.core v = some a ∧
        s' = s.setReg w.tel.i (some ⟨issuer, w.tel.i, a, fun _ => false⟩) := by
  sorry

/-- **M8. The mirror never reads current keys.** Opening, pushing and
re-anchoring are invariant under the issuer's current key state (S3
lifted to the system): "current keys cannot vouch for past events" and
cannot block them either. Mutant: `push` requiring `env.signed c.cur`. -/
theorem M8_mirror_ignores_current_keys (p : Params) (env : TelEnv) (s : Sys) (aid : AID) (x : Epoch)
    (a : Action) (hmirror : (∃ i w, a = .open i w) ∨ (∃ w, a = .push w) ∨ ∃ w, a = .reanchor w) :
    (stepFn p env (s.setCur aid x) a).map (fun t => t.reg) = (stepFn p env s a).map (fun t => t.reg) := by
  sorry

/-- **M9. A superseded push over-revokes.** A `rev` pushed under a
provisional walk whose issuer then rotates at or below the sealing
sequence stays in the set, while the same walk now fails: the mirror fails
closed. Mutant: an eviction of revocations on superseding. -/
theorem M9_superseded_push_over_revokes (p : Params) (env : TelEnv) {s s₁ s₂ : Sys} (h : Reach p env s)
    {w : Walk} {r : Registry} {c c' : Checkpoint} {e' : Seq} {t : Nat} {appr : Option Approval}
    (hr : s.reg w.tel.ri = some r) (hc : s.ckpt r.issuer = some c)
    (hprov : sealWalk p env c r.rid w = some .provisional)
    (h₁ : stepFn p env s (.push w) = some s₁)
    (h₂ : stepFn p env s₁ (.history r.issuer (.advance e' t appr)) = some s₂)
    (hle : e' ≤ w.core.kel.sn) (hc' : s₂.ckpt r.issuer = some c') :
    (∃ r', s₂.reg w.tel.ri = some r' ∧ r'.revoked w.tel.i = true) ∧
      sealWalk p env c' r.rid w = none := by
  sorry

/-- **M10. Freshness is not enforced** (a witness, not a guarantee). There
is a reachable system, an issuer and a `rev` whose seal walks — the issuer
anchored the revocation — while the mirror still reports absence, because
nobody pushed it. Refuting this would mean the model enforces a freshness
it does not have. Mutant: none — this documents a stated limit (#398). -/
theorem M10_freshness_unenforced :
    ∃ (p : Params) (env : TelEnv) (s : Sys) (issuer : AID) (c : Checkpoint) (rid : RegistryId)
      (w : Walk) (v : Verdict),
      Reach p env s ∧ s.ckpt issuer = some c ∧ (∃ r, s.reg rid = some r ∧ r.issuer = issuer) ∧
      w.tel.kind = .rev ∧ w.tel.ri = rid ∧ sealWalk p env c rid w = some v ∧
      miss s rid w.tel.i = true := by
  sorry

/-- **M11. No registry, no absence.** The gate's absence check fails closed
on a registry that was never opened. Mutant: `miss` returning `true` on
`none`. -/
theorem M11_miss_fails_closed (s : Sys) (rid : RegistryId) (said : Said) (h : s.reg rid = none) :
    miss s rid said = false := by
  sorry

/-- **M12. Re-anchor, exactly** (public inversion). A registry's inception
anchor is replaced iff the registry exists, its issuer has a checkpoint, a
`vcp` naming the registry walks, and the new anchor is that walk's; the
set and the issuer are untouched. Anyone may do it: the issuer's own seal
on its accepted branch is the permission. Mutant: `reanchor` that also
resets the set. -/
theorem M12_reanchor_iff (p : Params) (env : TelEnv) (s : Sys) (w : Walk) (s' : Sys) :
    stepFn p env s (.reanchor w) = some s' ↔
      ∃ r c v a, s.reg w.tel.i = some r ∧ s.ckpt r.issuer = some c ∧ w.tel.kind = .vcp ∧
        sealWalk p env c r.rid w = some v ∧ anchorOf c w.core v = some a ∧
        s' = s.setReg r.rid (some { r with inception := a }) := by
  sorry

/-- **M13. A registry's inception anchor is a walk's anchor.** In a
reachable system every registry's inception anchor was produced, by an
open or a re-anchor, from a successful walk of a `vcp` naming the registry
against the checkpoint of its issuer at the time. Mutant: `reanchor`
storing a caller-supplied anchor. -/
theorem M13_inception_is_a_walk_anchor (p : Params) (env : TelEnv) {s : Sys} (h : Reach p env s)
    {rid : RegistryId} {r : Registry} (hr : s.reg rid = some r) :
    ∃ s₀ s₁ w c v, ReachFrom p env Sys.init s₀ ∧ ReachFrom p env s₁ s ∧
      (stepFn p env s₀ (.open r.issuer w) = some s₁ ∨ stepFn p env s₀ (.reanchor w) = some s₁) ∧
      w.tel.kind = .vcp ∧ w.tel.i = rid ∧ s₀.ckpt r.issuer = some c ∧
      sealWalk p env c rid w = some v ∧ anchorOf c w.core v = some r.inception := by
  sorry

end CardanoKeri.Mirror
