{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.BountyCommitmentSpec
Description : S254-E unit proof of the #271 commitment component mirror

Behaviour of the off-chain bounty-commitment mirror: the derived marker, the
three structured well-formedness verdicts, the standalone entitlement matcher,
the raw validity-range semantics, authentic-value resolution, and the two
builders.

Every rejection row below is paired with an accepted honest neighbour that
differs in exactly the mutated field, so a row cannot pass because the fixture
was broken for some unrelated reason.  Cross-language byte parity is a
separate instrument: @scripts\/check-bounty-entitlement-vectors.sh@.
-}
module Cardano.KERI.AID.Checkpoint.BountyCommitmentSpec (spec) where

import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    BountyAction (..),
    BountyCommitment (..),
    BountyCommitmentPlan (..),
    BountyMint (..),
    BountyScope (..),
    BountySpend (..),
    CommitmentError (..),
    CommitmentOpenError (..),
    CommitmentParameters (..),
    CommitmentPayout (..),
    CommitmentVerdict (..),
    EntitlementError (..),
    EntitlementVerdict (..),
    ExpiredCommitmentSweepV1 (..),
    ExpiredSweepError (..),
    ExpiredSweepPlan (..),
    ParametersError (..),
    ParametersVerdict (..),
    ResolvedCommitment (..),
    ScopeError (..),
    ScopeVerdict (..),
    SlotRange (..),
    atOrAfter,
    atOrBefore,
    commitDepositFloor,
    commitMinAge,
    commitmentDomain,
    commitmentHash,
    commitmentPreimage,
    commitmentSchema,
    commitmentWellFormed,
    entitlementMatches,
    markerName,
    nonEmpty,
    ownCommitment,
    parametersWellFormed,
    prepareBountyCommitment,
    prepareExpiredSweep,
    scopeWellFormed,
    strictlyAfter,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Inclusivity (..),
    RawBound (..),
 )
import Cardano.KERI.AID.Migration.Types (
    OutputRef (..),
 )
import Data.Bits (
    xor,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
 )

spec :: Spec
spec = describe "S254-E bounty-commitment component mirror" $ do
    markerSpec
    parametersSpec
    scopeSpec
    commitmentSpec
    matcherSpec
    intervalSpec
    authenticitySpec
    openBuilderSpec
    sweepBuilderSpec

-- ---------------------------------------------------------
-- Marker identity
-- ---------------------------------------------------------

markerSpec :: Spec
markerSpec = describe "marker identity" $ do
    it "derives from the consumed seed and from nothing else" $
        markerName seedRef `shouldBe` markerName seedRef
    it "cannot be counterfeited by a second opening" $
        markerName seedRef `shouldNotBe` markerName otherSeedRef
    it "is a full blake2b-256 digest" $
        BS.length (markerName seedRef) `shouldBe` 32

-- ---------------------------------------------------------
-- Applied magnitudes
-- ---------------------------------------------------------

parametersSpec :: Spec
parametersSpec = describe "applied magnitudes" $ do
    it "accepts the honest applied parameters" $
        parametersWellFormed parameters `shouldBe` ParametersValid
    it "rejects an age other than the mandated one slot" $
        parametersWellFormed parameters{cpCommitMinAge = 2}
            `shouldBe` ParametersInvalid ParametersAge
    it "rejects a lifetime that expires before the first mature slot" $
        parametersWellFormed parameters{cpCommitmentLifetime = 0}
            `shouldBe` ParametersInvalid ParametersLifetime
    it "rejects a deposit one lovelace under the demonstrated floor" $
        parametersWellFormed
            parameters{cpCommitDeposit = commitDepositFloor - 1}
            `shouldBe` ParametersInvalid ParametersDeposit
    it "accepts a deposit exactly at the demonstrated floor" $
        parametersWellFormed parameters{cpCommitDeposit = commitDepositFloor}
            `shouldBe` ParametersValid

-- ---------------------------------------------------------
-- Scope
-- ---------------------------------------------------------

scopeSpec :: Spec
scopeSpec = describe "scope well-formedness" $ do
    it "accepts the honest scope" $
        scopeWellFormed parameters scope `shouldBe` ScopeValid
    mapM_ scopeRejection scopeMutants

