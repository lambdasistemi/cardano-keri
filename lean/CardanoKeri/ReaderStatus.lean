import CardanoKeri.ConsumerIdentity
import SingularApplicationHeld.RequestShapes
import SingularApplicationHeld.Effects
import SingularApplicationHeld.History

/-! What a reader answers about one identifier at one chain point (#353).

The consumer predicate (`ConsumerIdentity.consumableHolding`) judges one
output. This module states the answer about an identifier: one of five
outcomes, decided from the evidence the reader holds at the chain point it
answers for.

* The context is the consumer's (`ConsumerIdentity.Context`): network,
  release, registry seed, identifier and checkpoint credential, fixed before
  any evidence is read.
* The evidence is the resolved environment and two observations, each present
  or not: every unspent output holding the identifier's representative asset,
  and the history of the registry, every fold from its creation through the
  point. An observation names the chain point and the asset, or the registry,
  it is about. One made at another point, or about another asset or registry,
  establishes nothing for this question.
* The leaf of the identifier's key is not observed: it is replayed. The
  registry starts with no member; each fold's changes are applied in order, a
  registration binding an unknown key as active and a termination making an
  active key terminal. Only a complete history establishes a leaf: one that
  starts late or misses a fold establishes none, and so does one whose replay
  meets a change no accepted fold makes.
* A chain point is an identity. The model compares points for equality only:
  there is no order, no distance and no age. An observation that is absent,
  stale, failed or incomplete is an observation that is not established.

The statuses and what decides them:

* **active**: exactly one holder, a live checkpoint of the identifier. The
  leaf, when established, must read active.
* **pending termination**: exactly one holder, the convicted checkpoint of the
  identifier or, once the termination is booked, its termination request. The
  custody the reader reads says which of the two holds the asset. The leaf,
  when established, must read active.
* **terminal**: the leaf established terminal. The holders, when established,
  must be none.
* **never registered**: the leaf established unknown. The holders, when
  established, must be none.
* **unavailable**: everything else: an unauthenticated context, no deciding
  observation, or observations that contradict each other.

Eligibility is not a status. An active identity may be young, frozen or
poisoned; the consumer predicate decides that, per output.

Declared boundary. How a reader obtains an observation, and that the
observation is what it says, is outside the model, like the resolved
environment of the consumer predicate: that the holders listed are every
holder, that the history holds every fold of the registry from its creation
through the point, with no gap, on the canonical chain. The model states what
follows from such evidence. -/
namespace CardanoKeri.ReaderStatus
open CardanoKeri.Checkpoint CardanoKeri.ConsumerIdentity

/-- The five outcomes of a read. -/
inductive Status where
  | active
  | pendingTermination
  | terminal
  | neverRegistered
  | unavailable
  deriving Repr, DecidableEq

/-- The name of an outcome, as vectors and simulators write it. -/
def Status.word : Status → String
  | .active => "active"
  | .pendingTermination => "pending-termination"
  | .terminal => "terminal"
  | .neverRegistered => "never-registered"
  | .unavailable => "unavailable"

/-- The identity of a chain point. Compared for equality only. -/
abbrev ChainPoint := Nat

/-- Every unspent output holding `asset` at `point`. -/
structure HoldingObservation where
  point : ChainPoint
  asset : Singular.TokenId
  holders : List AH.ObservedOutput
  deriving Repr, DecidableEq

/-- The history of `registry` through `point`: the changes of each of its
folds, in order from its creation. `complete` says the reader followed the
registry from its creation through the point without a gap; a history that
starts late or misses a fold is not complete. -/
structure HistoryObservation where
  point : ChainPoint
  registry : Singular.TokenId
  complete : Bool
  folds : List (List SingularApplicationHeld.Change)
  deriving Repr, DecidableEq

/-- What the reader holds when it answers for `point`. `none` is an
observation that is not established. -/
structure Evidence where
  point : ChainPoint
  environment : Environment
  holding : Option HoldingObservation
  history : Option HistoryObservation
  deriving Repr, DecidableEq

/-! ## Replaying a registry's history -/

/-- One change as an accepted fold makes it: a registration binds a key the
registry does not know as active, and a termination makes an active key
terminal. No accepted fold makes any other change. -/
def applyChange (members : Singular.Trie) (change : SingularApplicationHeld.Change) :
    Option Singular.Trie :=
  match change with
  | .register _ key _ _ =>
    if Singular.trieGet members key = .unknown then
      some (SingularApplicationHeld.targetTrie members change) else none
  | .terminate _ key =>
    if Singular.trieGet members key = .known .active then
      some (SingularApplicationHeld.targetTrie members change) else none

/-- The changes of one fold, in order. A fold makes at least one change. -/
def applyFold (members : Singular.Trie) (changes : List SingularApplicationHeld.Change) :
    Option Singular.Trie :=
  if changes.isEmpty then none else changes.foldlM applyChange members

/-- The registry's members after every fold, from its creation with none. -/
def replay (folds : List (List SingularApplicationHeld.Change)) : Option Singular.Trie :=
  folds.foldlM applyFold []

/-! ## The relation -/

/-- The holding observation establishes, at the asked point and for the
identifier's representative asset, exactly these holders. -/
def HoldersAt (i : Interpretation) (c : Context) (ev : Evidence)
    (holders : List AH.ObservedOutput) : Prop :=
  ∃ h, ev.holding = some h ∧ h.point = ev.point ∧ h.asset = representativeAsset i c ∧
    h.holders = holders

/-- The history observation establishes this leaf for the identifier's key: it
is a complete history of the identifier's registry through the asked point,
its replay succeeds, and the replayed members read this leaf at the key. -/
def LeafAt (i : Interpretation) (c : Context) (ev : Evidence) (leaf : Singular.Leaf) : Prop :=
  ∃ h members, ev.history = some h ∧ h.point = ev.point ∧ h.registry = registryAsset i c ∧
    h.complete = true ∧ replay h.folds = some members ∧
    Singular.trieGet members (i.keyOf c.aid) = leaf

/-- A live checkpoint of the identifier: at the checkpoint credential, holding
the representative asset exactly once, with a live datum of the identifier. -/
def LiveCheckpoint (i : Interpretation) (c : Context) (o : AH.ObservedOutput) (l : Live) : Prop :=
  o.credential = c.checkpointCredential ∧ AH.quantity o (representativeAsset i c) = 1 ∧
    decoded i c o = some ⟨c.aid, .present l⟩

/-- The convicted checkpoint of the identifier: at the checkpoint credential,
holding the representative asset exactly once, with a pending-termination
datum of the identifier. -/
def ConvictedCheckpoint (i : Interpretation) (c : Context) (o : AH.ObservedOutput) (h : Hash) :
    Prop :=
  o.credential = c.checkpointCredential ∧ AH.quantity o (representativeAsset i c) = 1 ∧
    decoded i c o = some ⟨c.aid, .terminationPending h⟩

/-- The termination request of the identifier's key: the application's
credential, an empty datum, exactly the representative asset and the
termination approval of the registry and key. -/
def TerminationRequest (i : Interpretation) (c : Context) (o : AH.ObservedOutput) : Prop :=
  SingularApplicationHeld.terminationShape .none i.hash i.code c.release o
    (registryAsset i c) (i.keyOf c.aid) = true

/-- The history does not contradict an active leaf: it establishes no leaf, or
the leaf it establishes reads active. -/
def LeafAllowsActive (i : Interpretation) (c : Context) (ev : Evidence) : Prop :=
  ∀ leaf, LeafAt i c ev leaf → leaf = .known .active

/-- The holding observation does not show a holder: it is not established, or
it shows none. -/
def NoHolderSeen (i : Interpretation) (c : Context) (ev : Evidence) : Prop :=
  ∀ holders, HoldersAt i c ev holders → holders = []

/-- The evidence decides a status. No rule decides `unavailable`. -/
inductive Decides (i : Interpretation) (c : Context) (ev : Evidence) : Status → Prop where
  | active {o : AH.ObservedOutput} {l : Live} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] → LiveCheckpoint i c o l →
      LeafAllowsActive i c ev → Decides i c ev .active
  | convicted {o : AH.ObservedOutput} {h : Hash} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] →
      ConvictedCheckpoint i c o h → LeafAllowsActive i c ev → Decides i c ev .pendingTermination
  | requested {o : AH.ObservedOutput} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] → TerminationRequest i c o →
      LeafAllowsActive i c ev → Decides i c ev .pendingTermination
  | terminal :
      authenticatedContext c ev.environment → LeafAt i c ev (.known .terminal) →
      NoHolderSeen i c ev → Decides i c ev .terminal
  | neverRegistered :
      authenticatedContext c ev.environment → LeafAt i c ev .unknown →
      NoHolderSeen i c ev → Decides i c ev .neverRegistered

