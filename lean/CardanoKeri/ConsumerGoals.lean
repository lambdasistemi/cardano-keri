import CardanoKeri.ConsumerIdentity
import CardanoKeri.RegistryAdapterFacts
import CardanoKeri.CheckpointCompletionGoals

/-! Exact consumer identity and bounded registration correspondence laws.
The independently reviewed statement surface is CI01–CI26. -/
namespace CardanoKeri.ConsumerIdentity
open CardanoKeri.Checkpoint

deriving instance ReflBEq, LawfulBEq for SingularApplicationHeld.PublishedRelease
deriving instance ReflBEq, LawfulBEq for Singular.TerminationRequest
deriving instance ReflBEq, LawfulBEq for Singular.Holding
deriving instance ReflBEq, LawfulBEq for Singular.TerminationBooking
deriving instance ReflBEq, LawfulBEq for Singular.FoldMember

/-- CI01. Given any interpretation, independently fixed consumer context,
validated-environment observation, Params, slot and output; when comparing
the Boolean and proposition; then true iff all proposition clauses hold,
in both directions. No hash premise is needed for agreement. -/
theorem consumableHoldingB_iff (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) :
    consumableHoldingB i c e p now o = true ↔ consumableHolding i c e p now o := by
  cases hd : decoded i c o with
  | none => simp [consumableHoldingB, consumableHolding, hd, authenticatedContextB, authenticatedContext]
  | some d => simp [consumableHoldingB, consumableHolding, hd, authenticatedContextB,
      authenticatedContext, consumableStateB_iff, and_assoc]

/-- CI02. Given arbitrary inputs; when an output is evaluated; then acceptance
is equivalent to exact network, resolved complete release, application
credential, exact representative quantity one and a decoded intended-AID
live datum, unfrozen, unpoisoned and at least bornAt+W old. Both directions
and all eight clauses are obligations. -/
theorem consumableHolding_exact (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) :
    consumableHolding i c e p now o ↔
      e.network = c.network ∧ e.release = some c.release ∧
      o.credential = c.release.applicationCredential ∧
      AH.quantity o (representativeAsset i c) = 1 ∧
      ∃ l : Live, decoded i c o = some ⟨c.aid, .present l⟩ ∧
        l.frozen = false ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now := by
  cases hd : decoded i c o with
  | none => simp [consumableHolding, hd]
  | some d =>
    rcases d with ⟨aid, state⟩
    cases state <;> simp [consumableHolding, hd, authenticatedContext, consumableState, and_assoc]


/-- CI03. Given any actual output whose exact credential, unit asset quantity
and decoded AID/state realize the intended state, and an authenticated
external context; when consumed; then acceptance iff the full old lifecycle
predicate holds. This is a refinement premise, not evidence that an output
exists or its decoder is faithful. -/
theorem existing_eligibility_preserved (i : Interpretation) (c : Context)
    (e : Environment) (p : Params) (rp : CardanoKeri.Registry.Params) (now : Slot) (s : State)
    (o : AH.ObservedOutput) (context : authenticatedContext c e) (realizes : realizesState i c p rp s o) :
    consumableHolding i c e p now o ↔ consumableState p now s := by
  rcases realizes with ⟨credential, quantity, datum, _⟩
  obtain ⟨⟨aid, st⟩, hd, hf⟩ := Option.map_eq_some_iff.mp datum
  simp only [DecodedDatum.facts, DecodedDatum.mk.injEq] at hf
  obtain ⟨rfl, hst⟩ := hf
  -- The predicate never reads the pool, so equal datum facts give equal verdicts.
  have facts : ∀ x : State, consumableState p now x.datumFacts ↔ consumableState p now x := by
    intro x; cases x <;> simp [State.datumFacts, consumableState]
  have holding : consumableHolding i c e p now o ↔
      AH.quantity o (representativeAsset i c) = 1 ∧ consumableState p now st := by
    simp [consumableHolding, context, credential, hd]
  rw [holding, quantity, ← facts st, hst, facts]
  cases s <;> simp [State.representativeHeld, State.hasOutput, consumableState]

