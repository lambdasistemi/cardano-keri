import CardanoKeri.Statements.Credential
import CardanoKeri.Statements.CredentialHelpers

/-!
# Credential statements C1 … C20

Statements frozen in STATEMENTS mode (2026-09-10, repairs 1–3); proved in
PROOFS mode without change. Rulings: #31 as amended by #391/#392,
`docs/acdc-primer.md` ("how we verify an ACDC is not forged"),
`docs/design/credential-verification.md`, `docs/design/defi-gate.md`.
Mutants named per theorem; the ledger is `STATEMENTS-ATOMS.md`.

Repair 3 (invariant review, 2026-09-10): policy edge links (C16), the
registry inception anchor (C17), renewal after expiry (C18, C19),
evidence-based eviction (C9, C15), and the provisional-gate window stated
as a witness (C20).
-/

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

/-- **C1. An admitted chain is pinned.** It is non-empty, within the depth
bound, its schemas are the policy's by position with one link per edge,
its last hop has no edge and is issued by the pinned root. Mallory's chain
that does not lead to the root is refused. Mutant: drop the root check on
the last hop. -/
theorem C1_admitted_chain_is_pinned (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    hops ≠ [] ∧ hops.length ≤ pol.maxDepth ∧ hops.map (·.acdc.body.schema) = pol.schemas ∧
      pol.links.length + 1 = hops.length ∧
      ∃ last, hops.getLast? = some last ∧ last.acdc.body.edge = none ∧
        last.acdc.body.issuer = pol.root := by
  simp only [admitChain] at h
  split at h
  · rename_i hlen
    obtain ⟨hsc, hlk⟩ := chainFrom_schemas hops pol.schemas pol.links v h
    obtain ⟨last, hl, he, hr⟩ := chainFrom_last hops pol.schemas pol.links v h
    refine ⟨?_, hlen, hsc, hlk, last, hl, he, hr⟩
    intro hnil; subst hnil; simp at hl
  · simp at h

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
  simp only [admitChain] at h
  split at h
  · intro hop hin
    obtain ⟨parent, v', hv⟩ := chainFrom_hops hops pol.schemas pol.links v h hop hin
    obtain ⟨_, _, hk, hi, c, r, hc, _, _, _, _, hsw⟩ := hopVerdict_some hv
    exact ⟨hk, hi, c, v', hc, hsw⟩
  · simp at h

/-- **C3. Integrity and edges.** Every admitted credential's SAID is the
digest of its body, and each hop's edge names exactly the next hop's SAID:
change a byte, or swap a parent, and the chain is refused. Mutant:
`hopVerdict` that ignores `edge`. -/
theorem C3_integrity_and_edges (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    (∀ hop ∈ hops, env.saidOf hop.acdc.body = hop.acdc.said) ∧
      ∀ i h₁ h₂, hops[i]? = some h₁ → hops[i + 1]? = some h₂ →
        h₁.acdc.body.edge = some h₂.acdc.said := by
  simp only [admitChain] at h
  split at h
  · refine ⟨fun hop hin => ?_, chainFrom_edges hops pol.schemas pol.links v h⟩
    obtain ⟨parent, v', hv⟩ := chainFrom_hops hops pol.schemas pol.links v h hop hin
    exact (hopVerdict_some hv).1
  · simp at h

/-- **C4. A revoked link refuses the whole chain** (the cascade at
admission). Mutant: `hopVerdict` that checks the mirror on the leaf only. -/
theorem C4_revoked_link_refuses (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {hop : Hop} (hin : hop ∈ hops) {r : Registry}
    (hr : s.reg hop.acdc.body.registry = some r) (hrev : r.revoked hop.acdc.said = true) :
    admitChain p env s pol hops = none := by
  simp only [admitChain]
  split
  · exact chainFrom_none_of_hop hops pol.schemas pol.links hop hin
      (fun parent => hopVerdict_none_of_revoked parent hr hrev)
  · rfl

/-- **C5. No mirror, no admission.** A hop whose registry has not been
opened, or whose registry belongs to another issuer, cannot be admitted:
absence is proven against a registry UTxO or not at all. Mutant:
`hopVerdict` treating a missing registry as "nothing revoked". -/
theorem C5_unopened_registry_refuses (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {hop : Hop} (hin : hop ∈ hops)
    (hreg : s.reg hop.acdc.body.registry = none ∨
      ∃ r, s.reg hop.acdc.body.registry = some r ∧ r.issuer ≠ hop.acdc.body.issuer) :
    admitChain p env s pol hops = none := by
  simp only [admitChain]
  split
  · exact chainFrom_none_of_hop hops pol.schemas pol.links hop hin
      (fun parent => hopVerdict_none_of_registry parent hreg)
  · rfl

/-- **C6. The chain is provisional iff some hop is.** Exactly when one hop's
covering leaf is its issuer's latest (H4). Mutant: `Verdict.meet` that
returns `final` on any final. -/
theorem C6_provisional_iff_some_hop (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {v : Verdict} (h : admitChain p env s pol hops = some v) :
    v = .provisional ↔ ∃ hop ∈ hops, ∃ c, s.ckpt hop.acdc.body.issuer = some c ∧
      cover c hop.walk.core.e hop.walk.core.kel.sn hop.walk.core.succ = some .provisional := by
  simp only [admitChain] at h
  split at h
  · rw [chainFrom_provisional hops pol.schemas pol.links v h]
    constructor
    · rintro ⟨hop, hin, parent, hv⟩
      obtain ⟨_, _, _, _, c, r, hc, _, _, _, _, hsw⟩ := hopVerdict_some hv
      exact ⟨hop, hin, c, hc, sealWalk_some_cover hsw⟩
    · rintro ⟨hop, hin, c, hc, hcov⟩
      obtain ⟨parent, v', hv⟩ := chainFrom_hops hops pol.schemas pol.links v h hop hin
      obtain ⟨_, _, _, _, c', r, hc', _, _, _, _, hsw⟩ := hopVerdict_some hv
      rw [hc] at hc'; cases Option.some.inj hc'
      have := sealWalk_some_cover hsw
      rw [hcov] at this; cases Option.some.inj this
      exact ⟨hop, hin, parent, hv⟩
  · simp at h

/-- **C7. Admission never reads current keys.** The verdict is invariant
under any issuer's current key state: "issued then" is answered by history
leaves, "authorizes now" by a different reference input (S3 lifted).
Mutant: `hopVerdict` checking the issuer's `cur`. -/
theorem C7_admission_ignores_current_keys (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    (aid : AID) (x : Epoch) (hops : List Hop) :
    admitChain p env (s.setCur aid x) pol hops = admitChain p env s pol hops := by
  simp only [admitChain, chainFrom_setCur]

/-- **C8. A final admission is never evicted.** Eviction needs a moved
dependency, and a final dependency cannot move (H5, H11), whatever
evidence is presented. Mutant: `Anchor.moved` ignoring the verdict, or
`evict` without the `moved` guard. -/
theorem C8_final_never_evicted (p : Params) (env : CEnv) (pol : Policy) {s : Sys} (h : Reach p env pol s)
    {key : AID} {ad : Admission} (hc : s.cage key = some ad) (hfin : ad.verdict = .final) (m : Option Seq) :
    stepFn p env pol s (.evict key m) = none := by
  have hok := reach_cageOk h key ad hc hfin
  have hwf := reach_wf (reach_mirror h)
  cases hs : stepFn p env pol s (.evict key m) with
  | none => rfl
  | some s' =>
    exfalso
    obtain ⟨ad', had', hany, _⟩ := evict_some hs
    rw [hc] at had'; cases Option.some.inj had'
    obtain ⟨d, hd, hmoved⟩ := List.any_eq_true.mp hany
    obtain ⟨c, e', hcd, _, hst⟩ := hok d hd
    simp only [Dep.moved, hcd] at hmoved
    have := H12_moved_refutes_stands (hwf _ _ hcd) hmoved (some e')
    rw [hst] at this; simp at this

/-- **C9. Evict, exactly** (public inversion). An eviction is enabled iff an
admission exists and the presented evidence shows one of its dependencies
moved: the covering leaf's key state changed (or the leaf is gone), or the
presented leaf `m` sits at or below the sealing sequence and above the
covering leaf. Anyone may do it; the work is two lookups. Mutant: eviction
on a leaf *above* the sealing sequence. -/
theorem C9_evict_iff (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID) (m : Option Seq) (s' : Sys) :
    stepFn p env pol s (.evict key m) = some s' ↔
      ∃ ad, s.cage key = some ad ∧ s' = s.setCage key none ∧
        ∃ d ∈ ad.deps, ∃ c, s.ckpt d.issuer = some c ∧
          ((∀ l, c.hist d.anchor.e = some l → l.epoch ≠ d.anchor.epoch) ∨
            ∃ m', m = some m' ∧ d.anchor.e < m' ∧ m' ≤ d.anchor.k ∧ (c.hist m').isSome) := by
  constructor
  · intro h
    obtain ⟨ad, had, hany, rfl⟩ := evict_some h
    obtain ⟨d, hd, hmoved⟩ := List.any_eq_true.mp hany
    exact ⟨ad, had, rfl, d, hd, (moved_iff s.toSys d m).1 hmoved⟩
  · rintro ⟨ad, had, rfl, d, hd, hm⟩
    exact evict_of had (List.any_eq_true.mpr ⟨d, hd, (moved_iff s.toSys d m).2 hm⟩)

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
  simp only [gate, hc]
  cases hall : (ad.saids.zip ad.registries).all (fun (said, rid) => miss s'.toSys rid said)
  · simp
  · exfalso
    have := (zip_all_iff _ _ _).1 hall i said rid hsaid hrid
    simp [miss, hr, hrev] at this

/-- **C11. Gate, exactly** (public inversion). Open iff an admission is
cached, within the freshness bound, and every link is absent from its
registry as the mirror stands now. Mutant: drop the freshness bound. -/
theorem C11_gate_iff (pol : Policy) (s : Sys) (key : AID) (now : Slot) :
    gate pol s key now = true ↔
      ∃ ad, s.cage key = some ad ∧ now ≤ ad.admittedAt + pol.notAfter ∧
        ∀ (i : Nat) said rid, ad.saids[i]? = some said → ad.registries[i]? = some rid →
          miss s.toSys rid said = true := by
  simp only [gate]
  cases hc : s.cage key with
  | none => simp
  | some ad =>
    simp only [Bool.and_eq_true, decide_eq_true_eq, Option.some.injEq, exists_eq_left']
    rw [zip_all_iff]

/-- **C12. The gate reads no history and checks no signature.** It is
invariant under every checkpoint: a cheap lookup plus absence proofs. This
is the design's cache-then-evict shape; its consequence for provisional
admissions is C20. Mutant: `gate` re-walking a seal. -/
theorem C12_gate_reads_no_checkpoint (pol : Policy) (s : Sys) (f : AID → Option Checkpoint)
    (key : AID) (now : Slot) :
    gate pol { s with ckpt := f } key now = gate pol s key now := rfl

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
  constructor
  · intro s' hs
    obtain ⟨hd, v, deps, hhd, hkey, _, _, _, _⟩ := admit_some hs
    exact ⟨hd, hhd, hkey⟩
  · intro h hhd hne
    simp [stepFn, hhd, hne]

/-- **C14. Admit, exactly** (public inversion). An admission lands iff the
leaf names the key, the key is free or holds an expired admission, the
chain admits with verdict `v`, every hop yields a dependency, and what is
cached is exactly the chain's SAIDs, registries, verdict, dependencies and
time. Mutant: `admit` caching empty dependencies. -/
theorem C14_admit_iff (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID) (hops : List Hop)
    (now : Slot) (s' : Sys) :
    stepFn p env pol s (.admit key hops now) = some s' ↔
      ∃ h v deps, hops.head? = some h ∧ h.acdc.body.issuee = key ∧
        (∀ ad, s.cage key = some ad → ad.expired pol now = true) ∧
        admitChain p env s.toSys pol hops = some v ∧ hops.mapM (Hop.dep s.toSys) = some deps ∧
        s' = s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩) := by
  constructor
  · intro h
    obtain ⟨hd, v, deps, hhd, hkey, hfree, hv, hdeps, rfl⟩ := admit_some h
    exact ⟨hd, v, deps, hhd, hkey, hfree, hv, hdeps, rfl⟩
  · rintro ⟨hd, v, deps, hhd, hkey, hfree, hv, hdeps, rfl⟩
    exact admit_of hhd hkey hfree hv hdeps

/-- **C15. A provisional admission is evictable once its issuer supersedes.**
An admission whose hop rests on its issuer's latest leaf records that
dependency, and after the issuer advances at or below the sealing sequence
the eviction is enabled on the evidence of that new leaf: superseding
recovery reaches the cage. Mutant: `admit` caching empty dependencies, or
`anchorOf` dropping `k`. -/
theorem C15_provisional_admission_evictable_after_superseding (p : Params) (env : CEnv) (pol : Policy)
    {s s₁ s₂ : Sys} {key : AID} {hops : List Hop} {now : Slot}
    (h₁ : stepFn p env pol s (.admit key hops now) = some s₁)
    {hop : Hop} (hin : hop ∈ hops) {c : Checkpoint} (hc : s.ckpt hop.acdc.body.issuer = some c)
    (hlatest : hop.walk.core.e = c.latest) {e' : Seq} {t : Nat} {appr : Option Approval}
    (h₂ : stepFn p env pol s₁ (.mirror (.history hop.acdc.body.issuer (.advance e' t appr))) = some s₂)
    (hgt : c.latest < e') (hle : e' ≤ hop.walk.core.kel.sn) :
    ∃ s₃, stepFn p env pol s₂ (.evict key (some e')) = some s₃ := by
  obtain ⟨hd, v, deps, hhd, hkey, hfree, hv, hdeps, rfl⟩ := admit_some h₁
  obtain ⟨d, hd', hdep⟩ := mapM_dep_of_mem hops deps hdeps hop hin
  obtain ⟨c₀, l, v', hc₀, hl, hcov, rfl⟩ := dep_some hdep
  rw [hc] at hc₀; cases Option.some.inj hc₀
  obtain ⟨m, hm, rfl⟩ := mirror_some h₂
  obtain ⟨c₁, c₂, hc₁, hh, rfl⟩ := history_some hm
  have hcc : c₁ = c := by
    simp only [Sys.setCage] at hc₁
    rw [hc] at hc₁; exact (Option.some.inj hc₁).symm
  subst hcc
  obtain ⟨hlt, rfl⟩ := advance_some hh
  refine ⟨_, evict_of (ad := ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩) ?_ ?_⟩
  · simp [Sys.setCage]
  · apply List.any_eq_true.mpr
    refine ⟨_, hd', ?_⟩
    simp only [Dep.moved, Mirror.Sys.setCkpt, if_true]
    simp only [Anchor.moved, advanced, Bool.or_eq_true]
    right
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    refine ⟨⟨by rw [hlatest]; exact hgt, hle⟩, ?_⟩
    simp

/-- **C16. Every edge carries the policy's authority.** In an admitted chain
each adjacent pair satisfies the link the policy pins for that edge (for
vLEI, the issuer below is the issuee above), and a chain with one failing
link is refused: merely referencing a genuine root credential authorizes
no unrelated issuer. Mutant: `chainFrom` that ignores `lk`. -/
theorem C16_links_enforced (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) (hops : List Hop) :
    (∀ v, admitChain p env s pol hops = some v →
      ∀ i h₁ h₂ lk, hops[i]? = some h₁ → hops[i + 1]? = some h₂ → pol.links[i]? = some lk →
        lk h₁.acdc.body h₂.acdc.body = true) ∧
    (∀ i h₁ h₂ lk, hops[i]? = some h₁ → hops[i + 1]? = some h₂ → pol.links[i]? = some lk →
      lk h₁.acdc.body h₂.acdc.body = false → admitChain p env s pol hops = none) := by
  constructor
  · intro v h
    simp only [admitChain] at h
    split at h
    · exact chainFrom_links hops pol.schemas pol.links v h
    · simp at h
  · intro i h₁ h₂ lk hi hi' hlk hfail
    simp only [admitChain]
    split
    · exact chainFrom_none_of_link hops pol.schemas pol.links i h₁ h₂ lk hi hi' hlk hfail
    · rfl

/-- **C17. The registry's inception must stand.** A hop whose registry was
opened from a `vcp` seal that the issuer has since superseded — the
inception anchor no longer stands on the issuer's history under the
presented proof — is refused, whatever the credential's own walk says.
Continued existence of the registry UTxO is not authority. Mutant:
`hopVerdict` that skips `inception.stands`. -/
theorem C17_registry_inception_must_stand (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy)
    {hops : List Hop} {hop : Hop} (hin : hop ∈ hops) {c : Checkpoint} {r : Registry}
    (hc : s.ckpt hop.acdc.body.issuer = some c) (hr : s.reg hop.acdc.body.registry = some r)
    (hstand : r.inception.stands c hop.regProof = false) :
    admitChain p env s pol hops = none := by
  simp only [admitChain]
  split
  · exact chainFrom_none_of_hop hops pol.schemas pol.links hop hin
      (fun parent => hopVerdict_none_of_stands parent hc hr hstand)
  · rfl

/-- **C18. An expired admission can be renewed.** When the cached admission
is past the freshness bound, a chain that admits for the same key lands and
replaces it; an expired admission can also be removed by anyone. A
still-valid actor is never locked out of its own key. Mutant: `admit`
refusing every occupied key. -/
theorem C18_renewal_after_expiry (p : Params) (env : CEnv) (pol : Policy) (s : Sys) {key : AID}
    {ad : Admission} (hc : s.cage key = some ad) {now : Slot} (hexp : ad.expired pol now = true) :
    (∀ hops h v deps, hops.head? = some h → h.acdc.body.issuee = key →
      admitChain p env s.toSys pol hops = some v → hops.mapM (Hop.dep s.toSys) = some deps →
      ∃ s', stepFn p env pol s (.admit key hops now) = some s') ∧
    ∃ s', stepFn p env pol s (.expire key now) = some s' := by
  constructor
  · intro hops h v deps hhd hkey hv hdeps
    exact ⟨_, admit_of hhd hkey (fun ad' had' => by rw [hc] at had'; cases Option.some.inj had'; exact hexp) hv hdeps⟩
  · exact ⟨s.setCage key none, by simp [stepFn, hc, hexp]⟩

/-- **C19. A live admission is never replaced.** While the cached admission
is within the freshness bound, no admission lands on that key and the
expiry action is refused; eviction on evidence (C9) is the only way out.
Mutant: `admit` overwriting unconditionally. -/
theorem C19_live_admission_not_replaced (p : Params) (env : CEnv) (pol : Policy) (s : Sys) {key : AID}
    {ad : Admission} (hc : s.cage key = some ad) {now : Slot} (hlive : ad.expired pol now = false) :
    (∀ hops, stepFn p env pol s (.admit key hops now) = none) ∧
    stepFn p env pol s (.expire key now) = none := by
  constructor
  · intro hops
    cases hs : stepFn p env pol s (.admit key hops now) with
    | none => rfl
    | some s' =>
      obtain ⟨_, _, _, _, _, hfree, _, _, _⟩ := admit_some hs
      have := hfree ad hc
      rw [hlive] at this; simp at this
  · simp [stepFn, hc, hlive]

/-- **C20. The provisional-gate window** (a witness of a stated residual,
not a guarantee). There is a reachable system holding a provisional
admission whose dependency has moved — the eviction is enabled — while the
gate is still open. The design authority specifies cache-then-evict, so
the interval between an issuer's superseding rotation and the
permissionless eviction is bounded only by the freshness bound and by
whoever evicts. Closing it at the use boundary (the gate reading the
issuer checkpoint of every provisional dependency) is a recorded open
decision. Mutant: none — this documents the residual. -/
theorem C20_provisional_gate_window_witness :
    ∃ (p : Params) (env : CEnv) (pol : Policy) (s : Sys) (key : AID) (ad : Admission) (now : Slot)
      (m : Option Seq),
      Reach p env pol s ∧ s.cage key = some ad ∧ ad.verdict = .provisional ∧
      (∃ s', stepFn p env pol s (.evict key m) = some s') ∧ gate pol s key now = true := by
  let p : Params := ⟨0⟩
  let env : CEnv := { signed := fun _ _ => true, receipted := fun _ _ => true, digest := fun t => t.i,
                      saidOf := fun _ => 9 }
  let pol : Policy := ⟨1, [2], [], 1, 5⟩
  let wv : Walk := ⟨⟨.vcp, 5, 5, 0⟩, ⟨⟨1, false, [⟨5, 0, 5⟩]⟩, 0, none, 0⟩⟩
  let hop : Hop := ⟨⟨⟨1, 2, 5, 3, none⟩, 9⟩, ⟨⟨.iss, 9, 5, 0⟩, ⟨⟨2, false, [⟨9, 0, 9⟩]⟩, 0, none, 0⟩⟩, none⟩
  let c₀ : Checkpoint := inception 1 0 0 none none
  let s₁ : Sys := { toSys := Mirror.Sys.init.setCkpt 1 (some c₀), cage := fun _ => none }
  let s₂ : Sys := { s₁ with toSys := s₁.toSys.setReg 5 (some ⟨1, 5, ⟨0, 0, 1, .provisional⟩, fun _ => false⟩) }
  let s₃ : Sys := s₂.setCage 3 (some ⟨[9], [5], .provisional, [⟨1, ⟨0, 0, 2, .provisional⟩⟩], 10⟩)
  let s₄ : Sys := { s₃ with toSys := s₃.toSys.setCkpt 1 (some (advanced c₀ 1 0 none)) }
  refine ⟨p, env, pol, s₄, 3, _, 10, some 1, ?_, rfl, rfl, ⟨_, rfl⟩, by decide⟩
  exact ReachFrom.step (s' := s₁) (a := .mirror (.register 1 0 0 none)) rfl
    (ReachFrom.step (s' := s₂) (a := .mirror (.open 1 wv)) rfl
      (ReachFrom.step (s' := s₃) (a := .admit 3 [hop] 10) rfl
        (ReachFrom.step (s' := s₄) (a := .mirror (.history 1 (.advance 1 0 none))) rfl (ReachFrom.refl _))))

end CardanoKeri.Credential