/-- The reader's answer: the status the evidence decides, or `unavailable`
when it decides none. -/
def Answers (i : Interpretation) (c : Context) (ev : Evidence) (status : Status) : Prop :=
  Decides i c ev status ∨ (status = .unavailable ∧ ∀ s, ¬ Decides i c ev s)

/-! ## The classifier -/

/-- What a holding observation establishes about custody. -/
inductive Custody where
  | notEstablished
  | absent
  | live (l : Live)
  | convicted (h : Hash)
  | request
  | inconsistent
  deriving Repr, DecidableEq

/-- The checkpoint form of an output, if it has one. -/
def checkpointCustody (i : Interpretation) (c : Context) (o : AH.ObservedOutput) : Option Custody :=
  if o.credential = c.checkpointCredential ∧ AH.quantity o (representativeAsset i c) = 1 then
    match decoded i c o with
    | some ⟨aid, .present l⟩ => if aid = c.aid then some (.live l) else none
    | some ⟨aid, .terminationPending h⟩ => if aid = c.aid then some (.convicted h) else none
    | _ => none
  else none

/-- The output is the termination request of the identifier's key. -/
def requestShape (i : Interpretation) (c : Context) (o : AH.ObservedOutput) : Bool :=
  SingularApplicationHeld.terminationShape .none i.hash i.code c.release o
    (registryAsset i c) (i.keyOf c.aid)

