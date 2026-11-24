import CardanoKeri.ReaderStatus
import CardanoKeri.ConsumerGoals
import CardanoKeri.CheckpointLifecycleExamples
import SingularApplicationHeld.HistoryClaims

/-! The guarantees of the reader's status model (#353). Each theorem states
its Given/When/Then contract in its comment. -/
namespace CardanoKeri.ReaderStatus
open CardanoKeri.Checkpoint CardanoKeri.ConsumerIdentity

/-! ## The replay -/

/-- Given a change and the members it is applied to; when the replay applies
it; then a registration succeeds exactly when its key is unknown and binds it
active, and a termination exactly when its key is active and makes it
terminal. -/
theorem applyChange_exact (members next : Singular.Trie) (change : KeyChange) :
    applyChange members change = some next ↔
      match change with
      | .register key => Singular.trieGet members key = .unknown ∧
          next = Singular.trieSet members key (.known .active)
      | .terminate key => Singular.trieGet members key = .known .active ∧
          next = Singular.trieSet members key (.known .terminal) := by
  cases change with
  | register key =>
    by_cases unknown : Singular.trieGet members key = .unknown
    · simp [applyChange, unknown, eq_comm]
    · simp [applyChange, unknown]
  | terminate key =>
    by_cases active : Singular.trieGet members key = .known .active
    · simp [applyChange, active, eq_comm]
    · simp [applyChange, active]

/-- Given a change the replay applies; when another key is read afterwards;
then its leaf is unchanged. -/
theorem applyChange_frame (members next : Singular.Trie) (change : KeyChange)
    (key : Singular.Key) (applied : applyChange members change = some next)
    (other : change.key ≠ key) :
    Singular.trieGet next key = Singular.trieGet members key := by
  cases change with
  | register changeKey =>
    obtain ⟨_, rfl⟩ := (applyChange_exact members next _).mp applied
    exact Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm other)
  | terminate changeKey =>
    obtain ⟨_, rfl⟩ := (applyChange_exact members next _).mp applied
    exact Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm other)

/-- Given a list of changes the replay applies in order and a key.
When the key's leaf is read afterwards.
Then it is unknown exactly when it was unknown before and no change names the
key, and terminal exactly when it was terminal before or some change is a
termination of the key. -/
theorem changes_leaf (changes : List KeyChange) (members next : Singular.Trie)
    (key : Singular.Key) (applied : changes.foldlM applyChange members = some next) :
    (Singular.trieGet next key = .unknown ↔
      Singular.trieGet members key = .unknown ∧ ∀ change ∈ changes, change.key ≠ key) ∧
    (Singular.trieGet next key = .known .terminal ↔
      Singular.trieGet members key = .known .terminal ∨ KeyChange.terminate key ∈ changes) := by
  induction changes generalizing members with
  | nil =>
    simp only [List.foldlM_nil, Option.pure_def, Option.some.injEq] at applied
    subst applied
    simp
  | cons change rest ih =>
    simp only [List.foldlM_cons, Option.bind_eq_bind] at applied
    cases first : applyChange members change with
    | none => simp [first] at applied
    | some middle =>
      simp only [first, Option.bind_some] at applied
      obtain ⟨unknownIff, terminalIff⟩ := ih middle applied
      by_cases same : change.key = key
      · cases change with
        | register changeKey =>
          simp only [KeyChange.key] at same
          subst same
          obtain ⟨law, target⟩ := (applyChange_exact members middle _).mp first
          have read : Singular.trieGet middle changeKey = .known .active := by
            rw [target]; exact Singular.trieGet_set_eq _ _ _
          constructor
          · rw [unknownIff, read]
            simp [KeyChange.key]
          · rw [terminalIff, read, law]
            simp
        | terminate changeKey =>
          simp only [KeyChange.key] at same
          subst same
          obtain ⟨law, target⟩ := (applyChange_exact members middle _).mp first
          have read : Singular.trieGet middle changeKey = .known .terminal := by
            rw [target]; exact Singular.trieGet_set_eq _ _ _
          constructor
          · rw [unknownIff, read]
            simp [KeyChange.key]
          · rw [terminalIff, read, law]
            exact ⟨fun _ => Or.inr List.mem_cons_self, fun _ => Or.inl rfl⟩
      · have frame := applyChange_frame members middle change key first same
        constructor
        · rw [unknownIff, frame]
          simp [same]
        · rw [terminalIff, frame]
          have notHere : KeyChange.terminate key ≠ change := by
            rintro rfl
            exact same rfl
          constructor
          · rintro (terminal | member)
            · exact Or.inl terminal
            · exact Or.inr (List.mem_cons_of_mem _ member)
          · rintro (terminal | member)
            · exact Or.inl terminal
            · rcases List.mem_cons.mp member with here | later
              · exact (notHere here).elim
              · exact Or.inr later

/-- **Replaying folds is replaying their changes end to end, when no fold is
empty.**
Given folds, the members before them and members.
When the replay from those members is compared with applying every change of
every fold in order.
Then the replay gives the members exactly when no fold is without a change
and the changes, end to end, give them. -/
theorem replayFrom_iff (folds : List (List KeyChange)) (start members : Singular.Trie) :
    replayFrom start folds = some members ↔
      (∀ changes ∈ folds, changes ≠ []) ∧
      folds.flatten.foldlM applyChange start = some members := by
  unfold replayFrom
  induction folds generalizing start with
  | nil => simp
  | cons changes rest ih =>
    simp only [List.foldlM_cons, Option.bind_eq_bind, List.flatten_cons, List.foldlM_append,
      List.mem_cons, forall_eq_or_imp]
    by_cases empty : changes = []
    · subst empty
      simp [applyFold]
    · have fold : applyFold start changes = changes.foldlM applyChange start := by
        simp [applyFold, empty]
      rw [fold]
      cases first : changes.foldlM applyChange start with
      | none => simp
      | some middle => simp [ih middle, empty]

/-- **Never registered means no change of the key; terminal means its
termination.**
Given a history the replay accepts from the registry's creation, and a key.
When the key's leaf is read in the replayed members.
Then it is unknown exactly when no change of any fold names the key, and
terminal exactly when some fold terminates the key. -/
theorem replayed_leaf (folds : List (List KeyChange)) (members : Singular.Trie)
    (key : Singular.Key) (replayed : replay folds = some members) :
    (Singular.trieGet members key = .unknown ↔ ∀ change ∈ folds.flatten, change.key ≠ key) ∧
    (Singular.trieGet members key = .known .terminal ↔
      KeyChange.terminate key ∈ folds.flatten) := by
  have leaves := changes_leaf folds.flatten [] members key
    ((replayFrom_iff folds [] members).mp replayed).2
  have empty : Singular.trieGet ([] : Singular.Trie) key = .unknown := rfl
  simpa [empty] using leaves

/-- Whether a change is a registration. -/
def KeyChange.registers : KeyChange → Bool
  | .register _ => true
  | .terminate _ => false

/-- The changes a list makes to one key, in order: `true` for a registration,
`false` for a termination. -/
def kindsOf (key : Singular.Key) (changes : List KeyChange) : List Bool :=
  (changes.filter fun change => decide (change.key = key)).map KeyChange.registers

/-- A sequence of changes to one key is possible from a leaf: a registration
from unknown, then a termination from active, and nothing after. -/
def validFrom : Singular.Leaf → List Bool → Bool
  | _, [] => true
  | .unknown, true :: rest => validFrom (.known .active) rest
  | .known .active, false :: rest => validFrom (.known .terminal) rest
  | _, _ => false

/-- The leaf a sequence of changes to one key leaves. -/
def leafAfter : Singular.Leaf → List Bool → Singular.Leaf
  | leaf, [] => leaf
  | _, true :: rest => leafAfter (.known .active) rest
  | _, false :: rest => leafAfter (.known .terminal) rest

/-- The leaf a sequence of changes to one key presupposes before it: active
when it starts with a termination, unknown otherwise. -/
def startOf : List Bool → Singular.Leaf
  | false :: _ => .known .active
  | _ => .unknown

/-- The sequences of changes one key can go through in any history: none, a
registration, a termination, or a registration then a termination. -/
def Shape (kinds : List Bool) : Prop :=
  kinds = [] ∨ kinds = [true] ∨ kinds = [false] ∨ kinds = [true, false]

/-- Given a change and a key; when the changes to that key are listed; then
the change is first among them if it names the key, and absent otherwise. -/
theorem kindsOf_cons (key : Singular.Key) (change : KeyChange) (rest : List KeyChange) :
    kindsOf key (change :: rest) =
      if change.key = key then change.registers :: kindsOf key rest else kindsOf key rest := by
  by_cases same : change.key = key <;> simp [kindsOf, same]

/-- Given changes the replay applies in order from some members, and a key.
When the changes to that key are read.
Then they are a possible sequence from the key's leaf before, and the key's
leaf after is the one that sequence leaves. -/
theorem changes_follow_kinds (changes : List KeyChange) (members next : Singular.Trie)
    (key : Singular.Key) (applied : changes.foldlM applyChange members = some next) :
    validFrom (Singular.trieGet members key) (kindsOf key changes) = true ∧
    Singular.trieGet next key = leafAfter (Singular.trieGet members key) (kindsOf key changes) := by
  induction changes generalizing members with
  | nil =>
    simp only [List.foldlM_nil, Option.pure_def, Option.some.injEq] at applied
    subst applied
    simp [kindsOf, validFrom, leafAfter]
  | cons change rest ih =>
    simp only [List.foldlM_cons, Option.bind_eq_bind] at applied
    cases first : applyChange members change with
    | none => simp [first] at applied
    | some middle =>
      simp only [first, Option.bind_some] at applied
      obtain ⟨valid, final⟩ := ih middle applied
      rw [kindsOf_cons]
      by_cases same : change.key = key
      · rw [if_pos same]
        cases change with
        | register changeKey =>
          simp only [KeyChange.key] at same
          subst same
          obtain ⟨law, target⟩ := (applyChange_exact members middle _).mp first
          have read : Singular.trieGet middle changeKey = .known .active := by
            rw [target]; exact Singular.trieGet_set_eq _ _ _
          rw [read] at valid final
          rw [law]
          exact ⟨by simpa [KeyChange.registers, validFrom] using valid,
            by simpa [KeyChange.registers, leafAfter] using final⟩
        | terminate changeKey =>
          simp only [KeyChange.key] at same
          subst same
          obtain ⟨law, target⟩ := (applyChange_exact members middle _).mp first
          have read : Singular.trieGet middle changeKey = .known .terminal := by
            rw [target]; exact Singular.trieGet_set_eq _ _ _
          rw [read] at valid final
          rw [law]
          exact ⟨by simpa [KeyChange.registers, validFrom] using valid,
            by simpa [KeyChange.registers, leafAfter] using final⟩
      · rw [if_neg same, ← applyChange_frame members middle change key first same]
        exact ⟨valid, final⟩

/-- Given changes and members such that, for every key, the changes to that
key are a possible sequence from its leaf; when the replay applies the changes
in order; then it succeeds. -/
theorem changes_replay_of_valid (changes : List KeyChange) (members : Singular.Trie)
    (valid : ∀ key, validFrom (Singular.trieGet members key) (kindsOf key changes) = true) :
    ∃ next, changes.foldlM applyChange members = some next := by
  induction changes generalizing members with
  | nil => exact ⟨members, rfl⟩
  | cons change rest ih =>
    have here := valid change.key
    rw [kindsOf_cons, if_pos rfl] at here
    cases change with
    | register key =>
      simp only [KeyChange.key, KeyChange.registers] at here
      have unknown : Singular.trieGet members key = .unknown := by
        cases leaf : Singular.trieGet members key with
        | unknown => rfl
        | known state => rw [leaf] at here; cases state <;> simp [validFrom] at here
      have first : applyChange members (.register key) =
          some (Singular.trieSet members key (.known .active)) := by
        simp [applyChange, unknown]
      have later : ∀ k, validFrom
          (Singular.trieGet (Singular.trieSet members key (.known .active)) k)
          (kindsOf k rest) = true := by
        intro k
        by_cases same : key = k
        · subst same
          rw [Singular.trieGet_set_eq]
          rw [unknown] at here
          simpa [validFrom] using here
        · have other := valid k
          rw [kindsOf_cons, if_neg (by simpa [KeyChange.key] using same)] at other
          rw [Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm same)]
          exact other
      obtain ⟨next, applied⟩ := ih _ later
      exact ⟨next, by simp [List.foldlM_cons, first, applied]⟩
    | terminate key =>
      simp only [KeyChange.key, KeyChange.registers] at here
      have active : Singular.trieGet members key = .known .active := by
        cases leaf : Singular.trieGet members key with
        | unknown => rw [leaf] at here; simp [validFrom] at here
        | known state => rw [leaf] at here; cases state <;> simp [validFrom] at here ⊢
      have first : applyChange members (.terminate key) =
          some (Singular.trieSet members key (.known .terminal)) := by
        simp [applyChange, active]
      have later : ∀ k, validFrom
          (Singular.trieGet (Singular.trieSet members key (.known .terminal)) k)
          (kindsOf k rest) = true := by
        intro k
        by_cases same : key = k
        · subst same
          rw [Singular.trieGet_set_eq]
          rw [active] at here
          simpa [validFrom] using here
        · have other := valid k
          rw [kindsOf_cons, if_neg (by simpa [KeyChange.key] using same)] at other
          rw [Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm same)]
          exact other
      obtain ⟨next, applied⟩ := ih _ later
      exact ⟨next, by simp [List.foldlM_cons, first, applied]⟩

/-- Given changes and a key; when the members the changes presuppose are read
at the key; then the leaf is the one the changes to that key presuppose:
active when the first is a termination, unknown otherwise. -/
theorem presupposed_reads (changes : List KeyChange) (key : Singular.Key) :
    Singular.trieGet (presupposed changes) key = startOf (kindsOf key changes) := by
  induction changes with
  | nil => rfl
  | cons change rest ih =>
    rw [kindsOf_cons]
    cases change with
    | register changeKey =>
      by_cases same : changeKey = key
      · subst same
        simp [presupposed, KeyChange.key, KeyChange.registers, startOf]
      · rw [if_neg (by simpa [KeyChange.key] using same), ← ih]
        exact Singular.trieGet_erase_of_ne _ _ _ (Ne.symm same)
    | terminate changeKey =>
      by_cases same : changeKey = key
      · subst same
        simp [presupposed, KeyChange.key, KeyChange.registers, startOf]
      · rw [if_neg (by simpa [KeyChange.key] using same), ← ih]
        exact Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm same)

/-- Given a sequence of changes to one key that is possible from some leaf;
when its shape is read; then it is none, a registration, a termination, or a
registration then a termination. -/
theorem shape_of_valid (leaf : Singular.Leaf) (kinds : List Bool)
    (valid : validFrom leaf kinds = true) : Shape kinds := by
  rcases kinds with _ | ⟨first, _ | ⟨second, _ | ⟨third, rest⟩⟩⟩
  · exact Or.inl rfl
  · cases first
    · exact Or.inr (Or.inr (Or.inl rfl))
    · exact Or.inr (Or.inl rfl)
  · rcases leaf with _ | ⟨_ | _ | _⟩ <;> cases first <;> cases second <;>
      simp [validFrom, Shape] at valid ⊢
  · rcases leaf with _ | ⟨_ | _ | _⟩ <;> cases first <;> cases second <;> cases third <;>
      simp [validFrom] at valid

/-- Given a sequence of changes to one key of one of the four shapes; when it
is read from the leaf it presupposes; then it is possible. -/
theorem shape_valid (kinds : List Bool) (shape : Shape kinds) :
    validFrom (startOf kinds) kinds = true := by
  rcases shape with rfl | rfl | rfl | rfl <;> rfl

/-- Given a list of lists and some of them, in order; when both are laid end
to end; then the part is some of the whole, in order. -/
theorem flatten_sublist {α : Type} {part whole : List (List α)} (sub : part.Sublist whole) :
    part.flatten.Sublist whole.flatten := by
  induction sub with
  | slnil => exact .slnil
  | cons a _ ih =>
    rw [List.flatten_cons]
    exact ih.trans (List.sublist_append_right _ _)
  | cons₂ a _ ih =>
    rw [List.flatten_cons, List.flatten_cons]
    exact List.Sublist.append_left ih a

/-- Given some of the elements of a one-element list, in order; when they are
read; then they are none or that element. -/
theorem sublist_single {α : Type} (b : α) (s : List α) (sub : s.Sublist [b]) :
    s = [] ∨ s = [b] := by
  cases sub with
  | cons _ inner => exact Or.inl (List.sublist_nil.mp inner)
  | cons₂ _ inner => exact Or.inr (by rw [List.sublist_nil.mp inner])

