{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.BountyCommitment
Description : Off-chain mirror of the #271 bounty-commitment component

The validator-free Haskell mirror of
@onchain\/lib\/cardano_keri\/bounty_commitment.ak@ (@MOD-271-PROTOCOL@ +
@MOD-271-COMMITMENT@), adopted by #254 S254-E.  It owns the versioned
entitlement action, scope, opaque preimage and hash, marker identity,
reveal\/sweep data, applied parameters, the raw validity-range semantics, and
the three structured verdicts — plus the two builders that turn resolved chain
state into an exact opening or expired-sweep plan.

The enforcement evidence digest is an __opaque__ 32-byte value here, exactly
as it is on chain: this module cannot and does not claim a supplied digest is
the digest of actual evidence.  Deriving it from a real
'Cardano.KERI.AID.Checkpoint.Enforcement.EnforcementEvidence' is
"Cardano.KERI.AID.Checkpoint.Entitlement"'s row (@DATA-INV-271-02@).

Every wire shape below is byte-identical to the Aiken one and to the frozen
oracle in @offchain\/app\/GenBountyCommitmentVectors.hs@; the generated
vectors are what keep the three from drifting apart.
-}
module Cardano.KERI.AID.Checkpoint.BountyCommitment (
    -- * Frozen protocol surface
    commitmentDomain,
    commitmentSchema,
    commitMinAge,
    commitDepositFloor,
    markerWidth,
    pkhWidth,
    digestWidth,
    nonceMinWidth,

    -- * Wire types
    BountyAction (..),
    BountyScope (..),
    BountyCommitmentPreimage (..),
    BountyCommitment (..),
    BountyRevealV1 (..),
    ExpiredCommitmentSweepV1 (..),
    BountySpend (..),
    BountyMint (..),
    CommitmentParameters (..),
    CommitmentFamily (..),

    -- * Structured verdicts
    ParametersError (..),
    ParametersVerdict (..),
    ScopeError (..),
    ScopeVerdict (..),
    CommitmentError (..),
    CommitmentVerdict (..),
    EntitlementError (..),
    EntitlementVerdict (..),

    -- * Pure protocol
    markerName,
    commitmentPreimage,
    commitmentHash,
    parametersWellFormed,
    scopeWellFormed,
    commitmentWellFormed,
    entitlementMatches,

    -- * Raw validity-range semantics
    SlotRange (..),
    rawUpper,
    earliestSlot,
    latestSlot,
    nonEmpty,
    atOrAfter,
    atOrBefore,
    strictlyAfter,

    -- * Resolved chain state
    ResolvedCommitment (..),
    ownCommitment,

    -- * Builders
    CommitmentPayout (..),
    BountyCommitmentPlan (..),
    CommitmentOpenError (..),
    prepareBountyCommitment,
    ExpiredSweepPlan (..),
    ExpiredSweepError (..),
    prepareExpiredSweep,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_256,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Inclusivity (..),
    RawBound (..),
 )