/-- The custody one holder shows: a live checkpoint, the convicted checkpoint,
the termination request, or nothing the reader recognises. -/
def custodyOf (i : Interpretation) (c : Context) (o : AH.ObservedOutput) : Custody :=
  match checkpointCustody i c o with
  | some custody => custody
  | none => if requestShape i c o then .request else .inconsistent

/-- The custody a complete set of holders shows: none, the form of the one
holder, or inconsistent when two or more outputs hold the asset. -/
def holdersCustody (i : Interpretation) (c : Context) : List AH.ObservedOutput → Custody
  | [] => .absent
  | [o] => custodyOf i c o
  | _ :: _ :: _ => .inconsistent

/-- The custody the evidence establishes at the asked point. -/
def holdingCustody (i : Interpretation) (c : Context) (ev : Evidence) : Custody :=
  match ev.holding with
  | none => .notEstablished
  | some h =>
    if h.point = ev.point ∧ h.asset = representativeAsset i c then holdersCustody i c h.holders
    else .notEstablished

/-- The leaf the evidence establishes at the asked point: the replay of a
complete history of the identifier's registry, read at the identifier's key. -/
def establishedLeaf (i : Interpretation) (c : Context) (ev : Evidence) : Option Singular.Leaf :=
  match ev.history with
  | none => none
  | some h =>
    if h.point = ev.point ∧ h.registry = registryAsset i c ∧ h.complete = true then
      (replay h.folds).map fun members => Singular.trieGet members (i.keyOf c.aid)
    else none

/-- The table: custody against leaf. -/
def verdict : Custody → Option Singular.Leaf → Status
  | .live _, none => .active
  | .live _, some (.known .active) => .active
  | .convicted _, none => .pendingTermination
  | .convicted _, some (.known .active) => .pendingTermination
  | .request, none => .pendingTermination
  | .request, some (.known .active) => .pendingTermination
  | .notEstablished, some (.known .terminal) => .terminal
  | .absent, some (.known .terminal) => .terminal
  | .notEstablished, some .unknown => .neverRegistered
  | .absent, some .unknown => .neverRegistered
  | _, _ => .unavailable

