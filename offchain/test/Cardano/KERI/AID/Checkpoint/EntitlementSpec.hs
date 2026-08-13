{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.EntitlementSpec
Description : S254-E unit proof of the shared bounty-entitlement rule

The off-chain half of @INV-271-ENTITLEMENT@ and its neighbours: the canonical
digest over the COMPLETE actual evidence, the family policy pin
(@INV-271-COMMITMENT-POLICY-AUTHENTICITY@), scope, payee, maturity, expiry,
single-use retirement, and the two payout-admissibility legs.

Two rows are permanent calibration rather than coverage.
'signerOnlyMutantAcceptsSubstitution' shows the discarded consent-only rule
ACCEPTING exactly the attack the shipped rule refuses — without it, a green
suite would not distinguish a working entitlement rule from one that never
runs.  The digest cross-product shows every field of the evidence moving the
digest, which is what makes \"the digest of THIS evidence\" a real constraint
rather than a slogan.
-}
module Cardano.KERI.AID.Checkpoint.EntitlementSpec (spec) where

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
    SlotRange (..),
    commitDepositFloor,
    commitMinAge,
    commitmentDomain,
    commitmentHash,
    commitmentPreimage,
    commitmentSchema,
    markerName,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    EnforcementEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Entitlement (
    EnforcementProofV1 (..),
    EntitledEnforcementError (..),
    EntitledEnforcementPlan (..),
    SettlementContext (..),
    SettlementOutput (..),
    enforcementEvidenceDigest,
    entitlementMatches,
    prepareEntitledEnforcement,
    validateClaimEntitledPayout,
    validateConvictEntitlement,
    validateConvictPayouts,
    validateFreezeEntitlement,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    ArmedDatum (..),
    Inclusivity (..),
    RawBound (..),
    Role (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    OutputRef (..),
 )
import Data.Bits (
    xor,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.List (
    nub,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "S254-E shared bounty-entitlement rule" $ do
    digestSpec
    matcherSpec
    settlementSpec
    calibrationSpec
    claimPayoutSpec
    convictPayoutSpec
    builderSpec

-- ---------------------------------------------------------
-- The canonical digest over the complete actual payload
-- ---------------------------------------------------------

digestSpec :: Spec
digestSpec = describe "canonical enforcement evidence digest" $ do
    it "is a full blake2b-256 digest" $
        BS.length (enforcementEvidenceDigest evidence) `shouldBe` 32
    it "is deterministic over the same payload" $
        enforcementEvidenceDigest evidence
            `shouldBe` enforcementEvidenceDigest evidence
    it "moves when ANY single field of the evidence moves" $ do
        let digests = map (enforcementEvidenceDigest . snd) evidenceMutants
            honest = enforcementEvidenceDigest evidence
        -- every mutant differs from the honest payload...
        filter (== honest) digests `shouldBe` []
        -- ...and no two mutants collide, so each field is independently
        -- inside the hash rather than merely one of them being.
        length (nub digests) `shouldBe` length digests

{- | One independent single-field mutation per field of the payload.  The list
is the coverage claim: a field added to 'EnforcementEvidence' without a row
here leaves that field unproven, which is why the count is asserted above from
this list rather than written down.
-}
evidenceMutants :: [(String, EnforcementEvidence)]
evidenceMutants =
    [ ("event_bytes", perturbedEvidence)
    , ("off_t", evidence{eneOffT = eneOffT evidence + 1})
    , ("off_i", evidence{eneOffI = eneOffI evidence + 1})
    , ("off_s", evidence{eneOffS = eneOffS evidence + 1})
    , ("off_d", evidence{eneOffD = eneOffD evidence + 1})
    , ("off_k", evidence{eneOffK = [99]})
    , ("off_kt", evidence{eneOffKt = eneOffKt evidence + 1})
    , ("off_n", evidence{eneOffN = [98]})
    , ("off_nt", evidence{eneOffNt = eneOffNt evidence + 1})
    , ("off_bt", evidence{eneOffBt = eneOffBt evidence + 1})
    , ("native_sn", evidence{eneNativeSn = eneNativeSn evidence + 1})
    , ("said", evidence{eneSaid = flipLast said})
    , ("revealed_keys", evidence{eneRevealedKeys = [flipLast verkey]})
    , ("next_keys", evidence{eneNextKeys = [flipLast keyDigest]})
    , ("cur_threshold", evidence{eneCurThreshold = Unweighted 2})
    , ("next_threshold", evidence{eneNextThreshold = Unweighted 2})
    , ("toad", evidence{eneToad = eneToad evidence + 1})
    , ("ctrl_sigs", evidence{eneCtrlSigs = [(0, flipLast signature)]})
    , ("wit_sigs", evidence{eneWitSigs = [(1, signature)]})
    ]

-- ---------------------------------------------------------
-- Matching against actual evidence
-- ---------------------------------------------------------

matcherSpec :: Spec
matcherSpec = describe "matching against actual evidence" $ do
    it "accepts the reservation opened over THIS evidence" $
        entitlementMatches commitment checkpointRef FreezeEntitlement evidence nonce
            `shouldBe` EntitlementValid
    it "refuses a reservation opened over a different payload" $
        entitlementMatches
            commitment
            checkpointRef
            FreezeEntitlement
            perturbedEvidence
            nonce
            `shouldBe` EntitlementInvalid EntitlementHash
    it "refuses a Freeze reservation presented as a Convict one" $
        entitlementMatches
            commitment
            checkpointRef
            ConvictEntitlement
            evidence
            nonce
            `shouldBe` EntitlementInvalid EntitlementAction

-- ---------------------------------------------------------
-- The shared settlement rule
-- ---------------------------------------------------------

settlementSpec :: Spec
settlementSpec = describe "shared settlement rule" $ do
    it "settles an honest matured entitled reveal" $
        freeze family payee context `shouldBe` True
    it
        "refuses a counterfeit reservation at a FOREIGN script, however \
        \perfectly authored"
        $ freeze family payee counterfeitContext
            `shouldBe` False
    it "accepts that same counterfeit against the attacker's own family" $
        -- The fixture is sound: no other leg objects to it, so the refusal
        -- above is the policy pin's and nobody else's.
        freeze attackerFamily payee counterfeitContext `shouldBe` True
    it "refuses a reservation parked beside the wrong deposit" $
        freeze
            family
            payee
            context
                { scCommitmentInputs =
                    [resolved{rcLovelace = cpCommitDeposit parameters - 1}]
                }
            `shouldBe` False
    it "refuses to pay anyone but the committed beneficiary" $
        freeze family attacker context `shouldBe` False
    it "refuses a reveal naming a reservation that is not an input" $
        freeze
            family
            payee
            context{scCommitmentInputs = []}
            `shouldBe` False
    it "refuses a Freeze reservation spent as a Convict settlement" $
        validateConvictEntitlement family evidence payee reveal checkpointRef context
            `shouldBe` False
    it "refuses a settlement against another checkpoint" $
        validateFreezeEntitlement
            family
            evidence
            payee
            reveal
            otherCheckpointRef
            context
            `shouldBe` False
    it "refuses a substituted nonce" $
        validateFreezeEntitlement
            family
            evidence
            payee
            reveal{brNonce = BS.replicate 32 0x12}
            checkpointRef
            context
            `shouldBe` False
    it "refuses a reveal naming some other reservation's input" $
        validateFreezeEntitlement
            family
            evidence
            payee
            reveal{brCommitmentRef = otherCheckpointRef}
            checkpointRef
            context
            `shouldBe` False
    it "accepts a reveal at exactly the maturity boundary" $
        freezeIn (finiteRange 1001 1500) `shouldBe` True
    it "refuses a reveal one slot before maturity" $
        freezeIn (finiteRange 1000 1500) `shouldBe` False
    it "accepts a reveal at exactly the expiry boundary" $
        freezeIn (finiteRange 10_999 11_000) `shouldBe` True
    it "refuses a reveal one slot after expiry" $
        freezeIn (finiteRange 11_001 11_500) `shouldBe` False
    it "refuses a settlement in a window that denotes no slot at all" $
        freezeIn (finiteRange 1002 1001) `shouldBe` False
    it "refuses a reveal that does not retire the marker" $
        freeze family payee context{scPolicyMint = []} `shouldBe` False
    it "refuses a reveal that mints instead of burning" $
        freeze
            family
            payee
            context{scPolicyMint = [(marker, 1)]}
            `shouldBe` False
    it "refuses a reveal that burns some other marker too" $
        freeze
            family
            payee
            context
                { scPolicyMint =
                    [(marker, -1), (markerName otherSeedRef, -1)]
                }
            `shouldBe` False
  where
    freezeIn range = freeze family payee context{scValidity = range}

freeze :: CommitmentFamily -> ByteString -> SettlementContext -> Bool
freeze fam beneficiary =
    validateFreezeEntitlement fam evidence beneficiary reveal checkpointRef

-- ---------------------------------------------------------
-- Calibration: consent is not entitlement
-- ---------------------------------------------------------

calibrationSpec :: Spec
calibrationSpec = describe "consent is not entitlement" $ do
    it "signer-only mutant ACCEPTS the attacker's self-substitution" $
        signerOnlyMutant attacker [attacker] `shouldBe` True
    it "the shipped rule REFUSES that same transaction" $
        freeze family attacker context `shouldBe` False
    it "the shipped rule needs no fresh signature from the payee" $
        -- The context carries no signatory set at all, and the honest
        -- settlement still succeeds: withholding a signature is not a veto.
        freeze family payee context `shouldBe` True

{- | The discarded consent-only rule: whoever signs may be paid.

Kept executable, permanently, because it is the only thing that shows the
shipped rule is doing work.  An attacker signs as itself and names itself, so
this predicate accepts exactly the substitution the entitlement rule refuses.
-}
signerOnlyMutant :: ByteString -> [ByteString] -> Bool
signerOnlyMutant beneficiary signatories = beneficiary `elem` signatories

-- ---------------------------------------------------------
-- Claim payout
-- ---------------------------------------------------------

claimPayoutSpec :: Spec
claimPayoutSpec = describe "claim pays the stored hunter" $ do
    it "pays the hunter recorded in an ArmedV2 state" $
        claim armedV2 0 [hunterPayout] `shouldBe` True
    it "pays the hunter recorded in a legacy ArmedV1 state" $
        claim armedV1 0 [hunterPayout] `shouldBe` True
    it "cannot acquire a new payee" $
        claim
            armedV2
            0
            [hunterPayout{soPaymentCredential = VerificationKeyCredential attacker}]
            `shouldBe` False
    it "refuses a script payout standing in for the hunter" $
        claim
            armedV2
            0
            [hunterPayout{soPaymentCredential = ScriptCredential hunter}]
            `shouldBe` False
    it "refuses a delegated address" $
        claim armedV2 0 [hunterPayout{soHasStakeCredential = True}]
            `shouldBe` False
    it "refuses a datum-bearing payout" $
        claim armedV2 0 [hunterPayout{soHasDatum = True}] `shouldBe` False
    it "refuses a reference-script-bearing payout" $
        claim armedV2 0 [hunterPayout{soHasReferenceScript = True}]
            `shouldBe` False
    it "refuses an index past the end of the outputs" $
        claim armedV2 1 [hunterPayout] `shouldBe` False
    it "refuses a negative index" $
        claim armedV2 (-1) [hunterPayout] `shouldBe` False
  where
    claim = validateClaimEntitledPayout

-- ---------------------------------------------------------
-- Conviction payout admissibility
-- ---------------------------------------------------------

convictPayoutSpec :: Spec
convictPayoutSpec = describe "conviction payout admissibility" $ do
    it "routes nothing at all without entitlement, whatever the indices" $
        validateConvictPayouts Active False 0 1 twoOutputs `shouldBe` False
    it "admits an entitled ACTIVE conviction" $
        validateConvictPayouts Active True 0 1 twoOutputs `shouldBe` True
    it "admits an entitled ARMED conviction at distinct indices" $
        validateConvictPayouts Armed True 0 1 twoOutputs `shouldBe` True
    it "refuses one output satisfying both protected ARMED payouts" $
        validateConvictPayouts Armed True 0 0 twoOutputs `shouldBe` False
    it "refuses an ARMED hunter index past the end" $
        validateConvictPayouts Armed True 0 2 twoOutputs `shouldBe` False
    it "ignores the hunter index for a FROZEN conviction" $
        validateConvictPayouts Frozen True 0 99 twoOutputs `shouldBe` True
    it "admits no payout at all from a tombstone" $
        validateConvictPayouts Tombstone True 0 1 twoOutputs `shouldBe` False
    it "refuses a convictor index past the end" $
        validateConvictPayouts Active True 2 1 twoOutputs `shouldBe` False
    it "refuses a negative convictor index" $
        validateConvictPayouts Active True (-1) 1 twoOutputs `shouldBe` False
  where
    twoOutputs = [hunterPayout, hunterPayout]

-- ---------------------------------------------------------
-- Builder
-- ---------------------------------------------------------

builderSpec :: Spec
builderSpec = describe "prepareEntitledEnforcement" $ do
    it "reads the payee out of the reservation instead of choosing one" $
        fmap eepBountyPayee built `shouldBe` Right payee
    it "retires the reservation by burning its one marker" $
        fmap eepBurn built `shouldBe` Right (marker, -1)
    it "refunds exactly the applied deposit to the committed payee" $
        fmap eepRefund built
            `shouldBe` Right
                CommitmentPayout
                    { cpoIndex = 1
                    , cpoRecipientPkh = payee
                    , cpoLovelace = cpCommitDeposit parameters
                    }
    it "derives the observer payload's digest from the actual evidence" $
        fmap (epEvidence . eepProof) built `shouldBe` Right evidence
    it "names the same payee in the payload the register will bind" $
        fmap (epPayeePkh . eepProof) built `shouldBe` Right payee
    it "emits a plan the shared rule then accepts" $
        fmap
            ( \plan ->
                validateFreezeEntitlement
                    family
                    (epEvidence (eepProof plan))
                    (eepBountyPayee plan)
                    (eepReveal plan)
                    (eepCheckpointRef plan)
                    context{scPolicyMint = [eepBurn plan]}
            )
            built
            `shouldBe` Right True
    it "refuses to build against a reservation at a foreign script" $
        buildWith family resolved{rcPolicy = foreignPolicy} settlementRange
            `shouldBe` Left EnforcementForeignPolicy
    it "refuses to build against a counterfeit reservation" $
        buildWith family resolved{rcMarkerQuantity = 0} settlementRange
            `shouldBe` Left EnforcementCommitmentCounterfeit
    it "refuses to build a reveal one slot before maturity" $
        buildWith family resolved (finiteRange 1000 1500)
            `shouldBe` Left EnforcementNotMature
    it "refuses to build a reveal one slot after expiry" $
        buildWith family resolved (finiteRange 11_001 11_500)
            `shouldBe` Left EnforcementExpired
    it "refuses to build a settlement the reservation does not cover" $
        prepareEntitledEnforcement
            family
            resolved
            ConvictEntitlement
            evidence
            checkpointRef
            nonce
            1
            settlementRange
            `shouldBe` Left (EnforcementNotEntitled EntitlementAction)
  where
    built = buildWith family resolved settlementRange

buildWith ::
    CommitmentFamily ->
    ResolvedCommitment ->
    SlotRange ->
    Either EntitledEnforcementError EntitledEnforcementPlan
buildWith fam candidate =
    prepareEntitledEnforcement
        fam
        candidate
        FreezeEntitlement
        evidence
        checkpointRef
        nonce
        1

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

foreignPolicy :: ByteString
foreignPolicy = BS.replicate 28 0xf0

checkpointPolicy :: ByteString
checkpointPolicy = BS.replicate 28 0xc1

family :: CommitmentFamily
family = CommitmentFamily commitmentPolicy parameters

{- | The same applied magnitudes pinned to the script the attacker deployed.

It exists so the counterfeit can be shown accepted in one direction and
refused in the other over the /identical/ transaction: that is what makes the
refusal attributable to the policy pin rather than to a broken fixture.
-}
attackerFamily :: CommitmentFamily
attackerFamily = CommitmentFamily foreignPolicy parameters

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

marker :: ByteString
marker = markerName seedRef

payee :: ByteString
payee = BS.replicate 28 0x9a

attacker :: ByteString
attacker = BS.replicate 28 0xaa

hunter :: ByteString
hunter = BS.replicate 28 0x8b

nonce :: ByteString
nonce = BS.replicate 32 0x11

scope :: BountyScope
scope =
    BountyScope
        { bsDomain = commitmentDomain
        , bsSchema = commitmentSchema
        , bsNetwork = cpNetwork parameters
        , bsCheckpointPolicy = checkpointPolicy
        , bsCheckpointRef = checkpointRef
        , bsAction = FreezeEntitlement
        , bsMarker = marker
        , bsCommitUpper = 1000
        , bsEligibleAfter = 1000 + cpCommitMinAge parameters
        , bsExpiresAt = 1000 + cpCommitmentLifetime parameters
        }

-- | The honest reservation, opened over the digest of the actual evidence.
commitment :: BountyCommitment
commitment =
    BountyCommitmentV1
        { bcScope = scope
        , bcPayeePkh = payee
        , bcHash =
            commitmentHash $
                commitmentPreimage
                    scope
                    (enforcementEvidenceDigest evidence)
                    payee
                    nonce
        , bcMarker = marker
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

reveal :: BountyRevealV1
reveal =
    BountyRevealV1
        { brCommitmentRef = commitmentRef
        , brNonce = nonce
        , brRefundIndex = 1
        }

settlementRange :: SlotRange
settlementRange = finiteRange 1001 1500

context :: SettlementContext
context =
    SettlementContext
        { scCommitmentInputs = [resolved]
        , scValidity = settlementRange
        , scPolicyMint = [(marker, -1)]
        , scOutputs = [hunterPayout]
        }

{- | The counterfeit sits at a script the attacker deployed itself, so the
resolved policy is the foreign one.  Everything else about it is impeccable:
the attacker authored the whole datum — matching scope, its own payee, the
digest of someone else's evidence — and parked exactly the deposit beside a
self-minted marker.
-}
counterfeitContext :: SettlementContext
counterfeitContext =
    context{scCommitmentInputs = [resolved{rcPolicy = foreignPolicy}]}

hunterPayout :: SettlementOutput
hunterPayout =
    SettlementOutput
        { soPaymentCredential = VerificationKeyCredential hunter
        , soHasStakeCredential = False
        , soHasDatum = False
        , soHasReferenceScript = False
        }

armedV1 :: ArmedDatum
armedV1 = ArmedV1 checkpointState hunter 1500

armedV2 :: ArmedDatum
armedV2 = ArmedV2 checkpointState hunter 1500

checkpointState :: CheckpointDatumV1
checkpointState =
    CheckpointDatumV1
        { cdCesrAid = BS.replicate 32 0x01
        , cdCurKeys = [verkey]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [keyDigest]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 1
        , cdNativeSn = 1
        }

finiteRange :: Integer -> Integer -> SlotRange
finiteRange lower upper =
    SlotRange (Finite lower Inclusive) (Finite upper Inclusive)

eventBytes :: ByteString
eventBytes = "{\"v\":\"KERI10JSON000000_\",\"t\":\"rot\"}"

said :: ByteString
said = BS.replicate 32 0x44

verkey :: ByteString
verkey = BS.replicate 32 0x02

keyDigest :: ByteString
keyDigest = BS.replicate 32 0x03

signature :: ByteString
signature = BS.replicate 64 0x77

{- | A complete enforcement payload.  It is never bound or verified here — the
digest is a hash over the whole record, and its job in this module is to be
the thing a reservation is opened over.
-}
evidence :: EnforcementEvidence
evidence =
    EnforcementEvidence
        { eneEventBytes = eventBytes
        , eneOffT = 1
        , eneOffI = 2
        , eneOffS = 3
        , eneOffD = 4
        , eneOffK = [5]
        , eneOffKt = 6
        , eneOffN = [7]
        , eneOffNt = 8
        , eneOffBt = 9
        , eneNativeSn = 10
        , eneSaid = said
        , eneRevealedKeys = [verkey]
        , eneNextKeys = [keyDigest]
        , eneCurThreshold = Unweighted 1
        , eneNextThreshold = Unweighted 1
        , eneToad = 0
        , eneCtrlSigs = [(0, signature)]
        , eneWitSigs = []
        }

{- | The same payload with one byte of the signed event moved.  Named because
two rows depend on it being the /same/ perturbation.
-}
perturbedEvidence :: EnforcementEvidence
perturbedEvidence = evidence{eneEventBytes = flipLast eventBytes}

-- | Flip the low bit of the last byte, leaving the width unchanged.
flipLast :: ByteString -> ByteString
flipLast bs = case BS.unsnoc bs of
    Nothing -> bs
    Just (initial, final) -> BS.snoc initial (final `xor` 1)