/-- CI04. Given different intended and actual networks; when a consumer checks
any candidate; then it refuses regardless of asset or datum. The actual
network observation is supplied by the integration, not the candidate. -/
theorem wrong_network_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (wrong : e.network ≠ c.network) :
    ¬ consumableHolding i c e p now o := by
  intro h
  exact wrong h.1.1

/-- CI05. Given an unresolved or different complete PublishedRelease; when
checking any candidate; then refuse. Equality includes applicationPolicy,
applicationCredential, stateProgram and statePolicy; version text is not
silently treated as a published script identity. -/
theorem wrong_or_unknown_release_refused (i : Interpretation) (c : Context)
    (e : Environment) (p : Params) (now : Slot) (o : AH.ObservedOutput)
    (wrong : e.release ≠ some c.release) :
    ¬ consumableHolding i c e p now o := by
  intro h
  exact wrong h.1.2

/-- CI06. Given a wrong application credential on the actual output; when
checking it; then refuse even if it holds the exact token and a live datum. -/
theorem wrong_credential_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput)
    (wrong : o.credential ≠ c.release.applicationCredential) :
    ¬ consumableHolding i c e p now o := by
  intro h
  exact wrong h.2.1

/-- CI07. Given total quantity of the intended asset unequal to one; when
checking that output; then refuse, including zero and two, aggregated over
all matching asset entries. Other asset quantities cannot replace it. -/
theorem wrong_quantity_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput)
    (wrong : AH.quantity o (representativeAsset i c) ≠ 1) :
    ¬ consumableHolding i c e p now o := by
  intro h
  exact wrong h.2.2.1

/-- CI08. Given any singleton supplied asset distinct from the intended one,
with any quantity; when checking that output; then refuse. A wrong policy
OR wrong name suffices for distinctness. This does not reject an unrelated
asset merely for coexisting with one valid intended token. -/
theorem wrong_asset_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (a : Singular.TokenId) (n : Nat)
    (assets : o.assets = [(a, n)]) (wrong : a ≠ representativeAsset i c) :
    ¬ consumableHolding i c e p now o := by
  apply wrong_quantity_refused i c e p now o
  simp [SingularApplicationHeld.quantity, assets, wrong]

/-- CI09. Given a non-application datum, absent datum, or decoder rejection;
when checking the candidate; then refuse. Concrete malformed-byte detection
is delegated to the selected decoder and is not proved by this theorem. -/
theorem malformed_datum_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (bad : decoded i c o = none) :
    ¬ consumableHolding i c e p now o := by
  simp [consumableHolding, bad]

/-- CI10. Given a decoded datum for another AID; when checking it against the
independently fixed intended AID; then refuse, even if names collide. -/
theorem wrong_datum_aid_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (d : DecodedDatum)
    (datum : decoded i c o = some d) (wrong : d.aid ≠ c.aid) :
    ¬ consumableHolding i c e p now o := by
  simp [consumableHolding, datum, wrong]

/-- CI11. Given any decoded state refused by old consumableState; when the
stronger holding predicate is checked; then refuse for every identity and
quantity. Covers absent/pending/convicted/frozen/poisoned/juvenile. -/
theorem ineligible_state_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (d : DecodedDatum)
    (datum : decoded i c o = some d) (bad : ¬ consumableState p now d.state) :
    ¬ consumableHolding i c e p now o := by
  simp [consumableHolding, datum, bad]