/-- The reader's answer, executable. -/
def classify (i : Interpretation) (c : Context) (ev : Evidence) : Status :=
  if authenticatedContextB c ev.environment then
    verdict (holdingCustody i c ev) (establishedLeaf i c ev)
  else .unavailable

/-- The output an answer of active or pending termination rests on: the one
holder. Every other answer names none. -/
def holder (i : Interpretation) (c : Context) (ev : Evidence) : Option AH.ObservedOutput :=
  match classify i c ev, ev.holding with
  | .active, some h => h.holders.head?
  | .pendingTermination, some h => h.holders.head?
  | _, _ => none

/-! ## What a chain state warrants

Two models state the system. The public registry's history
(`SingularApplicationHeld.CandidateReachable`) has the complete unspent set and
every registry's leaves. The checkpoint system (`Checkpoint.SysReach`) has the
lifecycle state of every identifier. The reader's answer is stated against
both. -/

/-- Every unspent output of a world holding the identifier's representative asset. -/
def holdersIn (i : Interpretation) (c : Context) (world : SingularApplicationHeld.CandidateWorld) :
    List AH.ObservedOutput :=
  world.unspent.filter fun o => decide (0 < AH.quantity o (representativeAsset i c))

/-- The folds of one registry along a history of the public registry model,
in order from the registry's creation. The constructors are those of
`SingularApplicationHeld.CandidateReachable`, with the same premises: an
accepted fold of this registry adds its changes, and every other transaction
(the creation of a registry, a fold of another registry, a transaction that
touches no registry) leaves the list as it is. -/
inductive RegistryFolds (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) :
    SingularApplicationHeld.CandidateWorld → List (List SingularApplicationHeld.Change) → Prop where
  | initial (outputs : List AH.ObservedOutput)
      (unique : (outputs.map (·.reference)).Nodup)
      (noOwnAssets : ∀ output ∈ outputs,
        ∀ asset ∈ SingularApplicationHeld.assetSupport [output], asset.policy ≠ release.statePolicy) :
      RegistryFolds hash code commit release identity ⟨[], outputs, [], []⟩ []
  | genesis {before after : SingularApplicationHeld.CandidateWorld}
      {folds : List (List SingularApplicationHeld.Change)}
      (history : RegistryFolds hash code commit release identity before folds)
      (seed : Singular.OutRef) (view : SingularApplicationHeld.Assets.TxView)
      (inputs outputs : List AH.ObservedOutput)
      (registry : SingularApplicationHeld.PublicRegistry) (fee donation : Nat)
      (ledger : SingularApplicationHeld.LedgerObservationCorrespondence before after view inputs
        outputs fee donation)
      (accepted : SingularApplicationHeld.genesis .none hash code commit release seed view outputs
        = true)
      (created : registry.identity = AH.stateAsset hash code release seed)
      (seedBinding : registry.seed = seed)
      (statePresent : registry.state ∈ outputs)
      (recognized : SingularApplicationHeld.recognizeState .none hash code release seed
        registry.state = true)
      (emptyTrie : registry.trie = [])
      (newRegistry : registry.identity ∉ before.registries.map (·.identity))
      (registries : after.registries = before.registries ++ [registry])
      (domain : after.domain = before.domain ++ [.state seed]) :
      RegistryFolds hash code commit release identity after folds
  | fold {before after : SingularApplicationHeld.CandidateWorld}
      {folds : List (List SingularApplicationHeld.Change)}
      (history : RegistryFolds hash code commit release identity before folds)
      (observation : SingularApplicationHeld.FoldObservation)
      (ledger : SingularApplicationHeld.LedgerObservationCorrespondence before after
        observation.assets observation.spentOutputs observation.outputs observation.fee
        observation.donation)
      (present : observation.before ∈ before.registries)
      (accepted : SingularApplicationHeld.fold .none hash code commit release observation = true)
      (registries : after.registries = before.registries.map fun registry =>
        if registry.identity == observation.before.identity then observation.after else registry)
      (domain : after.domain = before.domain ++
        observation.changes.flatMap (SingularApplicationHeld.changePreimages observation)) :
      RegistryFolds hash code commit release identity after
        (if observation.before.identity = identity then folds ++ [observation.changes] else folds)
  | neutral {before after : SingularApplicationHeld.CandidateWorld}
      {folds : List (List SingularApplicationHeld.Change)}
      (history : RegistryFolds hash code commit release identity before folds)
      (view : SingularApplicationHeld.Assets.TxView) (inputs outputs : List AH.ObservedOutput)
      (fee donation : Nat)
      (ledger : SingularApplicationHeld.LedgerObservationCorrespondence before after view inputs
        outputs fee donation)
      (noOwnMint : SingularApplicationHeld.policyDelta view release.statePolicy [] = true)
      (stateUntouched : ∀ registry ∈ before.registries, registry.state.reference ∉ view.spent)
      (registries : after.registries = before.registries)
      (domain : after.domain = before.domain) :
      RegistryFolds hash code commit release identity after folds

