import CardanoKeri.RegistryReach

/-! Exact retained carrier and pending-request custody along actual histories. -/
namespace CardanoKeri.Registry


/-- Filtering keeps the first matching whole record when that record is kept. -/
theorem find_filter_kept {α : Type} (xs : List α) (predicate keep : α → Bool)
    (item : α) (found : xs.find? predicate = some item) (kept : keep item = true) :
    (xs.filter keep).find? predicate = some item := by
  induction xs with
  | nil => simp at found
  | cons head tail ih =>
    cases hp : predicate head <;> cases hk : keep head <;>
      simp_all

/-- An unconsumed pending reference retains its complete stored record. -/
theorem fold_pending_record (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s'))
    {ref : Singular.OutRef} {e : TerminationEntry} (hp : pendingAt s ref = some e)
    (hn : Singular.inputsContainReference tx.transaction.inputs ref = false) :
    pendingAt s' ref = some e := by
  have reference := (pending_lookup_mem s ref e hp).2
  unfold pendingAt
  rw [(fold_sound p env hs).2.2.2.2.2.2]
  exact find_filter_kept _ _ _ e hp (by simp [reference, hn])

/-- Every successful action that does not consume this reference preserves
its complete pending record. This frame is independent of a far-slot bound. -/
theorem pending_record_frame (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s'))
    (ref : Singular.OutRef) (e : TerminationEntry) (hp : pendingAt s ref = some e)
    (hn : ¬ ConsumesPending ref action) : pendingAt s' ref = some e := by
  cases action with
  | bookRegistration b =>
    obtain ⟨_, _, rfl, _⟩ := bookRegistration_sound p hs
    exact hp
  | convictCkpt aid =>
    obtain ⟨c, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
    exact hp
  | bookTermination aid booker fee b => exact (booking_keeps_prior_pending p hs hp).2.1
  | fold gen plugin u tx =>
    apply fold_pending_record p env hs hp
    cases consumed : Singular.inputsContainReference tx.transaction.inputs ref with
    | false => rfl
    | true => exact False.elim (hn ⟨gen, plugin, u, tx, rfl, consumed⟩)
  | genericRetraction u tx =>
    unfold pendingAt
    rw [(generic_retraction_sound s s' u tx f hs).2.2.1]
    exact hp
  | genericRejection u tx =>
    unfold pendingAt
    rw [(generic_rejection_sound s s' u tx f hs).2.2.1]
    exact hp

/-- A pending lookup in a well-formed state supplies its exact alias and
active leaf; imported supply sync then gives precisely one token. -/
theorem pending_record_facts (p : Params) {s : Sys} (hw : WellFormed p s)
    (ref : Singular.OutRef) (e : TerminationEntry) (hp : pendingAt s ref = some e) :
    bindingAt s e.payload.aid = some e.payload.token ∧
    Singular.trieGet s.trie e.payload.aid = .known .active ∧
    Singular.worldSingularSupply s.toWorld e.payload.aid = 1 := by
  have facts := hw.terminationShape e (pending_lookup_mem s ref e hp).1
  have active := facts.2.2.2.2.2.2.2.2.2.2
  exact ⟨facts.2.2.2.2.2.2.2.2.2.1, active,
    (Singular.Statements.world_supply_sync s.toWorld hw.worldReachable e.payload.aid).1.mpr active⟩

/-- In a well-formed state a terminal leaf has neither carrier nor pending
custody. The lookup and the entire filtered pending list are both empty. -/
theorem terminal_no_custody (p : Params) {s : Sys} (hw : WellFormed p s) (aid : Nat)
    (terminal : Singular.trieGet s.trie aid = .known .terminal) :
    carrierAt s aid = none ∧ (s.terminations.filter (fun e => e.payload.aid == aid)) = [] := by
  constructor
  · cases found : carrierAt s aid with
    | none => rfl
    | some c =>
      have shape := hw.carrierShape c (List.mem_of_find?_eq_some found)
      have key : c.aid = aid := by simpa using List.find?_some found
      have active := shape.2.2.2.2.1
      rw [key, terminal] at active
      contradiction
  · apply List.filter_eq_nil_iff.mpr
    intro e member
    have active := (hw.terminationShape e member).2.2.2.2.2.2.2.2.2.2
    have different : e.payload.aid ≠ aid := by
      intro equal
      rw [equal, terminal] at active
      contradiction
    simpa using different

/-- Given the actual full before Sys and actual successful adapter fold; when
reading its result; then the actual imported fold accepted exactly its full
projected successor and the exact two pools are filtered by consumed refs.
Conversely a reachable Sys, preserved KERI registration authorization and
actual upstream acceptance must reconstruct successfully: a metadata guard
cannot hide missing adapter behavior. The two custody theorems preserve the
entire unselected record and retire/burn/remove only the exact selected one,
including alias and tag identity observations. These types are universal over
mixed batches, not just terminal-only lists. Positive witness: registration
of a fresh AID plus termination of AID11, with AID12 still pending. Negative
controls isolate wrong root, config/plugin, generation, request/ref, donation,
carrier, mint, and unselected tail independently. Compile/setup failures do
not count as semantic kills. -/
theorem fold_keeps_unselected (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) {gen plugin : Nat}
    {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s'))
    {ref : Singular.OutRef} {e : TerminationEntry}
    (hp : pendingAt s ref = some e)
    (hn : Singular.inputsContainReference tx.transaction.inputs ref = false) :
    pendingAt s' ref = some e ∧
    Singular.trieGet s'.trie e.payload.aid = .known .active ∧
    bindingAt s' e.payload.aid = some e.payload.token ∧
    Singular.worldSingularSupply s'.toWorld e.payload.aid = 1 := by
  have kept := fold_pending_record p env hs hp hn
  have hw := wellFormed_fold p env (reachable_wellFormed p env cfg hr) hs
  obtain ⟨binding, active, supply⟩ := pending_record_facts p hw ref e kept
  exact ⟨kept, active, binding, supply⟩

/-- Given the whole WellFormed predicate, including the explicit bindingDomain
clause, when an arbitrary adapter step succeeds, then the
entire invariant persists. Reachable initial/step history supplies this
predicate and the explicit domain iff; generic reachability alone does not
prove anything about alias bindings. The empty-world/phantom-alias
fixture must fail bindingDomain, while a genuine fresh registration succeeds.
No policy rejects legitimate registration merely to avoid that missing proof.

Given an actual pending lookup in a reachable system, a successful arbitrary
competing action, and absence of consumption of its exact reference; when
observing its successor; then the complete old record, token binding, active
leaf and supply remain. This covers local steps, booking in either store,
generic recovery and mixed fold. No obsolete now<far premise is imported.
These are the successors to Agreement's
custody and refusal obligations, not merely names for the old go-request. -/
theorem pending_preserved_unless_consumed
    (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys}
    (hr : Reach p env cfg s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s'))
    (ref : Singular.OutRef) (e : TerminationEntry)
    (hp : pendingAt s ref = some e) (hn : ¬ ConsumesPending ref action) :
    pendingAt s' ref = some e ∧
    bindingAt s' e.payload.aid = some e.payload.token ∧
    Singular.trieGet s'.trie e.payload.aid = .known .active ∧
    Singular.worldSingularSupply s'.toWorld e.payload.aid = 1 := by
  have kept := pending_record_frame p env hs ref e hp hn
  have hw := wellFormed_step p env (reachable_wellFormed p env cfg hr) hs
  exact ⟨kept, pending_record_facts p hw ref e kept⟩

/-- Given an actual transition and changed leaf, or a reachable already-retired
key, or the exact lookup/state premises of the refusals; when taking/attempting
the action; then only an actual fold can change a leaf, retirement cannot be
re-registered, and unconvicted live booking is not admitted. An absent carrier after booking is separately refused
by carrier-missing. No far-slot convention protects termination; its actual
state and the generic request kind do. Positive registered/convicted/booked/folded
traces must accompany these refusals. -/
theorem retired_preserved (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) (aid : Nat)
    (retired : Singular.trieGet s.trie aid = .known .terminal) :
    Singular.trieGet s'.trie aid = .known .terminal ∧ carrierAt s' aid = none ∧
    (s'.terminations.filter (fun e => e.payload.aid == aid)) = [] := by
  have terminal := terminal_leaf_permanent p env hs aid retired
  have hw := wellFormed_step p env (reachable_wellFormed p env cfg hr) hs
  exact ⟨terminal, terminal_no_custody p hw aid terminal⟩

/-- An identity-preserving carrier edit maps the exact found carrier. -/
theorem carrier_edit_lookup (s : Sys) (edit : Carrier → Carrier)
    (same : ∀ c, (edit c).aid = c.aid) (aid : Nat) :
    carrierAt { s with carriers := s.carriers.map edit } aid = (carrierAt s aid).map edit := by
  simp only [carrierAt, List.find?_map, Function.comp_def]
  have predicate : (fun c => (edit c).aid == aid) = (fun c => c.aid == aid) := by
    funext c; rw [same c]
  rw [predicate]

/-- An edit fixing every carrier of an unrelated identity leaves its entire
lookup unchanged, not merely its token count. -/
theorem carrier_edit_other (s : Sys) (edit : Carrier → Carrier)
    (same : ∀ c, (edit c).aid = c.aid) (aid : Nat)
    (fixed : ∀ c, c.aid = aid → edit c = c) :
    carrierAt { s with carriers := s.carriers.map edit } aid = carrierAt s aid := by
  rw [carrier_edit_lookup s edit same aid]
  cases found : carrierAt s aid with
  | none => rfl
  | some c =>
    have key : c.aid = aid := by simpa using List.find?_some found
    simp [fixed c key]

/-- Given all typed inputs, and reachability/current carrier lookup in the
retention theorems; when one of the actual local functions succeeds; then
all source/guard/exact-flow/successor clauses in its iff hold in both
directions, and every stated actual-world, metadata, counter, other-AID,
key/alias/holding/min-ADA clause holds. Conviction preserves the key. Registry's empty internal conviction
flow is scoped to its coarse transport, not denial of Checkpoint's addressed
payments. Two-AID reachable witnesses and single-field key/token/Mc/frame
mutations are required. A fallback minAdaAt=0 alone is never the success
witness. No same-token claim is based only on token count. -/
theorem local_conviction_retains (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} {aid : Nat} {f : Flow} {c : Carrier}
    (hr : Reach p env cfg s) (hc : carrierAt s aid = some c)
    (hs : convictCkpt env s aid = .ok (f, s')) :
    carrierAt s' aid = some { c with st := .terminationPending } ∧
    minAdaAt s' aid = p.Mc ∧ s'.toWorld = s.toWorld ∧
    s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧ s'.gen = s.gen ∧
    s'.terminations = s.terminations ∧ s'.registrations = s.registrations ∧
    (∀ other, other ≠ aid → carrierAt s' other = carrierAt s other) ∧ f = {} := by
  have shape := (reachable_wellFormed p env cfg hr).carrierShape c (List.mem_of_find?_eq_some hc)
  have key : c.aid = aid := by simpa using List.find?_some hc
  have world := local_actions_world p env (action := .convictCkpt aid) ⟨aid, rfl⟩ hs
  obtain ⟨current, _, _, _, rfl, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
  let edit := fun old : Carrier => if old.aid == aid then { old with st := .terminationPending } else old
  have same : ∀ old, (edit old).aid = old.aid := by intro old; dsimp [edit]; split <;> rfl
  have found : carrierAt { s with carriers := s.carriers.map edit } aid = some { c with st := .terminationPending } := by
    rw [carrier_edit_lookup s edit same aid]
    simp [hc, edit, key]
  refine ⟨found, ?_, world, rfl, rfl, rfl, rfl, rfl, ?_, rfl⟩
  · change ((carrierAt { s with carriers := s.carriers.map edit } aid).map (·.minAda)).getD 0 = p.Mc
    simp [found, shape.2.2.1]
  · intro other different
    apply carrier_edit_other s edit same other
    intro old key
    simp [edit, key, different]

/-- Generic supply is exactly the two actual application custody counts.
The equality uses intrinsic field agreement, not a token-count abstraction. -/
theorem application_supply_counts (p : Params) {s : Sys} (hw : WellFormed p s) (aid : Nat) :
    Singular.worldSingularSupply s.toWorld aid =
      (s.carriers.filter (fun c => c.aid == aid)).length +
      (s.terminations.filter (fun e => e.payload.aid == aid)).length := by
  have carriers : Singular.kindCount s.toWorld.registry .active aid =
      (s.carriers.filter (fun c => c.aid == aid)).length := by
    simp only [Singular.kindCount, Sys.toWorld, List.filter_map, List.length_map]
    congr 1
    apply List.filter_congr
    intro c member
    have shape := hw.carrierShape c member
    simp [shape.1]
  have pending : Singular.pendingTerminationCount s.toWorld aid =
      (s.terminations.filter (fun e => e.payload.aid == aid)).length := by
    simp only [Singular.pendingTerminationCount, Sys.toWorld, List.filter_map, List.length_map]
    congr 1
    apply List.filter_congr
    intro e member
    simp only [Function.comp_def, (hw.terminationShape e member).1]
  unfold Singular.worldSingularSupply
  rw [carriers, (Singular.Statements.world_supply_sync s.toWorld hw.worldReachable aid).2.2.2, pending]

/-- Given any Sys for projection, or a Reach derivation from actual init/stepFn
for the latter two; when observing the entire current system; then every
projected field is the actual stored field, the complete named WellFormed
predicate holds, and active means exactly one custody location in both
directions. Prebooking terminationPending carriers count as carriers. No
ignored extra holding, duplicate pending record or free parallel World is
allowed. Required trace contains two registrations and two convictions,
books one while leaving the other carrier pending, then books the second. -/
theorem active_custody_iff (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (h : Reach p env cfg s) (aid : Nat) :
    Singular.trieGet s.trie aid = .known .active ↔
      ((s.carriers.filter (fun c => c.aid == aid)).length = 1 ∧
       (s.terminations.filter (fun e => e.payload.aid == aid)).length = 0) ∨
      ((s.carriers.filter (fun c => c.aid == aid)).length = 0 ∧
       (s.terminations.filter (fun e => e.payload.aid == aid)).length = 1) := by
  have hw := reachable_wellFormed p env cfg h
  have counts := application_supply_counts p hw aid
  have sync : Singular.worldSingularSupply s.toWorld aid = 1 ↔
      Singular.trieGet s.trie aid = .known .active :=
    (Singular.Statements.world_supply_sync s.toWorld hw.worldReachable aid).1
  rw [← sync, counts]
  omega

/-- Given the exact inputs and actual success, plus actual Reach history where
stated; when booking the convicted carrier or inspecting a reachable pending
record; then the iff includes every application field constraint, actual
imported admission and complete successor, premium, request and external fee
observation. Each reachable booked payload has a real prior reachable KERI
conviction at its retained key, using the existing opaque premise. This is
not a proof that the opaque predicate equals concrete Checkpoint duplicity.
All earlier pending records survive wholly; actual supply remains one and
custody moves exactly once. Required refusals: live without prior
conviction, invalid coarse proof, wrong holding/key/token, duplicate reference
in either store, second booking of the same carrier, and a tail-drop mutant
that otherwise still admits both bookings. Full concrete Checkpoint evidence
controls are exercised separately from the whole-record preservation claim. -/
theorem booking_keeps_active_supply (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} {aid booker fee : Nat} {b : Singular.TerminationBooking} {f : Flow}
    (hr : Reach p env cfg s)
    (hs : bookTermination p s aid booker fee b = .ok (f, s')) :
    Singular.trieGet s'.trie aid = .known .active ∧
    Singular.worldSingularSupply s'.toWorld aid = 1 ∧
    carrierAt s' aid = none ∧
    ∃ e, pendingAt s' b.request.reference = some e ∧ e.booking = b ∧
      e.payload.aid = aid ∧ bindingAt s' aid = some e.payload.token := by
  have hw := wellFormed_bookTermination p (reachable_wellFormed p env cfg hr) hs
  obtain ⟨c, world, _, _, _, _, _, _, _, _, _, _, successor, _, _⟩ :=
    (bookTermination_iff p s s' aid booker fee b f).mp hs
  subst s'
  let entry : TerminationEntry := { booking := b, payload := {
    aid := aid, token := c.token, keyState := c.k, original := c.original,
    booker := booker, bookingFee := fee } }
  have found : pendingAt { s with
      carriers := s.carriers.filter (fun old => old.aid != aid),
      terminations := entry :: s.terminations } b.request.reference = some entry := by
    simp [pendingAt, entry]
  have facts := pending_record_facts p hw b.request.reference entry found
  refine ⟨facts.2.1, facts.2.2, ?_, entry, found, rfl, rfl, facts.1⟩
  simp [carrierAt, List.find?_filter]

end CardanoKeri.Registry