/-- Given a sequence of one of the four shapes and a part of it, in order;
when the part's shape is read; then it is one of the four shapes too. -/
theorem shape_sublist (kinds part : List Bool) (shape : Shape kinds)
    (sublist : part.Sublist kinds) : Shape part := by
  have single := @sublist_single Bool
  rcases shape with rfl | rfl | rfl | rfl
  · exact Or.inl (List.sublist_nil.mp sublist)
  · rcases single _ _ sublist with rfl | rfl
    · exact Or.inl rfl
    · exact Or.inr (Or.inl rfl)
  · rcases single _ _ sublist with rfl | rfl
    · exact Or.inl rfl
    · exact Or.inr (Or.inr (Or.inl rfl))
  · cases sublist with
    | cons _ inner =>
      rcases single _ _ inner with rfl | rfl
      · exact Or.inl rfl
      · exact Or.inr (Or.inr (Or.inl rfl))
    | cons₂ _ inner =>
      rcases single _ _ inner with rfl | rfl
      · exact Or.inr (Or.inl rfl)
      · exact Or.inr (Or.inr (Or.inr rfl))

/-- Given folds none of which is empty, whose changes to every key have one
of the four shapes, and whose changes to one key are none or one
registration.
When the folds are replayed from the members an incomplete history is checked
from.
Then the replay succeeds and leaves that key active. -/
theorem admission_start_replays (folds : List (List KeyChange)) (key : Singular.Key)
    (nonempty : ∀ changes ∈ folds, changes ≠ [])
    (shapes : ∀ k, Shape (kindsOf k folds.flatten))
    (registered : kindsOf key folds.flatten = [] ∨ kindsOf key folds.flatten = [true]) :
    ∃ members, replayFrom (admissionStart false key folds.flatten) folds = some members ∧
      Singular.trieGet members key = .known .active := by
  have named : (folds.flatten.any fun change => decide (change.key = key)) = true ↔
      kindsOf key folds.flatten ≠ [] := by
    simp [kindsOf, List.filter_eq_nil_iff]
  rcases registered with untouched | once
  · have start : admissionStart false key folds.flatten =
        Singular.trieSet (presupposed folds.flatten) key (.known .active) := by
      have unnamed : (folds.flatten.any fun change => decide (change.key = key)) = false :=
        Bool.eq_false_iff.mpr fun any => named.mp any untouched
      simp [admissionStart, unnamed]
    have valid : ∀ k, validFrom (Singular.trieGet (admissionStart false key folds.flatten) k)
        (kindsOf k folds.flatten) = true := by
      intro k
      rw [start]
      by_cases same : key = k
      · subst same
        rw [Singular.trieGet_set_eq, untouched]
        rfl
      · rw [Singular.trieGet_set_of_ne _ _ _ _ (Ne.symm same), presupposed_reads]
        exact shape_valid _ (shapes k)
    obtain ⟨members, flat⟩ := changes_replay_of_valid folds.flatten _ valid
    refine ⟨members, (replayFrom_iff folds _ members).mpr ⟨nonempty, flat⟩, ?_⟩
    rw [(changes_follow_kinds folds.flatten _ members key flat).2, start,
      Singular.trieGet_set_eq, untouched]
    rfl
  · have start : admissionStart false key folds.flatten = presupposed folds.flatten := by
      have isNamed : (folds.flatten.any fun change => decide (change.key = key)) = true :=
        named.mpr (by rw [once]; simp)
      simp [admissionStart, isNamed]
    have valid : ∀ k, validFrom (Singular.trieGet (admissionStart false key folds.flatten) k)
        (kindsOf k folds.flatten) = true := by
      intro k
      rw [start, presupposed_reads]
      exact shape_valid _ (shapes k)
    obtain ⟨members, flat⟩ := changes_replay_of_valid folds.flatten _ valid
    refine ⟨members, (replayFrom_iff folds _ members).mpr ⟨nonempty, flat⟩, ?_⟩
    rw [(changes_follow_kinds folds.flatten _ members key flat).2, start, presupposed_reads, once]
    rfl

/-- **What an incomplete history admits.**
Given the folds of an incomplete history and a key.
When the rule is read on the changes themselves.
Then the history admits the key active exactly when no fold is without a
change, the changes to every key are none, a registration, a termination, or
a registration then a termination, and the changes to the key itself are none
or one registration. -/
theorem incomplete_admits_active_iff (key : Singular.Key) (folds : List (List KeyChange)) :
    AdmitsActive false key folds ↔
      (∀ changes ∈ folds, changes ≠ []) ∧ (∀ k, Shape (kindsOf k folds.flatten)) ∧
      (kindsOf key folds.flatten = [] ∨ kindsOf key folds.flatten = [true]) := by
  constructor
  · rintro ⟨start, members, _, replayed, active⟩
    obtain ⟨nonempty, flat⟩ := (replayFrom_iff folds start members).mp replayed
    have follow := fun k => changes_follow_kinds folds.flatten start members k flat
    have shapes : ∀ k, Shape (kindsOf k folds.flatten) := fun k =>
      shape_of_valid _ _ (follow k).1
    refine ⟨nonempty, shapes, ?_⟩
    have final := (follow key).2
    rw [active] at final
    rcases shapes key with shape | shape | shape | shape
    · exact Or.inl shape
    · exact Or.inr shape
    · rw [shape] at final; simp [leafAfter] at final
    · rw [shape] at final; simp [leafAfter] at final
  · rintro ⟨nonempty, shapes, registered⟩
    obtain ⟨members, replayed, active⟩ :=
      admission_start_replays folds key nonempty shapes registered
    exact ⟨_, members, by simp, replayed, active⟩

/-- Given folds none of which is without a change and whose changes to every
key have one of the four shapes; when they are replayed from the members
their changes presuppose; then the replay succeeds. -/
theorem replays_of_shapes (folds : List (List KeyChange))
    (nonempty : ∀ changes ∈ folds, changes ≠ [])
    (shapes : ∀ k, Shape (kindsOf k folds.flatten)) :
    ∃ members, replayFrom (presupposed folds.flatten) folds = some members := by
  have valid : ∀ k, validFrom (Singular.trieGet (presupposed folds.flatten) k)
      (kindsOf k folds.flatten) = true := fun k => by
    rw [presupposed_reads]
    exact shape_valid _ (shapes k)
  obtain ⟨members, flat⟩ := changes_replay_of_valid folds.flatten _ valid
  exact ⟨members, (replayFrom_iff folds _ members).mpr ⟨nonempty, flat⟩⟩

/-- **What a history refutes by itself.**
Given folds.
When every choice of members before them is considered.
Then none make the folds replay exactly when some fold is without a change,
or the changes to some key are not none, a registration, a termination, or a
registration then a termination: a key registered twice, terminated twice, or
registered after its termination. -/
theorem unreplayable_iff (folds : List (List KeyChange)) :
    (∀ start, replayFrom start folds = none) ↔
      (∃ changes ∈ folds, changes = []) ∨ ∃ k, ¬ Shape (kindsOf k folds.flatten) := by
  constructor
  · intro failed
    apply Classical.byContradiction
    intro sound
    obtain ⟨members, replayed⟩ := replays_of_shapes folds
      (fun changes member empty => sound (Or.inl ⟨changes, member, empty⟩))
      (fun k => Classical.byContradiction fun bad => sound (Or.inr ⟨k, bad⟩))
    rw [failed] at replayed
    contradiction
  · rintro bad start
    cases replayed : replayFrom start folds with
    | none => rfl
    | some members =>
      obtain ⟨nonempty, flat⟩ := (replayFrom_iff folds start members).mp replayed
      rcases bad with ⟨changes, member, empty⟩ | ⟨k, shape⟩
      · exact absurd empty (nonempty changes member)
      · exact absurd
          (shape_of_valid _ _ (changes_follow_kinds folds.flatten start members k flat).1) shape

/-- **The executable check of a history that refutes itself is the rule.**
Given a history.
When the executable check is compared with the rule.
Then the check holds exactly when no members before the folds, none when the
history says it is complete, make them replay. -/
theorem refutesItself_iff (h : HistoryObservation) :
    refutesItself h = true ↔ RefutesItself h := by
  unfold refutesItself RefutesItself
  cases h.complete with
  | true =>
    simp only [↓reduceIte, Option.isNone_iff_eq_none]
    constructor
    · intro failed start origin
      rw [origin trivial]
      exact failed
    · intro failed
      exact failed [] fun _ => rfl
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, Option.isNone_iff_eq_none]
    constructor
    · intro failed start _
      cases replayed : replayFrom start h.folds with
      | none => rfl
      | some members =>
        obtain ⟨nonempty, flat⟩ := (replayFrom_iff h.folds start members).mp replayed
        obtain ⟨members', replayed'⟩ := replays_of_shapes h.folds nonempty fun k =>
          shape_of_valid _ _ (changes_follow_kinds h.folds.flatten start members k flat).1
        rw [failed] at replayed'
        contradiction
    · intro failed
      exact failed _ (by simp)

/-- **The executable check is the rule.**
Given a history's completeness, a key and its folds.
When the executable check is compared with the rule.
Then the check accepts exactly when some members before the supplied folds,
none for a complete history, make them replay and leave the key active. -/
theorem admitsActive_iff (complete : Bool) (key : Singular.Key) (folds : List (List KeyChange)) :
    admitsActive complete key folds = true ↔ AdmitsActive complete key folds := by
  constructor
  · intro admitted
    unfold admitsActive at admitted
    cases replayed : replayFrom (admissionStart complete key folds.flatten) folds with
    | none => simp [replayed] at admitted
    | some members =>
      simp only [replayed, decide_eq_true_eq] at admitted
      refine ⟨admissionStart complete key folds.flatten, members, ?_, replayed, admitted⟩
      intro isComplete
      simp [admissionStart, isComplete]
  · rintro ⟨start, members, origin, replayed, active⟩
    cases complete with
    | true =>
      have empty := origin rfl
      subst empty
      simp [admitsActive, admissionStart, replayed, active]
    | false =>
      obtain ⟨nonempty, shapes, registered⟩ :=
        (incomplete_admits_active_iff key folds).mp ⟨start, members, origin, replayed, active⟩
      obtain ⟨members', replayed', active'⟩ :=
        admission_start_replays folds key nonempty shapes registered
      simp [admitsActive, replayed', active']

/-- **A part of a real history never refuses a holder.**
Given a history that replays from the registry's creation and leaves a key
active, and some of its folds, in order: a history that starts late, or
misses folds anywhere.
When the part is asked whether it admits the key active.
Then it does: an honest incomplete history is a gap, never a contradiction
of a genuine holder. -/
theorem part_of_history_admits_active (actual part : List (List KeyChange))
    (members : Singular.Trie) (key : Singular.Key) (replayed : replay actual = some members)
    (active : Singular.trieGet members key = .known .active) (some_ : part.Sublist actual) :
    AdmitsActive false key part := by
  obtain ⟨nonempty, flat⟩ := (replayFrom_iff actual [] members).mp replayed
  have follow := fun k => changes_follow_kinds actual.flatten [] members k flat
  have kindsPart : ∀ k, (kindsOf k part.flatten).Sublist (kindsOf k actual.flatten) := fun k =>
    ((flatten_sublist some_).filter _).map _
  have shapes : ∀ k, Shape (kindsOf k part.flatten) := fun k =>
    shape_sublist _ _ (shape_of_valid _ _ (follow k).1) (kindsPart k)
  have once : kindsOf key actual.flatten = [true] := by
    have final := (follow key).2
    have valid := (follow key).1
    have empty : Singular.trieGet ([] : Singular.Trie) key = .unknown := rfl
    rw [active, empty] at final
    rw [empty] at valid
    rcases shape_of_valid _ _ valid with shape | shape | shape | shape
    · rw [shape] at final; simp [leafAfter] at final
    · exact shape
    · rw [shape] at valid; simp [validFrom] at valid
    · rw [shape] at final; simp [leafAfter] at final
  have registered : kindsOf key part.flatten = [] ∨ kindsOf key part.flatten = [true] :=
    sublist_single true _ (once ▸ kindsPart key)
  exact (incomplete_admits_active_iff key part).mpr
    ⟨fun changes member => nonempty changes (some_.subset member), shapes, registered⟩

/-- **An honest history never refutes itself.**
Given a history that replays from the registry's creation, and a history
observation that holds some of its folds, in order, and all of them when it
says it is complete.
When the observation is asked whether it refutes itself.
Then it does not: some members make the observed folds replay. They need not
be the members the registry had before the first observed fold. -/
theorem honest_history_does_not_refute_itself (h : HistoryObservation)
    (actual : List (List KeyChange)) (members : Singular.Trie)
    (replayed : replay actual = some members) (part : h.folds.Sublist actual)
    (whole : h.complete = true → h.folds = actual) : ¬ RefutesItself h := by
  intro refutes
  cases complete : h.complete with
  | true =>
    have failed : replay h.folds = none := refutes [] fun _ => rfl
    rw [whole complete, replayed] at failed
    contradiction
  | false =>
    obtain ⟨nonempty, flat⟩ := (replayFrom_iff actual [] members).mp replayed
    obtain ⟨members', replayed'⟩ := replays_of_shapes h.folds
      (fun changes member => nonempty changes (part.subset member))
      (fun k => shape_sublist _ _
        (shape_of_valid _ _ (changes_follow_kinds actual.flatten [] members k flat).1)
        (((flatten_sublist part).filter _).map _))
    rw [refutes _ (by simp [complete])] at replayed'
    contradiction

/-! ## The classifier and its relation -/

/-- Given any context and environment; when the Boolean and the proposition of
the authenticated context are compared; then they agree. -/
theorem authenticatedContextB_iff (c : Context) (e : Environment) :
    authenticatedContextB c e = true ↔ authenticatedContext c e := by
  simp [authenticatedContextB, authenticatedContext, and_assoc]

/-- Given any evidence and leaf; when the leaf the classifier reads is compared
with the leaf the evidence establishes; then they are the same: the history is
complete, of the identifier's registry through the asked point, its replay
succeeds and the replayed members read that leaf at the identifier's key. -/
theorem establishedLeaf_eq_some_iff (i : Interpretation) (c : Context) (ev : Evidence)
    (leaf : Singular.Leaf) : establishedLeaf i c ev = some leaf ↔ LeafAt i c ev leaf := by
  unfold establishedLeaf LeafAt
  cases found : ev.history with
  | none => simp
  | some h =>
    by_cases guard : h.point = ev.point ∧ h.registry = registryAsset i c ∧ h.complete = true
    · obtain ⟨point, registry, complete⟩ := guard
      cases replayed : replay h.folds with
      | none => simp [point, registry, complete, replayed]
      | some members => simp [point, registry, complete, replayed]
    · simp only [guard, ↓reduceIte, reduceCtorEq, Option.some.injEq, false_iff, not_exists, not_and]
      intro x members same point registry complete
      subst same
      exact absurd ⟨point, registry, complete⟩ guard

/-- Given any evidence; when the classifier reads no leaf; then the evidence
establishes none, and conversely. -/
theorem establishedLeaf_eq_none_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    establishedLeaf i c ev = none ↔ ∀ leaf, ¬ LeafAt i c ev leaf := by
  constructor
  · intro none leaf at_
    rw [(establishedLeaf_eq_some_iff i c ev leaf).mpr at_] at none
    contradiction
  · intro absent
    cases found : establishedLeaf i c ev with
    | none => rfl
    | some leaf => exact absurd ((establishedLeaf_eq_some_iff i c ev leaf).mp found) (absent leaf)

/-- Given an output; when it has a checkpoint form; then that form is live
with the state of a live checkpoint of the identifier, or convicted with the
key state of the identifier's convicted checkpoint, and conversely. -/
theorem checkpointCustody_eq_some_iff (i : Interpretation) (c : Context) (o : AH.ObservedOutput)
    (k : Custody) :
    checkpointCustody i c o = some k ↔
      (∃ l, k = .live l ∧ LiveCheckpoint i c o l) ∨
      (∃ h, k = .convicted h ∧ ConvictedCheckpoint i c o h) := by
  unfold checkpointCustody LiveCheckpoint ConvictedCheckpoint
  by_cases guard : o.credential = c.checkpointCredential ∧
      AH.quantity o (representativeAsset i c) = 1
  · cases hd : decoded i c o with
    | none => simp [guard]
    | some d =>
      rcases d with ⟨aid, st⟩
      cases st <;> by_cases same : aid = c.aid <;> simp [guard, same, eq_comm]
  · simp only [guard, ↓reduceIte, reduceCtorEq, false_iff, not_or, not_exists, not_and]
    exact ⟨fun _ _ credential quantity => absurd ⟨credential, quantity⟩ guard,
      fun _ _ credential quantity => absurd ⟨credential, quantity⟩ guard⟩

