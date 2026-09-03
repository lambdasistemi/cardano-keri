/-!
# The good samaritan: reaping an abandoned checkpoint never costs the reaper

A parked or convicted checkpoint holds only its min-ADA `Mc`: the bonds and
the pool left it at the pause or the conviction. Anyone (the *reaper*) may
spend it, burn its token, and create the go-request that un-references it in
the registry. Two transactions move value:

* the **reap**: the checkpoint's `Mc` is split into the go-request (its own
  min-ADA `Mr` plus the cage's tip) and the reaper's premium; the reaper pays
  the ledger fee `fReap`;
* the **fold** of the go-request, by anyone: the request's `Mr` returns to
  the request's owner — the reaper — and the tip goes to the folder, who pays
  the fold's fee (#101: on the delegated path the folder funds the fee).

The reap validator's one value guard is that the checkpoint can fund the
request: `Mr + tip ≤ Mc`. Under it the reaper brings no value of their own
except the fee, and recovers `Mc - tip` in total, so they never lose as long
as `tip + fReap ≤ Mc`. A reaper who also folds recovers `Mc` against both
fees. Both are deployment facts about the cage's `tip` relative to a
checkpoint's min-ADA; the theorems state exactly that condition.

Truncated subtraction never bites: every difference below is guarded.
-/

namespace CardanoKeri.Samaritan



/-- The values a reap sees. -/
structure Reap where
  /-- What the checkpoint holds: its min-ADA and nothing else. -/
  Mc : Nat
  /-- The go-request's own min-ADA. -/
  Mr : Nat
  /-- The cage's tip, paid to whoever folds the request. -/
  tip : Nat
  /-- The ledger fee of the reap transaction, paid by the reaper. -/
  fReap : Nat
  /-- The reap validator's value guard: the checkpoint funds the request. -/
  hFund : Mr + tip ≤ Mc

/-- The reap transaction's value flow. -/
structure ReapFlow where
  /-- Into the go-request: `Mr + tip`. -/
  intoRequest : Nat
  /-- To the reaper, in the same transaction. -/
  premium : Nat
  /-- Paid by the reaper. -/
  reaperPays : Nat

def reap (r : Reap) : ReapFlow :=
  { intoRequest := r.Mr + r.tip, premium := r.Mc - r.Mr - r.tip, reaperPays := r.fReap }

/-- The fold's value flow for the go-request: `Mr` to its owner (the reaper),
`tip` to the folder. This is the plugin's obligation on a processed
receipt-carrying request (#101, #102). -/
structure FoldFlow where
  toOwner : Nat
  toFolder : Nat

def fold (r : Reap) : FoldFlow := { toOwner := r.Mr, toFolder := r.tip }

/-- **The reap conserves the checkpoint's value.** Nothing comes from the
reaper's pocket but the fee: request plus premium is exactly `Mc`. -/
theorem reap_conserves (r : Reap) : (reap r).intoRequest + (reap r).premium = r.Mc := by
  have := r.hFund
  simp only [reap]
  omega

/-- **The reaper's gross recovery.** Premium now plus `Mr` at the fold is
`Mc - tip`, whoever folds. -/
theorem reaper_recovers (r : Reap) : (reap r).premium + (fold r).toOwner = r.Mc - r.tip := by
  have := r.hFund
  simp only [reap, fold]
  omega

/-- **The good samaritan never loses.** If the cage's tip plus the reap fee
do not exceed the checkpoint's min-ADA, what the reaper gets back covers what
the reaper paid, without folding anything themselves. -/
theorem samaritan_never_loses (r : Reap) (h : r.tip + r.fReap ≤ r.Mc) :
    (reap r).reaperPays ≤ (reap r).premium + (fold r).toOwner := by
  have := r.hFund
  simp only [reap, fold]
  omega

/-- **The reaper who also folds recovers the whole min-ADA against both
fees.** -/
theorem self_folding_reaper_never_loses (r : Reap) (fFold : Nat) (h : r.fReap + fFold ≤ r.Mc) :
    (reap r).reaperPays + fFold ≤ (reap r).premium + (fold r).toOwner + (fold r).toFolder := by
  have := r.hFund
  simp only [reap, fold]
  omega

/-- **Nobody else pays or is paid.** The fold moves exactly the request's
value, split between its owner and the folder. -/
theorem fold_conserves (r : Reap) : (fold r).toOwner + (fold r).toFolder = (reap r).intoRequest := by
  simp only [reap, fold]

/-- **The deployment condition, stated once.** A checkpoint is worth reaping
by a stranger exactly when `tip + fReap ≤ Mc`; a cage tip above the
checkpoint's min-ADA makes reaping unprofitable and nobody will do it. -/
theorem unprofitable_when_tip_too_high (r : Reap) (h : r.Mc < r.tip + r.fReap) :
    (reap r).premium + (fold r).toOwner < (reap r).reaperPays := by
  have := r.hFund
  simp only [reap, fold]
  omega

end CardanoKeri.Samaritan
