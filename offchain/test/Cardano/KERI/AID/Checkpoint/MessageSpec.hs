module Cardano.KERI.AID.Checkpoint.MessageSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    NextCommitment (..),
    blake2b_256,
    canonicalCbor,
    keysetCommit,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError (..),
    AdvanceMessage (..),
    EventType (..),
    InceptionError (..),
    InceptionMessage (..),
    RevealedSuccessorSigners (..),
    SpentCheckpoint (..),
    advanceDomain,
    advanceEqualities,
    advanceMessage,
    checkpointAssetDomainTag,
    deriveAidAssetName,
    inceptionDomain,
    inceptionMessage,
    validateInception,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    evaluate,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet (
    IntSet,
 )
import Data.IntSet qualified as IntSet
import Data.Word (
    Word8,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- | A strict 'ByteString' from an ASCII hex literal.
hexBs :: ByteString -> ByteString
hexBs s = either error id (convertFromBase Base16 s)

b32 :: Word8 -> ByteString
b32 = BS.replicate 32

b28 :: Word8 -> ByteString
b28 = BS.replicate 28

{- | Positions in @keyset@ whose digest is among the @controlled@ signer
evidence — the same mapping eq6 performs, used here to demonstrate that one
attacker evidence satisfies the spent-current threshold yet fails the
revealed-successor threshold.
-}
positionsIn :: [ByteString] -> [ByteString] -> IntSet
positionsIn keyset controlled =
    IntSet.fromList [i | (i, k) <- zip [0 ..] keyset, k `elem` controlled]

-- Fixed test material shared with the independent golden generator.
k1, k2, policy, cesrA :: ByteString
k1 = b32 0x01
k2 = b32 0x02
policy = b28 0xcc
cesrA = BS.pack [0 .. 31] -- the derivation golden's fixed cesr_aid (0x00..0x1f)

-- One-bit flip of cesrA: byte 0 XOR 0x01 (0x00 -> 0x01), tail unchanged.
cesrAFlipped :: ByteString
cesrAFlipped = BS.pack (1 : [1 .. 31])

-- The golden asset name for cesrA (independently computed).
aidNameGolden :: ByteString
aidNameGolden =
    hexBs "c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac9"

-- The asset name derived with the WRONG code (0x45, not 0x46).
wrongCodeAsset :: ByteString
wrongCodeAsset = blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x45 cesrA)

-- ---------------------------------------------------------
-- Inception fixture (matched to the generator)
-- ---------------------------------------------------------

icpNext :: ByteString
icpNext = keysetCommit (NextCommitment [k2] (Unweighted 1))

validIcp :: InceptionMessage
validIcp =
    inceptionMessage
        1 -- network_id
        policy
        (deriveAidAssetName cesrA)
        cesrA
        [k1] -- cur_keys
        (Unweighted 1) -- cur_threshold
        icpNext
        [] -- witnesses
        0 -- toad
        0 -- native_sn

-- ---------------------------------------------------------
-- Advance fixture (valid succession) + eq6 stolen-quorum setup
-- ---------------------------------------------------------

-- The REVEALED successor set (pre-committed at the prior step).
newKeys :: [ByteString]
newKeys = [b32 0x11]

newThr :: Threshold
newThr = Unweighted 1

-- A spent-current set DISTINCT from the successor set: a 2-of-2 quorum whose
-- keys never appear in the successor set.
spentCurKeys :: [ByteString]
spentCurKeys = [k1, k2]

spentCurThr :: Threshold
spentCurThr = Unweighted 2

-- spent.next_digest == keyset_commit over the REVEALED successor set.
spentNext :: ByteString
spentNext = keysetCommit (NextCommitment newKeys newThr)

newNext :: ByteString
newNext = keysetCommit (NextCommitment [b32 0x22] (Unweighted 1))

spentTxid :: ByteString
spentTxid = b32 0xd0

spent :: SpentCheckpoint
spent =
    SpentCheckpoint
        { scNetworkId = 1
        , scPolicyId = policy
        , scAidAssetName = deriveAidAssetName cesrA
        , scTxid = spentTxid
        , scIndex = 1
        , scCesrAid = cesrA
        , scNextDigest = spentNext
        , scSeq = 0
        , scNativeSn = 0
        }

validAdv :: AdvanceMessage
validAdv =
    advanceMessage
        1 -- network_id
        policy
        (deriveAidAssetName cesrA)
        cesrA
        spentTxid
        1 -- spent_index
        spentNext -- prior_commit
        0 -- prior_seq
        0 -- prior_native_sn
        newKeys
        newThr
        newNext
        [] -- new_witnesses
        0 -- new_toad
        1 -- seq_to
        1 -- native_sn_to

-- The created checkpoint datum that matches validAdv's new-state fields.
createdValid :: CheckpointDatumV1
createdValid =
    CheckpointDatumV1
        { cdCesrAid = cesrA
        , cdCurKeys = newKeys
        , cdCurThreshold = newThr
        , cdNextDigest = newNext
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 1
        , cdNativeSn = 1
        }