/-- Given a termination request of the identifier's key; when its checkpoint
form is read; then it has none: its datum is empty, so nothing decodes. -/
theorem request_has_no_checkpoint_form (i : Interpretation) (c : Context) (o : AH.ObservedOutput)
    (request : TerminationRequest i c o) : checkpointCustody i c o = none := by
  have empty : decoded i c o = none := by
    unfold TerminationRequest SingularApplicationHeld.terminationShape at request
    unfold decoded
    cases hd : o.datum with
    | application raw =>
      have : (SingularApplicationHeld.OutputDatum.application raw ==
          SingularApplicationHeld.OutputDatum.empty) = false := rfl
      have unflipped : (SingularApplicationHeld.AppMutation.none ==
          SingularApplicationHeld.AppMutation.flip .terminationShape) = false := rfl
      simp [SingularApplicationHeld.appGuard, hd, this, unflipped] at request
    | _ => rfl
  unfold checkpointCustody
  simp [empty]

/-- Given an output; when its custody is read; then it is a live checkpoint, a
convicted checkpoint, a termination request or inconsistent, each exactly when
the output has that form; it is never "not established" and never "absent",
which are readings of an observation, not of a holder. -/
theorem custodyOf_exact (i : Interpretation) (c : Context) (o : AH.ObservedOutput) :
    (∀ l, custodyOf i c o = .live l ↔ LiveCheckpoint i c o l) ∧
    (∀ h, custodyOf i c o = .convicted h ↔ ConvictedCheckpoint i c o h) ∧
    (custodyOf i c o = .request ↔ TerminationRequest i c o) ∧
    custodyOf i c o ≠ .notEstablished ∧ custodyOf i c o ≠ .absent := by
  unfold custodyOf
  cases form : checkpointCustody i c o with
  | some k =>
    have shape := (checkpointCustody_eq_some_iff i c o k).mp form
    have notRequest : ¬ TerminationRequest i c o := fun request => by
      rw [request_has_no_checkpoint_form i c o request] at form
      contradiction
    rcases shape with ⟨l, rfl, live⟩ | ⟨h, rfl, convicted⟩
    · refine ⟨fun l' => ?_, fun h => ?_, ?_, by simp, by simp⟩
      · constructor
        · intro same
          cases same
          exact live
        · intro other
          have := live.2.2.symm.trans other.2.2
          simp only [Option.some.injEq, DecodedDatum.mk.injEq, State.present.injEq, true_and] at this
          rw [this]
      · constructor
        · intro same
          cases same
        · intro other
          have := live.2.2.symm.trans other.2.2
          simp at this
      · simp [notRequest]
    · refine ⟨fun l => ?_, fun h' => ?_, ?_, by simp, by simp⟩
      · constructor
        · intro same
          cases same
        · intro other
          have := convicted.2.2.symm.trans other.2.2
          simp at this
      · constructor
        · intro same
          cases same
          exact convicted
        · intro other
          have := convicted.2.2.symm.trans other.2.2
          simp only [Option.some.injEq, DecodedDatum.mk.injEq, State.terminationPending.injEq,
            true_and] at this
          rw [this]
      · simp [notRequest]
  | none =>
    have noLive : ∀ l, ¬ LiveCheckpoint i c o l := fun l live => by
      rw [(checkpointCustody_eq_some_iff i c o (.live l)).mpr (Or.inl ⟨l, rfl, live⟩)] at form
      contradiction
    have noConvicted : ∀ h, ¬ ConvictedCheckpoint i c o h := fun h convicted => by
      rw [(checkpointCustody_eq_some_iff i c o (.convicted h)).mpr
        (Or.inr ⟨h, rfl, convicted⟩)] at form
      contradiction
    by_cases request : requestShape i c o = true
    · simp only [request, ↓reduceIte, reduceCtorEq, false_iff, true_iff, ne_eq, not_false_eq_true,
        and_self, and_true]
      exact ⟨noLive, noConvicted, request⟩
    · have notRequest : ¬ TerminationRequest i c o := request
      simp only [request, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, false_iff, ne_eq,
        not_false_eq_true, and_self, and_true]
      exact ⟨noLive, noConvicted, notRequest⟩

/-- Given evidence that establishes a set of holders; when the classifier
reads the custody; then no holder reads absent, one holder reads as that
holder's form and two or more read inconsistent. -/
theorem holdingCustody_of_holders (i : Interpretation) (c : Context) (ev : Evidence)
    (holders : List AH.ObservedOutput) (established : HoldersAt i c ev holders) :
    holdingCustody i c ev = holdersCustody i c holders := by
  obtain ⟨h, found, point, asset, rfl⟩ := established
  unfold holdingCustody
  simp only [found, point, asset, and_self, ↓reduceIte]

/-- Given any evidence; when the classifier reads the custody as not
established; then the evidence establishes no set of holders, and conversely. -/
theorem holdingCustody_notEstablished_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    holdingCustody i c ev = .notEstablished ↔ ∀ holders, ¬ HoldersAt i c ev holders := by
  constructor
  · intro reading holders established
    rw [holdingCustody_of_holders i c ev holders established] at reading
    rcases holders with _ | ⟨o, _ | ⟨o', rest⟩⟩
    · contradiction
    · exact (custodyOf_exact i c o).2.2.2.1 reading
    · contradiction
  · intro none
    unfold holdingCustody
    cases found : ev.holding with
    | none => rfl
    | some h =>
      by_cases guard : h.point = ev.point ∧ h.asset = representativeAsset i c
      · exact absurd ⟨h, found, guard.1, guard.2, rfl⟩ (none h.holders)
      · simp [guard]

/-- Given any evidence; when the holding observation shows no holder (it is
not established, or it shows none); then the classifier reads the custody as
not established or absent, and conversely. -/
theorem noHolderSeen_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    NoHolderSeen i c ev ↔
      holdingCustody i c ev = .notEstablished ∨ holdingCustody i c ev = .absent := by
  constructor
  · intro none
    by_cases established : ∃ holders, HoldersAt i c ev holders
    · obtain ⟨holders, at_⟩ := established
      have empty := none holders at_
      subst empty
      exact Or.inr (holdingCustody_of_holders i c ev [] at_)
    · exact Or.inl ((holdingCustody_notEstablished_iff i c ev).mpr
        fun holders at_ => established ⟨holders, at_⟩)
  · rintro (reading | reading) holders at_
    · exact absurd at_ ((holdingCustody_notEstablished_iff i c ev).mp reading holders)
    · rw [holdingCustody_of_holders i c ev holders at_] at reading
      rcases holders with _ | ⟨o, _ | ⟨o', rest⟩⟩
      · rfl
      · exact absurd reading (custodyOf_exact i c o).2.2.2.2
      · contradiction

/-- Given any evidence; when the classifier reads the history as not refusing
a holder; then the reader holds no history of the identifier's registry
through the asked point, or the one it holds admits the identifier's key
active, and conversely. -/
theorem historyAdmitsHolder_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    historyAdmitsHolder i c ev = true ↔ HistoryAllowsHolder i c ev := by
  unfold historyAdmitsHolder HistoryAllowsHolder
  cases found : ev.history with
  | none => simp
  | some h =>
    dsimp only
    have sound : (!refutesItself h) = true ↔ ¬ RefutesItself h := by
      rw [← refutesItself_iff]
      simp
    by_cases guard : h.point = ev.point ∧ h.registry = registryAsset i c
    · rw [if_pos guard, Bool.and_eq_true, sound, admitsActive_iff]
      constructor
      · rintro ⟨intact, admits⟩ h' same
        cases same
        exact ⟨intact, fun _ _ => admits⟩
      · intro allows
        exact ⟨(allows h rfl).1, (allows h rfl).2 guard.1 guard.2⟩
    · rw [if_neg guard, Bool.and_true, sound]
      constructor
      · intro intact h' same
        cases same
        exact ⟨intact, fun point registry => absurd ⟨point, registry⟩ guard⟩
      · intro allows
        exact (allows h rfl).1

/-- Given evidence whose history establishes a leaf; when the history is asked
whether it refuses a holder; then it does not exactly when that leaf reads
active. -/
theorem leaf_allows_holder_iff (i : Interpretation) (c : Context) (ev : Evidence)
    (leaf : Singular.Leaf) (established : LeafAt i c ev leaf) :
    HistoryAllowsHolder i c ev ↔ leaf = .known .active := by
  obtain ⟨h, members, found, point, registry, complete, replayed, read⟩ := established
  constructor
  · intro allows
    obtain ⟨start, members', origin, replayed', active⟩ := (allows h found).2 point registry
    have empty := origin complete
    subst empty
    have same : members' = members := Option.some.inj (replayed'.symm.trans replayed)
    rw [← read, ← same]
    exact active
  · rintro rfl h' found'
    rw [found] at found'
    cases found'
    refine ⟨fun refutes => ?_, fun _ _ => ⟨[], members, fun _ => rfl, replayed, read⟩⟩
    have failed : replay h.folds = none := refutes [] fun _ => rfl
    rw [replayed] at failed
    contradiction

/-- Given evidence whose history refutes itself; when it is read; then it
refuses every holder and establishes no leaf. -/
theorem broken_history_refuses (i : Interpretation) (c : Context) (ev : Evidence)
    (broken : BrokenHistory ev) :
    ¬ HistoryAllowsHolder i c ev ∧ ∀ leaf, ¬ LeafAt i c ev leaf := by
  obtain ⟨h, found, failed⟩ := broken
  constructor
  · intro allows
    exact (allows h found).1 failed
  · rintro leaf ⟨h', members, found', _, _, complete, replayed, _⟩
    rw [found] at found'
    cases found'
    have none : replay h.folds = none := failed [] fun _ => rfl
    rw [none] at replayed
    contradiction

/-- Given evidence whose classifier custody is one recognised holder form;
when the evidence is read; then it establishes exactly one holder, of that
form. -/
theorem holdingCustody_single (i : Interpretation) (c : Context) (ev : Evidence) (k : Custody)
    (reading : holdingCustody i c ev = k)
    (form : (∃ l, k = .live l) ∨ (∃ h, k = .convicted h) ∨ k = .request) :
    ∃ o, HoldersAt i c ev [o] ∧ custodyOf i c o = k := by
  have established : ∃ holders, HoldersAt i c ev holders := by
    apply Classical.byContradiction
    intro none
    have missing := (holdingCustody_notEstablished_iff i c ev).mpr
      fun holders at_ => none ⟨holders, at_⟩
    rw [reading] at missing
    rcases form with ⟨l, rfl⟩ | ⟨h, rfl⟩ | rfl <;> contradiction
  obtain ⟨holders, at_⟩ := established
  have read := holdingCustody_of_holders i c ev holders at_
  rw [reading] at read
  rcases holders with _ | ⟨o, _ | ⟨o', rest⟩⟩
  · rcases form with ⟨l, rfl⟩ | ⟨h, rfl⟩ | rfl <;> contradiction
  · exact ⟨o, at_, read.symm⟩
  · rcases form with ⟨l, rfl⟩ | ⟨h, rfl⟩ | rfl <;> contradiction

/-- Given evidence that decides a status; when the classifier runs; then it
returns that status. -/
theorem decides_classify (i : Interpretation) (c : Context) (ev : Evidence) (status : Status)
    (decided : Decides i c ev status) : classify i c ev = status := by
  unfold classify
  cases decided with
  | @active o l context holders live allows =>
    rw [(authenticatedContextB_iff c ev.environment).mpr context,
      (historyAdmitsHolder_iff i c ev).mpr allows,
      holdingCustody_of_holders i c ev [o] holders, holdersCustody,
      ((custodyOf_exact i c o).1 l).mpr live]
    simp [verdict]
  | @convicted o h context holders convicted allows =>
    rw [(authenticatedContextB_iff c ev.environment).mpr context,
      (historyAdmitsHolder_iff i c ev).mpr allows,
      holdingCustody_of_holders i c ev [o] holders, holdersCustody,
      ((custodyOf_exact i c o).2.1 h).mpr convicted]
    simp [verdict]
  | @requested o context holders request allows =>
    rw [(authenticatedContextB_iff c ev.environment).mpr context,
      (historyAdmitsHolder_iff i c ev).mpr allows,
      holdingCustody_of_holders i c ev [o] holders, holdersCustody,
      (custodyOf_exact i c o).2.2.1.mpr request]
    simp [verdict]
  | terminal context leaf none =>
    rw [(authenticatedContextB_iff c ev.environment).mpr context,
      (establishedLeaf_eq_some_iff i c ev _).mpr leaf]
    rcases (noHolderSeen_iff i c ev).mp none with custody | custody <;>
      cases historyAdmitsHolder i c ev <;> simp [custody, verdict]
  | neverRegistered context leaf none =>
    rw [(authenticatedContextB_iff c ev.environment).mpr context,
      (establishedLeaf_eq_some_iff i c ev _).mpr leaf]
    rcases (noHolderSeen_iff i c ev).mp none with custody | custody <;>
      cases historyAdmitsHolder i c ev <;> simp [custody, verdict]

/-- Given a classifier result that is a status other than unavailable; when
the evidence is read; then the evidence decides that status. -/
theorem classify_decides (i : Interpretation) (c : Context) (ev : Evidence) (status : Status)
    (result : classify i c ev = status) (available : status ≠ .unavailable) :
    Decides i c ev status := by
  unfold classify at result
  by_cases context : authenticatedContextB c ev.environment = true
  · have authenticated := (authenticatedContextB_iff c ev.environment).mp context
    simp only [context, ↓reduceIte] at result
    generalize custody : holdingCustody i c ev = k at result
    generalize admitted : historyAdmitsHolder i c ev = admits at result
    generalize leaf : establishedLeaf i c ev = found at result
    have allows : admits = true → HistoryAllowsHolder i c ev :=
      fun yes => (historyAdmitsHolder_iff i c ev).mp (admitted.trans yes)
    have unseen : k = .notEstablished ∨ k = .absent → NoHolderSeen i c ev :=
      fun reading => (noHolderSeen_iff i c ev).mpr (custody ▸ reading)
    cases k with
    | live l =>
      obtain ⟨o, holders, form⟩ := holdingCustody_single i c ev _ custody (Or.inl ⟨l, rfl⟩)
      have live := ((custodyOf_exact i c o).1 l).mp form
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals first
        | exact absurd rfl available
        | exact .active authenticated holders live (allows rfl)
    | convicted h =>
      obtain ⟨o, holders, form⟩ := holdingCustody_single i c ev _ custody (Or.inr (Or.inl ⟨h, rfl⟩))
      have convicted := ((custodyOf_exact i c o).2.1 h).mp form
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals first
        | exact absurd rfl available
        | exact .convicted authenticated holders convicted (allows rfl)
    | request =>
      obtain ⟨o, holders, form⟩ := holdingCustody_single i c ev _ custody (Or.inr (Or.inr rfl))
      have request := (custodyOf_exact i c o).2.2.1.mp form
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals first
        | exact absurd rfl available
        | exact .requested authenticated holders request (allows rfl)
    | notEstablished =>
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals first
        | exact absurd rfl available
        | exact .terminal authenticated ((establishedLeaf_eq_some_iff i c ev _).mp leaf)
            (unseen (by simp))
        | exact .neverRegistered authenticated ((establishedLeaf_eq_some_iff i c ev _).mp leaf)
            (unseen (by simp))
    | absent =>
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals first
        | exact absurd rfl available
        | exact .terminal authenticated ((establishedLeaf_eq_some_iff i c ev _).mp leaf)
            (unseen (by simp))
        | exact .neverRegistered authenticated ((establishedLeaf_eq_some_iff i c ev _).mp leaf)
            (unseen (by simp))
    | inconsistent =>
      cases admits <;> rcases found with _ | ⟨_ | ⟨_ | _ | _⟩⟩ <;>
        simp only [verdict] at result <;> subst result
      all_goals exact absurd rfl available
  · simp only [context, Bool.false_eq_true, ↓reduceIte] at result
    exact absurd result.symm available

/-- **The classifier is the relation.**
Given any interpretation, context, evidence and status.
When the executable classifier and the relation are compared.
Then the classifier returns the status exactly when the relation gives it as
the reader's answer: the status the evidence decides, or unavailable when it
decides none. -/
theorem classify_iff_answers (i : Interpretation) (c : Context) (ev : Evidence) (status : Status) :
    classify i c ev = status ↔ Answers i c ev status := by
  constructor
  · intro result
    by_cases available : status = .unavailable
    · refine Or.inr ⟨available, fun s decided => ?_⟩
      have other := decides_classify i c ev s decided
      rw [result, available] at other
      subst other
      cases decided
    · exact Or.inl (classify_decides i c ev status result available)
  · rintro (decided | ⟨rfl, undecided⟩)
    · exact decides_classify i c ev status decided
    · apply Classical.byContradiction
      intro other
      exact undecided _ (classify_decides i c ev _ rfl other)