/-- Evidence faithful to a world of the registry's history: the holders it
establishes are the world's holders, and a complete history it holds of the
identifier's registry is that registry's history in the world, the registry
created and every one of its folds, in order. An observation that is not
established is faithful to every world. -/
structure Faithful (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit)
    (world : SingularApplicationHeld.CandidateWorld) (ev : Evidence) : Prop where
  holders : ∀ holders, HoldersAt i c ev holders → holders = holdersIn i c world
  history : ∀ h, ev.history = some h → h.point = ev.point → h.registry = registryAsset i c →
    h.complete = true →
    registryAsset i c ∈ world.registries.map (·.identity) ∧
    RegistryFolds i.hash i.code commit c.release (registryAsset i c) world h.folds

/-- What a world warrants about the identifier, each status by the one fact
that decides it: an unspent live checkpoint, an unspent convicted checkpoint or
termination request, the terminal leaf, the unknown leaf. A world warrants no
`unavailable`: that outcome is about the evidence. -/
def Warrants (i : Interpretation) (c : Context) (world : SingularApplicationHeld.CandidateWorld)
    (registry : SingularApplicationHeld.PublicRegistry) : Status → Prop
  | .active => ∃ o l, o ∈ world.unspent ∧ LiveCheckpoint i c o l
  | .pendingTermination => ∃ o, o ∈ world.unspent ∧
      ((∃ h, ConvictedCheckpoint i c o h) ∨ TerminationRequest i c o)
  | .terminal => Singular.trieGet registry.trie (i.keyOf c.aid) = .known .terminal
  | .neverRegistered => Singular.trieGet registry.trie (i.keyOf c.aid) = .unknown
  | .unavailable => False

/-- The status the lifecycle state of an identifier warrants. -/
def lifecycleStatus : State → Status
  | .absent => .neverRegistered
  | .present _ => .active
  | .terminationPending _ => .pendingTermination
  | .convicted => .terminal

/-- The registry leaf of a lifecycle leaf. -/
def registryLeaf : Leaf → Singular.Leaf
  | .absent => .unknown
  | .active => .known .active
  | .retired => .known .terminal

/-- The holders that realize the lifecycle state of the identifier: none for a
state without an output; the termination request once the termination is
booked; otherwise the one checkpoint output that realizes the state
(`ConsumerIdentity.realizesState`). -/
def holdersRealize (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (holders : List AH.ObservedOutput) : Prop :=
  match s.states c.aid with
  | .absent | .convicted => holders = []
  | .present l => ∃ o, holders = [o] ∧ realizesState i c p rp (.present l) o
  | .terminationPending h => ∃ o, holders = [o] ∧
      if (s.pending c.aid).isSome = true then TerminationRequest i c o
      else realizesState i c p rp (.terminationPending h) o

/-- Evidence that realizes a checkpoint system at the context's identifier: the
holders it establishes realize the identifier's lifecycle state and the leaf
its history establishes is the registry leaf of the identifier's lifecycle leaf. This is a
refinement premise, as `realizesState` is: it does not prove that an observer
is correct. -/
structure Realizes (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (ev : Evidence) : Prop where
  holders : ∀ holders, HoldersAt i c ev holders → holdersRealize i c p rp s holders
  leaf : ∀ leaf, LeafAt i c ev leaf → leaf = registryLeaf (s.leaves c.aid)

end CardanoKeri.ReaderStatus
