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
  establishes nothing for this question; a history that refutes itself is a
  contradiction whatever it names.
* The history holds, of each fold, what the replay reads: the keys it
  registers and the keys it terminates, in order.
* The leaf of the identifier's key is not observed: it is replayed. The
  registry starts with no member; each fold's changes are applied in order, a
  registration binding an unknown key as active and a termination making an
  active key terminal. Only a complete history establishes a leaf: one that
  starts late or misses a fold establishes none.
* A history refutes itself when no members before the supplied folds make
  them replay: the empty registry for a history that says it is complete, any
  members for an incomplete one. A fold with no change, a key registered
  twice and a complete history that starts with a termination are such
  histories. It is the history of no registry, whatever point and registry it
  names, and the answer beside it is unavailable.
* A history of the identifier's registry through the asked point refuses a
  holder when no such members make it replay and leave the key active: a
  complete history that does not read the key active, and an incomplete one
  that holds the key's termination.
* A chain point is an identity. The model compares points for equality only:
  there is no order, no distance and no age. An observation that is absent,
  stale, failed or incomplete is an observation that is not established.

The statuses and what decides them:

* **active**: exactly one holder, a live checkpoint of the identifier. The
  history, when the reader holds one, must not refuse the holder.
* **pending termination**: exactly one holder, the convicted checkpoint of the
  identifier or, once the termination is booked, its termination request. The
  custody the reader reads says which of the two holds the asset. The history,
  when the reader holds one, must not refuse the holder.
* **terminal**: the leaf established terminal. The holders, when established,
  must be none.
* **never registered**: the leaf established unknown. The holders, when
  established, must be none.
* **unavailable**: everything else: an unauthenticated context, no deciding
  observation, or observations that contradict each other or themselves.

One observation suffices. A recognised holder decides active or pending
termination when the history is missing, or is incomplete and does not refuse
it, and a complete history decides terminal or never registered when the
holders are not established. A gap in the observation an answer does not need
does not make it unavailable; a history that refuses the holder does.

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

/-- One change of a fold, as the replay reads it: the key it registers or the
key it terminates. A fold's transaction carries more (the request it spends,
the output it delivers); the reader's history holds none of it. -/
inductive KeyChange where
  | register (key : Singular.Key)
  | terminate (key : Singular.Key)
  deriving Repr, DecidableEq

/-- The key a change names. -/
def KeyChange.key : KeyChange → Singular.Key
  | .register key => key
  | .terminate key => key

/-- The change the replay reads of a change of the registry's fold. -/
def KeyChange.of : SingularApplicationHeld.Change → KeyChange
  | .register _ key _ _ => .register key
  | .terminate _ key => .terminate key

/-- The history of `registry` through `point`: the changes of each of its
folds, in order. `complete` says the reader followed the registry from its
creation through the point without a gap: the folds are then all of them. A
history that starts late or misses a fold is not complete: its folds are some
of them. -/
structure HistoryObservation where
  point : ChainPoint
  registry : Singular.TokenId
  complete : Bool
  folds : List (List KeyChange)
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
def applyChange (members : Singular.Trie) : KeyChange → Option Singular.Trie
  | .register key =>
    if Singular.trieGet members key = .unknown then
      some (Singular.trieSet members key (.known .active)) else none
  | .terminate key =>
    if Singular.trieGet members key = .known .active then
      some (Singular.trieSet members key (.known .terminal)) else none

/-- The changes of one fold, in order. A fold makes at least one change. -/
def applyFold (members : Singular.Trie) (changes : List KeyChange) : Option Singular.Trie :=
  if changes.isEmpty then none else changes.foldlM applyChange members

/-- The members after the supplied folds, from the members before them. -/
def replayFrom (start : Singular.Trie) (folds : List (List KeyChange)) : Option Singular.Trie :=
  folds.foldlM applyFold start

/-- The registry's members after every fold, from its creation with none. -/
def replay (folds : List (List KeyChange)) : Option Singular.Trie :=
  replayFrom [] folds

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