/-- **Exactly one outcome.**
Given any interpretation, context and evidence.
When the reader answers.
Then exactly one of the five outcomes is its answer. -/
theorem exactly_one_answer (i : Interpretation) (c : Context) (ev : Evidence) :
    ∃ status, Answers i c ev status ∧ ∀ other, Answers i c ev other → other = status :=
  ⟨classify i c ev, (classify_iff_answers i c ev _).mp rfl,
    fun other answer => ((classify_iff_answers i c ev other).mpr answer).symm⟩

/-- **The statuses exclude one another on every evidence value.**
Given evidence that decides two statuses.
When they are compared.
Then they are the same status. -/
theorem decides_unique (i : Interpretation) (c : Context) (ev : Evidence) (s t : Status)
    (first : Decides i c ev s) (second : Decides i c ev t) : s = t :=
  (decides_classify i c ev s first).symm.trans (decides_classify i c ev t second)

/-! ## What decides each status -/

/-- Given a status other than unavailable; when the classifier's result is
compared with what the evidence decides; then they agree. -/
theorem classify_eq_iff_decides (i : Interpretation) (c : Context) (ev : Evidence)
    (status : Status) (available : status ≠ .unavailable) :
    classify i c ev = status ↔ Decides i c ev status :=
  ⟨fun result => classify_decides i c ev status result available, decides_classify i c ev status⟩

/-- Given any evidence; when the classifier answers unavailable; then the
evidence decides no status, and conversely. -/
theorem unavailable_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    classify i c ev = .unavailable ↔ ∀ status, ¬ Decides i c ev status := by
  rw [classify_iff_answers]
  constructor
  · rintro (decided | ⟨_, undecided⟩)
    · cases decided
    · exact undecided
  · exact fun undecided => Or.inr ⟨rfl, undecided⟩

/-- **Active needs the live checkpoint.**
Given any evidence.
When the reader answers active.
Then the context is authenticated, the evidence establishes exactly one holder
of the representative asset at the asked point, that holder is at the
checkpoint credential, holds the asset exactly once and carries a live datum
of the identifier, and the history, when the reader holds one of the
identifier's registry through the asked point, admits the identifier's key
active; and conversely such evidence is answered active. -/
theorem active_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    classify i c ev = .active ↔
      authenticatedContext c ev.environment ∧
      (∃ o l, HoldersAt i c ev [o] ∧ LiveCheckpoint i c o l) ∧ HistoryAllowsHolder i c ev := by
  rw [classify_eq_iff_decides i c ev .active (by simp)]
  constructor
  · intro decided
    cases decided with
    | active context holders live allows => exact ⟨context, ⟨_, _, holders, live⟩, allows⟩
  · rintro ⟨context, ⟨o, l, holders, live⟩, allows⟩
    exact .active context holders live allows

/-- **Pending termination for the convicted checkpoint.**
Given any evidence.
When the reader answers pending termination.
Then the context is authenticated, the evidence establishes exactly one holder
of the representative asset at the asked point, that holder is the convicted
checkpoint of the identifier (at the checkpoint credential, the asset exactly
once, a pending-termination datum of the identifier) or the termination
request of the identifier's key, and the history, when the reader holds one
of the identifier's registry through the asked point, admits the identifier's
key active; and conversely such evidence is answered pending termination. -/
theorem pendingTermination_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    classify i c ev = .pendingTermination ↔
      authenticatedContext c ev.environment ∧
      (∃ o, HoldersAt i c ev [o] ∧
        ((∃ h, ConvictedCheckpoint i c o h) ∨ TerminationRequest i c o)) ∧
      HistoryAllowsHolder i c ev := by
  rw [classify_eq_iff_decides i c ev .pendingTermination (by simp)]
  constructor
  · intro decided
    cases decided with
    | convicted context holders convicted allows =>
      exact ⟨context, ⟨_, holders, Or.inl ⟨_, convicted⟩⟩, allows⟩
    | requested context holders request allows =>
      exact ⟨context, ⟨_, holders, Or.inr request⟩, allows⟩
  · rintro ⟨context, ⟨o, holders, ⟨h, convicted⟩ | request⟩, allows⟩
    · exact .convicted context holders convicted allows
    · exact .requested context holders request allows

/-- **Terminal only from the terminal leaf.**
Given any evidence.
When the reader answers terminal.
Then the context is authenticated, the evidence holds a complete history of
the identifier's registry through the asked point whose replay reads the
identifier's key terminal, and the holding observation is not established or
shows no holder; and conversely such evidence is answered terminal. No other
evidence gives terminal: not a missing token, and no observation of a burn,
which the evidence does not contain. -/
theorem terminal_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    classify i c ev = .terminal ↔
      authenticatedContext c ev.environment ∧ LeafAt i c ev (.known .terminal) ∧
      NoHolderSeen i c ev := by
  rw [classify_eq_iff_decides i c ev .terminal (by simp)]
  constructor
  · intro decided
    cases decided with
    | terminal context leaf none => exact ⟨context, leaf, none⟩
  · rintro ⟨context, leaf, none⟩
    exact .terminal context leaf none

/-- **Never registered only from the unknown leaf.**
Given any evidence.
When the reader answers never registered.
Then the context is authenticated, the evidence holds a complete history of
the identifier's registry through the asked point whose replay reads the
identifier's key unknown, and the holding observation is not established or
shows no holder; and conversely such evidence is answered never registered. -/
theorem neverRegistered_iff (i : Interpretation) (c : Context) (ev : Evidence) :
    classify i c ev = .neverRegistered ↔
      authenticatedContext c ev.environment ∧ LeafAt i c ev .unknown ∧ NoHolderSeen i c ev := by
  rw [classify_eq_iff_decides i c ev .neverRegistered (by simp)]
  constructor
  · intro decided
    cases decided with
    | neverRegistered context leaf none => exact ⟨context, leaf, none⟩
  · rintro ⟨context, leaf, none⟩
    exact .neverRegistered context leaf none

/-- **The holder the answer names.**
Given any evidence and output.
When the reader names that output as the holder.
Then the answer is active or pending termination and the evidence
establishes that output as the one holder, and conversely. -/
theorem holder_eq_some_iff (i : Interpretation) (c : Context) (ev : Evidence)
    (o : AH.ObservedOutput) :
    holder i c ev = some o ↔
      (classify i c ev = .active ∨ classify i c ev = .pendingTermination) ∧
      HoldersAt i c ev [o] := by
  have single : classify i c ev = .active ∨ classify i c ev = .pendingTermination →
      ∃ o', HoldersAt i c ev [o'] := by
    rintro (status | status)
    · obtain ⟨_, ⟨o', _, holders, _⟩, _⟩ := (active_iff i c ev).mp status
      exact ⟨o', holders⟩
    · obtain ⟨_, ⟨o', holders, _⟩, _⟩ := (pendingTermination_iff i c ev).mp status
      exact ⟨o', holders⟩
  constructor
  · intro named
    have status : classify i c ev = .active ∨ classify i c ev = .pendingTermination := by
      unfold holder at named
      split at named <;> simp_all
    obtain ⟨o', h, found, point, asset, holders⟩ := single status
    refine ⟨status, ?_⟩
    have read : holder i c ev = some o' := by
      unfold holder
      rcases status with status | status <;> simp [status, found, holders]
    rw [named] at read
    cases read
    exact ⟨h, found, point, asset, holders⟩
  · rintro ⟨status, h, found, _, _, holders⟩
    unfold holder
    rcases status with status | status <;> simp [status, found, holders]

/-! ## Pending termination says where the asset sits -/

/-- **Pending termination names the checkpoint or the request.**
Given evidence answered pending termination.
When the custody the reader read is inspected.
Then the answer names one holder, and the custody says which of the two it
is: the convicted checkpoint, with its key state, or the termination request.
The two never coincide. -/
theorem pending_termination_custody (i : Interpretation) (c : Context) (ev : Evidence)
    (pending : classify i c ev = .pendingTermination) :
    ∃ o, holder i c ev = some o ∧
      ((∃ h, holdingCustody i c ev = .convicted h ∧ ConvictedCheckpoint i c o h ∧
          ¬ TerminationRequest i c o) ∨
       (holdingCustody i c ev = .request ∧ TerminationRequest i c o ∧
          ∀ h, ¬ ConvictedCheckpoint i c o h)) := by
  obtain ⟨_, ⟨o, holders, form⟩, _⟩ := (pendingTermination_iff i c ev).mp pending
  have named := (holder_eq_some_iff i c ev o).mpr ⟨Or.inr pending, holders⟩
  have custody : holdingCustody i c ev = custodyOf i c o := by
    rw [holdingCustody_of_holders i c ev [o] holders, holdersCustody]
  have exact := custodyOf_exact i c o
  refine ⟨o, named, ?_⟩
  rcases form with ⟨h, convicted⟩ | request
  · have read := (exact.2.1 h).mpr convicted
    refine Or.inl ⟨h, custody.trans read, convicted, fun request => ?_⟩
    rw [exact.2.2.1.mpr request] at read
    cases read
  · have read := exact.2.2.1.mpr request
    refine Or.inr ⟨custody.trans read, request, fun h convicted => ?_⟩
    rw [(exact.2.1 h).mpr convicted] at read
    cases read

/-! ## Missing, incomplete or inconsistent evidence -/

/-- Given evidence that establishes a set of holders; when another set is
established by the same evidence; then the two are the same set. -/
theorem holdersAt_unique (i : Interpretation) (c : Context) (ev : Evidence)
    (first second : List AH.ObservedOutput) (a : HoldersAt i c ev first)
    (b : HoldersAt i c ev second) : first = second := by
  obtain ⟨h, found, _, _, rfl⟩ := a
  obtain ⟨h', found', _, _, rfl⟩ := b
  rw [found] at found'
  cases found'
  rfl

/-- Given evidence that establishes a leaf; when another leaf is established
by the same evidence; then the two are the same leaf. -/
theorem leafAt_unique (i : Interpretation) (c : Context) (ev : Evidence)
    (first second : Singular.Leaf) (a : LeafAt i c ev first) (b : LeafAt i c ev second) :
    first = second :=
  Option.some.inj (((establishedLeaf_eq_some_iff i c ev first).mpr a).symm.trans
    ((establishedLeaf_eq_some_iff i c ev second).mpr b))

/-- **An unauthenticated context is unavailable.**
Given an environment whose network differs from the context's, or whose
release or checkpoint credential is unresolved or differs.
When the reader answers on any evidence.
Then the answer is unavailable. -/
theorem unauthenticated_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (wrong : ¬ authenticatedContext c ev.environment) : classify i c ev = .unavailable := by
  rw [unavailable_iff]
  intro status decided
  cases decided <;> contradiction

/-- **No observation, no status.**
Given evidence with no holding observation established at the asked point
and no history that establishes a leaf.
When the reader answers.
Then the answer is unavailable. -/
theorem no_observation_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (noHolders : ∀ holders, ¬ HoldersAt i c ev holders) (noLeaf : ∀ leaf, ¬ LeafAt i c ev leaf) :
    classify i c ev = .unavailable := by
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ holders _ _ => exact noHolders _ holders
  | convicted _ holders _ _ => exact noHolders _ holders
  | requested _ holders _ _ => exact noHolders _ holders
  | terminal _ leaf _ => exact noLeaf _ leaf
  | neverRegistered _ leaf _ => exact noLeaf _ leaf

/-- **A missing token alone decides nothing.**
Given evidence that establishes that no output holds the representative asset
and establishes no leaf.
When the reader answers.
Then the answer is unavailable: neither terminal nor never registered. -/
theorem missing_token_alone_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (missing : HoldersAt i c ev []) (noLeaf : ∀ leaf, ¬ LeafAt i c ev leaf) :
    classify i c ev = .unavailable := by
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ holders _ _ => cases holdersAt_unique i c ev _ _ missing holders
  | convicted _ holders _ _ => cases holdersAt_unique i c ev _ _ missing holders
  | requested _ holders _ _ => cases holdersAt_unique i c ev _ _ missing holders
  | terminal _ leaf _ => exact noLeaf _ leaf
  | neverRegistered _ leaf _ => exact noLeaf _ leaf

/-- **With a missing token the leaf decides.**
Given an authenticated context and evidence that establishes that no output
holds the representative asset.
When the reader answers.
Then the answer is terminal exactly when the established leaf reads terminal,
never registered exactly when it reads unknown, and never active or pending
termination. -/
theorem missing_token_leaf_decides (i : Interpretation) (c : Context) (ev : Evidence)
    (context : authenticatedContext c ev.environment) (missing : HoldersAt i c ev []) :
    (classify i c ev = .terminal ↔ LeafAt i c ev (.known .terminal)) ∧
    (classify i c ev = .neverRegistered ↔ LeafAt i c ev .unknown) ∧
    classify i c ev ≠ .active ∧ classify i c ev ≠ .pendingTermination := by
  have unseen : NoHolderSeen i c ev := fun holders at_ => holdersAt_unique i c ev _ _ at_ missing
  refine ⟨?_, ?_, ?_, ?_⟩
  · rw [terminal_iff]
    exact ⟨fun h => h.2.1, fun leaf => ⟨context, leaf, unseen⟩⟩
  · rw [neverRegistered_iff]
    exact ⟨fun h => h.2.1, fun leaf => ⟨context, leaf, unseen⟩⟩
  · rw [Ne, active_iff]
    rintro ⟨_, ⟨o, l, holders, _⟩, _⟩
    cases holdersAt_unique i c ev _ _ missing holders
  · rw [Ne, pendingTermination_iff]
    rintro ⟨_, ⟨o, holders, _⟩, _⟩
    cases holdersAt_unique i c ev _ _ missing holders

/-- **A holding observation made elsewhere establishes nothing.**
Given a holding observation made at another chain point than the asked one,
or about another asset than the identifier's representative asset.
When the reader answers.
Then the answer is the one it gives with no holding observation at all. -/
theorem holding_observed_elsewhere (i : Interpretation) (c : Context) (ev : Evidence)
    (h : HoldingObservation) (found : ev.holding = some h)
    (elsewhere : h.point ≠ ev.point ∨ h.asset ≠ representativeAsset i c) :
    classify i c ev = classify i c { ev with holding := none } := by
  have guard : ¬ (h.point = ev.point ∧ h.asset = representativeAsset i c) := by
    rintro ⟨point, asset⟩
    rcases elsewhere with other | other <;> contradiction
  have unread : holdingCustody i c ev = .notEstablished := by
    simp [holdingCustody, found, guard]
  have cleared : holdingCustody i c { ev with holding := none } = .notEstablished := rfl
  have sameLeaf : establishedLeaf i c { ev with holding := none } = establishedLeaf i c ev := rfl
  have sameHistory :
      historyAdmitsHolder i c { ev with holding := none } = historyAdmitsHolder i c ev := rfl
  simp only [classify, unread, cleared, sameLeaf, sameHistory]

/-- **A history of another point or another registry establishes nothing,
unless it refutes itself.**
Given a history observation made at another chain point than the asked one,
or of another registry than the identifier's, that does not refute itself.
When the reader answers.
Then the answer is the one it gives with no history at all. -/
theorem history_not_established (i : Interpretation) (c : Context) (ev : Evidence)
    (h : HistoryObservation) (found : ev.history = some h)
    (elsewhere : h.point ≠ ev.point ∨ h.registry ≠ registryAsset i c)
    (sound : ¬ RefutesItself h) :
    classify i c ev = classify i c { ev with history := none } := by
  have guard : ¬ (h.point = ev.point ∧ h.registry = registryAsset i c) := by
    rintro ⟨point, registry⟩
    rcases elsewhere with other | other <;> contradiction
  have guardLeaf :
      ¬ (h.point = ev.point ∧ h.registry = registryAsset i c ∧ h.complete = true) :=
    fun all => guard ⟨all.1, all.2.1⟩
  have unread : establishedLeaf i c ev = none := by
    simp [establishedLeaf, found, guardLeaf]
  have admitted : historyAdmitsHolder i c ev = true :=
    (historyAdmitsHolder_iff i c ev).mpr fun h' same => by
      rw [found] at same
      cases same
      exact ⟨sound, fun point registry => absurd ⟨point, registry⟩ guard⟩
  have cleared : establishedLeaf i c { ev with history := none } = none := rfl
  have clearedAdmitted : historyAdmitsHolder i c { ev with history := none } = true := rfl
  have same : holdingCustody i c { ev with history := none } = holdingCustody i c ev := rfl
  simp only [classify, unread, admitted, cleared, clearedAdmitted, same]

