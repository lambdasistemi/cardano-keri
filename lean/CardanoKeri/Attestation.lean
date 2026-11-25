import SingularApplicationHeld.Assets

/-! Evidence issued and read in one transaction. The ledger observation and token
identity are the public registry's. Booking identifies a newly created request by
its position in the ordered outputs and its committed contents. A checkpoint spend
names the existing output by the transaction and index that created it. -/
namespace CardanoKeri.Attestation
open Singular
open SingularApplicationHeld.Assets

inductive Change where
  | advance | freeze | convict
  deriving DecidableEq, Repr, Lean.ToJson, Lean.FromJson

inductive Claim where
  | book (application output initialDatum deposit : Nat)
  | spend (kind : Change) (checkpoint : Nat) (input : OutRef)
  deriving DecidableEq, Repr

/-- A relying script is parameterized by its published attestation policy.
The name interprets the digest of the complete typed preimage. -/
structure Policy where
  id : Nat
  digest : Claim → Nat

def Policy.asset (policy : Policy) (claim : Claim) : TokenId :=
  ⟨policy.id, policy.digest claim⟩

def Policy.minted (policy : Policy) (tx : TxView) (claim : Claim) : Bool :=
  mintQty tx (policy.asset claim) == 1

/-- The checkpoint script and the two independent policies fixed at deployment. -/
structure ConvictionPolicies where
  script : Nat
  enforcement : Policy
  entitlement : Policy
  separate : enforcement.id ≠ entitlement.id

/-- Which spent output produced an indexed successor, and the mint transaction
observed for it. A custody history relates this projection to the ledger step. -/
structure Spend where
  input : OutRef
  transaction : TxView
  deriving DecidableEq, Repr, Lean.ToJson, Lean.FromJson

/-- A transaction's ledger-assigned identity and its observed asset view. -/
structure MintObservation where
  identity : Nat
  assets : TxView
  deriving Repr, Lean.ToJson, Lean.FromJson

/-- Projection from one indexed output to the transaction spending its precursor. -/
structure Production where
  output : OutRef
  observation : Spend
  deriving Repr, Lean.ToJson, Lean.FromJson

/-- The decoded transaction presented for an advance or a freeze. The deposit
variant of an advance uses the same claim and has a separate spending check. -/
structure AdvanceReads where
  script : Nat
  policy : Policy
  spend : Change → Nat → Nat → Nat → Option Spend

def AdvanceReads.attested (r : AdvanceReads) (kind : Change) (epoch sn next : Nat) : Bool :=
  (r.spend kind epoch sn next).any fun s =>
    s.transaction.spent.contains s.input &&
    r.policy.minted s.transaction (.spend kind r.script s.input)

structure ConvictionReads where
  policies : ConvictionPolicies
  producingSpend : OutRef → Option Spend

def ConvictionPolicies.requiresBoth (p : ConvictionPolicies) (tx : TxView) (input : OutRef) : Bool :=
  let claim := Claim.spend .convict p.script input
  tx.spent.contains input && p.enforcement.minted tx claim && p.entitlement.minted tx claim

def ConvictionReads.attested (r : ConvictionReads) (output : OutRef) : Bool :=
  (r.producingSpend output).any fun s => r.policies.requiresBoth s.transaction s.input

/-- A reader matches the checkpoint's decoded evidence view to the credential
and input actually spent, the indexed output produced and the mint field of the
same ledger transaction. Holdings and possibly unrelated transactions are absent
from the comparison. -/
def ConvictionReads.corresponds (r : ConvictionReads) (input output : OutRef)
    (script : Nat) (tx : TxView) : Prop :=
  r.policies.script = script ∧ ∃ observed, r.producingSpend output = some observed ∧
    observed.input = input ∧ observed.transaction.mint = tx.mint

/-- One net quantity per asset. Zero net quantities may be omitted. -/
def NetMintField (tx : TxView) : Prop := (tx.mint.map Prod.fst).Nodup

/-- A nonzero mint or burn runs the asset's policy in this transaction. -/
def InvokesMintPolicies (tx : TxView) : Prop :=
  ∀ asset, mintQty tx asset ≠ 0 → asset.policy ∈ tx.invoked

/-- The digest distinguishes the claims in the domain under consideration. -/
def FaithfulNames (policy : Policy) (a b : Claim) : Prop :=
  policy.digest a = policy.digest b → a = b

/-- Given a claim checked by a relying script, when its asset is required,
then the net quantity in the same observed transaction is exactly one. -/
theorem minted_iff (policy : Policy) (tx : TxView) (claim : Claim) :
    policy.minted tx claim = true ↔ mintQty tx (policy.asset claim) = 1 := by
  simp [Policy.minted]

/-- Given the observed producer of a pending checkpoint, when the conviction
check accepts and its read corresponds to the spending transaction, then its mint
field contains one enforcement token and one entitlement token for the actual
spent reference and relying script. -/
theorem conviction_mints_at_use {r : ConvictionReads} {input output : OutRef} {script tx}
    (actual : r.corresponds input output script tx) (checked : r.attested output = true) :
    let claim := Claim.spend .convict script input
    mintQty tx (r.policies.enforcement.asset claim) = 1 ∧
    mintQty tx (r.policies.entitlement.asset claim) = 1 := by
  obtain ⟨rfl, s, read, rfl, mint⟩ := actual
  simp [ConvictionReads.attested, read, ConvictionPolicies.requiresBoth, Policy.minted] at checked
  simpa [mintQty, ← mint] using And.intro checked.1.2 checked.2

