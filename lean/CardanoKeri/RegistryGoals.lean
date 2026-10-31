import CardanoKeri.Registry
import CardanoKeri.Samaritan
import Singular.Lemmas.RetractionFunding

/-! Exact retained-output registry contracts over actual imported execution. -/
namespace CardanoKeri.Registry

section Assoc
variable {α : Type}

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {r : α}
    (h : lookup rs id = some r)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

(id, r) ∈ rs
-/
theorem lookup_some_mem {rs : List (Nat × α)} {id : Nat} {r : α}
    (h : lookup rs id = some r) : (id, r) ∈ rs := by
  induction rs with
  | nil => simp [lookup] at h
  | cons x xs ih =>
    obtain ⟨i, r'⟩ := x
    simp only [lookup] at h
    split at h
    · rename_i hi; subst hi; cases h; exact List.mem_cons.2 (Or.inl rfl)
    · exact List.mem_cons_of_mem _ (ih h)

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat}
    (h : ∀ x, x ∈ rs → x.1 ≠ id)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup rs id = none
-/
theorem lookup_none_of_not_mem {rs : List (Nat × α)} {id : Nat}
    (h : ∀ x, x ∈ rs → x.1 ≠ id) : lookup rs id = none := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨i, r⟩ := x
    simp only [lookup]
    have hi : i ≠ id := h (i, r) (List.mem_cons.2 (Or.inl rfl))
    rw [if_neg hi]
    exact ih (fun y hy => h y (List.mem_cons_of_mem _ hy))

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∀ x, x ∈ rs → x.1 ≠ id
-/
theorem not_mem_of_lookup_none {rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none) :
    ∀ x, x ∈ rs → x.1 ≠ id := by
  induction rs with
  | nil => intro x hx; simp at hx
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [lookup] at h
    split at h
    · cases h
    · rename_i hi
      intro x hx
      rcases List.mem_cons.1 hx with hx | hx
      · subst hx; exact hi
      · exact ih h x hx

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

id ∉ rs.map (·.1)
-/
theorem key_not_mem_of_lookup_none {rs : List (Nat × α)} {id : Nat} (h : lookup rs id = none) :
    id ∉ rs.map (·.1) := by
  intro hm
  obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
  exact not_mem_of_lookup_none h y hy hyi

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {r : α}
    (hn : (rs.map (·.1)).Nodup) (h : (id, r) ∈ rs)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup rs id = some r
-/
theorem lookup_some_of_mem {rs : List (Nat × α)} {id : Nat} {r : α}
    (hn : (rs.map (·.1)).Nodup) (h : (id, r) ∈ rs) : lookup rs id = some r := by
  induction rs with
  | nil => simp at h
  | cons y ys ih =>
    obtain ⟨i, r'⟩ := y
    rw [List.map_cons, List.nodup_cons] at hn
    simp only [lookup]
    rcases List.mem_cons.1 h with h | h
    · cases h; simp
    · have hi : i ≠ id := by
        intro e; subst e
        exact hn.1 (List.mem_map.2 ⟨(i, r), h, rfl⟩)
      rw [if_neg hi]
      exact ih hn.2 h

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {r : α}

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup ((id, r) :: rs) id = some r
-/
theorem lookup_cons_self {rs : List (Nat × α)} {id : Nat} {r : α} :
    lookup ((id, r) :: rs) id = some r := by simp [lookup]

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id i : Nat} {r : α} (h : i ≠ id)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup ((i, r) :: rs) id = lookup rs id
-/
theorem lookup_cons_ne {rs : List (Nat × α)} {id i : Nat} {r : α} (h : i ≠ id) :
    lookup ((i, r) :: rs) id = lookup rs id := by simp [lookup, h]

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ remove rs id)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

x ∈ rs
-/
theorem mem_remove {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ remove rs id) : x ∈ rs := by
  induction rs with
  | nil => simp [remove] at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove] at h
    split at h
    · exact List.mem_cons_of_mem _ (ih h)
    · rcases List.mem_cons.1 h with h | h
      · subst h; exact List.mem_cons.2 (Or.inl rfl)
      · exact List.mem_cons_of_mem _ (ih h)

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ remove rs id)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

x.1 ≠ id
-/
theorem fst_ne_of_mem_remove {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ remove rs id) : x.1 ≠ id := by
  induction rs with
  | nil => simp [remove] at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove] at h
    split at h
    · exact ih h
    · rename_i hi
      rcases List.mem_cons.1 h with h | h
      · subst h; exact hi
      · exact ih h

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ rs) (hne : x.1 ≠ id)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

x ∈ remove rs id
-/
theorem mem_remove_of_mem {rs : List (Nat × α)} {id : Nat} {x : Nat × α}
    (h : x ∈ rs) (hne : x.1 ≠ id) : x ∈ remove rs id := by
  induction rs with
  | nil => simp at h
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    simp only [remove]
    rcases List.mem_cons.1 h with h | h
    · subst h
      rw [if_neg hne]
      exact List.mem_cons.2 (Or.inl rfl)
    · split
      · exact ih h
      · exact List.mem_cons_of_mem _ (ih h)

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat}
    (h : (rs.map (·.1)).Nodup)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

((remove rs id).map (·.1)).Nodup
-/
theorem nodup_map_remove {rs : List (Nat × α)} {id : Nat}
    (h : (rs.map (·.1)).Nodup) : ((remove rs id).map (·.1)).Nodup := by
  induction rs with
  | nil => simp [remove]
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    rw [List.map_cons, List.nodup_cons] at h
    obtain ⟨hi, hys⟩ := h
    simp only [remove]
    split
    · exact ih hys
    · rw [List.map_cons]
      refine List.nodup_cons.2 ⟨?_, ih hys⟩
      intro hm
      obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
      exact hi (List.mem_map.2 ⟨y, mem_remove hy, hyi⟩)

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat}

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup (remove rs id) id = none
-/
theorem lookup_remove_self {rs : List (Nat × α)} {id : Nat} :
    lookup (remove rs id) id = none :=
  lookup_none_of_not_mem (fun _ hx => fst_ne_of_mem_remove hx)

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id id' : Nat} (h : id ≠ id')

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