/-- **An honest partial history never refuses a holder.**
Given a registry's history that replays from its creation and leaves the
identifier's key active, and evidence whose history observation is incomplete
and holds some of those folds, in order, whatever point and registry it
names.
When the history is asked whether it refuses a holder.
Then it does not: it does not refute itself and it admits the key active. -/
theorem honest_partial_history_allows_holder (i : Interpretation) (c : Context) (ev : Evidence)
    (h : HistoryObservation) (actual : List (List KeyChange)) (members : Singular.Trie)
    (found : ev.history = some h) (incomplete : h.complete = false)
    (replayed : replay actual = some members)
    (active : Singular.trieGet members (i.keyOf c.aid) = .known .active)
    (part : h.folds.Sublist actual) : HistoryAllowsHolder i c ev := by
  intro h' same
  rw [found] at same
  cases same
  exact ⟨honest_history_does_not_refute_itself h actual members replayed part
      (fun complete => by rw [incomplete] at complete; contradiction),
    fun _ _ => incomplete ▸
      part_of_history_admits_active actual h.folds members (i.keyOf c.aid) replayed active part⟩

/-- **An incomplete history that does not refuse the holder is a gap.**
Given an incomplete history (it starts late or misses a fold) that does not
refuse a holder: some members before its folds make them replay and leave the
identifier's key active.
When the reader answers.
Then the answer is the one it gives with no history at all: the gap does not
make the answer unavailable when the holders decide it. -/
theorem incomplete_history_is_a_gap (i : Interpretation) (c : Context) (ev : Evidence)
    (h : HistoryObservation) (found : ev.history = some h) (incomplete : h.complete = false)
    (allows : HistoryAllowsHolder i c ev) :
    classify i c ev = classify i c { ev with history := none } := by
  have unread : establishedLeaf i c ev = none := by
    simp [establishedLeaf, found, incomplete]
  have admitted := (historyAdmitsHolder_iff i c ev).mpr allows
  have cleared : establishedLeaf i c { ev with history := none } = none := rfl
  have clearedAdmitted : historyAdmitsHolder i c { ev with history := none } = true := rfl
  have same : holdingCustody i c { ev with history := none } = holdingCustody i c ev := rfl
  simp only [classify, unread, admitted, cleared, clearedAdmitted, same]

/-- **An incomplete history that refuses the holder is a contradiction.**
Given an incomplete history of the identifier's registry through the asked
point that no members before its folds make replay with the identifier's key
left active: a fold makes no change, a key's changes are impossible in any
registry, or the identifier's key is terminated in it.
When the reader answers.
Then the answer is unavailable, whatever the holders show. -/
theorem incomplete_history_refusing_unavailable (i : Interpretation) (c : Context)
    (ev : Evidence) (h : HistoryObservation) (found : ev.history = some h)
    (point : h.point = ev.point) (registry : h.registry = registryAsset i c)
    (incomplete : h.complete = false)
    (refuses : ¬ AdmitsActive false (i.keyOf c.aid) h.folds) :
    classify i c ev = .unavailable := by
  have noLeaf : ∀ leaf, ¬ LeafAt i c ev leaf := by
    rintro leaf ⟨h', _, found', _, _, complete, _, _⟩
    rw [found] at found'
    cases found'
    rw [incomplete] at complete
    contradiction
  have refused : ¬ HistoryAllowsHolder i c ev := fun allows =>
    refuses (incomplete ▸ (allows h found).2 point registry)
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ _ _ allows => exact refused allows
  | convicted _ _ _ allows => exact refused allows
  | requested _ _ _ allows => exact refused allows
  | terminal _ leaf _ => exact noLeaf _ leaf
  | neverRegistered _ leaf _ => exact noLeaf _ leaf

/-- **A history that refutes itself is a contradiction, whatever the holders
show and whatever it names.**
Given evidence that holds a history that no members before its folds make
replay, none when it says it is complete: some fold makes no change, or
registers a key the registry knows, or terminates a key that is not active.
When the reader answers.
Then the answer is unavailable: with or without a holder, complete or not,
and whatever chain point and registry the history names. -/
theorem broken_history_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (broken : BrokenHistory ev) : classify i c ev = .unavailable := by
  obtain ⟨refused, noLeaf⟩ := broken_history_refuses i c ev broken
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ _ _ allows => exact refused allows
  | convicted _ _ _ allows => exact refused allows
  | requested _ _ _ allows => exact refused allows
  | terminal _ leaf _ => exact noLeaf _ leaf
  | neverRegistered _ leaf _ => exact noLeaf _ leaf

/-- **A holder against the history is inconsistent.**
Given evidence that establishes at least one holder of the representative
asset and holds a history that refuses a holder.
When the reader answers.
Then the answer is unavailable. -/
theorem holder_against_history_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (o : AH.ObservedOutput) (rest : List AH.ObservedOutput)
    (holders : HoldersAt i c ev (o :: rest)) (refuses : ¬ HistoryAllowsHolder i c ev) :
    classify i c ev = .unavailable := by
  have unseen : ¬ NoHolderSeen i c ev := fun none => by cases none _ holders
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ _ _ allows => exact refuses allows
  | convicted _ _ _ allows => exact refuses allows
  | requested _ _ _ allows => exact refuses allows
  | terminal _ _ none => exact unseen none
  | neverRegistered _ _ none => exact unseen none

