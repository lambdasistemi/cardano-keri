import Singular.Statements.FoldAccounting
import Singular.Statements.FoldTermination

/-! Convicted-carrier booking and actual imported fold accounting.
Parking retains its min-ADA; only booking a convicted carrier uses this split. -/
namespace CardanoKeri.Samaritan

structure Reap where

  Mc : Nat

  Mr : Nat

  tip : Nat

  fReap : Nat

  hFund : Mr + tip ≤ Mc


structure ReapFlow where

  intoRequest : Nat

  premium : Nat

  reaperPays : Nat

def reap (r : Reap) : ReapFlow :=
  { intoRequest := r.Mr + r.tip, premium := r.Mc - r.Mr - r.tip, reaperPays := r.fReap }


def fold (world : Singular.World) (unspent : Singular.EconomicUtxo)
    (tx : Singular.EconomicTransaction) : Except String Singular.World :=
  Singular.foldAccepted world unspent tx

-- Binds the retained application split to an actual pending economic member.
def MatchesBooking (r : Reap) (b : Singular.TerminationBooking) : Prop :=
  b.request.carrierAda = r.Mr ∧
  b.request.declaredTip = r.tip ∧
  b.request.contents.lovelace = (reap r).intoRequest

-- Read ordinary value at one actual address. This does not select a payee.
def ordinaryAt (address : Nat) (outputs : List Singular.EconomicOutput) : Nat :=
  ((outputs.filter (fun o => Singular.foldOrdinary o &&
    decide (o.output.address = some address))).map (·.output.lovelace)).sum

-- A transaction-specific allocation, not a universal property of folds.
def AllOrdinaryAt (address : Nat) (outputs : List Singular.EconomicOutput) : Prop :=
  ∀ o ∈ outputs, Singular.foldOrdinary o = true →
    o.output.address = some address

/-- Given every nonnegative amount in Reap and its funding inequality; when
convicted-carrier booking splits Mc; then request plus premium equals Mc.
The fee is an explicit external payment, not deducted from a bond or added
to this equation. This preserves the old exact theorem, with its domain
corrected from parked-or-convicted to convicted only. Witness Mc4/Mr2/tip1:
request3 plus premium1. This does not assert a real booking succeeds. -/
theorem reap_conserves (r : Reap) :
    (reap r).intoRequest + (reap r).premium = r.Mc := by
  have := r.hFund
  simp only [reap]
  omega

/-- Given all Reap fields and its funding inequality; when comparing the booked
premium with the external booking fee; then the exact recovery equation,
both directions of the non-loss condition, and strict-loss implication hold.
These statements do not treat outside fold input returned as a request
refund. Counterexample to the retired old condition: Mc4/Mr2/tip1/fee2
satisfies old tip+fee≤Mc, but premium1<fee2. Positive companion: fee1. -/
theorem booking_premium_exact (r : Reap) :
    (reap r).premium + r.Mr + r.tip = r.Mc := by
  have := r.hFund
  simp only [reap]
  omega

/-- Given all Reap fields and its funding inequality; when comparing the booked
premium with the external booking fee; then the exact recovery equation,
both directions of the non-loss condition, and strict-loss implication hold.
These statements do not treat outside fold input returned as a request
refund. Counterexample to the retired old condition: Mc4/Mr2/tip1/fee2
satisfies old tip+fee≤Mc, but premium1<fee2. Positive companion: fee1. -/
theorem booker_nonloss_iff (r : Reap) :
    (reap r).reaperPays ≤ (reap r).premium ↔
      r.Mr + r.tip + r.fReap ≤ r.Mc := by
  have := r.hFund
  simp only [reap]
  omega

/-- Given all Reap fields and its funding inequality; when comparing the booked
premium with the external booking fee; then the exact recovery equation,
both directions of the non-loss condition, and strict-loss implication hold.
These statements do not treat outside fold input returned as a request
refund. Counterexample to the retired old condition: Mc4/Mr2/tip1/fee2
satisfies old tip+fee≤Mc, but premium1<fee2. Positive companion: fee1. -/
theorem booker_loses_when_underfunded (r : Reap)
    (h : r.Mc < r.Mr + r.tip + r.fReap) :
    (reap r).premium < (reap r).reaperPays := by
  have := r.hFund
  simp only [reap]
  omega

/-- Given all actual execution premises above, with no restriction on member
kinds; when reading an accepted fold; then all eight upstream accounting
clauses hold by `fold_routes_every_amount` through the definition of fold.
`Registry.current_sys_fold_accounting` instantiates the actual Sys projection
and executed transition. `RegistryJourneyChecks` mixes a registration with
a termination while retaining another whole pending termination. Donation, carrier, tip and state-value mutations have separate
observations, rather than relying on one broad accounting failure. -/
theorem imported_fold_accounting
    (world after : Singular.World) (reachable : Singular.WorldReachable world)
    (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (accepted : fold world unspent tx = .ok after) :
    Singular.balanced unspent.ledger tx.transaction = true ∧
    Singular.foldStateLovelace (Singular.economicSpent unspent tx) =
      Singular.foldStateLovelace tx.outputs ∧
    tx.transaction.donation =
      (Singular.foldObligations (Singular.foldMembers world tx)).donation ∧
    Singular.foldCarrierLovelace tx.outputs =
      (Singular.foldObligations (Singular.foldMembers world tx)).carriers ∧
    Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee =
      Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) +
        (Singular.foldObligations (Singular.foldMembers world tx)).tips ∧
    tx.transaction.fee ≤
      Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) ∧
    after.treasury = world.treasury + tx.transaction.donation ∧
    Singular.requestTagsBurned unspent tx = true := by
  exact Singular.Statements.fold_routes_every_amount world after reachable unspent tx accepted