scopeRejection :: (String, BountyScope, ScopeError) -> Spec
scopeRejection (name, mutant, reason) =
    it ("rejects " <> name) $
        scopeWellFormed parameters mutant `shouldBe` ScopeInvalid reason

scopeMutants :: [(String, BountyScope, ScopeError)]
scopeMutants =
    [ ("a foreign protocol domain", scope{bsDomain = "other"}, ScopeDomain)
    ,
        ( "an unknown schema version"
        , scope{bsSchema = commitmentSchema + 1}
        , ScopeSchema
        )
    ,
        ( "a scope opened for another network"
        , scope{bsNetwork = cpNetwork parameters + 1}
        , ScopeNetwork
        )
    ,
        ( "a mis-sized checkpoint policy"
        , scope{bsCheckpointPolicy = BS.replicate 27 0xc1}
        , ScopeCheckpointPolicyWidth
        )
    ,
        ( "a mis-sized checkpoint transaction id"
        , scope
            { bsCheckpointRef =
                checkpointRef{orTransactionId = BS.replicate 31 0xc2}
            }
        , ScopeCheckpointRefWidth
        )
    ,
        ( "a negative checkpoint output index"
        , scope{bsCheckpointRef = checkpointRef{orOutputIndex = -1}}
        , ScopeCheckpointRefWidth
        )
    ,
        ( "a mis-sized marker"
        , scope{bsMarker = BS.replicate 31 0x5e}
        , ScopeMarkerWidth
        )
    ,
        ( "a maturity boundary that is not derived from the opening"
        , scope{bsEligibleAfter = bsEligibleAfter scope + 1}
        , ScopeAge
        )
    ,
        ( "an expiry boundary that is not derived from the opening"
        , scope{bsExpiresAt = bsExpiresAt scope + 1}
        , ScopeLifetime
        )
    ]

-- ---------------------------------------------------------
-- Commitment datum
-- ---------------------------------------------------------

commitmentSpec :: Spec
commitmentSpec = describe "commitment datum well-formedness" $ do
    it "accepts the honest commitment" $
        commitmentWellFormed parameters commitment `shouldBe` CommitmentValid
    it "propagates the scope reason rather than flattening it" $
        commitmentWellFormed
            parameters
            commitment{bcScope = scope{bsNetwork = 99}}
            `shouldBe` CommitmentInvalid (CommitmentScope ScopeNetwork)
    it "rejects a mis-sized payee" $
        commitmentWellFormed
            parameters
            commitment{bcPayeePkh = BS.replicate 27 0x9a}
            `shouldBe` CommitmentInvalid CommitmentPayeeWidth
    it "rejects a mis-sized hash" $
        commitmentWellFormed
            parameters
            commitment{bcHash = BS.replicate 31 0xab}
            `shouldBe` CommitmentInvalid CommitmentHashWidth
    it "rejects a datum whose marker is not the scope's marker" $
        commitmentWellFormed
            parameters
            commitment{bcMarker = markerName otherSeedRef}
            `shouldBe` CommitmentInvalid CommitmentMarkerBinding

-- ---------------------------------------------------------
-- Standalone matcher
-- ---------------------------------------------------------