-- The revealed successor key signs (its digest is in the evidence).
sigsRevealed :: RevealedSuccessorSigners
sigsRevealed = RevealedSuccessorSigners newKeys

-- The attacker holds the full SPENT-CURRENT quorum — and nothing else.
attackerKeys :: [ByteString]
attackerKeys = spentCurKeys

sigsStolenCurrent :: RevealedSuccessorSigners
sigsStolenCurrent = RevealedSuccessorSigners attackerKeys

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Frozen domain constants
    -- ------------------------------------------------------
    describe "frozen domain constants" $ do
        it "inceptionDomain is the icp/v1 literal" $
            inceptionDomain `shouldBe` ("cardano-keri/checkpoint/icp/v1" :: ByteString)
        it "advanceDomain is the adv/v1 literal" $
            advanceDomain `shouldBe` ("cardano-keri/checkpoint/adv/v1" :: ByteString)
        it "checkpointAssetDomainTag is the 32-byte asset/v1 tag" $
            checkpointAssetDomainTag
                `shouldBe` ("cardano-keri/checkpoint-asset/v1" :: ByteString)
        it "checkpointAssetDomainTag is exactly 32 bytes" $
            BS.length checkpointAssetDomainTag `shouldBe` 32

    -- ------------------------------------------------------
    -- deriveAidAssetName: exact-byte goldens (cross-language pins)
    -- ------------------------------------------------------
    describe "deriveAidAssetName goldens" $ do
        it "golden: fixed cesr_aid -> its exact 32-byte asset name" $
            deriveAidAssetName cesrA `shouldBe` aidNameGolden
        it "asset name is exactly 32 bytes" $
            BS.length (deriveAidAssetName cesrA) `shouldBe` 32
        it "definition: blake2b_256(tag ++ 0x46 ++ cesr_aid)" $
            deriveAidAssetName cesrA
                `shouldBe` blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x46 cesrA)
        it "wrong derivation code (0x45) has its own exact digest" $
            wrongCodeAsset
                `shouldBe` hexBs
                    "67cf5c95ae280e04d9d4b50854cc74aa198f0ff0335c615758e50f40dbb78536"
        it "wrong derivation code differs from the golden" $
            wrongCodeAsset `shouldSatisfy` (/= aidNameGolden)
        it "mutated AID (one-bit flip) has its own exact digest" $
            deriveAidAssetName cesrAFlipped
                `shouldBe` hexBs
                    "1e56b40cc1a6f1163f08fb24bcb29fe85bc4f5c721c9a4afac5a10588aafa3f0"
        it "one-bit flip differs from the golden" $
            deriveAidAssetName cesrAFlipped `shouldSatisfy` (/= aidNameGolden)

    -- ------------------------------------------------------
    -- InceptionMessage golden + validation (exact rejections)
    -- ------------------------------------------------------
    describe "InceptionMessage golden" $ do
        it "icp canonical CBOR golden" $
            canonicalCbor validIcp
                `shouldBe` hexBs
                    "d8799f581e63617264616e6f2d6b6572692f636865636b706f696e742f6963702f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac95820000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58207a3a5a75a5237ec477925c6cc500f6db3aa85cdb341295e5d78c81bdf278a8eb800000ff"
        it "builder fills the frozen icp domain" $
            imDomain validIcp `shouldBe` inceptionDomain

    describe "validateInception (exact rejections)" $ do
        it "accepts a non-delegated icp with a matching derived asset" $
            validateInception Icp validIcp `shouldBe` Right ()
        it "rejects a dip-typed inception -> DelegatedInceptionRejected" $
            validateInception Dip validIcp
                `shouldBe` Left DelegatedInceptionRejected
        it "rejects a drt-typed inception -> DelegatedInceptionRejected" $
            validateInception Drt validIcp
                `shouldBe` Left DelegatedInceptionRejected
        it "rejects a substituted asset name -> InceptionAssetMismatch" $
            validateInception Icp validIcp{imAidAssetName = b32 0x00}
                `shouldBe` Left InceptionAssetMismatch
        it "rejects a wrong-code-derived substituted asset -> InceptionAssetMismatch" $
            validateInception Icp validIcp{imAidAssetName = wrongCodeAsset}
                `shouldBe` Left InceptionAssetMismatch
        it "rejects a 31-byte AID (asset matches derive) -> InceptionAidWidth" $
            validateInception
                Icp
                validIcp
                    { imCesrAid = BS.take 31 cesrA
                    , imAidAssetName = deriveAidAssetName (BS.take 31 cesrA)
                    }
                `shouldBe` Left InceptionAidWidth
        it "rejects a 33-byte AID (asset matches derive) -> InceptionAidWidth" $
            let cesr33 = cesrA <> BS.singleton 0x00
             in validateInception
                    Icp
                    validIcp
                        { imCesrAid = cesr33
                        , imAidAssetName = deriveAidAssetName cesr33
                        }
                    `shouldBe` Left InceptionAidWidth
        it "rejects a mutated AID carrying the original asset -> InceptionAssetMismatch" $
            validateInception Icp validIcp{imCesrAid = cesrAFlipped}
                `shouldBe` Left InceptionAssetMismatch

    -- ------------------------------------------------------
    -- AdvanceMessage golden
    -- ------------------------------------------------------
    describe "AdvanceMessage golden" $ do
        it "advance (valid succession) canonical CBOR golden" $
            canonicalCbor validAdv
                `shouldBe` hexBs
                    "d8799f581e63617264616e6f2d6b6572692f636865636b706f696e742f6164762f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac95820000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f5820d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d00158206100bd9bb638fdadbe0727294eb099f38a3698b643a15f24023acd14cb310d6d00009f58201111111111111111111111111111111111111111111111111111111111111111ffd8799f01ff582024e5e385402220b63c92320512d818037a7f7cc24d9ec03bff16a7d4f1afbe9e80000101ff"
        it "builder fills the frozen adv domain" $
            amDomain validAdv `shouldBe` advanceDomain

    -- ------------------------------------------------------
    -- The seven F10 advance equalities (exact rejections).
    -- ------------------------------------------------------
    describe "advanceEqualities" $ do
        it "valid succession signed by the revealed successor set" $
            advanceEqualities spent validAdv createdValid sigsRevealed
                `shouldBe` Right ()

        -- eq6 — the parent #21 pre-rotation invariant (security-critical).
        -- The SAME attacker evidence satisfies the spent-current quorum but
        -- maps to no successor position, so the advance is rejected.
        it "the stolen quorum satisfies the spent-current threshold" $
            evaluate spentCurThr (length spentCurKeys) (positionsIn spentCurKeys attackerKeys)
                `shouldBe` True
        it "the same evidence fails the revealed-successor threshold" $
            evaluate newThr (length newKeys) (positionsIn newKeys attackerKeys)
                `shouldBe` False
        it "stolen current quorum signing the advance -> Eq6SuccessorQuorumUnsatisfied" $
            advanceEqualities spent validAdv createdValid sigsStolenCurrent
                `shouldBe` Left Eq6SuccessorQuorumUnsatisfied

        -- eq5 — sequence advance.
        it "bad seq_to (!= prior_seq + 1) -> Eq5SequenceMismatch" $
            advanceEqualities spent validAdv{amSeqTo = 5} createdValid sigsRevealed
                `shouldBe` Left Eq5SequenceMismatch
        it "non-increasing native_sn -> Eq5SequenceMismatch" $
            advanceEqualities spent validAdv{amNativeSnTo = 0} createdValid sigsRevealed
                `shouldBe` Left Eq5SequenceMismatch

        -- eq4 — reveal binds the successor to spent.next_digest.
        it "wrong prior_commit -> Eq4PriorMismatch" $
            advanceEqualities spent validAdv{amPriorCommit = b32 0x00} createdValid sigsRevealed
                `shouldBe` Left Eq4PriorMismatch
        it "substituted successor keys (reveal != commitment) -> Eq4PriorMismatch" $
            advanceEqualities spent validAdv{amNewCurKeys = [b32 0x99]} createdValid sigsRevealed
                `shouldBe` Left Eq4PriorMismatch

        -- eq2 — AID / asset binding.
        it "crossed cesr_aid -> Eq2AssetOrAidMismatch" $
            advanceEqualities spent validAdv{amCesrAid = b32 0x55} createdValid sigsRevealed
                `shouldBe` Left Eq2AssetOrAidMismatch
        it "cross aid_asset_name -> Eq2AssetOrAidMismatch" $
            advanceEqualities spent validAdv{amAidAssetName = b32 0x00} createdValid sigsRevealed
                `shouldBe` Left Eq2AssetOrAidMismatch

        -- eq1 — deployment binding.
        it "cross network_id -> Eq1NetworkPolicyMismatch" $
            advanceEqualities spent validAdv{amNetworkId = 0} createdValid sigsRevealed
                `shouldBe` Left Eq1NetworkPolicyMismatch
        it "cross checkpoint_policy_id -> Eq1NetworkPolicyMismatch" $
            advanceEqualities spent validAdv{amCheckpointPolicyId = b28 0xee} createdValid sigsRevealed
                `shouldBe` Left Eq1NetworkPolicyMismatch

        -- eq3 — exact spent TxOutRef.
        it "wrong spent_txid -> Eq3OutRefMismatch" $
            advanceEqualities spent validAdv{amSpentTxid = b32 0x00} createdValid sigsRevealed
                `shouldBe` Left Eq3OutRefMismatch
        it "wrong spent_index -> Eq3OutRefMismatch" $
            advanceEqualities spent validAdv{amSpentIndex = 2} createdValid sigsRevealed
                `shouldBe` Left Eq3OutRefMismatch

        -- eq7 — the created datum equals the message's new-state fields.
        it "created datum disagreeing with the message (seq) -> Eq7CreatedStateMismatch" $
            advanceEqualities spent validAdv createdValid{cdSeq = 9} sigsRevealed
                `shouldBe` Left Eq7CreatedStateMismatch
        it "substituted new_next in the message (created unchanged) -> Eq7CreatedStateMismatch" $
            advanceEqualities spent validAdv{amNewNextDigest = b32 0x00} createdValid sigsRevealed
                `shouldBe` Left Eq7CreatedStateMismatch