/-- Given a reachable actual World, actual unspent set/transaction, the single
selected booked termination matching the application split, and successful
actual fold; when reading outputs, fee, donation, tags and treasury; then
all seven clauses hold. No owner refund or named folder recipient follows.
`Registry.Examples.W5_connected_termination` starts with actual registration
and authorized application conviction. `RegistryJourneyChecks` checks wrong
donation and balanced old-refund refusals against successful actual folds. -/
theorem termination_fold_accounting
    (r : Reap) (world after : Singular.World)
    (reachable : Singular.WorldReachable world)
    (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (b : Singular.TerminationBooking)
    (matched : MatchesBooking r b)
    (members : Singular.foldMembers world tx = [.termination b])
    (accepted : fold world unspent tx = .ok after) :
    tx.transaction.donation = r.Mr ∧
    Singular.foldCarrierLovelace tx.outputs = 0 ∧
    Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee =
      Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) + r.tip ∧
    tx.transaction.fee ≤
      Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) ∧
    after.treasury = world.treasury + r.Mr ∧
    Singular.balanced unspent.ledger tx.transaction = true ∧
    Singular.requestTagsBurned unspent tx = true := by
  obtain ⟨balanced, state, donation, carrier, tips, fee, treasury, tags⟩ :=
    imported_fold_accounting world after reachable unspent tx accepted
  obtain ⟨mr, tip, held⟩ := matched
  simp only [members, Singular.foldObligations, List.map_cons, List.map_nil,
    List.sum_cons, List.sum_nil, Nat.add_zero, Singular.FoldMember.donation,
    Singular.FoldMember.carrier, Singular.FoldMember.tip] at donation carrier tips
  simp only [reap] at held
  have donated : tx.transaction.donation = r.Mr := by omega
  exact ⟨donated, carrier, by simpa [tip] using tips, fee, by simpa [donated] using treasury,
    balanced, tags⟩

/-- Given every ordinary output is at this address, its addressed ordinary
value equals the full ordinary category. -/
theorem ordinaryAt_eq_of_all {address : Nat} {outputs : List Singular.EconomicOutput}
    (h : AllOrdinaryAt address outputs) : ordinaryAt address outputs = Singular.foldOrdinaryLovelace outputs := by
  have filters : outputs.filter (fun o => Singular.foldOrdinary o &&
      decide (o.output.address = some address)) = outputs.filter Singular.foldOrdinary := by
    apply List.filter_congr
    intro o member
    cases value : Singular.foldOrdinary o with
    | false => simp []
    | true => simp [h o member value]
  unfold ordinaryAt Singular.foldOrdinaryLovelace
  rw [filters]

/-- Given a reachable World, actual unspent set and accepted fold, exactly one
termination member matching the Reap split, and all ordinary spent/output value at the
specified booker address; when comparing that address's ordinary outflow and
inflow plus its booking premium; then the exact tip/fee equation and both
directions of the non-loss criterion hold. The spent ordinary principal is
on the cost side; returning it is not profit. An address observation is not
a cryptographic ownership proof. A named funding party's authority and
available real funds remain outside this model. Positive model witness must
construct ordinary input and change at the same address. A split-recipient
accepted transaction is a negative control for the allocation premise, not
an assertion that the generic fold refuses other payees. -/
theorem self_fold_addressed_accounting
    (r : Reap) (world after : Singular.World)
    (reachable : Singular.WorldReachable world)
    (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (b : Singular.TerminationBooking) (booker : Nat)
    (matched : MatchesBooking r b)
    (members : Singular.foldMembers world tx = [.termination b])
    (accepted : fold world unspent tx = .ok after)
    (inputsAt : AllOrdinaryAt booker (Singular.economicSpent unspent tx))
    (outputsAt : AllOrdinaryAt booker tx.outputs) :
    ordinaryAt booker tx.outputs + tx.transaction.fee =
      ordinaryAt booker (Singular.economicSpent unspent tx) + r.tip := by
  have totals := (termination_fold_accounting r world after reachable unspent tx b matched members accepted).2.2.1
  rw [ordinaryAt_eq_of_all inputsAt, ordinaryAt_eq_of_all outputsAt]
  exact totals

/-- Given a reachable World, actual unspent set and accepted fold, exactly one
termination member matching the Reap split, and all ordinary spent/output value at the
specified booker address; when comparing that address's ordinary outflow and
inflow plus its booking premium; then the exact tip/fee equation and both
directions of the non-loss criterion hold. The spent ordinary principal is
on the cost side; returning it is not profit. An address observation is not
a cryptographic ownership proof. A named funding party's authority and
available real funds remain outside this model. Positive model witness must
construct ordinary input and change at the same address. A split-recipient
accepted transaction is a negative control for the allocation premise, not
an assertion that the generic fold refuses other payees. -/
theorem self_fold_nonloss_iff
    (r : Reap) (world after : Singular.World)
    (reachable : Singular.WorldReachable world)
    (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (b : Singular.TerminationBooking) (booker : Nat)
    (matched : MatchesBooking r b)
    (members : Singular.foldMembers world tx = [.termination b])
    (accepted : fold world unspent tx = .ok after)
    (inputsAt : AllOrdinaryAt booker (Singular.economicSpent unspent tx))
    (outputsAt : AllOrdinaryAt booker tx.outputs) :
    r.fReap + ordinaryAt booker (Singular.economicSpent unspent tx) ≤
      (reap r).premium + ordinaryAt booker tx.outputs ↔
    r.Mr + r.fReap + tx.transaction.fee ≤ r.Mc := by
  have totals := self_fold_addressed_accounting r world after reachable unspent tx b booker
    matched members accepted inputsAt outputsAt
  have premium := booking_premium_exact r
  omega

end CardanoKeri.Samaritan