lookup (remove rs id') id = lookup rs id
-/
theorem lookup_remove_ne {rs : List (Nat × α)} {id id' : Nat} (h : id ≠ id') :
    lookup (remove rs id') id = lookup rs id := by
  induction rs with
  | nil => rfl
  | cons y ys ih =>
    obtain ⟨i, r⟩ := y
    by_cases h1 : i = id'
    · subst h1
      have h2 : i ≠ id := fun e => h e.symm
      simp [remove, lookup, h2, ih]
    · simp [remove, lookup, h1, ih]

/-- Given the complete parameters and hypotheses:

{rs : List (Nat × α)} {id : Nat}

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

id ∉ (remove rs id).map (·.1)
-/
theorem key_not_mem_map_fst_remove_self {rs : List (Nat × α)} {id : Nat} :
    id ∉ (remove rs id).map (·.1) := by
  intro hm
  obtain ⟨y, hy, hyi⟩ := List.mem_map.1 hm
  exact fst_ne_of_mem_remove hy hyi

/-- Under unique identifiers, an entry of `rs` with the removed identifier is
the entry `lookup` returns. -/
theorem eq_of_mem_of_fst_eq {rs : List (Nat × α)} {id : Nat} {r : α} {x : Nat × α}
    (hn : (rs.map (·.1)).Nodup) (hl : lookup rs id = some r) (hx : x ∈ rs) (hid : x.1 = id) :
    x = (id, r) := by
  obtain ⟨i, r'⟩ := x
  simp only at hid
  subst hid
  have := lookup_some_of_mem hn hx
  rw [hl] at this
  cases this
  rfl

end Assoc

local instance : LawfulBEq CkState where
  eq_of_beq {a b} h := by cases a <;> cases b <;> first | rfl | exact absurd h (by decide)
  rfl {a} := by cases a <;> rfl

/-- Given any Sys for projection, or a Reach derivation from actual init/stepFn
for the latter two; when observing the entire current system; then every
projected field is the actual stored field, the complete named WellFormed
predicate holds, and active means exactly one custody location in both
directions. Prebooking terminationPending carriers count as carriers. No
ignored extra holding, duplicate pending record or free parallel World is
allowed. Required trace contains two registrations and two convictions,
books one while leaving the other carrier pending, then books the second. -/
theorem total_projection (s : Sys) :
    s.toWorld.registry = {
      config := s.config, trie := s.trie,
      held := s.carriers.map (·.original) } ∧
    s.toWorld.pending = s.registrations ∧
    s.toWorld.terminations = s.terminations.map (·.booking) ∧
    s.toWorld.treasury = s.treasury := by exact ⟨rfl, rfl, rfl, rfl⟩

/-- Given all typed inputs, and reachability/current carrier lookup in the
retention theorems; when one of the actual local functions succeeds; then
all source/guard/exact-flow/successor clauses in its iff hold in both
directions, and every stated actual-world, metadata, counter, other-AID,
key/alias/holding/min-ADA clause holds. Conviction preserves the key. Registry's empty internal conviction
flow is scoped to its coarse transport, not denial of Checkpoint's addressed
payments. Two-AID reachable witnesses and single-field key/token/Mc/frame
mutations are required. A fallback minAdaAt=0 alone is never the success
witness. No same-token claim is based only on token count. -/
theorem convictCkpt_iff (env : Env) (s s' : Sys) (aid : Nat) (f : Flow) :
    convictCkpt env s aid = .ok (f, s') ↔
      ∃ c, carrierAt s aid = some c ∧
        c.st = .live ∧ env.duplicity aid c.k = true ∧
        f = {} ∧ s' = { s with carriers := s.carriers.map (fun old =>
          if old.aid == aid then { old with st := .terminationPending } else old) } := by
  cases hc : carrierAt s aid with
  | none => simp [convictCkpt, hc]
  | some c =>
    cases hst : c.st <;> cases he : env.duplicity aid c.k <;>
      simp [convictCkpt, hc, hst, he, bind, Except.bind, pure, Except.pure]
    all_goals simp only [eq_comm]

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem fold_iff (p : Params) (env : Env) (s s' : Sys) (gen plugin : Nat)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (f : Flow) :
    fold p env s gen plugin u tx = .ok (f, s') ↔
      gen = s.gen ∧ plugin = s.config.applicationPolicy ∧
      registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true ∧
      ∃ world, Singular.foldAccepted s.toWorld u tx = .ok world ∧
        foldResult p s tx world = .ok (f, s') := by
  by_cases hg : gen = s.gen
  · by_cases hp : plugin = s.config.applicationPolicy
    · cases ha : registrationsAuthorized env (Singular.foldMembers s.toWorld tx) <;>
        cases hw : Singular.foldAccepted s.toWorld u tx <;>
        simp [fold, hg, hp, ha, hw, bind, Except.bind, pure, Except.pure]
    · simp [fold, hg, hp, bind, Except.bind, pure, Except.pure]
  · simp [fold, hg, bind, Except.bind]

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem fold_stale_refused (p : Params) (env : Env) (s : Sys) (gen plugin : Nat)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (hg : gen ≠ s.gen) :
    (fold p env s gen plugin u tx).toOption = none := by simp [fold, hg, bind, Except.bind, Except.toOption]

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem fold_plugin_swap_refused (p : Params) (env : Env) (s : Sys) (gen plugin : Nat)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (hp : plugin ≠ s.config.applicationPolicy) :
    (fold p env s gen plugin u tx).toOption = none := by
  by_cases hg : gen = s.gen <;> simp [fold, hg, hp, bind, Except.bind, pure, Except.pure, Except.toOption]

/-- Given any registry state whose carrier for the identifier is live, that is
alive and not convicted, and any booker, fee and termination booking.
When anyone books the termination of that identifier.
Then the booking is refused with `keri-conviction-required`: only a convicted
checkpoint, in pending termination, can be booked for retirement. There is no
owner exit that books a live checkpoint. Reachable witness: the registered
live carrier of `RegistryLifecycleExamples`. -/
theorem live_cannot_book (p : Params) (s : Sys) (aid booker fee : Nat)
    (b : Singular.TerminationBooking) (c : Carrier)
    (hc : carrierAt s aid = some c) (hp : c.st = .live) :
    bookTermination p s aid booker fee b = .error "keri-conviction-required" := by
  simp [bookTermination, hc, hp, bind, Except.bind]

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
theorem pending_lookup_mem (s : Sys) (ref : Singular.OutRef) (e : TerminationEntry)
    (hp : pendingAt s ref = some e) :
    e ∈ s.terminations ∧ e.booking.request.reference = ref := by
  exact ⟨List.mem_of_find?_eq_some hp, by simpa using List.find?_some hp⟩

/-- Given every actual fold input and any alternative signer list; when changing
only that list; then the exact result remains the same. KERI inception and
prior conviction authorization remain separate guards/history, and generic
value/tag/custody checks remain unchanged. This is a statement about the
modeled fold, not authorization to spend arbitrary ordinary ledger inputs.
`fold_plugin_swap_refused` separately protects the configured application
policy; `registration_delivery` and `current_sys_fold_accounting` describe
the actual output and value obligations. -/
theorem fold_signers_irrelevant (p : Params) (env : Env) (s : Sys)
    (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (signers : List Nat) :
    fold p env s gen plugin u
      { tx with transaction := { tx.transaction with signers := signers } } =
    fold p env s gen plugin u tx := by rfl

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
theorem wellFormed_initial (p : Params) (cfg : Singular.Config) :
    WellFormed p (Sys.init cfg) := by
  constructor
  all_goals try simp [Sys.init, bindingAt, registrationShape, Singular.trieGet]
  exact Singular.WorldReachable.initial _ (Singular.Reachable.initial cfg)

/-- Every accepted reconstruction exposes the same complete generic World and
keeps exactly the unconsumed records, with one generation increment. -/
theorem foldResult_sound (p : Params) {s s' : Sys} {tx : Singular.EconomicTransaction}
    {world : Singular.World} {f : Flow} (hs : foldResult p s tx world = .ok (f, s')) :
    s'.toWorld = world ∧ s'.gen = s.gen + 1 ∧
    s'.registrations = s.registrations.filter (fun b =>
      !Singular.inputsContainReference tx.transaction.inputs b.request.reference) ∧
    s'.terminations = s.terminations.filter (fun e =>
      !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference) := by
  unfold foldResult at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · split at hs
    · contradiction
    · rename_i good
      cases hs
      exact ⟨by simpa using good, rfl, rfl, rfl⟩

/-- Accepted recovery reconstruction changes only the registration pool and
its complete World equals the imported result. -/
theorem recoverRegistrations_sound {s s' : Sys} {world : Singular.World}
    (hs : recoverRegistrations s world = .ok s') :
    s'.toWorld = world ∧ s'.carriers = s.carriers ∧ s'.terminations = s.terminations ∧
    s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧
    s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken := by
  unfold recoverRegistrations at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i good
    cases hs
    exact ⟨by simpa using good, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

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
theorem fold_sound (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s')) :
    gen = s.gen ∧ plugin = s.config.applicationPolicy ∧
    registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true ∧
    Singular.foldAccepted s.toWorld u tx = .ok s'.toWorld ∧
    s'.gen = s.gen + 1 ∧
    s'.registrations = s.registrations.filter (fun b =>
      !Singular.inputsContainReference tx.transaction.inputs b.request.reference) ∧
    s'.terminations = s.terminations.filter (fun e =>
      !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference) := by
  obtain ⟨gen, plugin, auth, world, executed, reconstructed⟩ :=
    (fold_iff p env s s' gen plugin u tx f).mp hs
  obtain ⟨projected, generation, regs, terms⟩ := foldResult_sound p reconstructed
  exact ⟨gen, plugin, auth, by simpa [projected] using executed, generation, regs, terms⟩

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem generation_cannot_be_reused (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s'))
    (plugin' : Nat) (u' : Singular.EconomicUtxo) (tx' : Singular.EconomicTransaction) :
    (fold p env s' gen plugin' u' tx').toOption = none := by
  have facts := fold_sound p env hs
  apply fold_stale_refused
  have before := facts.1
  have after := facts.2.2.2.2.1
  omega

/-- Given the actual supplied UTxO and corresponding complete imported transaction
and actual wrapper success; when inspecting the successor; then its full World
is the imported result and every stated carrier/termination/registry/counter
field stays fixed. Empty coarse Flow records no added application payment;
actual refund/fee observations belong to the transaction and imported judgment.
No old phase-only enabling or arbitrary future-timestamp-rejection theorem is
inherited. No assertion of broader #468 application recovery is made. A
registration recovery alongside an untouched termination must supply the
positive frame exhibit; attempted termination recovery is a refusal control. -/
theorem generic_retraction_sound (s s' : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction) (f : Flow)
    (hs : genericRetraction s u tx = .ok (f, s')) :
    Singular.retractionAccepted s.toWorld u tx = .ok s'.toWorld ∧
    s'.carriers = s.carriers ∧ s'.terminations = s.terminations ∧
    s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧
    s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧
    f = {} := by
  unfold genericRetraction at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i world executed
    split at hs
    · contradiction
    · rename_i after reconstructed
      cases hs
      obtain ⟨projected, frames⟩ := recoverRegistrations_sound reconstructed
      exact ⟨by simpa [projected] using executed, frames.1, frames.2.1,
        frames.2.2.1, frames.2.2.2.1, frames.2.2.2.2.1, frames.2.2.2.2.2.1,
        frames.2.2.2.2.2.2.1, frames.2.2.2.2.2.2.2, rfl⟩

/-- Given the actual supplied UTxO and corresponding complete imported transaction
and actual wrapper success; when inspecting the successor; then its full World
is the imported result and every stated carrier/termination/registry/counter
field stays fixed. Empty coarse Flow records no added application payment;
actual refund/fee observations belong to the transaction and imported judgment.
No old phase-only enabling or arbitrary future-timestamp-rejection theorem is
inherited. No assertion of broader #468 application recovery is made. A
registration recovery alongside an untouched termination must supply the
positive frame exhibit; attempted termination recovery is a refusal control. -/
theorem generic_rejection_sound (s s' : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.Rejection) (f : Flow)
    (hs : genericRejection s u tx = .ok (f, s')) :
    Singular.rejectionAccepted s.toWorld u tx = .ok s'.toWorld ∧
    s'.carriers = s.carriers ∧ s'.terminations = s.terminations ∧
    s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧
    s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧
    f = {} := by
  unfold genericRejection at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i world executed
    split at hs
    · contradiction
    · rename_i after reconstructed
      cases hs
      obtain ⟨projected, frames⟩ := recoverRegistrations_sound reconstructed
      exact ⟨by simpa [projected] using executed, frames.1, frames.2.1,
        frames.2.2.1, frames.2.2.2.1, frames.2.2.2.2.1, frames.2.2.2.2.2.1,
        frames.2.2.2.2.2.2.1, frames.2.2.2.2.2.2.2, rfl⟩

/-- Given an accepted application registration booking, its entire imported
World, value guard, flow and successor registration pool are determined. -/
theorem bookRegistration_sound (p : Params) {s s' : Sys}
    {b : Singular.RegistrationBooking} {f : Flow}
    (hs : bookRegistration p s b = .ok (f, s')) :
    registrationShape p b ∧ Singular.book s.toWorld b = .ok s'.toWorld ∧
    s' = { s with registrations := b :: s.registrations } ∧
    f = { deposited := b.request.contents.lovelace } := by
  unfold bookRegistration at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i shape
    split at hs
    · contradiction
    · rename_i world booked
      split at hs
      · contradiction
      · rename_i projected
        cases hs
        have equal : ({ s with registrations := b :: s.registrations } : Sys).toWorld = world := by simpa using projected
        exact ⟨by simpa using shape, by simpa [equal] using booked, rfl, rfl⟩

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
theorem bookTermination_iff (p : Params) (s s' : Sys) (aid booker fee : Nat)
    (b : Singular.TerminationBooking) (f : Flow) :
    bookTermination p s aid booker fee b = .ok (f, s') ↔
      ∃ c world, carrierAt s aid = some c ∧ c.st = .terminationPending ∧
        b.request.key = aid ∧ b.request.destination = c.original.output ∧
        b.custodyInputs = [c.original] ∧ c.minAda = p.Mc ∧
        b.request.carrierAda = p.Mr ∧ b.request.declaredTip = p.tip ∧
        b.request.contents.lovelace = p.Mr + p.tip ∧
        Singular.bookTermination s.toWorld b = .ok world ∧
        s' = { s with
          carriers := s.carriers.filter (fun old => old.aid != aid),
          terminations := { booking := b, payload := {
            aid := aid, token := c.token, keyState := c.k, original := c.original,
            booker := booker, bookingFee := fee } } :: s.terminations } ∧
        s'.toWorld = world ∧
        f = {
          premium := some (booker, p.Mc - p.Mr - p.tip),
          bookingFee := fee, intoRequest := p.Mr + p.tip } := by
  constructor
  · intro hs
    cases hc : carrierAt s aid with
    | none => simp [bookTermination, hc] at hs
    | some c =>
      unfold bookTermination at hs
      simp only [hc, bind, Except.bind, pure, Except.pure] at hs
      split at hs
      · contradiction
      · rename_i state
        split at hs
        · contradiction
        · rename_i shape
          split at hs
          · contradiction
          · rename_i world booked
            split at hs
            · contradiction
            · rename_i projected
              cases hs
              have state' : c.st = .terminationPending := by simpa using state
              have shape' : b.request.key = aid ∧ b.request.destination = c.original.output ∧
                  b.custodyInputs = [c.original] ∧ c.minAda = p.Mc ∧
                  b.request.carrierAda = p.Mr ∧ b.request.declaredTip = p.tip ∧
                  b.request.contents.lovelace = p.Mr + p.tip := by simpa using shape
              exact ⟨c, world, rfl, state', shape'.1, shape'.2.1, shape'.2.2.1,
                shape'.2.2.2.1, shape'.2.2.2.2.1, shape'.2.2.2.2.2.1,
                shape'.2.2.2.2.2.2, booked, rfl, by simpa using projected, rfl⟩
  · rintro ⟨c, world, hc, state, key, dest, custody, mc, mr, tip, held,
      booked, rfl, projected, rfl⟩
    simp [bookTermination, hc, state, key, dest, custody, mc, mr, tip, held,
      booked, projected, bind, Except.bind, pure, Except.pure]

/-- Given an actual reachable/executed FoldReceipt and exact Completes relation;
when using it for a Checkpoint focused completion; then actual imported
acceptance, exact removal/retirement/supply/alias effects hold. If its tx did
not consume the reference, that receipt cannot complete it. Wrong AID or alias
must fail the full lookup binding; unrelated receipt and wrong pending-key
controls are distinct. Full transactions remain authoritative over all their
members; this receipt cannot stand for an unexecuted proposed fold. -/
theorem completion_not_unselected (p : Params) (env : Env) (cfg : Singular.Config)
    (r : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat)
    (hu : Singular.inputsContainReference r.transaction.transaction.inputs ref = false) :
    ¬ Completes r ref aid token := by
  rintro ⟨e, _, _, _, consumed⟩
  simp [hu] at consumed

/-- A successful action other than fold preserves the whole registry config,
trie and generation. The premise classifies the action, not its result. -/
theorem nonfold_frame (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s'))
    (hn : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx) :
    s'.gen = s.gen ∧ s'.config = s.config ∧ s'.trie = s.trie := by
  cases action with
  | bookRegistration b =>
    obtain ⟨_, _, rfl, _⟩ := bookRegistration_sound p hs
    exact ⟨rfl, rfl, rfl⟩
  | convictCkpt aid =>
    obtain ⟨c, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
    exact ⟨rfl, rfl, rfl⟩
  | bookTermination aid booker fee b =>
    obtain ⟨c, world, _, _, _, _, _, _, _, _, _, _, rfl, _, _⟩ :=
      (bookTermination_iff p s s' aid booker fee b f).mp hs
    exact ⟨rfl, rfl, rfl⟩
  | fold gen plugin u tx => exact False.elim (hn gen plugin u tx rfl)
  | genericRetraction u tx =>
    obtain ⟨_, _, _, config, trie, gen, _⟩ := generic_retraction_sound s s' u tx f hs
    exact ⟨gen, config, trie⟩
  | genericRejection u tx =>
    obtain ⟨_, _, _, config, trie, gen, _⟩ := generic_rejection_sound s s' u tx f hs
    exact ⟨gen, config, trie⟩

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem config_and_generation_frame (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s')) :
    s'.config = { s.config with root := s'.config.root } ∧
    (s'.gen = s.gen ∨ s'.gen = s.gen + 1) ∧
    ((∀ gen plugin u tx, action ≠ .fold gen plugin u tx) →
      s'.gen = s.gen ∧ s'.config = s.config ∧ s'.trie = s.trie) := by
  by_cases hf : ∃ gen plugin u tx, action = .fold gen plugin u tx
  · obtain ⟨gen, plugin, u, tx, rfl⟩ := hf
    have facts := fold_sound p env hs
    refine ⟨Singular.foldAccepted_config facts.2.2.2.1, Or.inr facts.2.2.2.2.1, ?_⟩
    intro hn
    exact False.elim (hn gen plugin u tx rfl)
  · have hn : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx := by
      intro gen plugin u tx equal
      exact hf ⟨gen, plugin, u, tx, equal⟩
    obtain ⟨gen, config, trie⟩ := nonfold_frame p env hs hn
    exact ⟨by simp [config], Or.inl gen, fun _ => ⟨gen, config, trie⟩⟩

/-- Given an actual transition and changed leaf, or a reachable already-retired
key, or the exact lookup/state premises of the refusals; when taking/attempting
the action; then only an actual fold can change a leaf, retirement cannot be
re-registered, and unconvicted live booking is not admitted. An absent carrier after booking is separately refused
by carrier-missing. No far-slot convention protects termination; its actual
state and the generic request kind do. Positive registered/convicted/booked/folded
traces must accompany these refusals. -/
theorem leaf_change_requires_fold (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s'))
    (aid : Nat) (changed : Singular.trieGet s'.trie aid ≠ Singular.trieGet s.trie aid) :
    ∃ gen plugin u tx, action = .fold gen plugin u tx := by
  apply Classical.byContradiction
  intro hn
  have nofold : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx := by
    intro gen plugin u tx equal
    exact hn ⟨gen, plugin, u, tx, equal⟩
  exact changed (congrArg (fun trie => Singular.trieGet trie aid) (nonfold_frame p env hs nofold).2.2)

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem fold_empty_refused (p : Params) (env : Env) (s : Sys) (gen plugin : Nat)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (he : Singular.foldMembers s.toWorld tx = []) :
    (fold p env s gen plugin u tx).toOption = none := by
  cases success : fold p env s gen plugin u tx with
  | error message => rfl
  | ok result =>
    rcases result with ⟨f, after⟩
    have accepted := (fold_sound p env success).2.2.2.1
    obtain ⟨_, result, batch, _, _⟩ := Singular.foldAccepted_checks accepted
    have nonempty := (Singular.foldBatch_inv _ _ _ batch).1
    simp [he] at nonempty

/-- Given actual successful recovery wrapper execution and all actual transaction
inputs; when reading the admitted request, signature/window and addressed
outputs; then retraction's recorded refund address receives at least the full
held request value, its required signer and full interval checks hold, donation
is zero, tags burn, ordinary funding covers fee and the ledger model balances.
Rejection refund floors sum the owed amounts per recorded address, rather
than trusting output labels or redirecting value to a processor. Its generic
judgment does not itself establish full transaction balance/fee funding, so
none is added to the second theorem. Actual generic outputs replace the old
synthetic exact Flow.refunds list; no named destination is silently discarded.
These inversion guarantees do not resurrect the old phase-only sufficient
premises, future-timestamp rejection or named-folder reward, and do not claim
operational application recovery/inclusion for #468. -/
theorem rejection_refund_destinations (s s' : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.Rejection) (f : Flow)
    (hs : genericRejection s u tx = .ok (f, s')) :
    ∀ address, Singular.refundOwed
      (Singular.rejectedRequests s.toWorld tx.members) false address ≤
      Singular.refundPaid tx.transaction address := by
  have accepted := (generic_rejection_sound s s' u tx f hs).1
  exact Singular.RefundProof.refund_floor (Singular.RefundProof.rejection_refunds accepted)

/-- Given a carrier edit preserving each original holding, its generic World
projection is exactly unchanged; application key and state stay local. -/
theorem carrier_edit_world (s : Sys) (edit : Carrier → Carrier)
    (same : ∀ c, (edit c).original = c.original) :
    ({ s with carriers := s.carriers.map edit } : Sys).toWorld = s.toWorld := by
  have originals : (s.carriers.map edit).map (·.original) = s.carriers.map (·.original) := by
    simp only [List.map_map]
    apply List.map_congr_left
    intro c _
    exact same c
  simp [Sys.toWorld, originals]

/-- Given any actual local action success, its generic World remains the
same. No generic token movement is attributed to these internal edits. -/
theorem local_actions_world (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow}
    (localAction : ∃ aid, action = .convictCkpt aid)
    (hs : stepFn p env action s = .ok (f, s')) : s'.toWorld = s.toWorld := by
  obtain ⟨aid, rfl⟩ := localAction
  · obtain ⟨c, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
    apply carrier_edit_world
    intro old
    split <;> rfl

/-- Each actual application transition transports generic reachability;
local transitions use equality of the complete projection. -/
theorem step_worldReachable (p : Params) (env : Env) {s s' : Sys}
    (hw : Singular.WorldReachable s.toWorld) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) : Singular.WorldReachable s'.toWorld := by
  cases action with
  | bookRegistration b => exact .booking hw b (bookRegistration_sound p hs).2.1
  | convictCkpt aid =>
    rw [local_actions_world p env ⟨aid, rfl⟩ hs]
    exact hw
  | bookTermination aid booker fee b =>
    obtain ⟨c, world, _, _, _, _, _, _, _, _, _, booked, _, projected, _⟩ :=
      (bookTermination_iff p s s' aid booker fee b f).mp hs
    rw [projected]
    exact .termination hw b booked
  | fold gen plugin u tx => exact .fold hw u tx (fold_sound p env hs).2.2.2.1
  | genericRetraction u tx => exact .retraction hw u tx (generic_retraction_sound s s' u tx f hs).1
  | genericRejection u tx => exact .rejection hw u tx (generic_rejection_sound s s' u tx f hs).1

/-- The actual initial/step history always projects to imported reachability.
This claim does not stand in for the additional application invariants. -/
theorem reachable_world (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (hr : Reach p env cfg s) : Singular.WorldReachable s.toWorld := by
  induction hr with
  | init => exact (wellFormed_initial p cfg).worldReachable
  | next _ hs ih => exact step_worldReachable p env ih hs

/-- Every actual history from this configuration preserves all its fields
except the root. The initial configuration remains the receipt's index. -/
theorem reachable_config (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (hr : Reach p env cfg s) :
    s.config = { cfg with root := s.config.root } := by
  induction hr with
  | init => rfl
  | @next before after action flow _ hs ih =>
    calc
      after.config = { before.config with root := after.config.root } :=
        (config_and_generation_frame p env hs).1
      _ = { cfg with root := after.config.root } := by rw [ih]

/-- Given the actual reachable canonical Sys and successful adapter execution;
when observing any accepted fold, including mixed members; then all eight
actual economic clauses hold with that Sys's own World, actual UTxO and tx.
This is the instantiation of `Samaritan.imported_fold_accounting`, not an unconstrained imported
World theorem. The conjunction must not be shortened to just donation or
mint. Registration carrier and addressed optional self-fold observations
remain their separately named clauses and premises. -/
theorem current_sys_fold_accounting (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) {gen plugin : Nat}
    {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s')) :
    Singular.balanced u.ledger tx.transaction = true ∧
    Singular.foldStateLovelace (Singular.economicSpent u tx) =
      Singular.foldStateLovelace tx.outputs ∧
    tx.transaction.donation =
      (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).donation ∧
    Singular.foldCarrierLovelace tx.outputs =
      (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).carriers ∧
    Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee =
      Singular.foldOrdinaryLovelace (Singular.economicSpent u tx) +
        (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).tips ∧
    tx.transaction.fee ≤ Singular.foldOrdinaryLovelace (Singular.economicSpent u tx) ∧
    s'.treasury = s.treasury + tx.transaction.donation ∧
    Singular.requestTagsBurned u tx = true := by
  exact Singular.Statements.fold_routes_every_amount s.toWorld s'.toWorld
    (reachable_world p env cfg hr) u tx (fold_sound p env hs).2.2.2.1

/-- Given actual successful recovery wrapper execution and all actual transaction
inputs; when reading the admitted request, signature/window and addressed
outputs; then retraction's recorded refund address receives at least the full
held request value, its required signer and full interval checks hold, donation
is zero, tags burn, ordinary funding covers fee and the ledger model balances.
Rejection refund floors sum the owed amounts per recorded address, rather
than trusting output labels or redirecting value to a processor. Its generic
judgment does not itself establish full transaction balance/fee funding, so
none is added to the second theorem. Actual generic outputs replace the old
synthetic exact Flow.refunds list; no named destination is silently discarded.
These inversion guarantees do not resurrect the old phase-only sufficient
premises, future-timestamp rejection or named-folder reward, and do not claim
operational application recovery/inclusion for #468. -/
theorem retraction_refund_and_guards (s s' : Sys) (u : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction) (f : Flow)
    (hs : genericRetraction s u tx = .ok (f, s')) :
    ∃ request : Singular.RegistrationRequest, ∃ interval : Singular.Interval,
      Singular.retractionRequest s.toWorld tx = .ok request ∧
      tx.transaction.signers.contains request.refundAddress = true ∧
      tx.transaction.validity = some interval ∧ interval.valid ∧
      request.submittedAt + s.config.processTime ≤ interval.lower ∧
      interval.upper ≤ request.submittedAt + s.config.processTime + s.config.retractTime ∧
      request.contents.lovelace ≤ Singular.refundPaid tx request.refundAddress ∧
      tx.transaction.donation = 0 ∧ Singular.requestTagsBurned u tx = true ∧
      tx.transaction.fee ≤ Singular.retractionFundingLovelace u tx request ∧
      Singular.balanced u.ledger tx.transaction = true := by
  have accepted := (generic_retraction_sound s s' u tx f hs).1
  obtain ⟨_, _, request, found, signed, ⟨interval, valid, bounds, lower, upper⟩, tags, _, refunds⟩ :=
    Singular.RefundProof.retraction_checks accepted
  obtain ⟨request', found', _, donation, fee, balanced, _⟩ :=
    Singular.retraction_funding_checks accepted
  have same : request' = request := by rw [found] at found'; exact (Except.ok.inj found').symm
  subst request'
  have refund := Singular.RefundProof.refund_floor refunds request.refundAddress
  refine ⟨request, interval, found, signed, valid, bounds, lower, upper, ?_,
    donation, tags, fee, balanced⟩
  simpa [Singular.refundOwed, Singular.refundAmount] using refund
/-- Given actual imported registration booking success, or an actual selected
registration in a successful adapter fold; when observing the request and
real economic output; then the entire declared carrier budget and exact
unique tagged destination output follow, with unchanged opaque datum and no
hidden tags/assets. This proves neither a Cardano minimum nor the full changing
serialized Checkpoint datum. `Examples.registration_folded` supplies the connected registration witness. `RegistryBoundaryDriver` executes complete delivery controls. -/
theorem registration_posted_value (p : Params) {s s' : Sys}
    {b : Singular.RegistrationBooking} {f : Flow}
    (hs : bookRegistration p s b = .ok (f, s')) :
    p.Mc + p.D ≤ b.request.carrierAda ∧ b.request.declaredTip = p.tip ∧
    b.request.contents.lovelace = b.request.registrationCost + p.tip + b.request.carrierAda ∧
    f = { deposited := b.request.contents.lovelace } := by
  obtain ⟨⟨carrier, tip⟩, booked, _, flow⟩ := bookRegistration_sound p hs
  have admitted : Singular.registrationBookingRefusal s.config b = none := by
    unfold Singular.book at booked
    split at booked
    · contradiction
    · assumption
  unfold Singular.registrationBookingRefusal at admitted
  dsimp only at admitted
  split at admitted
  · contradiction
  · rename_i lower
    split at admitted
    · contradiction
    · rename_i upper
      have low : Singular.registrationContentsShape s.config b.request = true ∧
          Singular.registrationDeclaredLovelace b.request ≤ b.request.contents.lovelace := by
        simpa using lower
      have high : b.request.contents.lovelace ≤ Singular.registrationDeclaredLovelace b.request := by
        simpa using upper
      refine ⟨carrier, tip, ?_, flow⟩
      simpa [Singular.registrationDeclaredLovelace, tip] using Nat.le_antisymm high low.2

/-- Given actual imported registration booking success, or an actual selected
registration in a successful adapter fold; when observing the request and
real economic output; then the entire declared carrier budget and exact
unique tagged destination output follow, with unchanged opaque datum and no
hidden tags/assets. This proves neither a Cardano minimum nor the full changing
serialized Checkpoint datum. `Examples.registration_folded` supplies the connected registration witness. `RegistryBoundaryDriver` executes complete delivery controls. -/
theorem registration_delivery (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s'))
    (b : Singular.RegistrationBooking)
    (selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx) :
    ∃ output : Singular.EconomicOutput,
      tx.outputs.filter (fun o => o.singularTags.contains (s.config.singularTag b.request.key)) = [output] ∧
      output.output.address = some b.request.destination ∧
      output.output.datumValue = b.request.datum ∧
      output.output.datum = Singular.datumFormOf b.request.datum ∧
      output.output.lovelace = b.request.carrierAda ∧
      output.singularTags = [s.config.singularTag b.request.key] ∧
      output.output.stateTokens = 0 ∧ output.request = none ∧
      output.contents.trieReadyTags = [] ∧ output.contents.applicationTags = [] ∧
      Singular.foldBareValue output = true := by
  obtain ⟨_, result, _, routing, _⟩ := Singular.foldAccepted_checks (fold_sound p env hs).2.2.2.1
  have checked := (Singular.foldRouting_partitions routing).2.1 (.registration b) selected
  unfold Singular.foldCarrierRefusal at checked
  simp only [bind, pure, Option.bind] at checked
  repeat (split at checked <;> try contradiction)
  all_goals simp_all [Sys.toWorld] <;> grind

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
theorem booking_keeps_prior_pending (p : Params) {s s' : Sys}
    {aid booker fee : Nat} {b : Singular.TerminationBooking} {f : Flow}
    (hs : bookTermination p s aid booker fee b = .ok (f, s'))
    {ref : Singular.OutRef} {e : TerminationEntry}
    (hp : pendingAt s ref = some e) :
    ref ≠ b.request.reference ∧ pendingAt s' ref = some e ∧
    s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧
    s'.registrations = s.registrations ∧ s'.treasury = s.treasury ∧
    s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken := by
  obtain ⟨c, world, _, _, _, _, _, _, _, _, _, booked, successor, _, _⟩ :=
    (bookTermination_iff p s s' aid booker fee b f).mp hs
  have old := pending_lookup_mem s ref e hp
  have different : ref ≠ b.request.reference := by
    intro same
    have duplicate : s.toWorld.terminations.any
        (fun pending => decide (pending.request.reference = b.request.reference)) = true := by
      apply List.any_eq_true.mpr
      exact ⟨e.booking, List.mem_map.mpr ⟨e, old.1, rfl⟩, by simp [old.2, same]⟩
    unfold Singular.bookTermination at booked
    split at booked
    · contradiction
    · simp [duplicate] at booked
  subst s'
  refine ⟨different, ?_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  simpa [pendingAt, Ne.symm different] using hp

/-- An admitted imported step cannot erase an already registered key. This
helper retains the arbitrary-state domain of the adapter's leaf contract. -/
theorem generic_step_registered (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (aid : Nat)
    (hk : Singular.trieGet s.trie aid = .known .active ∨
      Singular.trieGet s.trie aid = .known .terminal)
    (hs : Singular.step s a = .ok t) :
    Singular.trieGet t.state.trie aid = .known .active ∨
      Singular.trieGet t.state.trie aid = .known .terminal := by
  obtain ⟨admitted, rfl⟩ := Singular.step_eq_ok s a t hs
  obtain ⟨_, _, _, _, branch⟩ := (Singular.refusal_none_iff s a).mp admitted
  rcases branch with ⟨edge, _⟩ | ⟨edge, _, _⟩
  · rw [(Singular.applyEdge_insertActive s a edge).1]
    by_cases same : aid = a.key
    · simp [same]
    · rw [Singular.trieGet_set_of_ne _ _ _ _ same]; exact hk
  · rw [(Singular.applyEdge_updateTerminal s a edge).1]
    by_cases same : aid = a.key
    · simp [same]
    · rw [Singular.trieGet_set_of_ne _ _ _ _ same]; exact hk

/-- The imported sequential fold inherits permanent registration one actual
step at a time, including batches mixing both supported operations. -/
theorem generic_foldActions_registered (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result) (aid : Nat)
    (hk : Singular.trieGet s.trie aid = .known .active ∨
      Singular.trieGet s.trie aid = .known .terminal)
    (hs : Singular.foldActions s batch = .ok t) :
    Singular.trieGet t.state.trie aid = .known .active ∨
      Singular.trieGet t.state.trie aid = .known .terminal := by
  induction batch generalizing s t with
  | nil =>
    simp only [Singular.foldActions, Except.ok.injEq] at hs
    subst t
    exact hk
  | cons action rest ih =>
    unfold Singular.foldActions at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i middle first
      split at hs
      · contradiction
      · rename_i last remaining
        cases hs
        exact ih middle.state last (generic_step_registered s action middle aid hk first) remaining

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem registered_key_permanent (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s')) (aid : Nat)
    (hk : Singular.trieGet s.trie aid = .known .active ∨
          Singular.trieGet s.trie aid = .known .terminal) :
    Singular.trieGet s'.trie aid = .known .active ∨
    Singular.trieGet s'.trie aid = .known .terminal := by
  by_cases hf : ∃ gen plugin u tx, action = .fold gen plugin u tx
  · obtain ⟨gen, plugin, u, tx, rfl⟩ := hf
    obtain ⟨result, accepted, effect⟩ := Singular.economic_fold_registry_correspondence
      (fold_sound p env hs).2.2.2.1
    have permanent := generic_foldActions_registered _ _ result aid hk
      (Singular.foldBatch_inv _ _ _ accepted).2
    have trie := congrArg Singular.RegistryState.trie effect
    change s'.trie = result.state.trie at trie
    rw [trie]
    exact permanent
  · have hn : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx := by
      intro gen plugin u tx same
      exact hf ⟨gen, plugin, u, tx, same⟩
    rw [(nonfold_frame p env hs hn).2.2]
    exact hk

/-- Given arbitrary inputs for the inversions/refusals/frame and leaf laws, with
only the actual success or exact guard premises stated; when invoking the
actual adapter; then both directions of its complete fold definition hold,
stale generation/wrong plugin/empty actual members refuse, generations cannot
be reused, every config field other than root is fixed, nonfolds preserve
whole registry/gen, registered keys stay registered and terminal keys stay
terminal. The last two preserve the original arbitrary-Sys domain rather than
adding Reach merely for proof convenience. Stronger no-carrier/no-pending
custody consequences appropriately require reachable-state consistency.
`RegistryJourneyChecks` executes accepted generations and stale-generation/plugin controls. -/
theorem terminal_leaf_permanent (p : Params) (env : Env) {s s' : Sys}
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s')) (aid : Nat)
    (hk : Singular.trieGet s.trie aid = .known .terminal) :
    Singular.trieGet s'.trie aid = .known .terminal := by
  by_cases hf : ∃ gen plugin u tx, action = .fold gen plugin u tx
  · obtain ⟨gen, plugin, u, tx, rfl⟩ := hf
    obtain ⟨result, accepted, effect⟩ := Singular.economic_fold_registry_correspondence
      (fold_sound p env hs).2.2.2.1
    have permanent := Singular.foldActions_preserves_terminal _ _ result aid hk
      (Singular.foldBatch_inv _ _ _ accepted).2
    have trie := congrArg Singular.RegistryState.trie effect
    change s'.trie = result.state.trie at trie
    rw [trie]
    exact permanent
  · have hn : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx := by
      intro gen plugin u tx same
      exact hf ⟨gen, plugin, u, tx, same⟩
    rw [(nonfold_frame p env hs hn).2.2]
    exact hk
/-- Given an actual selected registration for an already active/terminal key, or
an actual pending termination in a reachable canonical Sys; when the supplied
actual transaction attempts registration/retraction/rejection as specified;
then the adapter refuses. Known-key refusal preserves the arbitrary-input
scope of the old registration refusal. Termination recovery refusal uses the
actual admitted request kind and current reachable custody, not now<far or
synthetic go-request timestamps. These are current source-bound generic
protection clauses; they do not establish all application recovery guarantees
in #468. A valid unrelated registration recovery and actual proper terminating
fold are required positive companions. -/
theorem termination_retraction_refused (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (_hr : Reach p env cfg s) (ref : Singular.OutRef) (e : TerminationEntry)
    (hp : pendingAt s ref = some e) (u : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction)
    (spent : Singular.inputsContainReference tx.transaction.inputs ref = true) :
    (genericRetraction s u tx).toOption = none := by
  cases success : genericRetraction s u tx with
  | error message => rfl
  | ok result =>
    obtain ⟨flow, after⟩ := result
    have accepted := (generic_retraction_sound s after u tx flow success).1
    obtain ⟨_, _, request, found, _⟩ := Singular.RefundProof.retraction_checks accepted
    have old := pending_lookup_mem s ref e hp
    have selected : s.toWorld.terminations.any (fun b =>
        Singular.inputsContainReference tx.transaction.inputs b.request.reference) = true := by
      apply List.any_eq_true.mpr
      exact ⟨e.booking, List.mem_map.mpr ⟨e, old.1, rfl⟩, by simpa [old.2] using spent⟩
    simp [Singular.retractionRequest, selected, bind, Except.bind] at found

/-- Given an actual selected registration for an already active/terminal key, or
an actual pending termination in a reachable canonical Sys; when the supplied
actual transaction attempts registration/retraction/rejection as specified;
then the adapter refuses. Known-key refusal preserves the arbitrary-input
scope of the old registration refusal. Termination recovery refusal uses the
actual admitted request kind and current reachable custody, not now<far or
synthetic go-request timestamps. These are current source-bound generic
protection clauses; they do not establish all application recovery guarantees
in #468. A valid unrelated registration recovery and actual proper terminating
fold are required positive companions. -/
theorem termination_rejection_refused (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (_hr : Reach p env cfg s) (ref : Singular.OutRef) (e : TerminationEntry)
    (hp : pendingAt s ref = some e) (u : Singular.EconomicUtxo)
    (tx : Singular.Rejection) (reason : Singular.RejectReason)
    (member : (ref, reason) ∈ tx.members) :
    (genericRejection s u tx).toOption = none := by
  cases success : genericRejection s u tx with
  | error message => rfl
  | ok result =>
    obtain ⟨flow, after⟩ := result
    have accepted := (generic_rejection_sound s after u tx flow success).1
    have checks := Singular.rejectionAccepted_checks accepted
    obtain ⟨interval, _, _, _, _, members, _⟩ := checks.2.2.2
    have checked := members (ref, reason) member
    have observed := (Singular.rejectionObservation_world checks.2.2.1).1
    have old := pending_lookup_mem s ref e hp
    unfold Singular.rejectionMemberRefusal at checked
    cases lookup : s.toWorld.pending.find? (fun b => b.request.reference == ref) with
    | none =>
      simp only [lookup] at checked
      repeat (split at checked <;> try contradiction)
    | some b =>
      have actualRef : b.request.reference = ref := by simpa using List.find?_some lookup
      have views := Bool.and_eq_true_iff.mp observed
      have registration := List.all_eq_true.mp views.1 b (List.mem_of_find?_eq_some lookup)
      have termination := List.all_eq_true.mp views.2 e.booking (List.mem_map.mpr ⟨e, old.1, rfl⟩)
      exact False.elim (Singular.observed_request_kinds_disjoint registration termination
        (actualRef.trans old.2.symm))

/-- An admitted imported insertion can only start at an unknown leaf. -/
theorem generic_insert_unknown (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (hs : Singular.step s a = .ok t)
    (edge : a.edge = .insertActive) : Singular.trieGet s.trie a.key = .unknown := by
  obtain ⟨admitted, _⟩ := Singular.step_eq_ok s a t hs
  obtain ⟨_, _, _, _, branch⟩ := (Singular.refusal_none_iff s a).mp admitted
  rcases branch with ⟨_, unknown⟩ | ⟨other, _, _⟩
  · exact unknown
  · rw [edge] at other; contradiction

/-- Any selected insertion of an already registered key contradicts an
admitted imported batch, even if other members run before that insertion. -/
theorem generic_fold_registered_insert_impossible (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result) (request : Singular.Action)
    (member : request ∈ batch) (edge : request.edge = .insertActive)
    (known : Singular.trieGet s.trie request.key = .known .active ∨
      Singular.trieGet s.trie request.key = .known .terminal)
    (hs : Singular.foldActions s batch = .ok t) : False := by
  induction batch generalizing s t with
  | nil => simp at member
  | cons action rest ih =>
    unfold Singular.foldActions at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i middle first
      split at hs
      · contradiction
      · rename_i last remaining
        rcases List.mem_cons.mp member with same | later
        · subst action
          have unknown := generic_insert_unknown s request middle first edge
          rcases known with active | terminal <;> rw [unknown] at * <;> contradiction
        · exact ih middle.state last later
            (generic_step_registered s action middle request.key known first) remaining

/-- Given an actual selected registration for an already active/terminal key, or
an actual pending termination in a reachable canonical Sys; when the supplied
actual transaction attempts registration/retraction/rejection as specified;
then the adapter refuses. Known-key refusal preserves the arbitrary-input
scope of the old registration refusal. Termination recovery refusal uses the
actual admitted request kind and current reachable custody, not now<far or
synthetic go-request timestamps. These are current source-bound generic
protection clauses; they do not establish all application recovery guarantees
in #468. A valid unrelated registration recovery and actual proper terminating
fold are required positive companions. -/
theorem registered_registration_refused (p : Params) (env : Env) (s : Sys)
    (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (b : Singular.RegistrationBooking)
    (selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx)
    (known : Singular.trieGet s.trie b.request.key = .known .active ∨
      Singular.trieGet s.trie b.request.key = .known .terminal) :
    (fold p env s gen plugin u tx).toOption = none := by
  cases success : fold p env s gen plugin u tx with
  | error message => rfl
  | ok result =>
    obtain ⟨flow, after⟩ := result
    obtain ⟨_, generic, batch, _, _⟩ := Singular.foldAccepted_checks
      (fold_sound p env success).2.2.2.1
    exact False.elim (generic_fold_registered_insert_impossible _ _ generic
      (Singular.foldLegacyRequest s.config (.registration b))
      (List.mem_map.mpr ⟨.registration b, selected, rfl⟩) rfl known
      (Singular.foldBatch_inv _ _ _ batch).2)

end CardanoKeri.Registry