/-- Given a ledger that invokes every nonzero mint policy, when an attestation
is presented at use, then its own policy ran in that transaction. -/
theorem minted_policy_invoked {policy : Policy} {tx : TxView} {claim : Claim}
    (ledger : InvokesMintPolicies tx) (issued : policy.minted tx claim = true) :
    policy.id ∈ tx.invoked := by
  apply ledger (policy.asset claim)
  rw [(minted_iff ..).mp issued]
  decide

/-- Given distinct claims with faithful names, when the transaction mints only
the other claim under this policy, then it refuses the required claim. -/
theorem another_claim_does_not_serve {policy : Policy} {tx : TxView} {required other : Claim}
    (names : FaithfulNames policy required other) (different : required ≠ other)
    (onlyOther : ∀ asset, asset.policy = policy.id → mintQty tx asset = 1 →
      asset = policy.asset other) : policy.minted tx required = false := by
  cases h : policy.minted tx required with
  | false => rfl
  | true =>
    have same := onlyOther (policy.asset required) rfl ((minted_iff ..).mp h)
    exact False.elim (different (names (congrArg TokenId.name same)))

/-- Given any spent references, output holdings and invoked policies, when they
change without changing the mint field, then they cannot supply an attestation. -/
theorem holdings_do_not_supply_mint (policy : Policy) (claim : Claim) {a b : TxView}
    (sameMint : a.mint = b.mint) : policy.minted a claim = policy.minted b claim := by
  simp [Policy.minted, mintQty, sameMint]

/-- Given a mint field containing only negative entries, when any evidence
policy looks up a claim, then its net quantity cannot supply the required +1. -/
theorem negative_mint_supplies_no_attestation (policy : Policy) (tx : TxView) (claim : Claim)
    (negative : ∀ entry ∈ tx.mint, entry.2 < 0) : policy.minted tx claim = false := by
  have nonpos (xs : List Int) (h : ∀ x ∈ xs, x < 0) : xs.sum ≤ 0 := by
    induction xs with
    | nil => decide
    | cons x xs ih =>
      have head := h x (by simp)
      have tail := ih (fun y hy => h y (by simp [hy]))
      simp only [List.sum_cons]
      omega
  have bound : mintQty tx (policy.asset claim) ≤ 0 := by
    apply nonpos
    intro n hn
    obtain ⟨entry, member, rfl⟩ := List.mem_map.mp hn
    exact negative entry (List.mem_filter.mp member).1
  simp [Policy.minted, show mintQty tx (policy.asset claim) ≠ 1 by omega]

/-- At issue the policy checks every positive entry of its own mint, including
the empty name. Its verification premise is indexed by the transaction and claim.
A pure burn presents no verified claims. -/
def Policy.authorizes (policy : Policy) (tx : TxView) (emptyName : Nat)
    (verified : TxView → Claim → Bool) (claims : List Claim) : Bool :=
  claims.all (fun c => verified tx c && policy.minted tx c) &&
  tx.mint.all (fun (asset, qty) => asset.policy != policy.id || qty < 0 ||
    (qty == 1 && asset.name != emptyName && claims.any (fun c => decide (policy.asset c = asset))))

/-- Given a policy execution and a positive entry of its own mint field, when
its name is read, then it is nonempty and identifies a claim verified in that
transaction. Negative entries cannot authorize an unchecked positive entry. -/
theorem positive_issue_verified {policy : Policy} {tx : TxView} {emptyName verified claims}
    (ok : policy.authorizes tx emptyName verified claims = true)
    {asset : TokenId} {q : Int} (entry : (asset, q) ∈ tx.mint) (own : asset.policy = policy.id)
    (positive : 0 < q) : q = 1 ∧ asset.name ≠ emptyName ∧
      ∃ c ∈ claims, policy.asset c = asset ∧ verified tx c = true := by
  simp only [Policy.authorizes, Bool.and_eq_true, List.all_eq_true] at ok
  have named := ok.2 _ entry
  have nonneg : ¬q < 0 := by omega
  simp [own, nonneg, List.any_eq_true] at named
  obtain ⟨⟨one, nonempty⟩, c, mem, same⟩ := named
  have both := ok.1 c mem
  simp only [Bool.and_eq_true] at both
  exact ⟨one, nonempty, c, mem, same, both.1⟩

/-- Given no issue claims, when a transaction contains only negative entries for
this policy, then its burn branch succeeds independently of evidence. -/
theorem pure_burn_needs_no_evidence (policy : Policy) (tx : TxView) (emptyName : Nat)
    (verified : TxView → Claim → Bool) :
    policy.authorizes tx emptyName verified [] = true ↔
      ∀ entry ∈ tx.mint, entry.1.policy = policy.id → entry.2 < 0 := by
  simp [Policy.authorizes, List.all_eq_true]
  constructor
  · intro h a b mem eq
    exact (h a b mem).resolve_left (fun ne => ne eq)
  · intro h a b mem
    by_cases eq : a.policy = policy.id
    · exact Or.inr (h a b mem eq)
    · exact Or.inl eq

end CardanoKeri.Attestation
