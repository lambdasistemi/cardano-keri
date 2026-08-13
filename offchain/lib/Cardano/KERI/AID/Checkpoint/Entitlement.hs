{- |
Module      : Cardano.KERI.AID.Checkpoint.Entitlement
Description : Off-chain mirror of the shared bounty-entitlement rule, #254

The validator-free Haskell mirror of
@onchain\/lib\/cardano_keri\/checkpoint\/entitlement.ak@ and of the enforcement
observer's @EnforcementProofV1@ payload (@MOD-271-OBSERVER@, T254-107).

This module is the seam between two things that must never be conflated.
"Cardano.KERI.AID.Checkpoint.BountyCommitment" owns the commitment object and
its hash, and at that boundary the enforcement evidence digest is __opaque__.
The enforcement observer owns the __actual__ Freeze\/Convict evidence, so
deriving the canonical digest from that complete payload and reconciling it
with the named mature commitment is this module's row.

Consent is not entitlement.  A signature proves a party agrees to be paid; it
never proves that party earned the payment, because an attacker signs as
itself and names itself.  Only a prior, matured, hash-committed reservation
over (checkpoint, action, actual evidence, payee, nonce) distinguishes the two.

The rule is modelled over an explicit 'SettlementContext' rather than a ledger
transaction: it names exactly the facts the on-chain rule reads, so a parity
vector can vary one of them at a time.  What that abstraction deliberately
does /not/ model is stated on 'SettlementContext' itself.
-}
module Cardano.KERI.AID.Checkpoint.Entitlement (
    -- * The enforcement observer payload
    EnforcementProofV1 (..),

    -- * Canonical evidence digest
    enforcementEvidenceDigest,
    entitlementMatches,

    -- * Settlement context
    SettlementOutput (..),
    SettlementContext (..),

    -- * The shared settlement rule
    validateEntitledEnforcement,
    validateFreezeEntitlement,
    validateConvictEntitlement,

    -- * Payout admissibility
    validateClaimEntitledPayout,
    validateConvictPayouts,

    -- * Builder
    EntitledEnforcementPlan (..),
    EntitledEnforcementError (..),
    prepareEntitledEnforcement,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_256,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    BountyAction (..),
    BountyCommitment (..),
    BountyRevealV1 (..),
    BountyScope (..),
    CommitmentFamily (..),
    CommitmentParameters (..),
    CommitmentPayout (..),
    EntitlementError (..),
    EntitlementVerdict (..),
    ResolvedCommitment (..),
    SlotRange,
    atOrAfter,
    atOrBefore,
    ownCommitment,
 )
import Cardano.KERI.AID.Checkpoint.BountyCommitment qualified as Component
import Cardano.KERI.AID.Checkpoint.Enforcement (
    EnforcementEvidence,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    ArmedDatum,
    Role (..),
    armedHunter,
 )
import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    OutputRef,
    canonicalCbor,
 )
import Data.ByteString (
    ByteString,
 )
import Data.List (
    find,
 )
import Data.Proxy (
    Proxy (..),
 )

-- ---------------------------------------------------------
-- The enforcement observer payload
-- ---------------------------------------------------------