import Cardano.KERI.AID.Migration.Types (
    OutputRef (..),
    canonicalCbor,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Proxy (
    Proxy (..),
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- ---------------------------------------------------------
-- Frozen protocol surface
-- ---------------------------------------------------------

{- | Canonical protocol domain.  Part of every commitment preimage, so a
foreign domain can never collide with this family's hashes.
-}
commitmentDomain :: ByteString
commitmentDomain = "cardano-keri/bounty-commitment"

-- | Canonical schema version of the wire shapes in this module.
commitmentSchema :: Integer
commitmentSchema = 1

-- | Mandated minimum commitment age: one network slot.
commitMinAge :: Integer
commitMinAge = 1

{- | Mandated floor for the applied commitment deposit, in lovelace.

Be exact about what it buys.  It raises the /concurrent capital/ an attacker
must lock to open @Open_1..Open_N@ over candidate
checkpoint\/action\/evidence preimages and reveal only the one that matches.
It does not defeat that grind and does not force a loss: the permissionless
expired sweep bounds how long each losing commitment's UTxO lives, and the
attacker may self-sweep its own expired losers and recycle the deposit.  A
surviving economic residual, not a defeated attack.
-}
commitDepositFloor :: Integer
commitDepositFloor = 5_000_000

-- | Marker asset names are a full blake2b-256 digest.
markerWidth :: Int
markerWidth = 32

-- | Cardano verification-key hash width.
pkhWidth :: Int
pkhWidth = 28

-- | Enforcement evidence digest width.
digestWidth :: Int
digestWidth = 32

-- | Minimum commitment nonce width.
nonceMinWidth :: Int
nonceMinWidth = 32

-- ---------------------------------------------------------
-- Wire types
-- ---------------------------------------------------------

{- | Closed versioned entitlement action.  Claim has no action of its own: it
consumes the hunter entitlement Freeze already recorded.
-}
data BountyAction
    = FreezeEntitlement
    | ConvictEntitlement
    deriving stock (Show, Eq)

{- | @DAT-271-SCOPE@.  Everything a commitment is scoped to, all of it inside
the hashed preimage, so no field can be swapped after the fact.
-}
data BountyScope = BountyScope
    { bsDomain :: !ByteString
    , bsSchema :: !Integer
    , bsNetwork :: !Integer
    , bsCheckpointPolicy :: !ByteString
    , bsCheckpointRef :: !OutputRef
    , bsAction :: !BountyAction
    , bsMarker :: !ByteString
    , bsCommitUpper :: !Integer
    , bsEligibleAfter :: !Integer
    , bsExpiresAt :: !Integer
    }
    deriving stock (Show, Eq)

{- | @DAT-271-PREIMAGE@.  Its canonical serialization is frozen protocol
surface; the digest and nonce never appear in the live datum.
-}
data BountyCommitmentPreimage = BountyCommitmentPreimage
    { bcpScope :: !BountyScope
    , bcpEvidenceDigest :: !ByteString
    , bcpPayeePkh :: !ByteString
    , bcpNonce :: !ByteString
    }
    deriving stock (Show, Eq)

{- | @DAT-271-COMMITMENT@.  Versioned by constructor: @BountyCommitmentV1@
bytes are frozen once deployed.
-}
data BountyCommitment = BountyCommitmentV1
    { bcScope :: !BountyScope
    , bcPayeePkh :: !ByteString
    , bcHash :: !ByteString
    , bcMarker :: !ByteString
    }
    deriving stock (Show, Eq)

-- | @DAT-271-REVEAL@.  The evidence is not duplicated here.
data BountyRevealV1 = BountyRevealV1
    { brCommitmentRef :: !OutputRef
    , brNonce :: !ByteString
    , brRefundIndex :: !Integer
    }
    deriving stock (Show, Eq)

-- | @DAT-271-SWEEP@.
data ExpiredCommitmentSweepV1 = ExpiredCommitmentSweepV1
    { ecsRecipientPkh :: !ByteString
    , ecsPayoutIndex :: !Integer
    }
    deriving stock (Show, Eq)

-- | Spending redeemer of the commitment program.
data BountySpend
    = Reveal !BountyRevealV1
    | Sweep !ExpiredCommitmentSweepV1
    deriving stock (Show, Eq)

-- | Minting redeemer of the commitment program.
data BountyMint
    = Open !OutputRef
    | Retire
    deriving stock (Show, Eq)

{- | @DAT-271-PARAMETERS@, applied magnitudes only.  No ambient manifest
lookup and no protocol default: every value, including the release lifetime,
is an explicit argument of the applied program.
-}
data CommitmentParameters = CommitmentParameters
    { cpNetwork :: !Integer
    , cpCommitMinAge :: !Integer
    , cpCommitmentLifetime :: !Integer
    , cpCommitDeposit :: !Integer
    }
    deriving stock (Show, Eq)

{- | Deployment identity of the applied program.  The #254 registry and the
enforcement observer name the policy through this record; the script itself
learns its policy from the ledger context instead, because embedding its own
hash as a parameter would be circular.
-}
data CommitmentFamily = CommitmentFamily
    { cfPolicy :: !ByteString
    , cfParameters :: !CommitmentParameters
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Canonical codecs
-- ---------------------------------------------------------

-- | Strip the 'BuiltinData' wrapper from a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- | Decode a public 'Data' tree through a frozen wire codec.
fromData :: (FromData a) => Data -> Maybe a
fromData = fromBuiltinData . BuiltinData

instance ToData BountyAction where
    toBuiltinData = \case
        FreezeEntitlement -> BuiltinData (Constr 0 [])
        ConvictEntitlement -> BuiltinData (Constr 1 [])

instance FromData BountyAction where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [] -> Just FreezeEntitlement
        Constr 1 [] -> Just ConvictEntitlement
        _ -> Nothing

instance ToData BountyScope where
    toBuiltinData BountyScope{..} =
        BuiltinData $
            Constr
                0
                [ B bsDomain
                , I bsSchema
                , I bsNetwork
                , B bsCheckpointPolicy
                , asData bsCheckpointRef
                , asData bsAction
                , B bsMarker
                , I bsCommitUpper
                , I bsEligibleAfter
                , I bsExpiresAt
                ]

instance FromData BountyScope where
    fromBuiltinData (BuiltinData d) = case d of
        Constr
            0
            [ B domain
                , I schema
                , I network
                , B policy
                , ref
                , action
                , B marker
                , I upper
                , I eligible
                , I expires
                ] ->
                BountyScope domain schema network policy
                    <$> fromData ref
                    <*> fromData action
                    <*> pure marker
                    <*> pure upper
                    <*> pure eligible
                    <*> pure expires
        _ -> Nothing

instance ToData BountyCommitmentPreimage where
    toBuiltinData BountyCommitmentPreimage{..} =
        BuiltinData $
            Constr
                0
                [ asData bcpScope
                , B bcpEvidenceDigest
                , B bcpPayeePkh
                , B bcpNonce
                ]

instance FromData BountyCommitmentPreimage where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [scope, B evidenceDigest, B payee, B nonce] ->
            BountyCommitmentPreimage
                <$> fromData scope
                <*> pure evidenceDigest
                <*> pure payee
                <*> pure nonce
        _ -> Nothing

instance ToData BountyCommitment where
    toBuiltinData BountyCommitmentV1{..} =
        BuiltinData $
            Constr 0 [asData bcScope, B bcPayeePkh, B bcHash, B bcMarker]

instance FromData BountyCommitment where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [scope, B payee, B hash, B marker] ->
            BountyCommitmentV1
                <$> fromData scope
                <*> pure payee
                <*> pure hash
                <*> pure marker
        _ -> Nothing

instance ToData BountyRevealV1 where
    toBuiltinData BountyRevealV1{..} =
        BuiltinData $
            Constr
                0
                [asData brCommitmentRef, B brNonce, I brRefundIndex]

instance FromData BountyRevealV1 where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [ref, B nonce, I refundIndex] ->
            BountyRevealV1 <$> fromData ref <*> pure nonce <*> pure refundIndex
        _ -> Nothing

instance ToData ExpiredCommitmentSweepV1 where
    toBuiltinData ExpiredCommitmentSweepV1{..} =
        BuiltinData $
            Constr 0 [B ecsRecipientPkh, I ecsPayoutIndex]

instance FromData ExpiredCommitmentSweepV1 where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B recipient, I payoutIndex] ->
            Just (ExpiredCommitmentSweepV1 recipient payoutIndex)
        _ -> Nothing

instance ToData BountySpend where
    toBuiltinData = \case
        Reveal reveal -> BuiltinData (Constr 0 [asData reveal])
        Sweep sweep -> BuiltinData (Constr 1 [asData sweep])

instance FromData BountySpend where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [reveal] -> Reveal <$> fromData reveal
        Constr 1 [sweep] -> Sweep <$> fromData sweep
        _ -> Nothing

instance ToData BountyMint where
    toBuiltinData = \case
        Open seedRef -> BuiltinData (Constr 0 [asData seedRef])
        Retire -> BuiltinData (Constr 1 [])

instance FromData BountyMint where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [seedRef] -> Open <$> fromData seedRef
        Constr 1 [] -> Just Retire
        _ -> Nothing

instance ToData CommitmentParameters where
    toBuiltinData CommitmentParameters{..} =
        BuiltinData $
            Constr
                0
                [ I cpNetwork
                , I cpCommitMinAge
                , I cpCommitmentLifetime
                , I cpCommitDeposit
                ]

instance FromData CommitmentParameters where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [I network, I minAge, I lifetime, I deposit] ->
            Just (CommitmentParameters network minAge lifetime deposit)
        _ -> Nothing

instance ToData CommitmentFamily where
    toBuiltinData CommitmentFamily{..} =
        BuiltinData $ Constr 0 [B cfPolicy, asData cfParameters]

instance FromData CommitmentFamily where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B policy, parameters] ->
            CommitmentFamily policy <$> fromData parameters
        _ -> Nothing

-- ---------------------------------------------------------
-- Structured verdicts
-- ---------------------------------------------------------

-- | Why applied magnitudes are inadmissible.
data ParametersError
    = ParametersAge
    | ParametersLifetime
    | ParametersDeposit
    deriving stock (Show, Eq)

-- | Applied-magnitude verdict.
data ParametersVerdict
    = ParametersValid
    | ParametersInvalid !ParametersError
    deriving stock (Show, Eq)

-- | Why a scope is not well formed against the applied parameters.
data ScopeError
    = ScopeDomain
    | ScopeSchema
    | ScopeNetwork
    | ScopeCheckpointPolicyWidth
    | ScopeCheckpointRefWidth
    | ScopeMarkerWidth
    | ScopeAge
    | ScopeLifetime
    deriving stock (Show, Eq)

-- | Scope well-formedness verdict.
data ScopeVerdict
    = ScopeValid
    | ScopeInvalid !ScopeError
    deriving stock (Show, Eq)

-- | Why a commitment datum is not well formed.
data CommitmentError
    = CommitmentScope !ScopeError
    | CommitmentPayeeWidth
    | CommitmentHashWidth
    | CommitmentMarkerBinding
    deriving stock (Show, Eq)

-- | Commitment datum verdict.
data CommitmentVerdict
    = CommitmentValid
    | CommitmentInvalid !CommitmentError
    deriving stock (Show, Eq)

-- | Why a commitment does not match the named entitlement.
data EntitlementError
    = EntitlementDigestWidth
    | EntitlementNonceWidth
    | EntitlementAction
    | EntitlementCheckpoint
    | EntitlementMarker
    | EntitlementHash
    deriving stock (Show, Eq)

-- | Entitlement matching verdict.
data EntitlementVerdict
    = EntitlementValid
    | EntitlementInvalid !EntitlementError
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Pure protocol
-- ---------------------------------------------------------

{- | @DAT-271-MARKER@.  The marker name derives from the consumed opening seed
and from nothing else, so two openings cannot counterfeit one identity.
-}
markerName :: OutputRef -> ByteString
markerName = blake2b256 . canonicalCbor

-- | Assemble a preimage.  Pure: no transaction or KERI effect.
commitmentPreimage ::
    BountyScope ->
    ByteString ->
    ByteString ->
    ByteString ->
    BountyCommitmentPreimage
commitmentPreimage scope evidenceDigest payeePkh nonce =
    BountyCommitmentPreimage
        { bcpScope = scope
        , bcpEvidenceDigest = evidenceDigest
        , bcpPayeePkh = payeePkh
        , bcpNonce = nonce
        }

{- | The canonical commitment hash: blake2b-256 of the canonical versioned
serialization of the preimage.  Identical in Haskell and Aiken.
-}
commitmentHash :: BountyCommitmentPreimage -> ByteString
commitmentHash = blake2b256 . canonicalCbor

blake2b256 :: ByteString -> ByteString
blake2b256 = digest (Proxy @Blake2b_256)

{- | The applied magnitudes must be admissible: exactly the mandated one-slot
age, an explicit release lifetime long enough to contain at least one mature
reveal slot, and a deposit at or above the floor.

Because the first leg has already pinned the applied age to the mandated one
slot, the lifetime comparison is also what rejects zero and negative
lifetimes — they are one class of magnitude, not three.
-}
parametersWellFormed :: CommitmentParameters -> ParametersVerdict
parametersWellFormed CommitmentParameters{..}
    | cpCommitMinAge /= commitMinAge = ParametersInvalid ParametersAge
    | cpCommitmentLifetime < cpCommitMinAge =
        ParametersInvalid ParametersLifetime
    | cpCommitDeposit < commitDepositFloor =
        ParametersInvalid ParametersDeposit
    | otherwise = ParametersValid

{- | Scope well-formedness against the applied parameters, including the two
derived timing identities.  @eligible_after@ and @expires_at@ are /derived/
from the stored raw opening endpoint, never merely asserted.
-}
scopeWellFormed :: CommitmentParameters -> BountyScope -> ScopeVerdict
scopeWellFormed parameters BountyScope{..}
    | bsDomain /= commitmentDomain = ScopeInvalid ScopeDomain
    | bsSchema /= commitmentSchema = ScopeInvalid ScopeSchema
    | bsNetwork /= cpNetwork parameters = ScopeInvalid ScopeNetwork
    | BS.length bsCheckpointPolicy /= pkhWidth =
        ScopeInvalid ScopeCheckpointPolicyWidth
    | BS.length (orTransactionId bsCheckpointRef) /= digestWidth
        || orOutputIndex bsCheckpointRef < 0 =
        ScopeInvalid ScopeCheckpointRefWidth
    | BS.length bsMarker /= markerWidth = ScopeInvalid ScopeMarkerWidth
    | bsEligibleAfter /= bsCommitUpper + cpCommitMinAge parameters =
        ScopeInvalid ScopeAge
    | bsExpiresAt /= bsCommitUpper + cpCommitmentLifetime parameters =
        ScopeInvalid ScopeLifetime
    | otherwise = ScopeValid

{- | Datum well-formedness: a well-formed scope, canonical widths, and the
marker binding between datum and scope.
-}
commitmentWellFormed ::
    CommitmentParameters -> BountyCommitment -> CommitmentVerdict
commitmentWellFormed parameters BountyCommitmentV1{..} =
    case scopeWellFormed parameters bcScope of
        ScopeInvalid reason -> CommitmentInvalid (CommitmentScope reason)
        ScopeValid
            | BS.length bcPayeePkh /= pkhWidth ->
                CommitmentInvalid CommitmentPayeeWidth
            | BS.length bcHash /= digestWidth ->
                CommitmentInvalid CommitmentHashWidth
            | bcMarker /= bsMarker bcScope ->
                CommitmentInvalid CommitmentMarkerBinding
            | otherwise -> CommitmentValid

{- | Pure standalone scope\/preimage matching.  It recomputes the commitment
hash from the committed scope and payee plus the supplied digest and nonce, so
independently changing any scope field, the payee, the digest, or the nonce
breaks the match.

It deliberately does __not__ claim the digest is the digest of actual
evidence, and it touches no checkpoint state: that coupling is the enforcement
observer's obligation (@DATA-INV-271-02@, S254-E).
-}
entitlementMatches ::
    BountyCommitment ->
    OutputRef ->
    BountyAction ->
    ByteString ->
    ByteString ->
    EntitlementVerdict
entitlementMatches commitment checkpointRef action evidenceDigest nonce
    | BS.length evidenceDigest /= digestWidth =
        EntitlementInvalid EntitlementDigestWidth
    | BS.length nonce < nonceMinWidth =
        EntitlementInvalid EntitlementNonceWidth
    | bsAction scope /= action = EntitlementInvalid EntitlementAction
    | bsCheckpointRef scope /= checkpointRef =
        EntitlementInvalid EntitlementCheckpoint
    | bcMarker commitment /= bsMarker scope =
        EntitlementInvalid EntitlementMarker
    | recomputed /= bcHash commitment = EntitlementInvalid EntitlementHash
    | otherwise = EntitlementValid
  where
    scope = bcScope commitment
    recomputed =
        commitmentHash $
            commitmentPreimage
                scope
                evidenceDigest
                (bcPayeePkh commitment)
                nonce

-- ---------------------------------------------------------
-- Raw ledger validity-range semantics
-- ---------------------------------------------------------

{- | A ledger validity range as the component reads it: two raw bounds whose
inclusivity is preserved rather than normalized inward.
-}
data SlotRange = SlotRange
    { srLowerBound :: !RawBound
    , srUpperBound :: !RawBound
    }
    deriving stock (Show, Eq)

{- | The raw finite upper endpoint, exactly as declared.  Inclusivity is
returned, never folded away: the opening stores the raw endpoint.
-}
rawUpper :: SlotRange -> Maybe (Integer, Inclusivity)
rawUpper range = case srUpperBound range of
    Finite upper inclusivity -> Just (upper, inclusivity)
    _ -> Nothing

-- | The earliest slot the transaction can be in, honouring exclusivity.
earliestSlot :: SlotRange -> Maybe Integer
earliestSlot range = case srLowerBound range of
    Finite lower Inclusive -> Just lower
    Finite lower Exclusive -> Just (lower + 1)
    _ -> Nothing

-- | The latest slot the transaction can be in, honouring exclusivity.
latestSlot :: SlotRange -> Maybe Integer
latestSlot range = case srUpperBound range of
    Finite upper Inclusive -> Just upper
    Finite upper Exclusive -> Just (upper - 1)
    _ -> Nothing

{- | Whether the interval denotes at least one ledger slot.

This is load-bearing, not hygiene.  \"Every possible execution slot is at or
after @t@\" is __vacuously true__ over an interval that admits no slot at all,
so comparing the two endpoints independently would accept a reversed finite
window whose lower is mature and whose upper is unexpired.  Every predicate
below therefore establishes non-emptiness /first/.
-}
nonEmpty :: SlotRange -> Bool
nonEmpty range = case (srLowerBound range, srUpperBound range) of
    (_, NegativeInfinity) -> False
    (PositiveInfinity, _) -> False
    (Finite _ _, Finite _ _) ->
        case (earliestSlot range, latestSlot range) of
            (Just lower, Just upper) -> lower <= upper
            _ -> False
    _ -> True

{- | The interval denotes at least one slot, and every one of them is at or
after @t@.
-}
atOrAfter :: SlotRange -> Integer -> Bool
atOrAfter range t =
    nonEmpty range && maybe False (>= t) (earliestSlot range)

{- | The interval denotes at least one slot, and every one of them is at or
before @t@.
-}
atOrBefore :: SlotRange -> Integer -> Bool
atOrBefore range t =
    nonEmpty range && maybe False (<= t) (latestSlot range)

{- | The interval denotes at least one slot, and every one of them is strictly
after @t@.
-}
strictlyAfter :: SlotRange -> Integer -> Bool
strictlyAfter range t =
    nonEmpty range && maybe False (> t) (earliestSlot range)

-- ---------------------------------------------------------
-- Resolved chain state
-- ---------------------------------------------------------

{- | A commitment as it was actually resolved from chain state.

A builder consumes this; it never invents one.  The fields are exactly what
the on-chain @own_commitment@ reads: where the input sits, the script policy
of the credential holding it, its decoded inline datum, and the complete value
it carries.
-}
data ResolvedCommitment = ResolvedCommitment
    { rcRef :: !OutputRef
    -- ^ the output reference the commitment sits at
    , rcPolicy :: !ByteString
    -- ^ the script policy of the credential holding it
    , rcDatum :: !BountyCommitment
    -- ^ the decoded inline commitment datum
    , rcLovelace :: !Integer
    -- ^ the exact lovelace the output holds
    , rcMarkerQuantity :: !Integer
    -- ^ how many of its own marker the output holds
    , rcHoldsOtherAssets :: !Bool
    -- ^ whether anything else at all sits in the value
    }
    deriving stock (Show, Eq)

{- | The authentic commitment being spent, mirroring the on-chain
@own_commitment@ value leg: the named input must hold exactly its own
seed-derived marker plus the applied deposit.  A matching-looking datum
without that value is counterfeit and yields 'Nothing'.
-}
ownCommitment ::
    CommitmentParameters ->
    ResolvedCommitment ->
    Maybe (ByteString, BountyCommitment)
ownCommitment parameters ResolvedCommitment{..}
    | rcHoldsOtherAssets = Nothing
    | rcMarkerQuantity /= 1 = Nothing
    | rcLovelace /= cpCommitDeposit parameters = Nothing
    | otherwise = Just (rcPolicy, rcDatum)

-- ---------------------------------------------------------
-- Builders
-- ---------------------------------------------------------

-- | One exact lovelace-only enterprise payout the plan requires.
data CommitmentPayout = CommitmentPayout
    { cpoIndex :: !Integer
    , cpoRecipientPkh :: !ByteString
    , cpoLovelace :: !Integer
    }
    deriving stock (Show, Eq)

{- | Everything a caller must place in an opening transaction, and nothing it
may choose for itself.
-}
data BountyCommitmentPlan = BountyCommitmentPlan
    { bcplSeedRef :: !OutputRef
    -- ^ the exact seed input this opening consumes
    , bcplPolicy :: !ByteString
    -- ^ the applied commitment policy the marker mints under
    , bcplMintRedeemer :: !BountyMint
    -- ^ @Open@ naming that same seed
    , bcplMint :: !(ByteString, Integer)
    -- ^ the whole mint map under the policy: this marker, quantity one
    , bcplDatum :: !BountyCommitment
    -- ^ the inline datum of the single script output
    , bcplScriptOutputLovelace :: !Integer
    -- ^ exactly the applied deposit
    , bcplRequiredSigners :: ![ByteString]
    -- ^ creation-time consent of the fixed future beneficiary
    }
    deriving stock (Show, Eq)

-- | Why an opening cannot be built.
data CommitmentOpenError
    = OpenParametersInvalid !ParametersError
    | OpenCommitmentInvalid !CommitmentError
    | OpenWindowEmpty
    | OpenUpperEndpointMissing
    deriving stock (Show, Eq)

{- | Build the exact opening of one bounty commitment.

The marker is derived from the consumed seed and from nothing else, the raw
opening upper endpoint is taken from the declared validity range verbatim, and
both derived boundaries come from the applied parameters.  The plan is then
put through the same two predicates the on-chain program runs, so a commitment
that could never open is refused here instead of on chain.

The evidence digest is an argument, not a computation: at this boundary it is
opaque.  A caller that wants it bound to real enforcement evidence derives it
through @enforcementEvidenceDigest@.
-}
prepareBountyCommitment ::
    -- | applied parameters of the deployed commitment program
    CommitmentParameters ->
    -- | resolved policy of that applied program
    ByteString ->
    -- | the seed input being consumed
    OutputRef ->
    -- | the declared opening validity range
    SlotRange ->
    -- | checkpoint policy this reservation is scoped to
    ByteString ->
    -- | the exact checkpoint output being reserved against
    OutputRef ->
    -- | which enforcement action is reserved
    BountyAction ->
    -- | the opaque enforcement evidence digest
    ByteString ->
    -- | the fixed future beneficiary
    ByteString ->
    -- | the commitment nonce
    ByteString ->
    Either CommitmentOpenError BountyCommitmentPlan
prepareBountyCommitment
    parameters
    policy
    seedRef
    range
    checkpointPolicy
    checkpointRef
    action
    evidenceDigest
    payeePkh
    nonce = do
        case parametersWellFormed parameters of
            ParametersInvalid reason -> Left (OpenParametersInvalid reason)
            ParametersValid -> Right ()
        if nonEmpty range then Right () else Left OpenWindowEmpty
        commitUpper <- case rawUpper range of
            Nothing -> Left OpenUpperEndpointMissing
            Just (upper, _inclusive) -> Right upper
        let marker = markerName seedRef
            scope =
                BountyScope
                    { bsDomain = commitmentDomain
                    , bsSchema = commitmentSchema
                    , bsNetwork = cpNetwork parameters
                    , bsCheckpointPolicy = checkpointPolicy
                    , bsCheckpointRef = checkpointRef
                    , bsAction = action
                    , bsMarker = marker
                    , bsCommitUpper = commitUpper
                    , bsEligibleAfter =
                        commitUpper + cpCommitMinAge parameters
                    , bsExpiresAt =
                        commitUpper + cpCommitmentLifetime parameters
                    }
            datum =
                BountyCommitmentV1
                    { bcScope = scope
                    , bcPayeePkh = payeePkh
                    , bcHash =
                        commitmentHash $
                            commitmentPreimage
                                scope
                                evidenceDigest
                                payeePkh
                                nonce
                    , bcMarker = marker
                    }
        case commitmentWellFormed parameters datum of
            CommitmentInvalid reason -> Left (OpenCommitmentInvalid reason)
            CommitmentValid -> Right ()
        pure
            BountyCommitmentPlan
                { bcplSeedRef = seedRef
                , bcplPolicy = policy
                , bcplMintRedeemer = Open seedRef
                , bcplMint = (marker, 1)
                , bcplDatum = datum
                , bcplScriptOutputLovelace = cpCommitDeposit parameters
                , bcplRequiredSigners = [payeePkh]
                }

{- | Everything a caller must place in an expired-sweep transaction.

A sweep grants no entitlement, so the plan deliberately carries no checkpoint
effect at all: no checkpoint input, no checkpoint mint, and no settlement.
-}
data ExpiredSweepPlan = ExpiredSweepPlan
    { espCommitmentRef :: !OutputRef
    , espPolicy :: !ByteString
    , espSpendRedeemer :: !BountySpend
    , espBurn :: !(ByteString, Integer)
    -- ^ the whole mint map under the policy: this marker, quantity minus one
    , espPayout :: !CommitmentPayout
    , espRequiredSigners :: ![ByteString]
    }
    deriving stock (Show, Eq)

-- | Why an expired sweep cannot be built.
data ExpiredSweepError
    = SweepParametersInvalid !ParametersError
    | SweepCommitmentInvalid !CommitmentError
    | SweepCommitmentCounterfeit
    | SweepNotExpired
    deriving stock (Show, Eq)

{- | Build the permissionless sweep of one expired commitment.

It consumes a commitment resolved from chain state and refuses to build a
transaction the program would reject: the reservation must be authentic by
value, well formed, and strictly past its stored expiry.  Recovering the
deposit is the whole effect — the losing reservation never settles anything.
-}
prepareExpiredSweep ::
    -- | applied parameters of the deployed commitment program
    CommitmentParameters ->
    -- | the resolved commitment being swept
    ResolvedCommitment ->
    -- | the declared sweep validity range
    SlotRange ->
    -- | who receives the recovered deposit, and at which output index
    ByteString ->
    Integer ->
    Either ExpiredSweepError ExpiredSweepPlan
prepareExpiredSweep parameters resolved range recipientPkh payoutIndex = do
    case parametersWellFormed parameters of
        ParametersInvalid reason -> Left (SweepParametersInvalid reason)
        ParametersValid -> Right ()
    (policy, commitment) <- case ownCommitment parameters resolved of
        Nothing -> Left SweepCommitmentCounterfeit
        Just resolvedPair -> Right resolvedPair
    case commitmentWellFormed parameters commitment of
        CommitmentInvalid reason -> Left (SweepCommitmentInvalid reason)
        CommitmentValid -> Right ()
    let scope = bcScope commitment
    if strictlyAfter range (bsExpiresAt scope)
        then Right ()
        else Left SweepNotExpired
    let sweep =
            ExpiredCommitmentSweepV1
                { ecsRecipientPkh = recipientPkh
                , ecsPayoutIndex = payoutIndex
                }
    pure
        ExpiredSweepPlan
            { espCommitmentRef = rcRef resolved
            , espPolicy = policy
            , espSpendRedeemer = Sweep sweep
            , espBurn = (bcMarker commitment, -1)
            , espPayout =
                CommitmentPayout
                    { cpoIndex = payoutIndex
                    , cpoRecipientPkh = recipientPkh
                    , cpoLovelace = cpCommitDeposit parameters
                    }
            , espRequiredSigners = [recipientPkh]
            }