/-- **Two holders are inconsistent.**
Given evidence that establishes two or more outputs holding the
representative asset.
When the reader answers.
Then the answer is unavailable. -/
theorem two_holders_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (o o' : AH.ObservedOutput) (rest : List AH.ObservedOutput)
    (holders : HoldersAt i c ev (o :: o' :: rest)) : classify i c ev = .unavailable := by
  have unseen : ¬ NoHolderSeen i c ev := fun none => by cases none _ holders
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ single _ _ => cases holdersAt_unique i c ev _ _ holders single
  | convicted _ single _ _ => cases holdersAt_unique i c ev _ _ holders single
  | requested _ single _ _ => cases holdersAt_unique i c ev _ _ holders single
  | terminal _ _ none => exact unseen none
  | neverRegistered _ _ none => exact unseen none

/-- **A holder the reader does not recognise is inconsistent.**
Given evidence that establishes one holder that is neither a live checkpoint
of the identifier, nor its convicted checkpoint, nor its termination request.
When the reader answers.
Then the answer is unavailable. -/
theorem unrecognised_holder_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (o : AH.ObservedOutput) (holders : HoldersAt i c ev [o])
    (notLive : ∀ l, ¬ LiveCheckpoint i c o l) (notConvicted : ∀ h, ¬ ConvictedCheckpoint i c o h)
    (notRequest : ¬ TerminationRequest i c o) : classify i c ev = .unavailable := by
  have unseen : ¬ NoHolderSeen i c ev := fun none => by cases none _ holders
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ single live _ =>
    cases holdersAt_unique i c ev _ _ holders single
    exact notLive _ live
  | convicted _ single convicted _ =>
    cases holdersAt_unique i c ev _ _ holders single
    exact notConvicted _ convicted
  | requested _ single request _ =>
    cases holdersAt_unique i c ev _ _ holders single
    exact notRequest request
  | terminal _ _ none => exact unseen none
  | neverRegistered _ _ none => exact unseen none

/-- **What is not a checkpoint of the identifier.**
Given an output at another credential than the checkpoint's, or holding the
representative asset in another quantity than one, or whose datum does not
decode, or decodes for another identifier, or decodes to a state without an
output.
When its form is read.
Then it is neither a live checkpoint nor the convicted checkpoint of the
identifier. -/
theorem not_a_checkpoint (i : Interpretation) (c : Context) (o : AH.ObservedOutput)
    (bad : o.credential ≠ c.checkpointCredential ∨
      AH.quantity o (representativeAsset i c) ≠ 1 ∨ decoded i c o = none ∨
      (∃ d, decoded i c o = some d ∧ d.aid ≠ c.aid) ∨
      (∃ d, decoded i c o = some d ∧ d.state.hasOutput = false)) :
    (∀ l, ¬ LiveCheckpoint i c o l) ∧ (∀ h, ¬ ConvictedCheckpoint i c o h) := by
  constructor
  · rintro l ⟨credential, quantity, datum⟩
    rcases bad with wrong | wrong | wrong | ⟨d, found, wrong⟩ | ⟨d, found, wrong⟩
    · exact wrong credential
    · exact wrong quantity
    · rw [datum] at wrong; contradiction
    · rw [datum] at found; cases found; exact wrong rfl
    · rw [datum] at found; cases found; simp [State.hasOutput] at wrong
  · rintro h ⟨credential, quantity, datum⟩
    rcases bad with wrong | wrong | wrong | ⟨d, found, wrong⟩ | ⟨d, found, wrong⟩
    · exact wrong credential
    · exact wrong quantity
    · rw [datum] at wrong; contradiction
    · rw [datum] at found; cases found; exact wrong rfl
    · rw [datum] at found; cases found; simp [State.hasOutput] at wrong

/-- **A holder against the leaf is inconsistent.**
Given evidence that establishes at least one holder of the representative
asset and establishes a leaf that does not read active.
When the reader answers.
Then the answer is unavailable. -/
theorem holder_against_leaf_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (o : AH.ObservedOutput) (rest : List AH.ObservedOutput) (leaf : Singular.Leaf)
    (holders : HoldersAt i c ev (o :: rest)) (established : LeafAt i c ev leaf)
    (inactive : leaf ≠ .known .active) : classify i c ev = .unavailable :=
  holder_against_history_unavailable i c ev o rest holders fun allows =>
    inactive ((leaf_allows_holder_iff i c ev leaf established).mp allows)

/-- **A registered key decides nothing without its holder.**
Given evidence whose history reads the identifier's key active, and that
establishes no single holder of the representative asset.
When the reader answers.
Then the answer is unavailable: the history says the key was registered and
not terminated, and does not say whether its checkpoint is live or
convicted. -/
theorem active_leaf_without_holder_unavailable (i : Interpretation) (c : Context) (ev : Evidence)
    (established : LeafAt i c ev (.known .active))
    (noSingle : ∀ o, ¬ HoldersAt i c ev [o]) : classify i c ev = .unavailable := by
  rw [unavailable_iff]
  intro status decided
  cases decided with
  | active _ single _ _ => exact noSingle _ single
  | convicted _ single _ _ => exact noSingle _ single
  | requested _ single _ _ => exact noSingle _ single
  | terminal _ other _ => cases leafAt_unique i c ev _ _ established other
  | neverRegistered _ other _ => cases leafAt_unique i c ev _ _ established other

/-! ## Eligibility is the consumer predicate's -/

/-- **An eligible holding is active.**
Given an output the consumer predicate accepts, that the evidence establishes
as the one holder of the representative asset, with no history of the
identifier's registry through the asked point or one that admits the
identifier's key active.
When the reader answers.
Then the answer is active. -/
theorem eligible_holder_is_active (i : Interpretation) (c : Context) (ev : Evidence)
    (p : Params) (now : Slot) (o : AH.ObservedOutput)
    (eligible : consumableHolding i c ev.environment p now o) (holders : HoldersAt i c ev [o])
    (allows : HistoryAllowsHolder i c ev) : classify i c ev = .active := by
  obtain ⟨network, release, resolved, credential, quantity, l, datum, _⟩ :=
    (consumableHolding_exact i c ev.environment p now o).mp eligible
  exact (active_iff i c ev).mpr ⟨⟨network, release, resolved⟩,
    ⟨o, l, holders, credential, quantity, datum⟩, allows⟩

/-- **An active identity may be ineligible.**
Given an authenticated context and a live checkpoint of the identifier with
state `l`.
When the consumer predicate judges that output at `now`.
Then it accepts exactly when the checkpoint is not frozen, not poisoned and at
least the juvenility window old. A young, a frozen and a poisoned checkpoint
are each an active identity the consumer refuses. -/
theorem active_holder_eligibility (i : Interpretation) (c : Context) (e : Environment)
    (p : Params) (now : Slot) (o : AH.ObservedOutput) (l : Live)
    (context : authenticatedContext c e) (live : LiveCheckpoint i c o l) :
    consumableHolding i c e p now o ↔
      l.frozen = false ∧ l.poisoned = false ∧ l.bornAt + p.W ≤ now := by
  obtain ⟨credential, quantity, datum⟩ := live
  simp [consumableHolding, context, credential, quantity, datum, consumableState]

/-- **A pending-termination or terminal identity never satisfies the consumer
predicate, at the outputs the evidence shows.**
Given evidence answered pending termination or terminal, and the holders it
establishes.
When the consumer predicate judges any of those holders at any time.
Then it refuses, as a proposition and as a Boolean. -/
theorem pending_or_terminal_holder_refused (i : Interpretation) (c : Context) (ev : Evidence)
    (p : Params) (now : Slot) (holders : List AH.ObservedOutput)
    (status : classify i c ev = .pendingTermination ∨ classify i c ev = .terminal)
    (established : HoldersAt i c ev holders) :
    ∀ o ∈ holders, ¬ consumableHolding i c ev.environment p now o ∧
      consumableHoldingB i c ev.environment p now o = false := by
  intro o member
  have refused : ¬ consumableHolding i c ev.environment p now o := by
    intro eligible
    obtain ⟨_, _, _, _, _, l, datum, _⟩ :=
      (consumableHolding_exact i c ev.environment p now o).mp eligible
    rcases status with pending | terminal
    · obtain ⟨_, ⟨o', single, form⟩, _⟩ := (pendingTermination_iff i c ev).mp pending
      cases holdersAt_unique i c ev _ _ established single
      cases List.mem_singleton.mp member
      rcases form with ⟨h, convicted⟩ | request
      · have := convicted.2.2.symm.trans datum
        simp at this
      · have form := request_has_no_checkpoint_form i c o request
        rw [(checkpointCustody_eq_some_iff i c o (.live l)).mpr
          (Or.inl ⟨l, rfl, ‹_›, ‹_›, datum⟩)] at form
        contradiction
    · have none := ((terminal_iff i c ev).mp terminal).2.2 holders established
      subst none
      contradiction
  exact ⟨refused, Bool.eq_false_iff.mpr fun accepted =>
    refused ((consumableHoldingB_iff i c ev.environment p now o).mp accepted)⟩

/-! ## The replay follows the registry's folds -/

/-- **A replayed leaf is unknown, active or terminal.**
Given a history the replay accepts and a key.
When the key's leaf is read in the replayed members.
Then it is never the known absent leaf, which no registration and no
termination writes. -/
theorem replayed_leaf_never_absent (folds : List (List KeyChange))
    (members : Singular.Trie) (key : Singular.Key) (replayed : replay folds = some members) :
    Singular.trieGet members key ≠ .known .absent := by
  have flat := ((replayFrom_iff folds [] members).mp replayed).2
  have kept : ∀ (changes : List KeyChange) (start next : Singular.Trie),
      changes.foldlM applyChange start = some next →
      Singular.trieGet start key ≠ .known .absent → Singular.trieGet next key ≠ .known .absent := by
    intro changes
    induction changes with
    | nil =>
      intro start next applied
      simp only [List.foldlM_nil, Option.pure_def, Option.some.injEq] at applied
      subst applied
      exact id
    | cons change rest ih =>
      intro start next applied present
      simp only [List.foldlM_cons, Option.bind_eq_bind] at applied
      cases first : applyChange start change with
      | none => simp [first] at applied
      | some middle =>
        simp only [first, Option.bind_some] at applied
        apply ih middle next applied
        by_cases same : change.key = key
        · cases change with
          | register changeKey =>
            simp only [KeyChange.key] at same
            subst same
            obtain ⟨_, target⟩ := (applyChange_exact start middle _).mp first
            rw [target, Singular.trieGet_set_eq]
            simp
          | terminate changeKey =>
            simp only [KeyChange.key] at same
            subst same
            obtain ⟨_, target⟩ := (applyChange_exact start middle _).mp first
            rw [target, Singular.trieGet_set_eq]
            simp
        · rw [applyChange_frame start middle change key first same]
          exact present
  exact kept folds.flatten [] members flat (by simp [Singular.trieGet])

/-- Given a history the replay accepts and one more fold; when the longer
history is replayed; then it is the replay of the shorter one followed by the
changes of the new fold. -/
theorem replay_append (folds : List (List KeyChange)) (changes : List KeyChange) :
    replay (folds ++ [changes]) = (replay folds).bind fun members => applyFold members changes := by
  simp [replay, replayFrom, List.foldlM_append]

/-- Given an accepted change of the registry's fold; when the replay applies
what it reads of that change to the same members; then it gives the same
successor. -/
theorem applyChange_of_accepted (hash : AH.Hash) (code : AH.Codec) (release : AH.PublishedRelease)
    (members next : Singular.Trie) (change : SingularApplicationHeld.Change)
    (observation : SingularApplicationHeld.FoldObservation)
    (accepted : SingularApplicationHeld.change .none hash code release members change observation
      = .ok next) : applyChange members (KeyChange.of change) = some next := by
  have target := SingularApplicationHeld.Proofs.change_success hash code release members next
    change observation accepted
  have law := SingularApplicationHeld.HistoryProofs.change_key_law hash code release members next
    change observation accepted
  rw [applyChange_exact]
  cases change <;> exact ⟨law.1, target⟩

/-- Given an accepted batch of changes of the registry's fold; when the replay
applies what it reads of them in order; then it gives the same members. -/
theorem applyChanges_of_accepted (hash : AH.Hash) (code : AH.Codec) (release : AH.PublishedRelease)
    (observation : SingularApplicationHeld.FoldObservation)
    (changes : List SingularApplicationHeld.Change) (members next : Singular.Trie)
    (accepted : changes.foldlM (fun trie change =>
      SingularApplicationHeld.change .none hash code release trie change observation) members
      = .ok next) : (changes.map KeyChange.of).foldlM applyChange members = some next := by
  induction changes generalizing members with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at accepted
    simp [accepted]
  | cons change rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at accepted
    cases first : SingularApplicationHeld.change .none hash code release members change observation with
    | error why => simp [first] at accepted
    | ok middle =>
      simp only [first] at accepted
      simp only [List.map_cons, List.foldlM_cons, Option.bind_eq_bind,
        applyChange_of_accepted hash code release members middle change observation first,
        Option.bind_some]
      exact ih middle accepted

/-- **The replay follows the registry's fold.**
Given a fold the public registry accepts.
When the replay applies what it reads of the fold's changes to the registry's
members before it.
Then it gives the registry's members after it. -/
theorem applyFold_of_accepted (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (observation : SingularApplicationHeld.FoldObservation)
    (accepted : SingularApplicationHeld.fold .none hash code commit release observation = true) :
    applyFold observation.before.trie (observation.changes.map KeyChange.of) =
      some observation.after.trie := by
  have result := (SingularApplicationHeld.Proofs.fold_result hash code commit release observation
    accepted).1
  have conditions := accepted
  simp only [SingularApplicationHeld.fold, SingularApplicationHeld.Proofs.applyGuard_none,
    Bool.and_eq_true] at conditions
  have nonempty : observation.changes.isEmpty = false := by
    simpa using conditions.1.1.1.1.1.1.1.1.2
  unfold applyFold
  rw [if_neg (by simp [nonempty])]
  exact applyChanges_of_accepted hash code release observation observation.changes
    observation.before.trie observation.after.trie result

/-! ## The registry's folds along its history -/

/-- A registry identity compares equal to itself. -/
theorem tokenId_beq_self (a : Singular.TokenId) : (a == a) = true := by
  cases a; simp [BEq.beq, Singular.instBEqTokenId.beq]

/-- Given a fold the public registry accepts; when the registry's identity is
read after it; then it is the identity before it. -/
theorem fold_keeps_identity (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (observation : SingularApplicationHeld.FoldObservation)
    (accepted : SingularApplicationHeld.fold .none hash code commit release observation = true) :
    observation.after.identity = observation.before.identity := by
  have conditions := accepted
  simp only [SingularApplicationHeld.fold, SingularApplicationHeld.Proofs.applyGuard_none,
    Bool.and_eq_true] at conditions
  exact SingularApplicationHeld.Proofs.token_eq _ _ conditions.1.1.1.1.1.1.1.1.1.1.1.2

/-- Given the folds of a registry along a history; when the history is read
without them; then it is a reachable history of the public registry model. -/
theorem registryFolds_reachable (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) (world : SingularApplicationHeld.CandidateWorld)
    (folds : List (List KeyChange))
    (history : RegistryFolds hash code commit release identity world folds) :
    SingularApplicationHeld.CandidateReachable hash code commit release world := by
  induction history with
  | initial outputs unique noOwnAssets => exact .initial outputs unique noOwnAssets
  | genesis _ seed view inputs outputs registry fee donation ledger accepted created seedBinding
      statePresent recognized emptyTrie newRegistry registries domain ih =>
    exact .genesis ih seed view inputs outputs registry fee donation ledger accepted created
      seedBinding statePresent recognized emptyTrie newRegistry registries domain
  | fold _ observation ledger present accepted registries domain ih =>
    exact .fold ih observation ledger present accepted registries domain
  | neutral _ view inputs outputs fee donation ledger noOwnMint stateUntouched registries domain ih =>
    exact .neutral ih view inputs outputs fee donation ledger noOwnMint stateUntouched registries
      domain

/-- Given a reachable history of the public registry model and any registry
identity; when the registry's folds along the history are asked for; then
there is such a list: the relation adds the folds to the history and removes
no history. -/
theorem reachable_has_registryFolds (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) (world : SingularApplicationHeld.CandidateWorld)
    (reachable : SingularApplicationHeld.CandidateReachable hash code commit release world) :
    ∃ folds, RegistryFolds hash code commit release identity world folds := by
  induction reachable with
  | initial outputs unique noOwnAssets => exact ⟨[], .initial outputs unique noOwnAssets⟩
  | genesis _ seed view inputs outputs registry fee donation ledger accepted created seedBinding
      statePresent recognized emptyTrie newRegistry registries domain ih =>
    obtain ⟨folds, history⟩ := ih
    exact ⟨folds, .genesis history seed view inputs outputs registry fee donation ledger accepted
      created seedBinding statePresent recognized emptyTrie newRegistry registries domain⟩
  | fold _ observation ledger present accepted registries domain ih =>
    obtain ⟨folds, history⟩ := ih
    exact ⟨_, .fold history observation ledger present accepted registries domain⟩
  | neutral _ view inputs outputs fee donation ledger noOwnMint stateUntouched registries domain ih =>
    obtain ⟨folds, history⟩ := ih
    exact ⟨folds, .neutral history view inputs outputs fee donation ledger noOwnMint stateUntouched
      registries domain⟩

/-- Given the folds of a registry along a history in whose world the registry
does not exist; when they are read; then there are none: a registry has no
fold before its creation. -/
theorem no_folds_before_creation (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) (world : SingularApplicationHeld.CandidateWorld)
    (folds : List (List KeyChange))
    (history : RegistryFolds hash code commit release identity world folds)
    (absent : identity ∉ world.registries.map (·.identity)) : folds = [] := by
  induction history with
  | initial => rfl
  | genesis _ seed view inputs outputs registry fee donation ledger accepted created seedBinding
      statePresent recognized emptyTrie newRegistry registries domain ih =>
    apply ih
    intro member
    apply absent
    rw [registries, List.map_append]
    exact List.mem_append_left _ member
  | @fold before after folds _ observation ledger present accepted registries domain ih =>
    have afterIdentity := fold_keeps_identity hash code commit release observation accepted
    have same : after.registries.map (·.identity) = before.registries.map (·.identity) := by
      rw [registries, List.map_map]
      apply List.map_congr_left
      intro registry _
      simp only [Function.comp_apply]
      split
      · rename_i hit
        exact afterIdentity.trans (SingularApplicationHeld.Proofs.token_eq _ _ hit).symm
      · rfl
    rw [same] at absent
    have other : observation.before.identity ≠ identity := fun equal =>
      absent (List.mem_map.mpr ⟨observation.before, present, equal⟩)
    rw [if_neg other]
    exact ih absent
  | neutral _ view inputs outputs fee donation ledger noOwnMint stateUntouched registries domain ih =>
    rw [registries] at absent
    exact ih absent

/-- **Replaying a registry's folds gives the registry's members.**
Given the folds of a registry along a history of the public registry model.
When they are replayed from no member.
Then the replay succeeds and gives exactly the members of that registry in
the history's world. -/
theorem registry_members_are_replayed (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) (world : SingularApplicationHeld.CandidateWorld)
    (folds : List (List KeyChange))
    (history : RegistryFolds hash code commit release identity world folds) :
    ∀ registry ∈ world.registries, registry.identity = identity →
      replay folds = some registry.trie := by
  induction history with
  | initial =>
    intro registry member
    simp at member
  | @genesis before after folds previous seed view inputs outputs registry fee donation ledger
      accepted created seedBinding statePresent recognized emptyTrie newRegistry registries domain ih =>
    intro candidate member named
    rw [registries] at member
    rcases List.mem_append.mp member with old | added
    · exact ih candidate old named
    · have same : candidate = registry := by simpa using added
      subst same
      have none := no_folds_before_creation hash code commit release identity before folds previous
        (named ▸ newRegistry)
      rw [none, emptyTrie]
      rfl
  | @fold before after folds previous observation ledger present accepted registries domain ih =>
    intro candidate member named
    rw [registries] at member
    obtain ⟨earlier, earlierMember, same⟩ := List.mem_map.mp member
    have afterIdentity := fold_keeps_identity hash code commit release observation accepted
    by_cases hit : (earlier.identity == observation.before.identity) = true
    · simp only [hit, ↓reduceIte] at same
      subst same
      have this : observation.before.identity = identity := afterIdentity.symm.trans named
      rw [if_pos this, replay_append, ih observation.before present this]
      exact applyFold_of_accepted hash code commit release observation accepted
    · simp only [hit, Bool.false_eq_true, ↓reduceIte] at same
      subst same
      have other : observation.before.identity ≠ identity := by
        intro equal
        apply hit
        rw [named, equal]
        exact tokenId_beq_self identity
      rw [if_neg other]
      exact ih earlier earlierMember named
  | neutral _ view inputs outputs fee donation ledger noOwnMint stateUntouched registries domain ih =>
    intro candidate member named
    rw [registries] at member
    exact ih candidate member named

/-- **The replayed leaf is the registry's leaf.**
Given a world of the registry's history, the context's registry in it, and
evidence faithful to the world.
When the evidence establishes a leaf for the identifier's key by replaying
its history.
Then that leaf is the leaf of the key in the registry. -/
theorem replayed_leaf_is_registry_leaf (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry) (ev : Evidence) (leaf : Singular.Leaf)
    (faithful : FaithfulHistory i c commit world ev) (member : registry ∈ world.registries)
    (named : registry.identity = registryAsset i c) (established : LeafAt i c ev leaf) :
    leaf = Singular.trieGet registry.trie (i.keyOf c.aid) := by
  obtain ⟨h, members, found, point, registryOf, complete, replayed, read⟩ := established
  obtain ⟨_, folds⟩ := faithful h found point registryOf complete
  have actual := registry_members_are_replayed i.hash i.code commit c.release (registryAsset i c)
    world h.folds folds registry member named
  rw [replayed] at actual
  cases actual
  exact read.symm

/-- **A complete faithful history always establishes the leaf.**
Given evidence faithful to a world that holds a complete history of the
identifier's registry through the asked point.
When the history is replayed.
Then the registry exists in the world, the replay succeeds, and the evidence
establishes the leaf of the identifier's key in that registry. -/
theorem complete_history_establishes_the_leaf (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (ev : Evidence) (h : HistoryObservation) (faithful : FaithfulHistory i c commit world ev)
    (found : ev.history = some h) (point : h.point = ev.point)
    (registryOf : h.registry = registryAsset i c) (complete : h.complete = true) :
    ∃ registry ∈ world.registries, registry.identity = registryAsset i c ∧
      LeafAt i c ev (Singular.trieGet registry.trie (i.keyOf c.aid)) := by
  obtain ⟨exists_, folds⟩ := faithful h found point registryOf complete
  obtain ⟨registry, member, named⟩ := List.mem_map.mp exists_
  have actual := registry_members_are_replayed i.hash i.code commit c.release (registryAsset i c)
    world h.folds folds registry member named
  exact ⟨registry, member, named, h, registry.trie, found, point, registryOf, complete, actual, rfl⟩

/-! ## Soundness against the registry's history

The public registry's history model has the complete unspent set and every
registry's leaves, and proves that the supply of a key's active asset is one
exactly while the key's leaf is active
(`SingularApplicationHeld.HistoryStatements.supply_in_step`). The premises of
that theorem are the premises here, each named in every statement: a
reachable world, the context's registry in it, and the two identity
assumptions the consumer statements already take, a faithful finite encoding
(`FiniteEncoding`) and collision freedom (`FiniteCollisionFree`), over the
preimages the history holds and the identifier's active preimage
(`historyDomain`). Without them two keys could share an asset name, and no
count of holders would say anything about a leaf. -/

/-- Given a list and a count per element whose total is zero; when the
elements with a positive count are selected; then there are none. -/
theorem no_positive_of_sum_zero {α : Type} (xs : List α) (f : α → Nat)
    (zero : (xs.map f).sum = 0) : xs.filter (fun x => decide (0 < f x)) = [] := by
  induction xs with
  | nil => rfl
  | cons x rest ih =>
    simp only [List.map_cons, List.sum_cons] at zero
    have head : f x = 0 := by omega
    have tail : (rest.map f).sum = 0 := by omega
    simp [head, ih tail]

/-- Given a list and a count per element whose total is one; when the elements
with a positive count are selected; then there is exactly one, with count one. -/
theorem single_positive_of_sum_one {α : Type} (xs : List α) (f : α → Nat)
    (one : (xs.map f).sum = 1) :
    ∃ x, xs.filter (fun x => decide (0 < f x)) = [x] ∧ f x = 1 := by
  induction xs with
  | nil => simp at one
  | cons x rest ih =>
    simp only [List.map_cons, List.sum_cons] at one
    by_cases head : f x = 0
    · obtain ⟨y, selected, count⟩ := ih (by omega)
      exact ⟨y, by simp [head, selected], count⟩
    · have exact : f x = 1 := by omega
      have none := no_positive_of_sum_zero rest f (by omega)
      exact ⟨x, by simp [exact, none], exact⟩

/-- Given a world; when an output is among the holders of the identifier's
representative asset; then it is unspent in the world and holds a positive
quantity of the asset, and conversely. -/
theorem mem_holdersIn (i : Interpretation) (c : Context)
    (world : SingularApplicationHeld.CandidateWorld) (o : AH.ObservedOutput) :
    o ∈ holdersIn i c world ↔
      o ∈ world.unspent ∧ 0 < AH.quantity o (representativeAsset i c) := by
  simp [holdersIn]

/-- Given a termination request of the identifier's key; when its assets are
read; then it holds a positive quantity of the representative asset. -/
theorem request_holds_asset (i : Interpretation) (c : Context) (o : AH.ObservedOutput)
    (request : TerminationRequest i c o) : 0 < AH.quantity o (representativeAsset i c) := by
  unfold TerminationRequest SingularApplicationHeld.terminationShape at request
  have unflipped : (SingularApplicationHeld.AppMutation.none ==
      SingularApplicationHeld.AppMutation.flip .terminationShape) = false := rfl
  simp only [SingularApplicationHeld.appGuard, unflipped, Bool.false_eq_true, ↓reduceIte,
    Bool.and_eq_true] at request
  have assets := request.2
  unfold SingularApplicationHeld.exactAssets at assets
  have each := List.all_eq_true.mp assets (representativeAsset i c)
    (by simp [representativeAsset])
  by_cases same : (SingularApplicationHeld.terminationApproval i.hash i.code c.release
      (registryAsset i c) (i.keyOf c.aid) == representativeAsset i c) = true
  all_goals
    simp [representativeAsset] at each same
    simp [representativeAsset, same] at each ⊢
    omega

/-- **The supply follows the leaf.**
Given a reachable world of the registry's history, the context's registry in
it and the history's finite encoding and collision premises.
When the unspent outputs holding the identifier's representative asset are
listed.
Then an active leaf has exactly one holder, holding the asset exactly once,
and every other leaf (unknown, terminal) has none. A missing token therefore
fits a key that was never registered and a key that is terminal alike. -/
theorem holders_follow_leaf (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) :
    (Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active →
      ∃ o, holdersIn i c world = [o] ∧ AH.quantity o (representativeAsset i c) = 1) ∧
    (Singular.trieGet registry.trie (i.keyOf c.aid) ≠ .known .active →
      holdersIn i c world = []) := by
  have supply := SingularApplicationHeld.HistoryStatements.supply_in_step i.hash i.code commit
    c.release world registry (i.keyOf c.aid) ⟨reachable, member, encoding, collision⟩
  unfold SingularApplicationHeld.SupplyAt SingularApplicationHeld.liveActiveCount at supply
  rw [named] at supply
  constructor
  · intro active
    rw [if_pos active] at supply
    exact single_positive_of_sum_one world.unspent _ supply
  · intro inactive
    rw [if_neg inactive] at supply
    exact no_positive_of_sum_zero world.unspent _ supply

/-- **A status is never wrong.**
Given a world of the registry's history, the context's registry in it and
evidence faithful to the world.
When the reader answers a status other than unavailable.
Then the world warrants that status: an unspent live checkpoint for active,
an unspent convicted checkpoint or termination request for pending
termination, the terminal leaf for terminal, the unknown leaf for never
registered. -/
theorem status_is_warranted (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry) (ev : Evidence) (status : Status)
    (member : registry ∈ world.registries) (named : registry.identity = registryAsset i c)
    (faithful : Faithful i c commit world ev) (answer : classify i c ev = status)
    (available : status ≠ .unavailable) : Warrants i c world registry status := by
  have leafOf := replayed_leaf_is_registry_leaf i c commit world registry ev
  have unspent : ∀ o, HoldersAt i c ev [o] → o ∈ world.unspent := fun o holders =>
    ((mem_holdersIn i c world o).mp (faithful.holders _ holders ▸ List.mem_singleton.mpr rfl)).1
  cases classify_decides i c ev status answer available with
  | active _ holders live _ => exact ⟨_, _, unspent _ holders, live⟩
  | convicted _ holders convicted _ => exact ⟨_, unspent _ holders, Or.inl ⟨_, convicted⟩⟩
  | requested _ holders request _ => exact ⟨_, unspent _ holders, Or.inr request⟩
  | terminal _ leaf _ => exact (leafOf _ faithful.history member named leaf).symm
  | neverRegistered _ leaf _ => exact (leafOf _ faithful.history member named leaf).symm

/-- Given a reachable world and an unspent output that holds a positive
quantity of the identifier's representative asset; when the leaf and the
holders are read; then the leaf is active and that output is the only holder. -/
theorem holder_is_the_only_one (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (o : AH.ObservedOutput)
    (unspent : o ∈ world.unspent) (held : 0 < AH.quantity o (representativeAsset i c)) :
    Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active ∧
      holdersIn i c world = [o] := by
  have census := holders_follow_leaf i c commit world registry reachable member encoding collision named
  have member := (mem_holdersIn i c world o).mpr ⟨unspent, held⟩
  have active : Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active := by
    apply Classical.byContradiction
    intro inactive
    rw [census.2 inactive] at member
    contradiction
  obtain ⟨only, single, _⟩ := census.1 active
  rw [single] at member
  rw [single, List.mem_singleton.mp member]
  exact ⟨active, rfl⟩

/-- **A holder decides alone.**
Given a reachable world of the registry's history, the context's registry in
it, a faithful finite encoding and collision freedom over the history's
preimages and the identifier's active preimage, and evidence whose
established holders are the world's holders, whatever its history: missing,
incomplete, of another point, or not the registry's at all.
When the reader answers active or pending termination.
Then the registry's leaf of the identifier's key is active, and the holder
the answer names is unspent in the world and is the only output holding the
asset. The holder alone warrants the answer: the asset exists only while the
leaf is active. -/
theorem holder_decides_alone (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (ev : Evidence)
    (faithful : FaithfulHolders i c world ev)
    (answer : classify i c ev = .active ∨ classify i c ev = .pendingTermination) :
    Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active ∧
    ∃ o, holder i c ev = some o ∧ o ∈ world.unspent ∧ holdersIn i c world = [o] := by
  have single : ∃ o, HoldersAt i c ev [o] ∧ 0 < AH.quantity o (representativeAsset i c) := by
    rcases answer with active | pending
    · obtain ⟨_, ⟨o, l, holders, live⟩, _⟩ := (active_iff i c ev).mp active
      exact ⟨o, holders, by rw [live.2.1]; decide⟩
    · obtain ⟨_, ⟨o, holders, form⟩, _⟩ := (pendingTermination_iff i c ev).mp pending
      refine ⟨o, holders, ?_⟩
      rcases form with ⟨h, convicted⟩ | request
      · rw [convicted.2.1]; decide
      · exact request_holds_asset i c o request
  obtain ⟨o, holders, held⟩ := single
  have unspent : o ∈ world.unspent :=
    ((mem_holdersIn i c world o).mp (faithful _ holders ▸ List.mem_singleton.mpr rfl)).1
  obtain ⟨active, only⟩ := holder_is_the_only_one i c commit world registry reachable member
    encoding collision named o unspent held
  exact ⟨active, o, (holder_eq_some_iff i c ev o).mpr ⟨answer, holders⟩, unspent, only⟩

/-- **A complete history decides alone.**
Given a reachable world of the registry's history, the context's registry in
it, a faithful finite encoding and collision freedom over the history's
preimages and the identifier's active preimage, and evidence whose complete
history is the registry's history in the world, whatever its holding
observation: missing, failed, or of another point.
When the reader answers terminal or never registered.
Then the registry's leaf of the identifier's key is terminal, or unknown,
as answered, and no unspent output of the world holds the asset. The history
alone warrants the answer. -/
theorem history_decides_alone (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (ev : Evidence)
    (faithful : FaithfulHistory i c commit world ev)
    (answer : classify i c ev = .terminal ∨ classify i c ev = .neverRegistered) :
    holdersIn i c world = [] ∧
    (classify i c ev = .terminal →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .known .terminal) ∧
    (classify i c ev = .neverRegistered →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .unknown) := by
  have census := holders_follow_leaf i c commit world registry reachable member encoding collision
    named
  have leafOf := replayed_leaf_is_registry_leaf i c commit world registry ev
  have terminal : classify i c ev = .terminal →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .known .terminal := fun status =>
    (leafOf _ faithful member named ((terminal_iff i c ev).mp status).2.1).symm
  have unknown : classify i c ev = .neverRegistered →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .unknown := fun status =>
    (leafOf _ faithful member named ((neverRegistered_iff i c ev).mp status).2.1).symm
  refine ⟨?_, terminal, unknown⟩
  apply census.2
  rcases answer with status | status
  · rw [terminal status]; simp
  · rw [unknown status]; simp

/-- **The four statuses exclude one another on reachable states.**
Given a reachable world of the registry's history, the context's registry in
it, and the model's two identity assumptions over the history's preimages and
the identifier's active preimage: a faithful finite encoding and collision
freedom. Both are named in the statement; without them a world can warrant
two statuses, because two keys can share an asset name.
When the world warrants two statuses.
Then they are the same status. -/
theorem warrants_exclusive (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (s t : Status)
    (first : Warrants i c world registry s) (second : Warrants i c world registry t) : s = t := by
  have only := holder_is_the_only_one i c commit world registry reachable member encoding collision named
  -- The facts each status rests on, as the leaf and the holders they force.
  have live : Warrants i c world registry .active →
      ∃ o l, LiveCheckpoint i c o l ∧ holdersIn i c world = [o] ∧
        Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active := by
    rintro ⟨o, l, unspent, form⟩
    obtain ⟨active, single⟩ := only o unspent (by rw [form.2.1]; decide)
    exact ⟨o, l, form, single, active⟩
  have pending : Warrants i c world registry .pendingTermination →
      ∃ o, ((∃ h, ConvictedCheckpoint i c o h) ∨ TerminationRequest i c o) ∧
        holdersIn i c world = [o] ∧
        Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active := by
    rintro ⟨o, unspent, form⟩
    have held : 0 < AH.quantity o (representativeAsset i c) := by
      rcases form with ⟨h, convicted⟩ | request
      · rw [convicted.2.1]; decide
      · exact request_holds_asset i c o request
    obtain ⟨active, single⟩ := only o unspent held
    exact ⟨o, form, single, active⟩
  have clash : ∀ o l, LiveCheckpoint i c o l →
      ((∃ h, ConvictedCheckpoint i c o h) ∨ TerminationRequest i c o) → False := by
    rintro o l form (⟨h, convicted⟩ | request)
    · have := form.2.2.symm.trans convicted.2.2
      simp at this
    · have none := request_has_no_checkpoint_form i c o request
      rw [(checkpointCustody_eq_some_iff i c o (.live l)).mpr (Or.inl ⟨l, rfl, form⟩)] at none
      contradiction
  have liveLeaf : Warrants i c world registry .active →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active :=
    fun w => (live w).choose_spec.choose_spec.2.2
  have pendingLeaf : Warrants i c world registry .pendingTermination →
      Singular.trieGet registry.trie (i.keyOf c.aid) = .known .active :=
    fun w => (pending w).choose_spec.2.2
  have apart : Warrants i c world registry .active →
      Warrants i c world registry .pendingTermination → False := by
    intro a b
    obtain ⟨o, l, form, single, _⟩ := live a
    obtain ⟨o', other, single', _⟩ := pending b
    rw [single] at single'
    cases single'
    exact clash o l form other
  have leaves : ∀ x y : Singular.Leaf, Singular.trieGet registry.trie (i.keyOf c.aid) = x →
      Singular.trieGet registry.trie (i.keyOf c.aid) = y → x ≠ y → False :=
    fun x y a b different => different (a.symm.trans b)
  cases s with
  | active =>
    cases t with
    | active => rfl
    | pendingTermination => exact (apart first second).elim
    | terminal => exact (leaves _ _ (liveLeaf first) second (by simp)).elim
    | neverRegistered => exact (leaves _ _ (liveLeaf first) second (by simp)).elim
    | unavailable => exact absurd second id
  | pendingTermination =>
    cases t with
    | active => exact (apart second first).elim
    | pendingTermination => rfl
    | terminal => exact (leaves _ _ (pendingLeaf first) second (by simp)).elim
    | neverRegistered => exact (leaves _ _ (pendingLeaf first) second (by simp)).elim
    | unavailable => exact absurd second id
  | terminal =>
    cases t with
    | active => exact (leaves _ _ (liveLeaf second) first (by simp)).elim
    | pendingTermination => exact (leaves _ _ (pendingLeaf second) first (by simp)).elim
    | terminal => rfl
    | neverRegistered => exact (leaves _ _ first second (by simp)).elim
    | unavailable => exact absurd second id
  | neverRegistered =>
    cases t with
    | active => exact (leaves _ _ (liveLeaf second) first (by simp)).elim
    | pendingTermination => exact (leaves _ _ (pendingLeaf second) first (by simp)).elim
    | terminal => exact (leaves _ _ first second (by simp)).elim
    | neverRegistered => rfl
    | unavailable => exact absurd second id
  | unavailable => exact absurd first id

/-- **Faithful and complete evidence gets the status the state warrants.**
Given a reachable world of the registry's history, the context's registry in
it, the history's finite encoding and collision premises, an authenticated
context, and evidence faithful to the world that establishes both the holders
and the leaf at the asked point.
When the world warrants a status.
Then the reader answers that status. -/
theorem warranted_status_is_answered (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (ev : Evidence) (status : Status)
    (context : authenticatedContext c ev.environment)
    (faithful : Faithful i c commit world ev)
    (holdersSeen : ∃ holders, HoldersAt i c ev holders) (leafSeen : ∃ leaf, LeafAt i c ev leaf)
    (warranted : Warrants i c world registry status) : classify i c ev = status := by
  obtain ⟨holders, at_⟩ := holdersSeen
  obtain ⟨leaf, leafAt⟩ := leafSeen
  have holdersEq := faithful.holders _ at_
  have leafEq := replayed_leaf_is_registry_leaf i c commit world registry ev leaf
    faithful.history member named leafAt
  subst holdersEq leafEq
  have only := holder_is_the_only_one i c commit world registry reachable member encoding collision named
  have census := holders_follow_leaf i c commit world registry reachable member encoding collision named
  have allows : ∀ o, o ∈ world.unspent → 0 < AH.quantity o (representativeAsset i c) →
      HoldersAt i c ev [o] ∧ HistoryAllowsHolder i c ev := by
    intro o unspent held
    obtain ⟨active, single⟩ := only o unspent held
    exact ⟨single ▸ at_, (leaf_allows_holder_iff i c ev _ leafAt).mpr active⟩
  have unseen : Singular.trieGet registry.trie (i.keyOf c.aid) ≠ .known .active →
      NoHolderSeen i c ev := fun inactive other otherAt => by
    rw [holdersAt_unique i c ev _ _ otherAt at_, census.2 inactive]
  apply decides_classify
  cases status with
  | active =>
    obtain ⟨o, l, unspent, form⟩ := warranted
    obtain ⟨single, leafOk⟩ := allows o unspent (by rw [form.2.1]; decide)
    exact .active context single form leafOk
  | pendingTermination =>
    obtain ⟨o, unspent, ⟨h, convicted⟩ | request⟩ := warranted
    · obtain ⟨single, leafOk⟩ := allows o unspent (by rw [convicted.2.1]; decide)
      exact .convicted context single convicted leafOk
    · obtain ⟨single, leafOk⟩ := allows o unspent (request_holds_asset i c o request)
      exact .requested context single request leafOk
  | terminal =>
    have terminal : Singular.trieGet registry.trie (i.keyOf c.aid) = .known .terminal := warranted
    exact .terminal context (terminal ▸ leafAt) (unseen (by rw [terminal]; simp))
  | neverRegistered =>
    have unknown : Singular.trieGet registry.trie (i.keyOf c.aid) = .unknown := warranted
    exact .neverRegistered context (unknown ▸ leafAt) (unseen (by rw [unknown]; simp))
  | unavailable => exact absurd warranted id

/-- **A pending-termination or terminal identity never satisfies the consumer
predicate.**
Given a reachable world of the registry's history, the context's registry in
it and the history's finite encoding and collision premises, where the world
warrants pending termination or terminal.
When the consumer predicate judges any unspent output of that world, under
any environment and parameters, at any time.
Then it refuses, as a proposition and as a Boolean. -/
theorem pending_or_terminal_never_consumable (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release world)
    (member : registry ∈ world.registries)
    (encoding : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain world registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c) (e : Environment) (p : Params) (now : Slot)
    (warranted : Warrants i c world registry .pendingTermination ∨
      Warrants i c world registry .terminal) :
    ∀ o ∈ world.unspent, ¬ consumableHolding i c e p now o ∧
      consumableHoldingB i c e p now o = false := by
  intro o unspent
  have refused : ¬ consumableHolding i c e p now o := by
    intro eligible
    obtain ⟨_, _, _, credential, quantity, l, datum, _⟩ :=
      (consumableHolding_exact i c e p now o).mp eligible
    have live : Warrants i c world registry .active := ⟨o, l, unspent, credential, quantity, datum⟩
    rcases warranted with pending | terminal
    · cases warrants_exclusive i c commit world registry reachable member encoding collision named _ _ live pending
    · cases warrants_exclusive i c commit world registry reachable member encoding collision named _ _ live terminal
  exact ⟨refused, Bool.eq_false_iff.mpr fun accepted =>
    refused ((consumableHoldingB_iff i c e p now o).mp accepted)⟩

/-- **A burn of the identifier's asset is the terminating fold of its registry
and key.**
Given a reachable world of the registry's history, its next transaction (a
genesis, a fold or an application-only transaction), the context's registry
in the world before, the finite encoding and collision premises before and
after, and that the transaction burns the identifier's representative asset.
When the transaction is read.
Then it is a fold of the context's registry that terminates the identifier's
key, and the key's leaf after it is terminal. The terminal leaf is what
records the termination; no other transaction burns the asset. -/
theorem burn_is_the_terminating_fold (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit)
    (before after : SingularApplicationHeld.CandidateWorld)
    (view : SingularApplicationHeld.Assets.TxView)
    (folded : Option SingularApplicationHeld.FoldObservation)
    (registry : SingularApplicationHeld.PublicRegistry)
    (transaction : SingularApplicationHeld.HistoryTransaction i.hash i.code commit c.release
      before after view folded)
    (reachable : SingularApplicationHeld.CandidateReachable i.hash i.code commit c.release before)
    (member : registry ∈ before.registries)
    (encodingBefore : AH.FiniteEncoding i.code
      (SingularApplicationHeld.historyDomain before registry (i.keyOf c.aid)))
    (collisionBefore : AH.FiniteCollisionFree i.hash i.code
      (SingularApplicationHeld.historyDomain before registry (i.keyOf c.aid)))
    (named : registry.identity = registryAsset i c)
    (encoding : AH.FiniteEncoding i.code
      (after.domain ++ [.active registry.identity (i.keyOf c.aid)]))
    (collision : AH.FiniteCollisionFree i.hash i.code
      (after.domain ++ [.active registry.identity (i.keyOf c.aid)]))
    (burn : SingularApplicationHeld.Assets.mintQty view (representativeAsset i c) < 0) :
    ∃ o, folded = some o ∧ registryAsset i c = o.before.identity ∧
      (∃ reference, SingularApplicationHeld.Change.terminate reference (i.keyOf c.aid) ∈
        o.changes) ∧
      Singular.trieGet o.after.trie (i.keyOf c.aid) = .known .terminal := by
  have upstream := SingularApplicationHeld.HistoryStatements.burn_only_terminating_fold i.hash
    i.code commit c.release before after view folded registry (i.keyOf c.aid)
    ⟨transaction, ⟨reachable, member, encodingBefore, collisionBefore⟩, encoding, collision,
      by rw [named]; exact burn⟩
  rw [named] at upstream
  exact upstream

/-! ## Soundness against the checkpoint system

The checkpoint system has the lifecycle state of every identifier: absent,
live, pending termination, convicted. Evidence realizes a system when its
holders realize the identifier's state and its leaf is the identifier's leaf
(`Realizes`). In a reachable system the leaf agrees with the state
(`T8_leaf_agrees_with_state`), so realized evidence never contradicts itself. -/

/-- Given a checkpoint output that realizes a live state; when its form is
read; then it is a live checkpoint of the identifier whose datum facts are
that state's. -/
theorem realized_present_is_live (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (l : Live) (o : AH.ObservedOutput)
    (realized : realizesState i c p rp (.present l) o) :
    ∃ l', LiveCheckpoint i c o l' ∧ { l' with pool := 0 } = { l with pool := 0 } := by
  obtain ⟨credential, quantity, datum, _⟩ := realized
  obtain ⟨⟨aid, st⟩, found, facts⟩ := Option.map_eq_some_iff.mp datum
  simp only [DecodedDatum.facts, DecodedDatum.mk.injEq] at facts
  obtain ⟨rfl, state⟩ := facts
  cases st with
  | present l' =>
    simp only [State.datumFacts, State.present.injEq] at state
    exact ⟨l', ⟨credential, by simpa [State.representativeHeld, State.hasOutput] using quantity,
      found⟩, state⟩
  | absent | terminationPending _ | convicted => simp [State.datumFacts] at state

/-- Given a checkpoint output that realizes a pending-termination state; when
its form is read; then it is the convicted checkpoint of the identifier with
that state's key state. -/
theorem realized_pending_is_convicted (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (h : Hash) (o : AH.ObservedOutput)
    (realized : realizesState i c p rp (.terminationPending h) o) :
    ConvictedCheckpoint i c o h := by
  obtain ⟨credential, quantity, datum, _⟩ := realized
  obtain ⟨⟨aid, st⟩, found, facts⟩ := Option.map_eq_some_iff.mp datum
  simp only [DecodedDatum.facts, DecodedDatum.mk.injEq] at facts
  obtain ⟨rfl, state⟩ := facts
  cases st with
  | terminationPending h' =>
    simp only [State.datumFacts, State.terminationPending.injEq] at state
    subst state
    exact ⟨credential, by simpa [State.representativeHeld, State.hasOutput] using quantity, found⟩
  | absent | present _ | convicted => simp [State.datumFacts] at state

/-- **A status never contradicts the lifecycle.**
Given a reachable checkpoint system and evidence that realizes it at the
context's identifier.
When the reader answers a status other than unavailable.
Then it is the status of the identifier's lifecycle state: never registered
for absent, active for live, pending termination for pending termination,
terminal for convicted. -/
theorem status_follows_lifecycle (i : Interpretation) (c : Context) (p : Params) (env : SystemEnv)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (ev : Evidence) (status : Status)
    (reach : SysReach p env s) (realizes : Realizes i c p rp s ev)
    (answer : classify i c ev = status) (available : status ≠ .unavailable) :
    status = lifecycleStatus (s.states c.aid) := by
  have agrees := T8_leaf_agrees_with_state p env reach c.aid
  have ofLeaf : ∀ leaf, LeafAt i c ev leaf → leaf = registryLeaf (s.states c.aid).leaf :=
    fun leaf at_ => agrees ▸ realizes.leaf leaf at_
  have clash : ∀ o l, LiveCheckpoint i c o l →
      ((∃ h, ConvictedCheckpoint i c o h) ∨ TerminationRequest i c o) → False := by
    rintro o l form (⟨h, convicted⟩ | request)
    · have := form.2.2.symm.trans convicted.2.2
      simp at this
    · have none := request_has_no_checkpoint_form i c o request
      rw [(checkpointCustody_eq_some_iff i c o (.live l)).mpr (Or.inl ⟨l, rfl, form⟩)] at none
      contradiction
  have single : ∀ o, HoldersAt i c ev [o] →
      (∃ l, s.states c.aid = .present l ∧ ∃ l', LiveCheckpoint i c o l') ∨
      (∃ h, s.states c.aid = .terminationPending h ∧
        ((∃ k, ConvictedCheckpoint i c o k) ∨ TerminationRequest i c o)) := by
    intro o holders
    have realized := realizes.holders _ holders
    unfold holdersRealize at realized
    cases state : s.states c.aid with
    | absent => simp [state] at realized
    | convicted => simp [state] at realized
    | present l =>
      simp only [state] at realized
      obtain ⟨o', same, form⟩ := realized
      cases same
      obtain ⟨l', live, _⟩ := realized_present_is_live i c p rp l o form
      exact Or.inl ⟨l, rfl, l', live⟩
    | terminationPending h =>
      simp only [state] at realized
      obtain ⟨o', same, form⟩ := realized
      cases same
      refine Or.inr ⟨h, rfl, ?_⟩
      split at form
      · exact Or.inr form.1
      · exact Or.inl ⟨h, realized_pending_is_convicted i c p rp h o form⟩
  cases classify_decides i c ev status answer available with
  | active _ holders live _ =>
    rcases single _ holders with ⟨l, state, _⟩ | ⟨h, state, form⟩
    · simp [state, lifecycleStatus]
    · exact (clash _ _ live form).elim
  | convicted _ holders convicted _ =>
    rcases single _ holders with ⟨l, state, l', live⟩ | ⟨h, state, _⟩
    · exact (clash _ _ live (Or.inl ⟨_, convicted⟩)).elim
    · simp [state, lifecycleStatus]
  | requested _ holders request _ =>
    rcases single _ holders with ⟨l, state, l', live⟩ | ⟨h, state, _⟩
    · exact (clash _ _ live (Or.inr request)).elim
    · simp [state, lifecycleStatus]
  | terminal _ leaf _ =>
    have read := ofLeaf _ leaf
    cases state : s.states c.aid <;> simp [state, State.leaf, registryLeaf, lifecycleStatus] at read ⊢
  | neverRegistered _ leaf _ =>
    have read := ofLeaf _ leaf
    cases state : s.states c.aid <;> simp [state, State.leaf, registryLeaf, lifecycleStatus] at read ⊢

/-- **Realized and complete evidence gets the lifecycle's status.**
Given a reachable checkpoint system, an authenticated context and evidence
that realizes the system at the context's identifier and establishes both the
holders and the leaf at the asked point.
When the reader answers.
Then the answer is the status of the identifier's lifecycle state. -/
theorem lifecycle_status_is_answered (i : Interpretation) (c : Context) (p : Params) (env : SystemEnv)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (ev : Evidence)
    (reach : SysReach p env s) (realizes : Realizes i c p rp s ev)
    (context : authenticatedContext c ev.environment)
    (holdersSeen : ∃ holders, HoldersAt i c ev holders) (leafSeen : ∃ leaf, LeafAt i c ev leaf) :
    classify i c ev = lifecycleStatus (s.states c.aid) := by
  obtain ⟨holders, at_⟩ := holdersSeen
  obtain ⟨leaf, leafAt⟩ := leafSeen
  have agrees := T8_leaf_agrees_with_state p env reach c.aid
  have leafEq : leaf = registryLeaf (s.states c.aid).leaf := agrees ▸ realizes.leaf leaf leafAt
  have realized := realizes.holders _ at_
  unfold holdersRealize at realized
  have allows : (s.states c.aid).leaf = .active → HistoryAllowsHolder i c ev := by
    intro active
    refine (leaf_allows_holder_iff i c ev _ leafAt).mpr ?_
    rw [leafEq, active]
    rfl
  have unseen : holders = [] → NoHolderSeen i c ev :=
    fun empty other otherAt => (holdersAt_unique i c ev _ _ otherAt at_).trans empty
  apply decides_classify
  cases state : s.states c.aid with
  | absent =>
    simp only [state] at realized
    simp only [state, State.leaf, registryLeaf] at leafEq
    exact .neverRegistered context (leafEq ▸ leafAt) (unseen realized)
  | convicted =>
    simp only [state] at realized
    simp only [state, State.leaf, registryLeaf] at leafEq
    exact .terminal context (leafEq ▸ leafAt) (unseen realized)
  | present l =>
    simp only [state] at realized
    obtain ⟨o, rfl, form⟩ := realized
    obtain ⟨l', live, _⟩ := realized_present_is_live i c p rp l o form
    exact .active context at_ live (allows (by simp [state, State.leaf]))
  | terminationPending h =>
    simp only [state] at realized
    obtain ⟨o, rfl, form⟩ := realized
    split at form
    · exact .requested context at_ form.1 (allows (by simp [state, State.leaf]))
    · exact .convicted context at_ (realized_pending_is_convicted i c p rp h o form)
        (allows (by simp [state, State.leaf]))

/-- **The booked termination is pending termination, held by the booked
request.**
Given a reachable checkpoint system in which the identifier is pending
termination with key state `h`, an authenticated context, and evidence that
realizes the system and establishes both the holders and the leaf.
When the reader answers.
Then the answer is pending termination both before and after the termination
is booked. Before the booking the custody it reads is the convicted
checkpoint with key state `h`. After it the custody is the termination
request, and the holder the answer names is the request the booking placed:
its reference is the one the system's pending association records. -/
theorem booked_termination_is_pending (i : Interpretation) (c : Context) (p : Params) (env : SystemEnv)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (ev : Evidence) (h : Hash)
    (reach : SysReach p env s) (realizes : Realizes i c p rp s ev)
    (context : authenticatedContext c ev.environment)
    (holdersSeen : ∃ holders, HoldersAt i c ev holders) (leafSeen : ∃ leaf, LeafAt i c ev leaf)
    (state : s.states c.aid = .terminationPending h) :
    classify i c ev = .pendingTermination ∧
    (∀ association, s.pending c.aid = some association →
      holdingCustody i c ev = .request ∧
      ∃ o, holder i c ev = some o ∧ o.reference = association.reference) ∧
    (s.pending c.aid = none → holdingCustody i c ev = .convicted h) := by
  have answered := lifecycle_status_is_answered i c p env rp s ev reach realizes context
    holdersSeen leafSeen
  rw [state] at answered
  obtain ⟨holders, at_⟩ := holdersSeen
  have realized := realizes.holders _ at_
  unfold holdersRealize at realized
  simp only [state] at realized
  obtain ⟨o, rfl, form⟩ := realized
  have custody : holdingCustody i c ev = custodyOf i c o := by
    rw [holdingCustody_of_holders i c ev [o] at_, holdersCustody]
  refine ⟨answered, fun association booked => ?_, fun unbooked => ?_⟩
  · rw [booked] at form
    exact ⟨custody.trans ((custodyOf_exact i c o).2.2.1.mpr form.1), o,
      (holder_eq_some_iff i c ev o).mpr ⟨Or.inr answered, at_⟩, form.2⟩
  · rw [unbooked] at form
    exact custody.trans (((custodyOf_exact i c o).2.1 h).mpr
      (realized_pending_is_convicted i c p rp h o form))

/-- **The lifecycle refuses the consumer where the status says so.**
Given a lifecycle state whose status is pending termination or terminal.
When the lifecycle eligibility is evaluated at any time.
Then it refuses, as a proposition and as a Boolean; with
`existing_eligibility_preserved`, so does the consumer predicate on every
output that realizes the state. -/
theorem lifecycle_pending_or_terminal_not_consumable (p : Params) (now : Slot) (st : State)
    (status : lifecycleStatus st = .pendingTermination ∨ lifecycleStatus st = .terminal) :
    ¬ consumableState p now st ∧ consumableStateB p now st = false := by
  cases st <;> simp [lifecycleStatus, consumableState, consumableStateB] at status ⊢

/-- Evidence in which no output holds the identifier's representative asset
and the registry's complete history through `point` is `folds`. -/
def missingTokenEvidence (i : Interpretation) (c : Context) (point : ChainPoint)
    (e : Environment) (folds : List (List KeyChange)) : Evidence :=
  { point, environment := e,
    holding := some { point, asset := representativeAsset i c, holders := [] },
    history := some { point, registry := registryAsset i c, complete := true, folds } }

/-- **A missing token fits two reachable lifecycles.**
Given the connected lifecycle example, a context for its identifier 11 with an
authenticated environment, and two evidence values with the same holding
observation, no holder, that differ only in the history: no fold, and a fold
that registers the identifier's key followed by a fold that terminates it.
When each is read against the system it realizes: the system at its creation,
and the same system after identifier 11 was registered, convicted, booked and
folded.
Then both systems are reachable, each evidence realizes its system, the
holding observations are equal, and the answers differ: never registered at
creation, terminal after the fold. Only the history tells them apart. -/
theorem missing_token_fits_two_lifecycles (i : Interpretation) (c : Context)
    (rp : CardanoKeri.Registry.Params) (point : ChainPoint) (e : Environment)
    (context : authenticatedContext c e) (identifier : c.aid = 11) :
    let registered : List (List KeyChange) :=
      [[.register (i.keyOf c.aid)], [.terminate (i.keyOf c.aid)]]
    SysReach Examples.p Examples.env (Sys.init Examples.deployment) ∧
    SysReach Examples.p Examples.env Examples.completed ∧
    Realizes i c Examples.p rp (Sys.init Examples.deployment)
      (missingTokenEvidence i c point e []) ∧
    Realizes i c Examples.p rp Examples.completed (missingTokenEvidence i c point e registered) ∧
    (missingTokenEvidence i c point e []).holding =
      (missingTokenEvidence i c point e registered).holding ∧
    classify i c (missingTokenEvidence i c point e []) = .neverRegistered ∧
    classify i c (missingTokenEvidence i c point e registered) = .terminal := by
  intro registered
  obtain ⟨reach, state, leaf, _, _⟩ := Examples.connected_completion
  have empty : Singular.trieGet ([] : Singular.Trie) (i.keyOf c.aid) = .unknown := rfl
  have unknown : establishedLeaf i c (missingTokenEvidence i c point e []) = some .unknown := by
    simp [establishedLeaf, missingTokenEvidence, replay, replayFrom, empty]
  have terminal : establishedLeaf i c (missingTokenEvidence i c point e registered) =
      some (.known .terminal) := by
    simp [establishedLeaf, missingTokenEvidence, registered, replay, replayFrom, applyFold,
      applyChange, empty, Singular.trieGet_set_eq]
  have holdersSeen : ∀ folds, ∃ holders,
      HoldersAt i c (missingTokenEvidence i c point e folds) holders :=
    fun _ => ⟨[], _, rfl, rfl, rfl, rfl⟩
  have noHolders : ∀ folds holders,
      HoldersAt i c (missingTokenEvidence i c point e folds) holders → holders = [] := by
    rintro folds holders ⟨h, found, _, _, rfl⟩
    cases found
    rfl
  have atCreation : Realizes i c Examples.p rp (Sys.init Examples.deployment)
      (missingTokenEvidence i c point e []) :=
    { holders := fun holders at_ => by
        rw [noHolders _ _ at_]
        simp [holdersRealize, Sys.init]
      leaf := fun found at_ => by
        have read := (establishedLeaf_eq_some_iff i c _ found).mpr at_
        rw [unknown] at read
        cases read
        rfl }
  have afterFold : Realizes i c Examples.p rp Examples.completed
      (missingTokenEvidence i c point e registered) :=
    { holders := fun holders at_ => by
        rw [noHolders _ _ at_]
        simp [holdersRealize, identifier, state]
      leaf := fun found at_ => by
        have read := (establishedLeaf_eq_some_iff i c _ found).mpr at_
        rw [terminal] at read
        cases read
        rw [identifier, leaf]
        rfl }
  refine ⟨.init _, reach, atCreation, afterFold, rfl, ?_, ?_⟩
  · rw [lifecycle_status_is_answered i c Examples.p Examples.env rp _ _ (.init _) atCreation
      context (holdersSeen _) ⟨_, (establishedLeaf_eq_some_iff i c _ _).mp unknown⟩]
    rfl
  · rw [lifecycle_status_is_answered i c Examples.p Examples.env rp _ _ reach afterFold
      context (holdersSeen _) ⟨_, (establishedLeaf_eq_some_iff i c _ _).mp terminal⟩, identifier,
      state]
    rfl

end CardanoKeri.ReaderStatus