/-- A history admits an active key: some members before the supplied folds
make them replay and leave the key active. For a complete history the members
before are none: the registry's creation. -/
def AdmitsActive (complete : Bool) (key : Singular.Key) (folds : List (List KeyChange)) : Prop :=
  ∃ start members, (complete = true → start = []) ∧ replayFrom start folds = some members ∧
    Singular.trieGet members key = .known .active

/-- A history refutes itself: no members before its folds, none when it says
it is complete, make them replay. It is the history of no registry, whatever
point and registry it names. -/
def RefutesItself (h : HistoryObservation) : Prop :=
  ∀ start, (h.complete = true → start = []) → replayFrom start h.folds = none

/-- The history does not refuse a holder: the reader holds none, or the one it
holds does not refute itself and, when it is of the identifier's registry
through the asked point, admits the identifier's key active. A holder exists
only while the key is active, so a history that does not admit it contradicts
every holder. -/
def HistoryAllowsHolder (i : Interpretation) (c : Context) (ev : Evidence) : Prop :=
  ∀ h, ev.history = some h → ¬ RefutesItself h ∧
    (h.point = ev.point → h.registry = registryAsset i c →
      AdmitsActive h.complete (i.keyOf c.aid) h.folds)

/-- The evidence holds a history that refutes itself. -/
def BrokenHistory (ev : Evidence) : Prop :=
  ∃ h, ev.history = some h ∧ RefutesItself h

/-- The holding observation does not show a holder: it is not established, or
it shows none. -/
def NoHolderSeen (i : Interpretation) (c : Context) (ev : Evidence) : Prop :=
  ∀ holders, HoldersAt i c ev holders → holders = []

/-- The evidence decides a status. No rule decides `unavailable`. -/
inductive Decides (i : Interpretation) (c : Context) (ev : Evidence) : Status → Prop where
  | active {o : AH.ObservedOutput} {l : Live} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] → LiveCheckpoint i c o l →
      HistoryAllowsHolder i c ev → Decides i c ev .active
  | convicted {o : AH.ObservedOutput} {h : Hash} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] →
      ConvictedCheckpoint i c o h → HistoryAllowsHolder i c ev → Decides i c ev .pendingTermination
  | requested {o : AH.ObservedOutput} :
      authenticatedContext c ev.environment → HoldersAt i c ev [o] → TerminationRequest i c o →
      HistoryAllowsHolder i c ev → Decides i c ev .pendingTermination
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

/-- The members a list of changes presupposes before it: a key whose first
change is a termination was active, and nothing is presupposed of a key whose
first change is a registration. -/
def presupposed : List KeyChange → Singular.Trie
  | [] => []
  | .register key :: rest => Singular.trieErase (presupposed rest) key
  | .terminate key :: rest => Singular.trieSet (presupposed rest) key (.known .active)

/-- The members to replay a history from when asking whether it admits the key
active: none for a complete history; for an incomplete one what its changes
presuppose, with the key itself active when no change names it. -/
def admissionStart (complete : Bool) (key : Singular.Key) (changes : List KeyChange) :
    Singular.Trie :=
  if complete then [] else
    if changes.any (fun change => decide (change.key = key)) then presupposed changes
    else Singular.trieSet (presupposed changes) key (.known .active)

/-- The history admits the key active, executable. -/
def admitsActive (complete : Bool) (key : Singular.Key) (folds : List (List KeyChange)) : Bool :=
  match replayFrom (admissionStart complete key folds.flatten) folds with
  | some members => decide (Singular.trieGet members key = .known .active)
  | none => false

/-- The history refutes itself, executable: replayed from no member when it
says it is complete, and otherwise from the members its changes presuppose. -/
def refutesItself (h : HistoryObservation) : Bool :=
  (replayFrom (if h.complete then [] else presupposed h.folds.flatten) h.folds).isNone

/-- The history does not refuse a holder, executable. -/
def historyAdmitsHolder (i : Interpretation) (c : Context) (ev : Evidence) : Bool :=
  match ev.history with
  | none => true
  | some h =>
    !refutesItself h &&
      (if h.point = ev.point ∧ h.registry = registryAsset i c then
        admitsActive h.complete (i.keyOf c.aid) h.folds
      else true)

