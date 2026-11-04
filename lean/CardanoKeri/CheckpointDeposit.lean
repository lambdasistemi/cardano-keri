import CardanoKeri.CheckpointDatum

/-! The deposit intent and its signed bytes (#517).

`Env.depositAuthorized e` reads: the keys of epoch `e` signed the deposit of
the rotation that opens `e`. This module declares what they sign and how the
signature is checked.

The intent (`DepositIntent`, Plutus Data constructor 0, eight fields in this
order; constructor index and field order are protocol surface):

* `domain`: the UTF-8 bytes of `cardano-keri/checkpoint/deposit/v1`, frozen;
* `network_id`: the network the validator is applied to;
* `checkpoint_policy`: the policy of the checkpoint being advanced;
* `spent_ref`: the output reference of the exact checkpoint output being
  advanced, `OutputReference { transaction_id, output_index }`;
* `aid`: the AID the datum carries, its qualified CESR text bytes;
* `new_sn`: the sequence number of the rotation event;
* `new_epoch`: the epoch the rotation opens, one more than the spent state's;
* `deposit`: the amount the deposit moves into the output, `B − bHeld`:
  the freeze bond `B` when the spent state is frozen, `0` when it is not.

The signed bytes are the intent's Plutus Data serialisation (`cbor` of
`CheckpointDatum`, the Plutus encoding the validators' `cbor.serialise`
produces). Byte strings travel on the bijective numeral of #489.

The signers are the current keys the rotation event reveals, the keys of the
epoch it opens, at the threshold it declares. A signature is a position in
that key list and the signature bytes; a position outside the list never
counts, a repeated position counts once, a signature that does not verify
never counts, and the distinct counted positions must satisfy the threshold
as `Duplicity.Threshold.satisfied` reads it.

Declared gaps. Ed25519 verification is a cryptographic primitive the model
does not enter: it is a parameter (`Verify`). That one signature cannot verify
over two different messages is an explicit assumption where it is used
(`SignatureBinding`), not a proof. The observed facts (network, policy, spent
output, AID) are what the validator reads from the transaction and its own
parameters; reading them is the validator's obligation. -/
namespace CardanoKeri.CheckpointDeposit
open CardanoKeri.Checkpoint
open CardanoKeri.CheckpointDatum
open CardanoKeri.ConsumerIdentity.Bytes (utf8 unpack)

/-- The domain tag, frozen. A new layout is a new tag. -/
def domainTag : String := "cardano-keri/checkpoint/deposit/v1"

/-- The bytes of the domain tag. -/
def domain : List Nat := utf8 domainTag

/-- The deposit intent. Byte strings other than the domain are carried as
`Nat` through the numeral of #489. -/
structure DepositIntent where
  domain : List Nat
  networkId : Nat
  checkpointPolicy : Nat
  spentRef : Singular.OutRef
  aid : AID
  newSn : Seq
  newEpoch : Epoch
  deposit : Value
  deriving Repr, DecidableEq

/-- The intent as Plutus Data, constructor 0 with its eight fields. -/
def DepositIntent.toData (i : DepositIntent) : Data :=
  .constr 0 [.bytes i.domain, .int i.networkId, .bytes (unpack i.checkpointPolicy),
    .constr 0 [.bytes (unpack i.spentRef.tx), .int i.spentRef.index],
    .bytes (unpack i.aid), .int i.newSn, .int i.newEpoch, .int i.deposit]

/-- The signed bytes: the intent's Plutus Data serialisation. -/
def DepositIntent.preimage (i : DepositIntent) : List Nat := cbor i.toData

/-- What the validator observes about the Advance it checks, from the
transaction and its own parameters, never from the caller. -/
structure Observed where
  networkId : Nat
  checkpointPolicy : Nat
  spentRef : Singular.OutRef
  aid : AID
  deriving Repr, DecidableEq

/-- The intent the validator requires for the deposit rotation of the spent
state `l` to the sequence number `sn'`. -/
def intentFor (p : Params) (o : Observed) (l : Live) (sn' : Seq) : DepositIntent :=
  { domain := domain, networkId := o.networkId, checkpointPolicy := o.checkpointPolicy,
    spentRef := o.spentRef, aid := o.aid, newSn := sn', newEpoch := l.epoch + 1,
    deposit := p.B - l.bHeld p }

/-- Ed25519 verification of a signature by a public key over a message, all
byte strings. A declared gap: the model does not enter the primitive. -/
abbrev Verify := List Nat → List Nat → List Nat → Bool

/-- One signature cannot verify, under one key, over two different messages.
An assumption about the primitive, stated where it is used. -/
def SignatureBinding (verify : Verify) : Prop :=
  ∀ key m m' s, verify key m s = true → verify key m' s = true → m = m'

/-- The position a signature claims, if its key exists and the signature
verifies over the message. -/
def counted (verify : Verify) (keys : List (List Nat)) (message : List Nat) :
    Nat × List Nat → Option Nat
  | (i, s) => match keys[i]? with
    | some k => if verify k message s then some i else none
    | none => none

/-- The positions of `keys` whose signature over `message` verifies. The
threshold reads positions by membership, so a repeated position counts once. -/
def verifiedPositions (verify : Verify) (keys : List (List Nat)) (message : List Nat)
    (signatures : List (Nat × List Nat)) : List Nat :=
  signatures.filterMap (counted verify keys message)

/-- The keys `keys`, at the threshold `threshold`, signed `message`: the
verified positions satisfy the threshold. Keys are carried as `Nat`,
as the rotation event carries them. -/
def signed (verify : Verify) (keys : List Nat) (threshold : Duplicity.Threshold)
    (signatures : List (Nat × List Nat)) (message : List Nat) : Bool :=
  threshold.satisfied (List.range keys.length)
    (verifiedPositions verify (keys.map unpack) message signatures)

/-- What a deposit Advance carries and observes for the rotation it lands:
the observed facts, the current keys and threshold the rotation event reveals
(the keys of the epoch it opens), and the signatures. -/
structure Evidence where
  observed : Observed
  newKeys : List Nat
  newThreshold : Duplicity.Threshold
  signatures : List (Nat × List Nat)
  deriving Repr, DecidableEq

/-- The new keys at the new threshold signed the intent for this spent state,
this output and this amount. -/
def Evidence.authorizes (verify : Verify) (p : Params) (ev : Evidence) (l : Live) (sn' : Seq) :
    Bool :=
  signed verify ev.newKeys ev.newThreshold ev.signatures (intentFor p ev.observed l sn').preimage

/-- The concrete reading of `Env.depositAuthorized` at the rotation of `l` to
`sn'`: the keys of the epoch it opens signed the deposit exactly when the
evidence authorizes the intent for that rotation. -/
def ReadsDeposit (verify : Verify) (p : Params) (env : Env) (ev : Evidence) (l : Live) (sn' : Seq) :
    Prop :=
  env.depositAuthorized (l.epoch + 1) = ev.authorizes verify p l sn'

end CardanoKeri.CheckpointDeposit