{- | @DAT-254-ENFORCEMENT-PROOF@.  The enforcement observer's payload.

It carries the actual KERI evidence exactly as before, and adds the two facts
an entitlement verdict needs and evidence alone cannot supply: WHO this
enforcement is about to pay, and WHICH prior reservation earns it.

@epPayeePkh@ is stated here rather than inferred because the observer must be
able to authorize one specific beneficiary.  The combined register compares
this field against the payee it actually routes value to, so an envelope
naming the honest hunter cannot be paired with a redeemer paying an attacker.

Field order is wire surface; its @Data@ encoding lives in
"Cardano.KERI.AID.Checkpoint.Wire" beside the other observer envelopes.
-}
data EnforcementProofV1 = EnforcementProofV1
    { epEvidence :: !EnforcementEvidence
    , epPayeePkh :: !ByteString
    , epReveal :: !BountyRevealV1
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Canonical evidence digest
-- ---------------------------------------------------------

{- | The canonical digest of the COMPLETE actual enforcement payload.

Every field of the observer's evidence is inside the hash — the signed event
bytes, every offset, the decoded key material, both thresholds, and both
signature lists.  Mutating any one of them yields a different digest, which is
precisely why a caller-supplied digest can never establish entitlement: the
commitment was opened over the digest of the evidence the hunter actually
found, and only that evidence reproduces it.
-}
enforcementEvidenceDigest :: EnforcementEvidence -> ByteString
enforcementEvidenceDigest =
    digest (Proxy @Blake2b_256) . canonicalCbor

{- | Reconcile a commitment against ACTUAL evidence.

This is the component's pure matcher with the opaque digest slot filled in
from the real observer payload rather than from anything the caller says.  The
component still owns the hash recomputation, so independently changing any
scope field, the payee, the evidence, or the nonce breaks the match.
-}
entitlementMatches ::
    BountyCommitment ->
    OutputRef ->
    BountyAction ->
    EnforcementEvidence ->
    ByteString ->
    EntitlementVerdict
entitlementMatches commitment checkpointRef action evidence =
    Component.entitlementMatches
        commitment
        checkpointRef
        action
        (enforcementEvidenceDigest evidence)

-- ---------------------------------------------------------
-- Settlement context
-- ---------------------------------------------------------

{- | One transaction output, in the shape the payout legs actually read: a
payment credential, whether it carries a delegation part, and whether it
carries a datum or a reference script.  Value is deliberately absent — the
shared rule constrains the payout's /shape/, and the lovelace magnitude stays
with the checkpoint, which owns the bond parameter.
-}
data SettlementOutput = SettlementOutput
    { soPaymentCredential :: !AddressCredential
    , soHasStakeCredential :: !Bool
    , soHasDatum :: !Bool
    , soHasReferenceScript :: !Bool
    }
    deriving stock (Show, Eq)

{- | Exactly the transaction facts the shared settlement rule reads.

@scCommitmentInputs@ holds the resolved commitment-shaped inputs.  An input
that does not sit at a script credential, or whose datum is not a decodable
inline commitment, is simply absent from this list — the on-chain
@own_commitment@ returns @None@ for all three cases, so collapsing them here
loses no verdict.  What this model does __not__ carry is anything the rule
never reads: fee, certificates, withdrawals, reference inputs, or any mint
outside the commitment policy.
-}
data SettlementContext = SettlementContext
    { scCommitmentInputs :: ![ResolvedCommitment]
    , scValidity :: !SlotRange
    , scPolicyMint :: ![(ByteString, Integer)]
    -- ^ the whole mint map under the resolved commitment policy
    , scOutputs :: ![SettlementOutput]
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- The shared settlement rule
-- ---------------------------------------------------------

{- | The shared settlement rule behind both enforcement actions.

Every leg is load-bearing:

* the FAMILY POLICY PIN establishes that the consumed reservation belongs to
  this release's commitment program at all.  Without it the rule accepts a
  commitment-shaped datum at ANY script: an attacker deploys an
  always-succeeding script, self-mints a marker, parks exactly the deposit
  beside it and authors the whole datum — matching scope, its own payee, the
  digest of someone else's evidence, and an @eligible_after@ already in the
  past — so every remaining leg passes and the substitution attack settles
  with no reservation, no capital at risk and no aging.
  @INV-271-COMMITMENT-POLICY-AUTHENTICITY@.
* 'ownCommitment' establishes STRUCTURAL AUTHENTICITY — the named input holds
  exactly its own seed-derived marker plus the applied deposit.
* 'entitlementMatches' establishes SCOPE over actual evidence.
* the payee equality establishes that the settlement pays the committed
  beneficiary and no one else.  This is the leg the substitution attack
  breaks, and the reason a signature check cannot replace it.
* maturity and expiry establish LIVENESS.
* the marker burn makes the reveal SINGLE-USE.

Note what is deliberately absent: no fresh signature from the payee is
required here.  Consent was given when the commitment was opened and its
deposit locked; requiring it again would hand any party a veto.

Note also what this rule does NOT recheck, and why that is sound only because
of the policy pin.  Scope well-formedness is established once, at open time,
by the genuine commitment program running over @cfParameters@.  That
inheritance is exactly what the pin buys.
-}
validateEntitledEnforcement ::
    CommitmentFamily ->
    BountyAction ->
    EnforcementEvidence ->
    -- | the payee this settlement is about to pay
    ByteString ->
    BountyRevealV1 ->
    -- | the checkpoint output being settled
    OutputRef ->
    SettlementContext ->
    Bool
validateEntitledEnforcement
    family
    action
    evidence
    payee
    reveal
    checkpointRef
    context =
        case resolveCommitment family reveal context of
            Nothing -> False
            Just (policy, commitment) ->
                -- The pin comes FIRST: nothing below can authorize a
                -- settlement out of a reservation that never belonged to
                -- this release's family.
                policy == cfPolicy family
                    && entitlementMatches
                        commitment
                        checkpointRef
                        action
                        evidence
                        (brNonce reveal)
                        == EntitlementValid
                    && bcPayeePkh commitment == payee
                    && atOrAfter
                        (scValidity context)
                        (bsEligibleAfter (bcScope commitment))
                    && atOrBefore
                        (scValidity context)
                        (bsExpiresAt (bcScope commitment))
                    && burnsExactlyOne context (bcMarker commitment)

{- | The authentic commitment the reveal names, or 'Nothing' when the named
input is absent, is not commitment-shaped, or does not hold exactly its own
marker plus the applied deposit.
-}
resolveCommitment ::
    CommitmentFamily ->
    BountyRevealV1 ->
    SettlementContext ->
    Maybe (ByteString, BountyCommitment)
resolveCommitment family reveal context = do
    resolved <-
        find
            ((== brCommitmentRef reveal) . rcRef)
            (scCommitmentInputs context)
    ownCommitment (cfParameters family) resolved

{- | The transaction's whole mint map under the commitment policy is exactly
one entry burning exactly one marker.
-}
burnsExactlyOne :: SettlementContext -> ByteString -> Bool
burnsExactlyOne context marker = scPolicyMint context == [(marker, -1)]

{- | Freeze entitlement: the hunter named by this arming transaction must be
the payee of a matured, authentic commitment opened over THIS checkpoint, the
Freeze action, and the digest of THIS actual evidence.
-}
validateFreezeEntitlement ::
    CommitmentFamily ->
    EnforcementEvidence ->
    ByteString ->
    BountyRevealV1 ->
    OutputRef ->
    SettlementContext ->
    Bool
validateFreezeEntitlement family =
    validateEntitledEnforcement family FreezeEntitlement

{- | Convict entitlement, over any of ACTIVE, ARMED or FROZEN.  The action is
a distinct scope value, so a Freeze reservation can never be spent as a
Convict one.
-}
validateConvictEntitlement ::
    CommitmentFamily ->
    EnforcementEvidence ->
    ByteString ->
    BountyRevealV1 ->
    OutputRef ->
    SettlementContext ->
    Bool
validateConvictEntitlement family =
    validateEntitledEnforcement family ConvictEntitlement

-- ---------------------------------------------------------
-- Payout admissibility
-- ---------------------------------------------------------

{- | Claim pays the hunter recorded in the ARMED state — stored consent, not a
fresh redeemer field and not a fresh signature.

The beneficiary is read through 'armedHunter' and nothing else, so Claim
cannot acquire a new payee.  The output must be a datum-free,
reference-script-free enterprise payout to that exact key hash.
-}
validateClaimEntitledPayout ::
    ArmedDatum -> Integer -> [SettlementOutput] -> Bool
validateClaimEntitledPayout armed hunterOutputIndex outputs =
    case indexOutput outputs hunterOutputIndex of
        Nothing -> False
        Just out ->
            soPaymentCredential out
                == VerificationKeyCredential (armedHunter armed)
                && not (soHasStakeCredential out)
                && not (soHasDatum out)
                && not (soHasReferenceScript out)

{- | Admissibility of a conviction's payout structure for the source role.

The convictor's entitlement is a STRUCTURAL precondition of any payout: a
conviction that did not establish entitlement routes nothing at all, whatever
its indices say.  ARMED additionally keeps the two protected payouts at
distinct indices so one output cannot satisfy both the convictor's deposit and
the hunter's bond.  A tombstone is terminal and admits no payout.
-}
validateConvictPayouts ::
    Role -> Bool -> Integer -> Integer -> [SettlementOutput] -> Bool
validateConvictPayouts source validEntitlement convictorIndex hunterIndex outputs =
    validEntitlement
        && convictorIndex >= 0
        && convictorIndex < outputCount
        && case source of
            Armed ->
                convictorIndex /= hunterIndex
                    && hunterIndex >= 0
                    && hunterIndex < outputCount
            Active -> True
            Frozen -> True
            Tombstone -> False
  where
    outputCount = fromIntegral (length outputs)

-- | Aiken @list.at@: a negative or out-of-range index resolves to nothing.
indexOutput :: [SettlementOutput] -> Integer -> Maybe SettlementOutput
indexOutput outputs index
    | index < 0 = Nothing
    | index >= fromIntegral (length outputs) = Nothing
    | otherwise = Just (outputs !! fromIntegral index)

-- ---------------------------------------------------------
-- Builder
-- ---------------------------------------------------------

{- | Everything a caller must place in an entitled enforcement transaction.

Nothing here is invented.  The commitment is one the caller resolved from
chain state, the digest is derived from the evidence the observer will itself
validate, and the payee is the one the reservation already named.
-}
data EntitledEnforcementPlan = EntitledEnforcementPlan
    { eepAction :: !BountyAction
    , eepCheckpointRef :: !OutputRef
    -- ^ the checkpoint output being settled
    , eepCommitmentRef :: !OutputRef
    -- ^ the reservation input being revealed and retired
    , eepPolicy :: !ByteString
    -- ^ the pinned commitment policy the marker burns under
    , eepReveal :: !BountyRevealV1
    , eepProof :: !EnforcementProofV1
    -- ^ the observer envelope payload
    , eepBurn :: !(ByteString, Integer)
    -- ^ the whole mint map under the policy: this marker, quantity minus one
    , eepRefund :: !CommitmentPayout
    -- ^ the exact deposit refund the commitment program requires
    , eepBountyPayee :: !ByteString
    -- ^ the beneficiary the checkpoint family pays
    , eepRequiredSigners :: ![ByteString]
    -- ^ the commitment program's reveal signature, and nothing else
    }
    deriving stock (Show, Eq)

-- | Why an entitled enforcement cannot be built.
data EntitledEnforcementError
    = -- | the named input is not an authentic reservation by value
      EnforcementCommitmentCounterfeit
    | -- | the reservation does not belong to this release's family
      EnforcementForeignPolicy
    | -- | the reservation does not cover this settlement
      EnforcementNotEntitled !EntitlementError
    | -- | the reservation names a different beneficiary
      EnforcementPayeeMismatch
    | -- | the declared window is not entirely at or after maturity
      EnforcementNotMature
    | -- | the declared window is not entirely at or before expiry
      EnforcementExpired
    deriving stock (Show, Eq)

{- | Build the exact reveal of one matured reservation against actual
enforcement evidence.

The digest is __derived here from the evidence__, never accepted from a
caller, and every leg the on-chain rule will apply is applied first, in the
same order — policy pin, scope match, payee, maturity, expiry — so a
settlement that could not succeed is refused off chain rather than on it.

This is the boundary at which "no builder may synthesize entitlement at
reveal" is enforced: 'prepareEntitledEnforcement' cannot mint a reservation,
cannot choose a payee, and cannot move a boundary.  Everything it emits is
read out of the reservation the caller resolved.  Opening a reservation is a
strictly earlier, separate transaction built by
@Cardano.KERI.AID.Checkpoint.BountyCommitment.prepareBountyCommitment@.
-}
prepareEntitledEnforcement ::
    -- | the deployed commitment family the checkpoint program is applied to
    CommitmentFamily ->
    -- | the reservation resolved from chain state
    ResolvedCommitment ->
    -- | which enforcement action is being settled
    BountyAction ->
    -- | the COMPLETE actual enforcement evidence
    EnforcementEvidence ->
    -- | the checkpoint output being settled
    OutputRef ->
    -- | the reveal nonce
    ByteString ->
    -- | the output index the deposit refund sits at
    Integer ->
    -- | the declared settlement validity range
    SlotRange ->
    Either EntitledEnforcementError EntitledEnforcementPlan
prepareEntitledEnforcement
    family
    resolved
    action
    evidence
    checkpointRef
    nonce
    refundIndex
    range = do
        (policy, commitment) <-
            maybe
                (Left EnforcementCommitmentCounterfeit)
                Right
                (ownCommitment (cfParameters family) resolved)
        if policy == cfPolicy family
            then Right ()
            else Left EnforcementForeignPolicy
        case entitlementMatches
            commitment
            checkpointRef
            action
            evidence
            nonce of
            EntitlementInvalid reason ->
                Left (EnforcementNotEntitled reason)
            EntitlementValid -> Right ()
        let scope = bcScope commitment
            payee = bcPayeePkh commitment
        if atOrAfter range (bsEligibleAfter scope)
            then Right ()
            else Left EnforcementNotMature
        if atOrBefore range (bsExpiresAt scope)
            then Right ()
            else Left EnforcementExpired
        let reveal =
                BountyRevealV1
                    { brCommitmentRef = rcRef resolved
                    , brNonce = nonce
                    , brRefundIndex = refundIndex
                    }
        pure
            EntitledEnforcementPlan
                { eepAction = action
                , eepCheckpointRef = checkpointRef
                , eepCommitmentRef = rcRef resolved
                , eepPolicy = policy
                , eepReveal = reveal
                , eepProof =
                    EnforcementProofV1
                        { epEvidence = evidence
                        , epPayeePkh = payee
                        , epReveal = reveal
                        }
                , eepBurn = (bcMarker commitment, -1)
                , eepRefund =
                    CommitmentPayout
                        { cpoIndex = refundIndex
                        , cpoRecipientPkh = payee
                        , cpoLovelace = cpCommitDeposit (cfParameters family)
                        }
                , eepBountyPayee = payee
                , eepRequiredSigners = [payee]
                }
