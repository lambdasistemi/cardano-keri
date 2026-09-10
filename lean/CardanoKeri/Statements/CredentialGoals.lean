import CardanoKeri.Statements.Credential

/-!
# Credential statements C1 … C15 — unproven

STATEMENTS mode: every theorem ends in `sorry`. Rulings: #31 as amended by
#391/#392, `docs/acdc-primer.md` ("how we verify an ACDC is not forged"),
`docs/design/credential-verification.md`, `docs/design/defi-gate.md`.
Mutants named per theorem; the ledger is `STATEMENTS-ATOMS.md`.
-/

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

/-- **C1. An admitted chain is pinned.** It is non-empty, within the depth
bound, its schemas are the policy's by position, its last hop has no edge
and is issued by the pinned root. Mallory's chain that does not lead to the
root is refused. Mutant: drop the root check on the last hop. -/
theorem C1_admitted_chain_is_pinned (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    hops ≠ [] ∧ hops.length ≤ pol.maxDepth ∧ hops.map (·.acdc.body.schema) = pol.schemas ∧
      ∃ last, hops.getLast? = some last ∧ last.acdc.body.edge = none ∧
        last.acdc.body.issuer = pol.root := by
  sorry

/-- **C2. Every hop was sealed by its issuer.** Each credential's `iss`,
naming that credential and its registry, walks against the checkpoint of
the AID the credential names as issuer. A credential with `i = QVI` and a
signature by Mallory's keys has no leaf whose keys signed it. Mutant:
`hopVerdict` that walks against the *presenter's* checkpoint. -/
theorem C2_every_hop_sealed_by_its_issuer (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    ∀ hop ∈ hops, hop.walk.tel.kind = .iss ∧ hop.walk.tel.i = hop.acdc.said ∧
      ∃ c v', s.ckpt hop.acdc.body.issuer = some c ∧
        sealWalk p env.toTelEnv c hop.acdc.body.registry hop.walk = some v' := by
  sorry

/-- **C3. Integrity and edges.** Every admitted credential's SAID is the
digest of its body, and each hop's edge names exactly the next hop's SAID:
change a byte, or swap a parent, and the chain is refused. Mutant:
`hopVerdict` that ignores `edge`. -/
theorem C3_integrity_and_edges (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    (∀ hop ∈ hops, env.saidOf hop.acdc.body = hop.acdc.said) ∧
      ∀ i h₁ h₂, hops[i]? = some h₁ → hops[i + 1]? = some h₂ →
        h₁.acdc.body.edge = some h₂.acdc.said := by
  sorry

/-- **C4. A revoked link refuses the whole chain** (the cascade at
admission). Mutant: `hopVerdict` that checks the mirror on the leaf only. -/
theorem C4_revoked_link_refuses (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {hop : Hop} (hin : hop ∈ hops) {r : Registry}
    (hr : s.reg hop.acdc.body.registry = some r) (hrev : r.revoked hop.acdc.said = true) :
    admitChain p env s pol hops = none := by
  sorry

/-- **C5. No mirror, no admission.** A hop whose registry has not been
opened, or whose registry belongs to another issuer, cannot be admitted:
absence is proven against a registry UTxO or not at all. Mutant:
`hopVerdict` treating a missing registry as "nothing revoked". -/
theorem C5_unopened_registry_refuses (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {hop : Hop} (hin : hop ∈ hops)
    (hreg : s.reg hop.acdc.body.registry = none ∨
      ∃ r, s.reg hop.acdc.body.registry = some r ∧ r.issuer ≠ hop.acdc.body.issuer) :
    admitChain p env s pol hops = none := by
  sorry

/-- **C6. The chain is provisional iff some hop is.** Exactly when one hop's
covering leaf is its issuer's latest (H4). Mutant: `Verdict.meet` that
returns `final` on any final. -/
theorem C6_provisional_iff_some_hop (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    v = .provisional ↔ ∃ hop ∈ hops, ∃ c, s.ckpt hop.acdc.body.issuer = some c ∧
      cover c hop.walk.core.e hop.walk.core.kel.sn hop.walk.core.succ = some .provisional := by
  sorry

/-- **C7. Admission never reads current keys.** The verdict is invariant
under any issuer's current key state: "issued then" is answered by history
leaves, "authorizes now" by a different reference input (S3 lifted).
Mutant: `hopVerdict` checking the issuer's `cur`. -/
theorem C7_admission_ignores_current_keys (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    (aid : AID) (x : Epoch) (hops : List Hop) :
    admitChain p env (s.setCur aid x) pol hops = admitChain p env s pol hops := by
  sorry

/-- **C8. A final admission is never evicted.** Eviction needs a moved
dependency, and a final dependency cannot move (H5). Mutant: `Dep.moved`
ignoring the verdict, or `evict` without the `moved` guard. -/
theorem C8_final_never_evicted (p : Params) (env : CEnv) (pol : Policy) {s : Sys} (h : Reach p env pol s)
    {key : AID} {ad : Admission} (hc : s.cage key = some ad) (hfin : ad.verdict = .final) :
    stepFn p env pol s (.evict key) = none := by
  sorry

/-- **C9. Evict, exactly** (public inversion). An eviction is enabled iff an
admission exists and one of its dependencies moved: the covering leaf's key
state changed, or a leaf appeared at or below the sealing sequence. Anyone
may do it. Mutant: eviction on a leaf *above* the sealing sequence. -/
theorem C9_evict_iff (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID) (s' : Sys) :
    stepFn p env pol s (.evict key) = some s' ↔
      ∃ ad, s.cage key = some ad ∧ s' = s.setCage key none ∧
        ∃ d ∈ ad.deps, ∃ c, s.ckpt d.issuer = some c ∧
          ((∀ l, c.hist d.e = some l → l.epoch ≠ d.epoch) ∨
            ∃ m, d.e < m ∧ m ≤ d.k ∧ (c.hist m).isSome) := by
  sorry

/-- **C10. A pushed revocation closes every gate below it.** After any
step that puts a SAID of the admitted chain into its registry, the gate is
closed for that key: a revoked QVI credential fails every chain below it
with no extra logic. Mutant: `gate` checking the leaf's registry only. -/
theorem C10_cascade_at_gate (p : Params) (env : CEnv) (pol : Policy) {s s' : Sys} {a : Action}
    (hs : stepFn p env pol s a = some s') {key : AID} {ad : Admission} (hc : s'.cage key = some ad)
    {i : Nat} {said : Said} {rid : RegistryId} (hsaid : ad.saids[i]? = some said)
    (hrid : ad.registries[i]? = some rid) {r : Registry} (hr : s'.reg rid = some r)
    (hrev : r.revoked said = true) (now : Slot) :
    gate pol s' key now = false := by
  sorry

/-- **C11. Gate, exactly** (public inversion). Open iff an admission is
cached, within the freshness bound, and every link is absent from its
registry as the mirror stands now. Mutant: drop the freshness bound. -/
theorem C11_gate_iff (pol : Policy) (s : Sys) (key : AID) (now : Slot) :
    gate pol s key now = true ↔
      ∃ ad, s.cage key = some ad ∧ now ≤ ad.admittedAt + pol.notAfter ∧
        ∀ (i : Nat) said rid, ad.saids[i]? = some said → ad.registries[i]? = some rid →
          miss s.toSys rid said = true := by
  sorry

/-- **C12. The gate reads no history and checks no signature.** It is
invariant under every checkpoint: a cheap lookup plus absence proofs.
Mutant: `gate` re-walking a seal. -/
theorem C12_gate_reads_no_checkpoint (pol : Policy) (s : Sys) (f : AID → Option Checkpoint)
    (key : AID) (now : Slot) :
    gate pol { s with ckpt := f } key now = gate pol s key now := by
  sorry

/-- **C13. Admission binds the actor to the credential.** An admission is
cached under a key only when the leaf credential names that key as its
issuee, and a chain whose leaf names someone else is refused for that key.
The actor's own signatures, checked by the checkpoint machine, cannot
establish this relationship. Mutant: drop the issuee guard on `admit`. -/
theorem C13_admission_binds_actor (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID)
    (hops : List Hop) (now : Slot) :
    (∀ s', stepFn p env pol s (.admit key hops now) = some s' →
      ∃ h, hops.head? = some h ∧ h.acdc.body.issuee = key) ∧
    (∀ h, hops.head? = some h → h.acdc.body.issuee ≠ key →
      stepFn p env pol s (.admit key hops now) = none) := by
  sorry

/-- **C14. Admit, exactly** (public inversion). An admission lands iff the
key is free, the leaf names the key, the chain admits with verdict `v`, every
hop yields a dependency, and what is cached is exactly the chain's SAIDs,
registries, verdict, dependencies and time. Mutant: `admit` caching empty
dependencies. -/
theorem C14_admit_iff (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID) (hops : List Hop)
    (now : Slot) (s' : Sys) :
    stepFn p env pol s (.admit key hops now) = some s' ↔
      ∃ h v deps, hops.head? = some h ∧ h.acdc.body.issuee = key ∧ s.cage key = none ∧
        admitChain p env s.toSys pol hops = some v ∧ hops.mapM (Hop.dep s.toSys) = some deps ∧
        s' = s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩) := by
  sorry

/-- **C15. A provisional admission is evictable once its issuer supersedes.**
An admission whose hop rests on its issuer's latest leaf records that
dependency, and after the issuer advances at or below the sealing sequence
the eviction is enabled: superseding recovery reaches the cage. Mutant:
`admit` caching empty dependencies, or `Hop.dep` dropping `k`. -/
theorem C15_provisional_admission_evictable_after_superseding (p : Params) (env : CEnv) (pol : Policy)
    {s s₁ s₂ : Sys} {key : AID} {hops : List Hop} {now : Slot}
    (h₁ : stepFn p env pol s (.admit key hops now) = some s₁)
    {hop : Hop} (hin : hop ∈ hops) {c : Checkpoint} (hc : s.ckpt hop.acdc.body.issuer = some c)
    (hlatest : hop.walk.core.e = c.latest) {e' : Seq} {t : Nat} {appr : Option Approval}
    (h₂ : stepFn p env pol s₁ (.mirror (.history hop.acdc.body.issuer (.advance e' t appr))) = some s₂)
    (hgt : c.latest < e') (hle : e' ≤ hop.walk.core.kel.sn) :
    ∃ s₃, stepFn p env pol s₂ (.evict key) = some s₃ := by
  sorry

end CardanoKeri.Credential