/-- The table. A holder decides when the history does not refuse it; with no
holder the replayed leaf decides. -/
def verdict : Custody → Bool → Option Singular.Leaf → Status
  | .live _, true, _ => .active
  | .convicted _, true, _ => .pendingTermination
  | .request, true, _ => .pendingTermination
  | .notEstablished, _, some (.known .terminal) => .terminal
  | .absent, _, some (.known .terminal) => .terminal
  | .notEstablished, _, some .unknown => .neverRegistered
  | .absent, _, some .unknown => .neverRegistered
  | _, _, _ => .unavailable

/-- The reader's answer, executable. -/
def classify (i : Interpretation) (c : Context) (ev : Evidence) : Status :=
  if authenticatedContextB c ev.environment then
    verdict (holdingCustody i c ev) (historyAdmitsHolder i c ev) (establishedLeaf i c ev)
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
accepted fold of this registry adds its changes, as the replay reads them, and
every other transaction
(the creation of a registry, a fold of another registry, a transaction that
touches no registry) leaves the list as it is. -/
inductive RegistryFolds (hash : AH.Hash) (code : AH.Codec)
    (commit : SingularApplicationHeld.TrieCommit) (release : AH.PublishedRelease)
    (identity : Singular.TokenId) :
    SingularApplicationHeld.CandidateWorld → List (List KeyChange) → Prop where
  | initial (outputs : List AH.ObservedOutput)
      (unique : (outputs.map (·.reference)).Nodup)
      (noOwnAssets : ∀ output ∈ outputs,
        ∀ asset ∈ SingularApplicationHeld.assetSupport [output], asset.policy ≠ release.statePolicy) :
      RegistryFolds hash code commit release identity ⟨[], outputs, [], []⟩ []
  | genesis {before after : SingularApplicationHeld.CandidateWorld}
      {folds : List (List KeyChange)}
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
      {folds : List (List KeyChange)}
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
        (if observation.before.identity = identity then
          folds ++ [observation.changes.map KeyChange.of] else folds)
  | neutral {before after : SingularApplicationHeld.CandidateWorld}
      {folds : List (List KeyChange)}
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

/-- The holders the evidence establishes are the world's holders. An
observation that is not established is faithful to every world. -/
def FaithfulHolders (i : Interpretation) (c : Context)
    (world : SingularApplicationHeld.CandidateWorld) (ev : Evidence) : Prop :=
  ∀ holders, HoldersAt i c ev holders → holders = holdersIn i c world

/-- A complete history the evidence holds of the identifier's registry through
the asked point is that registry's history in the world: the registry was
created, and the folds are its folds, in order. Nothing is asked here of a
history that is absent, incomplete, at another point or of another registry. -/
def FaithfulHistory (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit)
    (world : SingularApplicationHeld.CandidateWorld) (ev : Evidence) : Prop :=
  ∀ h, ev.history = some h → h.point = ev.point → h.registry = registryAsset i c →
    h.complete = true →
    registryAsset i c ∈ world.registries.map (·.identity) ∧
    RegistryFolds i.hash i.code commit c.release (registryAsset i c) world h.folds

/-- Evidence faithful to a world of the registry's history: both of its
observations are. -/
structure Faithful (i : Interpretation) (c : Context)
    (commit : SingularApplicationHeld.TrieCommit)
    (world : SingularApplicationHeld.CandidateWorld) (ev : Evidence) : Prop where
  holders : FaithfulHolders i c world ev
  history : FaithfulHistory i c commit world ev

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
state without an output; once the termination is booked, the termination
request the booking placed, at the reference the system's pending association
records; otherwise the one checkpoint output that realizes the state
(`ConsumerIdentity.realizesState`). -/
def holdersRealize (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (s : Sys) (holders : List AH.ObservedOutput) : Prop :=
  match s.states c.aid with
  | .absent | .convicted => holders = []
  | .present l => ∃ o, holders = [o] ∧ realizesState i c p rp (.present l) o
  | .terminationPending h => ∃ o, holders = [o] ∧
      match s.pending c.aid with
      | some association => TerminationRequest i c o ∧ o.reference = association.reference
      | none => realizesState i c p rp (.terminationPending h) o

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