/-- CI12. Given a pending-termination datum and arbitrary key state; when checked
at any time; then refuse both proposition and Boolean, even though a token
and an active registry key can still exist. -/
theorem retained_custody_refused (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (d : DecodedDatum) (h : Hash)
    (datum : decoded i c o = some d)
    (retained : d.state = .terminationPending h) :
    ¬ consumableHolding i c e p now o ∧ consumableHoldingB i c e p now o = false := by
  have no : ¬ consumableHolding i c e p now o := by
    apply ineligible_state_refused i c e p now o d datum
    simp [retained, consumableState]
  exact ⟨no, Bool.eq_false_iff.mpr (fun h => no ((consumableHoldingB_iff i c e p now o).mp h))⟩

/-- CI13. Given the same registry and two distinct encoded keys, with explicit
finite encoding and collision premises on the two Active preimages; when
deriving names using the actual imported activeAsset; then the full assets
differ. AID-to-key injectivity is not inferred from distinct AID labels. -/
theorem different_encoded_keys_distinct (i : Interpretation) (c d : Context)
    (sameRegistry : registryAsset i c = registryAsset i d)
    (keys : i.keyOf c.aid ≠ i.keyOf d.aid)
    (encoding : AH.FiniteEncoding i.code (identityDomain i c d))
    (collision : AH.FiniteCollisionFree i.hash i.code (identityDomain i c d)) :
    representativeAsset i c ≠ representativeAsset i d := by
  clear sameRegistry
  intro same
  have names := congrArg Singular.TokenId.name same
  have codes := collision _ (by simp [identityDomain]) _ (by simp [identityDomain]) names
  have preimages := encoding _ (by simp [identityDomain]) _ (by simp [identityDomain]) codes
  exact keys (SingularApplicationHeld.Preimage.active.inj preimages).2

/-- CI14. Given two unequal complete registry identities and explicit finite
encoding and collision premises covering both Active preimages; when naming
any keys; then active assets differ. A name-only registry comparison is not
the premise: either the state policy or state name can distinguish them. -/
theorem different_registries_distinct (i : Interpretation) (c d : Context)
    (registries : registryAsset i c ≠ registryAsset i d)
    (encoding : AH.FiniteEncoding i.code (identityDomain i c d))
    (collision : AH.FiniteCollisionFree i.hash i.code (identityDomain i c d)) :
    representativeAsset i c ≠ representativeAsset i d := by
  intro same
  have names := congrArg Singular.TokenId.name same
  have codes := collision _ (by simp [identityDomain]) _ (by simp [identityDomain]) names
  have preimages := encoding _ (by simp [identityDomain]) _ (by simp [identityDomain]) codes
  exact registries (SingularApplicationHeld.Preimage.active.inj preimages).1

/-- CI15. Given different seeds (transaction or index), arbitrary releases and
AIDs, with separate finite encoding and collision premises containing both
State and Active preimages; when deriving full registry/active identities;
then both registry and representative assets differ. No global hash
injectivity is assumed. -/
theorem different_seeds_distinct (i : Interpretation) (c d : Context)
    (seeds : c.seed ≠ d.seed)
    (encoding : AH.FiniteEncoding i.code (identityDomain i c d))
    (collision : AH.FiniteCollisionFree i.hash i.code (identityDomain i c d)) :
    registryAsset i c ≠ registryAsset i d ∧
    representativeAsset i c ≠ representativeAsset i d := by
  have registries : registryAsset i c ≠ registryAsset i d := by
    intro same
    have names := congrArg Singular.TokenId.name same
    have codes := collision _ (by simp [identityDomain]) _ (by simp [identityDomain]) names
    have preimages := encoding _ (by simp [identityDomain]) _ (by simp [identityDomain]) codes
    exact seeds (SingularApplicationHeld.Preimage.state.inj preimages)
  exact ⟨registries, different_registries_distinct i c d registries encoding collision⟩

/-- CI16. Given a consistent rival seed's singleton active asset, any quantity,
and explicit finite encoding/collision premises; when checked against the
consumer's original fixed context; then refuse. Rival self-consistency never
selects the context. No claim is made if expected assets also coexist. -/
theorem rival_seed_refused (i : Interpretation) (c rival : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (n : Nat)
    (seeds : c.seed ≠ rival.seed)
    (assets : o.assets = [(representativeAsset i rival, n)])
    (encoding : AH.FiniteEncoding i.code (identityDomain i c rival))
    (collision : AH.FiniteCollisionFree i.hash i.code (identityDomain i c rival)) :
    ¬ consumableHolding i c e p now o := by
  apply wrong_asset_refused i c e p now o (representativeAsset i rival) n assets
  exact Ne.symm (different_seeds_distinct i c rival seeds encoding collision).2

/-- CI17. Given an actual accepted local Checkpoint Step from any state holding
an output; when observing logical custody afterward; then the output remains
and the complete representative asset is unchanged. This covers every
rotation branch, park, revival, poison, freeze, top-up and local conviction;
it does not assert full current ledger-output correspondence. -/
theorem local_step_retains_exact_asset (i : Interpretation) (c : Context)
    (p : Params) (env : Env) (a : Action) (now : Slot) (s s' : State) (f : Flow)
    (step : Step p env a now s f s') (held : s.hasOutput = true) :
    s'.hasOutput = true ∧ heldRepresentative i c s' = heldRepresentative i c s := by
  cases step <;> simp_all [State.hasOutput, heldRepresentative]

/-- CI18. Given actual system completion using its stored origin/request/receipt;
when observing the target key; then some previously pending AID becomes
convicted, its pending association clears, its logical representative is
absent, its new consumer predicate refuses any output decoding to that state,
and all origins remain unchanged. The imported receipt owns burn/retirement. -/
theorem completion_refuses_consumer (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (s s' : Sys) (event : CompletionEvent s s') :
    ∃ aid association, s.pending aid = some association ∧
      s.states aid = .terminationPending association.keyState ∧
      s'.states aid = .convicted ∧ s'.pending aid = none ∧
      heldRepresentative i { c with aid := aid } (s'.states aid) = none ∧
      (∀ o, decoded i { c with aid := aid } o = some ⟨aid, s'.states aid⟩ →
        ¬ consumableHolding i { c with aid := aid } e p now o) ∧
      s'.origins = s.origins := by
  obtain ⟨aid, association, pending, stored, before, after, cleared, origins⟩ :=
    completion_uses_recorded_pending_key s s' event
  refine ⟨aid, association, pending, before, after, cleared, ?_, ?_, origins⟩
  · simp [after, heldRepresentative, State.hasOutput]
  · intro o decoded
    simp [consumableHolding, decoded, after, consumableState]

/-- CI19. Given any accepted system step and a previously bound stored origin;
when inspecting that AID afterward; then the exact stored origin and its
reduced-to-full configuration binding remain. No changing current output
reference or datum is inferred from stable origin provenance. -/
theorem system_preserves_identity_binding (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (p : Params) (env : Env)
    (s s' : Sys) (origin : Origin) (bound : originBinding i c abstractRegistry origin)
    (stored : s.origins c.aid = some origin) (step : SysStep p env s s') :
    s'.origins c.aid = some origin ∧ originBinding i c abstractRegistry origin := by
  exact ⟨sysstep_preserves_existing_origin p env step c.aid origin stored, bound⟩

/-- CI20. Given two distinct full registry identities, two bound origins and
an explicitly faithful abstractRegistry map on exactly these identities;
when observing reduced configuration registry ids; then they differ. Without
faithfulness, binding alone provides no separation theorem. -/
theorem faithful_origin_registry_separation (i : Interpretation) (c d : Context)
    (abstractRegistry : Singular.TokenId → Nat) (oc od : Origin)
    (bc : originBinding i c abstractRegistry oc)
    (bd : originBinding i d abstractRegistry od)
    (different : registryAsset i c ≠ registryAsset i d)
    (faithful : faithfulRegistryMap abstractRegistry [registryAsset i c, registryAsset i d]) :
    oc.configuration.registryId ≠ od.configuration.registryId := by
  intro same
  apply different
  apply faithful _ (by simp) _ (by simp)
  exact bc.1.symm.trans (same.trans bd.1)

/-- CI21. Given any successful proposed creation bridge; when observing its
result; then the exact configuration binding and actual imported genesis
passed, the selected state is an actual supplied output carrying the registry
asset, the full identity/seed/empty trie are fixed by consumer Context, and
the economic state is exactly the old Sys.init cfg. This is a conditional
inversion, not a claim that every genesis observation is ledger-valid. -/
theorem createRegistry_exact (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (cfg : Singular.Config)
    (commit : SingularApplicationHeld.TrieCommit)
    (tx : SingularApplicationHeld.Assets.TxView) (outputs : List AH.ObservedOutput)
    (result : CreatedRegistry)
    (accepted : createRegistry i c abstractRegistry cfg commit tx outputs = .ok result) :
    configBinding i c abstractRegistry cfg = true ∧
    SingularApplicationHeld.genesis .none i.hash i.code commit c.release c.seed tx outputs = true ∧
    result.full.identity = registryAsset i c ∧ result.full.seed = c.seed ∧
    result.full.trie = [] ∧ result.full.state ∈ outputs ∧
    0 < AH.quantity result.full.state (registryAsset i c) ∧
    result.economic = CardanoKeri.Registry.Sys.init cfg := by
  cases hb : configBinding i c abstractRegistry cfg <;>
    simp [createRegistry, hb, bind, Except.bind, pure, Except.pure] at accepted
  cases hg : SingularApplicationHeld.genesis .none i.hash i.code commit c.release c.seed tx outputs <;>
    simp [hg] at accepted
  cases hf : outputs.find? (fun o => AH.quantity o (registryAsset i c) > 0) with
  | none => simp [hf] at accepted
  | some state =>
    simp [hf] at accepted
    subst result
    exact ⟨rfl, rfl, rfl, rfl, rfl, List.mem_of_find?_eq_some hf,
      by simpa using List.find?_some hf, rfl⟩

/-- CI22. Given matching trusted configuration and an actual successful
imported genesis observation; when running the bridge; then some result
exists. The adapter cannot refuse a permitted genesis solely through its
state-selection guard. Together with CI21 this constrains both directions. -/
theorem createRegistry_complete (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (cfg : Singular.Config)
    (commit : SingularApplicationHeld.TrieCommit)
    (tx : SingularApplicationHeld.Assets.TxView) (outputs : List AH.ObservedOutput)
    (binding : configBinding i c abstractRegistry cfg = true)
    (genesis : SingularApplicationHeld.genesis .none i.hash i.code commit c.release c.seed tx outputs = true) :
    ∃ result, createRegistry i c abstractRegistry cfg commit tx outputs = .ok result := by
  have nonempty : (outputs.filter fun o => AH.quantity o (registryAsset i c) > 0).length = 1 := by
    simp [SingularApplicationHeld.genesis, SingularApplicationHeld.applyGuard,
      registryAsset] at genesis ⊢
    exact genesis.1.2.1
  cases found : outputs.find? (fun o => AH.quantity o (registryAsset i c) > 0) with
  | none =>
    have empty : outputs.filter (fun o => AH.quantity o (registryAsset i c) > 0) = [] := by
      apply List.filter_eq_nil_iff.mpr
      simpa using List.find?_eq_none.mp found
    simp [empty] at nonempty
  | some state => simp [createRegistry, binding, genesis, found, bind, Except.bind, pure, Except.pure]

/-- CI23. Given any successful bounded joint registration (the complete input
contains genesis outputs, genuine booking, economic unspent/transaction,
full-identity fold and selected holding index, plus fixed model contexts);
when observing its result; then actual creation/book/economic fold/full fold/
Checkpoint registration all succeeded, the complete registration agreement
passed, and an actual indexed #437 receipt delivers the stored origin. Its
current initial holding realizes that exact AID/Checkpoint state, and its
reference equals the stored carrier reference. No consumer conclusion is an
input and no arbitrary physical-ledger equivalence is asserted. -/
theorem registerJoint_sound (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) (r : Registered)
    (accepted : registerJoint i c abstractRegistry commit q = .ok r) :
    createRegistry i c abstractRegistry q.configuration commit q.genesisTx q.genesisOutputs = .ok r.created ∧
    CardanoKeri.Registry.bookRegistration q.registryParams r.created.economic q.booking =
      .ok (r.registrationFlow, r.booked) ∧
    CardanoKeri.Registry.fold q.registryParams q.registryEnv r.booked r.booked.gen
      r.booked.config.applicationPolicy q.unspent q.economicTx = .ok (r.foldFlow, r.after) ∧
    SingularApplicationHeld.fold .none i.hash i.code commit c.release q.fullFold = true ∧
    stepFn q.checkpointParams q.checkpointEnv (.register q.refund q.pool) q.now .absent =
      some (r.checkpointFlow, r.checkpoint) ∧
    registrationAgreementB i c q r.created r.booked r.after r.checkpoint r.holding r.economicHolding = true ∧
    ∃ receipt : CardanoKeri.Registry.FoldReceipt q.registryParams q.registryEnv q.configuration,
      receipt.before = r.booked ∧ receipt.after = r.after ∧
      receipt.unspent = q.unspent ∧ receipt.transaction = q.economicTx ∧
      receipt.flow = r.foldFlow ∧ DeliveredOrigin receipt q.booking c.aid r.origin ∧
      realizesState i c q.checkpointParams q.registryParams r.checkpoint r.holding ∧ r.origin.carrierRef = r.holding.reference := by
  unfold registerJoint at accepted
  simp only [bind, Except.bind, pure, Except.pure] at accepted
  repeat first | split at accepted | contradiction
  all_goals try { change Except.error _ = Except.ok _ at accepted; contradiction }
  cases accepted
  rename_i _ created hc _ book hb _ folded hf hff _ cpFlow st hcp _ o ho _ eo heo hag _ token ht
  have full : SingularApplicationHeld.fold .none i.hash i.code commit c.release q.fullFold = true := by simpa using hff
  have agree : registrationAgreementB i c q created book.2 folded.2 st o eo = true := by simpa using hag
  refine ⟨hc, hb, hf, full, hcp, agree, ?_⟩
  have initial := (createRegistry_exact i c abstractRegistry q.configuration commit q.genesisTx q.genesisOutputs created hc).2.2.2.2.2.2.2
  have reach : CardanoKeri.Registry.Reach q.registryParams q.registryEnv q.configuration book.2 := by
    apply CardanoKeri.Registry.Reach.next (action := .bookRegistration q.booking)
      (s := created.economic) (flow := book.1)
    · rw [initial]; exact .init
    · exact hb
  let receipt : CardanoKeri.Registry.FoldReceipt q.registryParams q.registryEnv q.configuration :=
    ⟨book.2, folded.2, q.unspent, q.economicTx, folded.1, reach, hf⟩
  refine ⟨receipt, rfl, rfl, rfl, rfl, rfl, ?_, ?_, ?_⟩
  all_goals have clauses := agree
  all_goals simp only [registrationAgreementB, Bool.and_eq_true, and_assoc] at clauses
  all_goals rcases clauses with ⟨_, _, _, key, _, selected, _, _, ref, _, cred,
    addr, datum, value, _, carrierHeld, tags, holdingValue, _, qty, decoded, _⟩
  · refine ⟨?_, by simpa using key, rfl, rfl, rfl, rfl, rfl, ht,
      q.holdingIndex, eo, heo, rfl, ?_, ?_, ?_, ?_⟩
    · simpa [receipt] using selected
    · simpa using tags
    · simpa using addr
    · simpa using datum
    · simpa using value
  · have held : st.representativeHeld = 1 := by
      simp [stepFn] at hcp
      rcases hcp with ⟨_, rfl⟩
      rfl
    exact ⟨by simpa using cred, by simpa [held] using qty, by simpa using decoded,
      by simpa [beq_iff_eq] using (beq_iff_eq.mp holdingValue).trans (beq_iff_eq.mp carrierHeld)⟩
  · exact (by simpa using ref : o.reference = ⟨q.economicTx.identity, q.holdingIndex⟩).symm

/-- CI24. Given a successful joint registration; when comparing its two actual
fold money observations; then complete spent references agree with every
referenced economic input (none omitted), input reference/value pairs agree,
all output amounts agree in order, fees/donations agree and the full validity
interval equals the economic transaction's present interval. All conjuncts
are required; this does not identify approval token encodings. -/
theorem registerJoint_money (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) (r : Registered)
    (accepted : registerJoint i c abstractRegistry commit q = .ok r) :
    q.fullFold.assets.spent = q.economicTx.transaction.inputs.filterMap (·.ref) ∧
    q.economicTx.transaction.inputs.length = (q.economicTx.transaction.inputs.filterMap (·.ref)).length ∧
    q.fullFold.spentOutputs.map (fun o => (o.reference, o.lovelace)) =
      (q.unspent.filter fun item => Singular.inputsContainReference
        q.economicTx.transaction.inputs item.1).map (fun item => (item.1, item.2.output.lovelace)) ∧
    q.fullFold.outputs.map (·.lovelace) = q.economicTx.outputs.map (fun o => o.output.lovelace) ∧
    q.fullFold.fee = q.economicTx.transaction.fee ∧
    q.fullFold.donation = q.economicTx.transaction.donation ∧
    some q.fullFold.interval = q.economicTx.transaction.validity := by
  have agreement := (registerJoint_sound i c abstractRegistry commit q r accepted).2.2.2.2.2.1
  have money : moneyAgreementB q = true := (Bool.and_eq_true_iff.mp agreement).2
  simpa [moneyAgreementB, and_assoc] using money

/-- CI25. Given actual successful joint registration and independently
authenticated environment; when the treasury reads its actual delivered
holding at any time; then acceptance iff the unchanged old lifecycle
eligibility holds at that time. Juvenility remains effective; success of
registration alone is never assumed to imply immediate consumer acceptance. -/
theorem registered_consumer_iff (i : Interpretation) (c : Context) (e : Environment)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) (r : Registered) (now : Slot)
    (accepted : registerJoint i c abstractRegistry commit q = .ok r)
    (context : authenticatedContext c e) :
    consumableHolding i c e q.checkpointParams now r.holding ↔
      consumableState q.checkpointParams now r.checkpoint := by
  obtain ⟨receipt, _, _, _, _, _, _, realized, _⟩ :=
    (registerJoint_sound i c abstractRegistry commit q r accepted).2.2.2.2.2.2
  exact existing_eligibility_preserved i c e q.checkpointParams q.registryParams now r.checkpoint r.holding
    context realized

/-- CI26. Given concrete successful genesis, booking, economic fold and
full-identity fold; actual Checkpoint registration; actual selected output in
both transactions; successful complete relation check; and the installed
binding alias; when running the bridge; then it returns some result. These
are executable component/representation preconditions, not a consumer verdict
or a whole-machine equivalence premise. The connected witness must establish
every premise by execution rather than seed final states. -/
theorem registerJoint_complete (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) (created : CreatedRegistry)
    (booked after : CardanoKeri.Registry.Sys) (bookFlow foldFlow : CardanoKeri.Registry.Flow)
    (cpFlow : Flow) (st : State) (o : AH.ObservedOutput) (eo : Singular.EconomicOutput) (token : Nat)
    (genesis : createRegistry i c abstractRegistry q.configuration commit q.genesisTx q.genesisOutputs = .ok created)
    (book : CardanoKeri.Registry.bookRegistration q.registryParams created.economic q.booking = .ok (bookFlow, booked))
    (fold : CardanoKeri.Registry.fold q.registryParams q.registryEnv booked booked.gen
      booked.config.applicationPolicy q.unspent q.economicTx = .ok (foldFlow, after))
    (fullFold : SingularApplicationHeld.fold .none i.hash i.code commit c.release q.fullFold = true)
    (registration : stepFn q.checkpointParams q.checkpointEnv (.register q.refund q.pool) q.now .absent = some (cpFlow, st))
    (fullOutput : q.fullFold.outputs[q.holdingIndex]? = some o)
    (economicOutput : q.economicTx.outputs[q.holdingIndex]? = some eo)
    (agreement : registrationAgreementB i c q created booked after st o eo = true)
    (binding : CardanoKeri.Registry.bindingAt after c.aid = some token) :
    ∃ r, registerJoint i c abstractRegistry commit q = .ok r := by
  simp [registerJoint, genesis, book, fold, fullFold, registration, fullOutput,
    economicOutput, agreement, binding, bind, Except.bind, pure, Except.pure]

end CardanoKeri.ConsumerIdentity