matcherSpec :: Spec
matcherSpec = describe "standalone entitlement matching" $ do
    it "accepts the reservation it was opened as" $
        matches commitment checkpointRef FreezeEntitlement digest nonce
            `shouldBe` EntitlementValid
    it "rejects a digest that is not 32 bytes" $
        matches
            commitment
            checkpointRef
            FreezeEntitlement
            (BS.replicate 31 0xed)
            nonce
            `shouldBe` EntitlementInvalid EntitlementDigestWidth
    it "rejects a nonce below the minimum width" $
        matches
            commitment
            checkpointRef
            FreezeEntitlement
            digest
            (BS.replicate 31 0x11)
            `shouldBe` EntitlementInvalid EntitlementNonceWidth
    it "rejects a Freeze reservation spent as a Convict one" $
        matches commitment checkpointRef ConvictEntitlement digest nonce
            `shouldBe` EntitlementInvalid EntitlementAction
    it "rejects a reservation opened over another checkpoint" $
        matches commitment otherCheckpointRef FreezeEntitlement digest nonce
            `shouldBe` EntitlementInvalid EntitlementCheckpoint
    it "rejects a datum whose marker left its scope" $
        matches
            commitment{bcMarker = markerName otherSeedRef}
            checkpointRef
            FreezeEntitlement
            digest
            nonce
            `shouldBe` EntitlementInvalid EntitlementMarker
    it "rejects a substituted evidence digest" $
        matches
            commitment
            checkpointRef
            FreezeEntitlement
            (flipLast digest)
            nonce
            `shouldBe` EntitlementInvalid EntitlementHash
    it "rejects a substituted nonce" $
        matches commitment checkpointRef FreezeEntitlement digest otherNonce
            `shouldBe` EntitlementInvalid EntitlementHash
    it "rejects a substituted payee, hash unchanged" $
        matches
            commitment{bcPayeePkh = attacker}
            checkpointRef
            FreezeEntitlement
            digest
            nonce
            `shouldBe` EntitlementInvalid EntitlementHash
  where
    matches = entitlementMatches

-- ---------------------------------------------------------
-- Raw validity-range semantics
-- ---------------------------------------------------------

intervalSpec :: Spec
intervalSpec = describe "raw validity-range semantics" $ do
    it "accepts a window that starts exactly at maturity" $
        atOrAfter (finiteRange 1001 1500) 1001 `shouldBe` True
    it "rejects a window that starts one slot early" $
        atOrAfter (finiteRange 1000 1500) 1001 `shouldBe` False
    it "accepts a window that ends exactly at expiry" $
        atOrBefore (finiteRange 1001 11_000) 11_000 `shouldBe` True
    it "rejects a window that ends one slot late" $
        atOrBefore (finiteRange 1001 11_001) 11_000 `shouldBe` False
    it "honours an exclusive lower endpoint" $
        atOrAfter (SlotRange (Finite 1000 Exclusive) (Finite 1500 Inclusive)) 1001
            `shouldBe` True
    it "honours an exclusive upper endpoint" $
        atOrBefore
            (SlotRange (Finite 1001 Inclusive) (Finite 11_001 Exclusive))
            11_000
            `shouldBe` True
    it "refuses a reversed finite window that denotes no slot at all" $ do
        nonEmpty (finiteRange 1002 1001) `shouldBe` False
        atOrAfter (finiteRange 1002 1001) 1001 `shouldBe` False
        atOrBefore (finiteRange 1002 1001) 11_000 `shouldBe` False
    it "refuses a zero-width exclusive pair" $
        nonEmpty (SlotRange (Finite 1000 Exclusive) (Finite 1001 Exclusive))
            `shouldBe` False
    it "refuses an unbounded-above window for expiry" $
        atOrBefore (SlotRange (Finite 1001 Inclusive) PositiveInfinity) 11_000
            `shouldBe` False
    it "refuses an unbounded-below window for maturity" $
        atOrAfter (SlotRange NegativeInfinity (Finite 1500 Inclusive)) 1001
            `shouldBe` False
    it "sweeps only strictly after expiry" $ do
        strictlyAfter (finiteRange 11_000 11_500) 11_000 `shouldBe` False
        strictlyAfter (finiteRange 11_001 11_500) 11_000 `shouldBe` True

-- ---------------------------------------------------------
-- Authentic value
-- ---------------------------------------------------------

authenticitySpec :: Spec
authenticitySpec = describe "authentic reservation value" $ do
    it "resolves a reservation holding exactly its marker and deposit" $
        ownCommitment parameters resolved
            `shouldBe` Just (commitmentPolicy, commitment)
    it "refuses a datum parked beside the wrong deposit" $
        ownCommitment
            parameters
            resolved{rcLovelace = cpCommitDeposit parameters - 1}
            `shouldBe` Nothing
    it "refuses a datum with no marker at all" $
        ownCommitment parameters resolved{rcMarkerQuantity = 0}
            `shouldBe` Nothing
    it "refuses a value carrying anything beyond marker and deposit" $
        ownCommitment parameters resolved{rcHoldsOtherAssets = True}
            `shouldBe` Nothing

-- ---------------------------------------------------------
-- Opening builder
-- ---------------------------------------------------------

