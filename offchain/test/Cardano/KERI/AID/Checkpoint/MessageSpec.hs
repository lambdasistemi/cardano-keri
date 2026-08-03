module Cardano.KERI.AID.Checkpoint.MessageSpec (
    spec,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (
    blake3Hash,
 )
import Cardano.KERI.AID.CESR (
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    DatumError (..),
    blake2b_256,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    digestRaw,
    loadFixture,
    lookupKey,
    note,
    textArrayField,
    textField,
    verkeyRaw,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError (..),
    RevealedSuccessorSigners (..),
    SpentCheckpoint (..),
    advanceDomain,
    advanceEqualities,
    checkpointAssetDomainTag,
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
    evaluate,
 )
import Data.Aeson (
    Value (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Foldable (
    toList,
 )
import Data.IntSet (
    IntSet,
 )
import Data.IntSet qualified as IntSet
import Data.Text (
    Text,
 )
import Data.Text qualified as T
import Data.Word (
    Word8,
 )
import Numeric (
    readHex,
 )
import Test.Hspec (
    Spec,
    beforeAll,
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
pre-rotation threshold over the committed next keys.
-}
positionsIn :: [ByteString] -> [ByteString] -> IntSet
positionsIn keyset controlled =
    IntSet.fromList [i | (i, k) <- zip [0 ..] keyset, k `elem` controlled]

{- | The committed next-key digest of a raw verkey:
@blake3_256(qb64(key))@ — the KERI KEL @n@ entry byte-for-byte.
-}
nkd :: ByteString -> ByteString
nkd = blake3Hash . qb64Verkey

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
    hexBs "67cf5c95ae280e04d9d4b50854cc74aa198f0ff0335c615758e50f40dbb78536"

-- The asset name derived with the WRONG code (0x46 'F', not 0x45 'E').
wrongCodeAsset :: ByteString
wrongCodeAsset = blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x46 cesrA)

-- ---------------------------------------------------------
-- Advance fixture (valid succession) + eq6 dual-threshold setup
-- ---------------------------------------------------------

-- The REVEALED successor set (pre-committed at the prior step).
newKeys :: [ByteString]
newKeys = [b32 0x11]

newThr :: Threshold
newThr = Unweighted 1

-- A spent-current set DISTINCT from the successor set: a 2-of-2 quorum whose
-- keys never appear in the committed next set.
spentCurKeys :: [ByteString]
spentCurKeys = [k1, k2]

spentCurThr :: Threshold
spentCurThr = Unweighted 2

-- The new pre-rotation commitment written by the advance.
newNextKeys :: [ByteString]
newNextKeys = [b32 0x22]

newNextThr :: Threshold
newNextThr = Unweighted 1

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
        , scWitnesses = []
        , scNextKeys = map nkd newKeys
        , scNextThreshold = newThr
        , scSeq = 0
        , scNativeSn = 0
        }

-- The created (successor) checkpoint datum for a valid succession.
createdValid :: CheckpointDatumV1
createdValid =
    CheckpointDatumV1
        { cdCesrAid = cesrA
        , cdCurKeys = newKeys
        , cdCurThreshold = newThr
        , cdNextKeys = newNextKeys
        , cdNextThreshold = newNextThr
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

-- ---------------------------------------------------------
-- Partial (reserve) rotation fixture — the GLEIF production Root shape:
-- 7 committed digests at nt = [[1/3 x7]]; the rotation reveals 3 of them
-- with its own restated kt = [[1/3 x3]] and re-commits the 4 unexposed
-- reserves plus 3 fresh digests. Verified against the live Root KEL
-- (icp -> rot s=1, indices {0,5,6}).
-- ---------------------------------------------------------

rn :: Word8 -> ByteString
rn i = b32 (0x30 + i)

-- The committed digests: the KEL n entries of the raw reserve keys.
reserveN :: [ByteString]
reserveN = map (nkd . rn) [0 .. 6]

third :: Integer -> Threshold
third n = Weighted [replicate (fromIntegral n) (Weight 1 3)]

-- Revealed subset: indices {0, 5, 6} of the committed set.
reserveRevealed :: [ByteString]
reserveRevealed = [rn 0, rn 5, rn 6]

-- Re-commitment: the 4 unexposed reserve digests carried forward + 3 fresh.
reserveNextN :: [ByteString]
reserveNextN =
    map (nkd . rn) [1, 2, 3, 4]
        <> map b32 [0x71, 0x72, 0x73]

reserveSpent :: SpentCheckpoint
reserveSpent =
    spent
        { scNextKeys = reserveN
        , scNextThreshold = third 7
        }

reserveCreated :: CheckpointDatumV1
reserveCreated =
    createdValid
        { cdCurKeys = reserveRevealed
        , cdCurThreshold = third 3
        , cdNextKeys = reserveNextN
        , cdNextThreshold = third 7
        }

-- ---------------------------------------------------------
-- S1 fixture-driven witness-delta (W1-W3) coverage (#115 S2)
--
-- Everything below is derived straight from the committed S1 keripy bundle
-- (advance.json): the outgoing witness set (icp.b), the delta (rot.br/ba),
-- the rotation's own key state (rot.k/kt/n/nt), and the genesis pre-rotation
-- commitment the delta is checked against (icp.n/nt). Nothing is hand
-- transcribed; only eq1-eq5's deployment/outref plumbing (irrelevant to
-- W1-W3) is a fixed constant shared across fixtures.
-- ---------------------------------------------------------

{- | A fixed spent 'TxOutRef' shared by every delta fixture below (eq1-eq5
plumbing only; irrelevant to the W1-W3/eq7 checks under test).
-}
deltaSpentTxid :: ByteString
deltaSpentTxid = b32 0xd1

-- | One committed advance fixture's fully-derived validation material.
data DeltaFixture = DeltaFixture
    { dfSpent :: SpentCheckpoint
    , dfWitCut :: [ByteString]
    , dfWitAdd :: [ByteString]
    , dfCreated :: CheckpointDatumV1
    , dfSigners :: RevealedSuccessorSigners
    , dfIcpKeys :: [ByteString]
    , dfOldWitnesses :: [ByteString]
    , dfSurvivors :: [ByteString]
    }

-- | Base-16 (KERI hex, e.g. @bt@/@s@) text to an 'Integer'.
hexInt :: Text -> Integer
hexInt t = case readHex (T.unpack t) of
    [(n, "")] -> n
    _ -> error ("not a lowercase hex integer: " <> T.unpack t)

-- | The first element of a fixture-guaranteed non-empty list.
firstOf :: String -> [a] -> a
firstOf _ (x : _) = x
firstOf label [] = error (label <> ": unexpectedly empty")

{- | A KERI @kt@\/@nt@ threshold JSON value: a plain hex @m@-of-@n@ string, or
a single-clause array of @"num/den"@ fraction strings (KERI reserve
rotation weights).
-}
parseThreshold :: Value -> Threshold
parseThreshold (String t) = Unweighted (hexInt t)
parseThreshold (Array vs) = Weighted [map parseWeight (toList vs)]
parseThreshold v = error ("threshold: unexpected JSON shape: " <> show v)

parseWeight :: Value -> Weight
parseWeight (String t) = case T.splitOn "/" t of
    [numT, denT] -> Weight (read (T.unpack numT)) (read (T.unpack denT))
    _ -> error ("weight: malformed fraction " <> T.unpack t)
parseWeight v = error ("weight: unexpected JSON shape: " <> show v)

{- | A committed advance fixture's validation material — the spent context,
the reconstructed message, the honest (W3-derived) created datum, and the
revealed successor signer evidence — pulled from @advance.json@ by key
(@adv_wit_2key@\/@adv_wit_7key@\/@adv_downgrade@\/@adv_keep@).
-}
deltaFixture :: Value -> Text -> DeltaFixture
deltaFixture doc key = either error id $ do
    sub <- field doc key
    icp <- field sub "icp"
    rot <- field sub "rot"
    icpKed <- field icp "ked"
    rotKed <- field rot "ked"
    aid <- digestRaw =<< textField icpKed "i"
    icpKeys <- traverse verkeyRaw =<< textArrayField icpKed "k"
    oldWitnesses <- traverse verkeyRaw =<< textArrayField icpKed "b"
    icpNext <- traverse digestRaw =<< textArrayField icpKed "n"
    icpNextThr <- parseThreshold <$> field icpKed "nt"
    cuts <- traverse verkeyRaw =<< textArrayField rotKed "br"
    adds <- traverse verkeyRaw =<< textArrayField rotKed "ba"
    rotKeys <- traverse verkeyRaw =<< textArrayField rotKed "k"
    rotThr <- parseThreshold <$> field rotKed "kt"
    rotNext <- traverse digestRaw =<< textArrayField rotKed "n"
    rotNextThr <- parseThreshold <$> field rotKed "nt"
    toad <- hexInt <$> textField rotKed "bt"
    let survivors = filter (`notElem` cuts) oldWitnesses
        newSet = survivors <> adds
        asset = deriveAidAssetName aid
        sc =
            SpentCheckpoint
                { scNetworkId = 1
                , scPolicyId = policy
                , scAidAssetName = asset
                , scTxid = deltaSpentTxid
                , scIndex = 0
                , scCesrAid = aid
                , scWitnesses = oldWitnesses
                , scNextKeys = icpNext
                , scNextThreshold = icpNextThr
                , scSeq = 0
                , scNativeSn = 0
                }
        created =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = rotKeys
                , cdCurThreshold = rotThr
                , cdNextKeys = rotNext
                , cdNextThreshold = rotNextThr
                , cdWitnesses = newSet
                , cdToad = toad
                , cdSeq = 1
                , cdNativeSn = 1
                }
    pure
        DeltaFixture
            { dfSpent = sc
            , dfWitCut = cuts
            , dfWitAdd = adds
            , dfCreated = created
            , dfSigners = RevealedSuccessorSigners rotKeys
            , dfIcpKeys = icpKeys
            , dfOldWitnesses = oldWitnesses
            , dfSurvivors = survivors
            }
  where
    field v k = note (k <> " missing") (lookupKey k v)

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Frozen domain constants
    -- ------------------------------------------------------
    describe "frozen domain constants" $ do
        it "advanceDomain (retained only for mkAdvancePackage, #219) is the adv/v1 literal" $
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
        it "definition: blake2b_256(tag ++ 0x45 ++ cesr_aid)" $
            deriveAidAssetName cesrA
                `shouldBe` blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x45 cesrA)
        it "wrong derivation code (0x46) has its own exact digest" $
            wrongCodeAsset
                `shouldBe` hexBs
                    "c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac9"
        it "wrong derivation code differs from the golden" $
            wrongCodeAsset `shouldSatisfy` (/= aidNameGolden)
        it "mutated AID (one-bit flip) has its own exact digest" $
            deriveAidAssetName cesrAFlipped
                `shouldBe` hexBs
                    "a45ec3ef92f14458cc127a7a43d349e55d6f6e08e3c722e718574eb637f6762d"
        it "one-bit flip differs from the golden" $
            deriveAidAssetName cesrAFlipped `shouldSatisfy` (/= aidNameGolden)

    -- ------------------------------------------------------
    -- The F10 advance checks (exact rejections). #219: checked directly
    -- against the spent context and the actual successor datum -- no
    -- reconstructed signed-message layer; eq1/eq3/eq4/domain (tautological
    -- on the wired path) are deleted with that layer (see spec.md).
    -- ------------------------------------------------------
    describe "advanceEqualities" $ do
        it "valid succession signed by the revealed successor set" $
            advanceEqualities spent createdValid [] [] sigsRevealed
                `shouldBe` Right ()

        -- eq6 — the parent #21 pre-rotation invariant (security-critical).
        -- The SAME attacker evidence satisfies the spent-current threshold but
        -- maps to no committed next-key position, so the advance is rejected.
        it "the stolen quorum satisfies the spent-current threshold" $
            evaluate spentCurThr (length spentCurKeys) (positionsIn spentCurKeys attackerKeys)
                `shouldBe` True
        it "the same evidence maps to no committed next-key position" $
            evaluate (scNextThreshold spent) (length (scNextKeys spent)) (positionsIn (scNextKeys spent) (map nkd attackerKeys))
                `shouldBe` False
        it "stolen current quorum on the honest datum -> Eq6CurrentQuorumUnsatisfied" $
            advanceEqualities spent createdValid [] [] sigsStolenCurrent
                `shouldBe` Left Eq6CurrentQuorumUnsatisfied
        it "stolen current quorum on an attacker-crafted successor -> Eq6PriorNextQuorumUnsatisfied" $
            -- The attacker reveals THEIR OWN keys as the successor set and
            -- satisfies their own threshold, but none of their keys was
            -- pre-committed, so the pre-rotation gate rejects.
            let atkCreated =
                    createdValid
                        { cdCurKeys = attackerKeys
                        , cdCurThreshold = spentCurThr
                        }
             in advanceEqualities spent atkCreated [] [] sigsStolenCurrent
                    `shouldBe` Left Eq6PriorNextQuorumUnsatisfied
        it "substituted successor set with fresh keys -> Eq6PriorNextQuorumUnsatisfied" $
            let subKeys = [b32 0x99]
                subCreated = createdValid{cdCurKeys = subKeys}
             in advanceEqualities spent subCreated [] [] (RevealedSuccessorSigners subKeys)
                    `shouldBe` Left Eq6PriorNextQuorumUnsatisfied

        -- eq5 — sequence advance.
        it "bad seq (!= spent.seq + 1) -> Eq5SequenceMismatch" $
            advanceEqualities spent createdValid{cdSeq = 5} [] [] sigsRevealed
                `shouldBe` Left Eq5SequenceMismatch
        it "non-increasing native_sn -> Eq5SequenceMismatch" $
            advanceEqualities spent createdValid{cdNativeSn = 0} [] [] sigsRevealed
                `shouldBe` Left Eq5SequenceMismatch

        -- eq2 — AID / asset binding.
        it "crossed cesr_aid -> Eq2AssetOrAidMismatch" $
            advanceEqualities spent createdValid{cdCesrAid = b32 0x55} [] [] sigsRevealed
                `shouldBe` Left Eq2AssetOrAidMismatch
        it "spent context's own asset name drifted from its derived locator -> Eq2AssetOrAidMismatch" $
            advanceEqualities spent{scAidAssetName = b32 0x00} createdValid [] [] sigsRevealed
                `shouldBe` Left Eq2AssetOrAidMismatch

        -- eq8 — nothing ill-formed can be written.
        it "toad=1 with no witnesses -> Eq8CreatedIllFormed" $
            advanceEqualities
                spent
                createdValid{cdToad = 1}
                []
                []
                sigsRevealed
                `shouldBe` Left (Eq8CreatedIllFormed ToadRange)
        it "duplicated successor key in the written state -> Eq8CreatedIllFormed" $
            let dupKey = b32 0x11 -- the committed key, listed twice
                dupCreated =
                    createdValid
                        { cdCurKeys = [dupKey, dupKey]
                        , cdCurThreshold = Unweighted 2
                        }
             in advanceEqualities spent dupCreated [] [] (RevealedSuccessorSigners [dupKey])
                    `shouldBe` Left (Eq8CreatedIllFormed (ThresholdIllFormed DuplicateKey))

    -- ------------------------------------------------------
    -- Partial (reserve) rotation — the KERI dual-threshold rule on the
    -- GLEIF production Root shape (verified against the live Root KEL).
    -- ------------------------------------------------------
    describe "advanceEqualities partial (reserve) rotation" $ do
        it "revealing 3 of 7 committed digests with a restated kt is accepted" $
            advanceEqualities
                reserveSpent
                reserveCreated
                []
                []
                (RevealedSuccessorSigners reserveRevealed)
                `shouldBe` Right ()
        it "the restated kt differs from the committed nt (KERI-legal)" $
            cdCurThreshold reserveCreated `shouldSatisfy` (/= scNextThreshold reserveSpent)
        it "an insufficient reveal fails the pre-rotation gate" $
            -- Two committed keys + one augmented fresh key satisfy the
            -- rotation's own lenient threshold, but only 2/3 of the
            -- committed weight signs: the pre-rotation gate rejects.
            let aug = b32 0x77
                curKeys = [rn 0, rn 5, aug]
                shortCreated =
                    reserveCreated
                        { cdCurKeys = curKeys
                        , cdCurThreshold = Unweighted 1
                        }
             in advanceEqualities
                    reserveSpent
                    shortCreated
                    []
                    []
                    (RevealedSuccessorSigners [rn 0, aug])
                    `shouldBe` Left Eq6PriorNextQuorumUnsatisfied
        it "an augmented (never-committed) key counts only toward the current threshold" $
            -- Same shape, but all three committed positions sign too: the
            -- augmented key's signature is harmless and the advance passes.
            let aug = b32 0x77
                curKeys = [rn 0, rn 5, rn 6, aug]
                augCreated =
                    reserveCreated
                        { cdCurKeys = curKeys
                        , cdCurThreshold = Unweighted 3
                        }
             in advanceEqualities
                    reserveSpent
                    augCreated
                    []
                    []
                    (RevealedSuccessorSigners (aug : reserveRevealed))
                    `shouldBe` Right ()

    -- ------------------------------------------------------
    -- S1 fixture-driven witness-delta (W1-W3) coverage (#115 S2): the
    -- witnessed cut/add, keep, and downgrade family shapes, plus a
    -- fixture-grounded stolen-current-quorum rejection.
    -- ------------------------------------------------------
    describe "advance witness-delta (W1-W3) - S1 fixture-driven" $
        beforeAll (loadFixture "advance.json") $ do
            it "adv_wit_2key: witnessed cut+add accepted with the W3-derived set" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Right ()
            it "adv_wit_7key: GLEIF-scale witnessed cut+add accepted" $ \doc ->
                let df = deltaFixture doc "adv_wit_7key"
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Right ()
            it "adv_keep: no-delta rotation accepted; witnesses unchanged" $ \doc -> do
                let df = deltaFixture doc "adv_keep"
                advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitAdd df) (dfSigners df)
                    `shouldBe` Right ()
                cdWitnesses (dfCreated df) `shouldBe` dfOldWitnesses df
            it "adv_downgrade: cutting every witness yields toad=0 and an empty derived set" $ \doc -> do
                let df = deltaFixture doc "adv_downgrade"
                advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitAdd df) (dfSigners df)
                    `shouldBe` Right ()
                cdWitnesses (dfCreated df) `shouldBe` []
                cdToad (dfCreated df) `shouldBe` 0
            it "stolen spent-current quorum (real icp keys) rejected -> Eq6CurrentQuorumUnsatisfied" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    attacker = RevealedSuccessorSigners (dfIcpKeys df)
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitAdd df) attacker
                        `shouldBe` Left Eq6CurrentQuorumUnsatisfied

    -- ------------------------------------------------------
    -- S1 fixture-driven delta malformations (#115 S2): every W1/W2/derived-
    -- set/toad rejection constructed over the honest adv_wit_2key material.
    -- ------------------------------------------------------
    describe "advance witness-delta malformations - S1 fixture-driven" $
        beforeAll (loadFixture "advance.json") $ do
            it "duplicate cut -> EqW1CutInvalid" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    cut = firstOf "dfWitCut" (dfWitCut df)
                 in advanceEqualities (dfSpent df) (dfCreated df) [cut, cut] (dfWitAdd df) (dfSigners df)
                        `shouldBe` Left EqW1CutInvalid
            it "cut of a non-member witness -> EqW1CutInvalid" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitAdd df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Left EqW1CutInvalid
            it "duplicate add -> EqW2AddInvalid" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    add = firstOf "dfWitAdd" (dfWitAdd df)
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) [add, add] (dfSigners df)
                        `shouldBe` Left EqW2AddInvalid
            it "add already present among survivors -> EqW2AddInvalid" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    survivor = firstOf "dfSurvivors" (dfSurvivors df)
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) [survivor] (dfSigners df)
                        `shouldBe` Left EqW2AddInvalid
            it "cut/add overlap (re-adding the cut witness) -> EqW2AddInvalid" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                 in advanceEqualities (dfSpent df) (dfCreated df) (dfWitCut df) (dfWitCut df) (dfSigners df)
                        `shouldBe` Left EqW2AddInvalid
            it "derived-set mismatch (datum keeps the outgoing set) -> Eq7CreatedStateMismatch" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    created = (dfCreated df){cdWitnesses = dfOldWitnesses df}
                 in advanceEqualities (dfSpent df) created (dfWitCut df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Left Eq7CreatedStateMismatch
            it "wrong survivor order (adds before survivors) -> Eq7CreatedStateMismatch" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    wrongOrder = dfWitAdd df <> dfSurvivors df
                    created = (dfCreated df){cdWitnesses = wrongOrder}
                 in advanceEqualities (dfSpent df) created (dfWitCut df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Left Eq7CreatedStateMismatch
            it "toad out of bounds -> Eq8CreatedIllFormed ToadRange" $ \doc ->
                let df = deltaFixture doc "adv_wit_2key"
                    badToad = toInteger (length (cdWitnesses (dfCreated df))) + 5
                    created = (dfCreated df){cdToad = badToad}
                 in advanceEqualities (dfSpent df) created (dfWitCut df) (dfWitAdd df) (dfSigners df)
                        `shouldBe` Left (Eq8CreatedIllFormed ToadRange)