openBuilderSpec :: Spec
openBuilderSpec = describe "prepareBountyCommitment" $ do
    it "derives the marker from the seed the plan consumes" $
        fmap bcplMint plan `shouldBe` Right (markerName seedRef, 1)
    it "opens under the Open redeemer naming that same seed" $
        fmap bcplMintRedeemer plan `shouldBe` Right (Open seedRef)
    it "confines exactly the applied deposit at the script output" $
        fmap bcplScriptOutputLovelace plan
            `shouldBe` Right (cpCommitDeposit parameters)
    it "requires the fixed future beneficiary to sign the opening" $
        fmap bcplRequiredSigners plan `shouldBe` Right [payee]
    it "stores the raw opening upper endpoint verbatim" $
        fmap (bsCommitUpper . bcScope . bcplDatum) plan `shouldBe` Right 1000
    it "derives both boundaries from the applied parameters" $ do
        fmap (bsEligibleAfter . bcScope . bcplDatum) plan `shouldBe` Right 1001
        fmap (bsExpiresAt . bcScope . bcplDatum) plan `shouldBe` Right 11_000
    it "emits a datum the on-chain well-formedness rule accepts" $
        fmap (commitmentWellFormed parameters . bcplDatum) plan
            `shouldBe` Right CommitmentValid
    it "emits a datum the standalone matcher then accepts" $
        fmap
            ( \built ->
                entitlementMatches
                    (bcplDatum built)
                    checkpointRef
                    FreezeEntitlement
                    digest
                    nonce
            )
            plan
            `shouldBe` Right EntitlementValid
    it "refuses to open under inadmissible applied magnitudes" $
        openWith parameters{cpCommitDeposit = commitDepositFloor - 1} openRange
            `shouldBe` Left (OpenParametersInvalid ParametersDeposit)
    it "refuses a reversed opening window that denotes no slot" $
        openWith parameters (finiteRange 1001 1000)
            `shouldBe` Left OpenWindowEmpty
    it "refuses an opening with no finite upper endpoint to store" $
        openWith
            parameters
            (SlotRange (Finite 900 Inclusive) PositiveInfinity)
            `shouldBe` Left OpenUpperEndpointMissing
    it "refuses to name a mis-sized beneficiary" $
        openFor (BS.replicate 27 0x9a)
            `shouldBe` Left
                (OpenCommitmentInvalid CommitmentPayeeWidth)
  where
    plan = openWith parameters openRange
    openFor beneficiary =
        prepareBountyCommitment
            parameters
            commitmentPolicy
            seedRef
            openRange
            checkpointPolicy
            checkpointRef
            FreezeEntitlement
            digest
            beneficiary
            nonce

openWith ::
    CommitmentParameters ->
    SlotRange ->
    Either CommitmentOpenError BountyCommitmentPlan
openWith params range =
    prepareBountyCommitment
        params
        commitmentPolicy
        seedRef
        range
        checkpointPolicy
        checkpointRef
        FreezeEntitlement
        digest
        payee
        nonce

-- ---------------------------------------------------------
-- Expired-sweep builder
-- ---------------------------------------------------------

sweepBuilderSpec :: Spec
sweepBuilderSpec = describe "prepareExpiredSweep" $ do
    it "recovers exactly the deposit to the signing recipient" $
        fmap espPayout swept
            `shouldBe` Right
                CommitmentPayout
                    { cpoIndex = 0
                    , cpoRecipientPkh = recipient
                    , cpoLovelace = cpCommitDeposit parameters
                    }
    it "retires the reservation by burning its one marker" $
        fmap espBurn swept `shouldBe` Right (markerName seedRef, -1)
    it "requires the recipient's own signature" $
        fmap espRequiredSigners swept `shouldBe` Right [recipient]
    it "refuses a sweep at exactly the expiry slot" $
        sweepIn (finiteRange 11_000 11_500) `shouldBe` Left SweepNotExpired
    it "sweeps one slot after expiry" $
        fmap espCommitmentRef (sweepIn (finiteRange 11_001 11_500))
            `shouldBe` Right commitmentRef
    it "refuses a counterfeit reservation however expired it looks" $
        sweepResolved resolved{rcHoldsOtherAssets = True}
            `shouldBe` Left SweepCommitmentCounterfeit
    it "refuses a reservation whose stored boundaries were not derived" $
        sweepResolved
            resolved
                { rcDatum =
                    commitment{bcScope = scope{bsExpiresAt = 11_001}}
                }
            `shouldBe` Left
                (SweepCommitmentInvalid (CommitmentScope ScopeLifetime))
    it "spends under Sweep naming the recipient and its payout index" $
        fmap espSpendRedeemer swept
            `shouldBe` Right
                ( Sweep
                    ExpiredCommitmentSweepV1
                        { ecsRecipientPkh = recipient
                        , ecsPayoutIndex = 0
                        }
                )
  where
    swept = sweepIn expiredRange
    sweepIn = sweepWith resolved
    sweepResolved candidate = sweepWith candidate expiredRange
    sweepWith candidate range =
        prepareExpiredSweep parameters candidate range recipient 0

-- ---------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------

parameters :: CommitmentParameters
parameters =
    CommitmentParameters
        { cpNetwork = 42
        , cpCommitMinAge = commitMinAge
        , cpCommitmentLifetime = 10_000
        , cpCommitDeposit = commitDepositFloor + 1_000_000
        }

commitmentPolicy :: ByteString
commitmentPolicy = BS.replicate 28 0xb0

checkpointPolicy :: ByteString
checkpointPolicy = BS.replicate 28 0xc1

seedRef :: OutputRef
seedRef = OutputRef (BS.replicate 32 0x5e) 7

otherSeedRef :: OutputRef
otherSeedRef = OutputRef (BS.replicate 32 0x5e) 8

commitmentRef :: OutputRef
commitmentRef = OutputRef (BS.replicate 32 0x0c) 0

checkpointRef :: OutputRef
checkpointRef = OutputRef (BS.replicate 32 0xc2) 3

otherCheckpointRef :: OutputRef
otherCheckpointRef = OutputRef (BS.replicate 32 0xc2) 4

payee :: ByteString
payee = BS.replicate 28 0x9a

attacker :: ByteString
attacker = BS.replicate 28 0xaa

recipient :: ByteString
recipient = BS.replicate 28 0x7e

digest :: ByteString
digest = BS.replicate 32 0xed

nonce :: ByteString
nonce = BS.replicate 32 0x11

otherNonce :: ByteString
otherNonce = BS.replicate 32 0x12

scope :: BountyScope
scope =
    BountyScope
        { bsDomain = commitmentDomain
        , bsSchema = commitmentSchema
        , bsNetwork = cpNetwork parameters
        , bsCheckpointPolicy = checkpointPolicy
        , bsCheckpointRef = checkpointRef
        , bsAction = FreezeEntitlement
        , bsMarker = markerName seedRef
        , bsCommitUpper = 1000
        , bsEligibleAfter = 1000 + cpCommitMinAge parameters
        , bsExpiresAt = 1000 + cpCommitmentLifetime parameters
        }

commitment :: BountyCommitment
commitment =
    BountyCommitmentV1
        { bcScope = scope
        , bcPayeePkh = payee
        , bcHash = commitmentHash (commitmentPreimage scope digest payee nonce)
        , bcMarker = markerName seedRef
        }

resolved :: ResolvedCommitment
resolved =
    ResolvedCommitment
        { rcRef = commitmentRef
        , rcPolicy = commitmentPolicy
        , rcDatum = commitment
        , rcLovelace = cpCommitDeposit parameters
        , rcMarkerQuantity = 1
        , rcHoldsOtherAssets = False
        }

openRange :: SlotRange
openRange = finiteRange 900 1000

expiredRange :: SlotRange
expiredRange = finiteRange 11_001 11_500

finiteRange :: Integer -> Integer -> SlotRange
finiteRange lower upper =
    SlotRange (Finite lower Inclusive) (Finite upper Inclusive)

-- | Flip the low bit of the last byte, leaving the width unchanged.
flipLast :: ByteString -> ByteString
flipLast bs = case BS.unsnoc bs of
    Nothing -> bs
    Just (initial, final) -> BS.snoc initial (final `xor` 1)
