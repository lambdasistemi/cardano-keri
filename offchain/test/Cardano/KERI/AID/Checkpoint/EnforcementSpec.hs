{- |
Module      : Cardano.KERI.AID.Checkpoint.EnforcementSpec
Description : Convict/Freeze predicates over the committed keripy fixtures

Builds a tip 'CheckpointDatumV1' and decoded 'EventEvidence' from the committed
keripy fixtures (reusing the shared "FixtureLoader" decoders) and drives the
Slice-3 enforcement predicates. Positive cases are the four fixture scenarios;
negatives (F1/F4/F5/F7/F8/F9/F10) mutate a loaded fixture in-spec — the fixture
JSON files are never edited.
-}
module Cardano.KERI.AID.Checkpoint.EnforcementSpec (spec) where

import Cardano.Crypto.Hash (Blake2b_256, digest)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    AddressRole (..),
    ContinuingOutput (..),
    ConvictError (..),
    ConvictOutputError (..),
    EventEvidence (..),
    FreezeError (..),
    FreezeOutputError (..),
    OutputDatum (..),
    TombstoneV1 (..),
    convictOutputPredicate,
    convictPredicate,
    freezeOutputPredicate,
    freezePredicate,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    digestRaw,
    intArrayField,
    intField,
    loadFixture,
    lookupKey,
    note,
    textArrayField,
    textField,
    verkeyRaw,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value (..))
import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Numeric (readHex)
import PlutusTx.IsData.Class (
    fromBuiltinData,
    toBuiltinData,
 )
import Test.Hspec (
    Expectation,
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )
import Text.Read (readMaybe)

spec :: Spec
spec = describe "Enforcement - convict/freeze over the keripy fixtures" $ do
    fork <- runIO (loadFixture "fork.json")
    honest2 <- runIO (loadFixture "honest_2key.json")
    honest7 <- runIO (loadFixture "honest_7key.json")
    lagFx <- runIO (loadFixture "lag.json")
    forkW <- runIO (loadFixture "fork_witnessed.json")

    describe "T116-S1 oracle offsets and artifact preservation" $ do
        forM_ (enforcementFixtureCfgs fork forkW lagFx) $ \cfg -> do
            it (T.unpack (efName cfg) <> ": offsets reproduce every protected KERI field") $
                checkEnforcementOffsets (efEvents cfg) (efFixture cfg)
            it (T.unpack (efName cfg) <> ": events and signatures retain their pre-offset bytes") $
                fixtureArtifactFingerprint (efEvents cfg) (efSignatures cfg) (efFixture cfg)
                    `shouldBe` Right (efFingerprint cfg)

    describe "convict" $ do
        -- fork: rot_conflict double-signs the rot_recorded tip (VALID conviction).
        it "fork: rot_conflict convicts the rot_recorded tip" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictPredicate tip ev `shouldBe` Right ()

        -- F3: the honest rot equals the state it reflects -> not a double-sign.
        it "honest_2key: rot vs its own reflected state is no conflict (F3)" $
            withBuilt (honestConvictSetup honest2) $ \(tip, ev) ->
                convictPredicate tip ev `shouldBe` Left CvNoConflict

        -- F4: a wrong sn breaks the same-slot gate.
        it "F4: evidence at a different sn -> CvSeqMismatch" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictPredicate tip ev{eeNativeSn = eeNativeSn ev + 7}
                    `shouldBe` Left CvSeqMismatch

        -- F5: a swapped AID.
        it "F5: evidence for a different AID -> CvAidMismatch" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictPredicate tip ev{eeCesrAid = flip1 (eeCesrAid ev)}
                    `shouldBe` Left CvAidMismatch

        -- F7: a reveal that is not the tip's cur_keys.
        it "F7: a different reveal -> CvRevealMismatch" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictPredicate
                    tip
                    ev{eeRevealedKeys = map flip1 (eeRevealedKeys ev)}
                    `shouldBe` Left CvRevealMismatch

        -- F1: no verifying controller signatures.
        it "F1: dropped controller sigs -> CvQuorumUnsatisfied" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictPredicate tip ev{eeCtrlSigs = []}
                    `shouldBe` Left CvQuorumUnsatisfied

    describe "convict anti-fork witness gate (Slice 7)" $ do
        -- A WITNESSED fork (witness double-receipts sn=1, diverging n) convicts.
        it "fork_witnessed: witnessed rot_conflict convicts" $
            withBuilt (forkWitnessedConvictSetup forkW) $ \(tip, ev) ->
                convictPredicate tip ev `shouldBe` Right ()

        -- F3b: the witnessed AID's OWN honest rot_recorded, presented as
        -- evidence, agrees on n/nt/bt -> must NOT convict. Failed RED before
        -- the Slice-7 fix (the conflict check's phantom `b` mismatch faked a
        -- conflict).
        it "F3b: witnessed honest rot_recorded is no conflict" $
            withBuilt (forkWitnessedHonestSetup forkW) $ \(tip, ev) ->
                convictPredicate tip ev `shouldBe` Left CvNoConflict

        -- F1b: a witnessed fork (toad=1) with too few witness receipts cannot
        -- convict. Failed RED before the Slice-7 witness gate.
        it "F1b: insufficient receipts -> CvInsufficientReceipts" $
            withBuilt (forkWitnessedConvictSetup forkW) $ \(tip, ev) ->
                convictPredicate tip ev{eeWitSigs = []}
                    `shouldBe` Left CvInsufficientReceipts

    describe "freeze" $ do
        -- honest_2key: a legit later event, toad=0 tier (Cardano is behind).
        it "honest_2key: witnessless later rot freezes" $
            withBuilt (freezeSetup honest2 Nothing) $ \(tip, ev) ->
                freezePredicate tip ev `shouldBe` Right ()

        -- lag: witnessed later event; the receipt satisfies toad=1.
        it "lag: witnessed later rot freezes" $
            withBuilt (freezeSetup lagFx (Just "rot_witness_receipts")) $ \(tip, ev) ->
                freezePredicate tip ev `shouldBe` Right ()

        -- honest_7key: 3-of-7 partial reveal still satisfies the weighted nt.
        it "honest_7key: partial reveal satisfies the committed weighted nt" $
            withBuilt (freezeSetup honest7 Nothing) $ \(tip, ev) ->
                freezePredicate tip ev `shouldBe` Right ()

        -- F10: an event not strictly ahead of the tip.
        it "F10: evidence at the tip's sn -> FzNotAhead" $
            withBuilt (freezeSetup honest2 Nothing) $ \(tip, ev) ->
                freezePredicate tip ev{eeNativeSn = cdNativeSn tip}
                    `shouldBe` Left FzNotAhead

        -- F9: a revealed key whose digest is not in the tip's next_keys.
        it "F9: reveal not in next_keys -> FzUncommittedReveal" $
            withBuilt (freezeSetup honest2 Nothing) $ \(tip, ev) ->
                freezePredicate tip{cdNextKeys = [BS.replicate 32 0]} ev
                    `shouldBe` Left FzUncommittedReveal

        -- F8: fewer verifying receipts than toad.
        it "F8: receipts below toad -> FzInsufficientReceipts" $
            withBuilt (freezeSetup lagFx (Just "rot_witness_receipts")) $ \(tip, ev) ->
                freezePredicate tip ev{eeWitSigs = []}
                    `shouldBe` Left FzInsufficientReceipts

        -- F2: some controller sigs verify, but not enough for cur_threshold
        -- (distinct from F1's zero-signature case).
        it "F2: sigs below threshold -> CvQuorumUnsatisfied" $
            withBuilt (honestConvictSetup honest2) $ \(tip, ev) ->
                convictPredicate tip ev{eeCtrlSigs = take 1 (eeCtrlSigs ev)}
                    `shouldBe` Left CvQuorumUnsatisfied

    describe "TombstoneV1 wire codec" $ do
        it "canonical CBOR golden (Constr 0, 3 fields)" $
            canonicalCbor goldenTombstone
                `shouldBe` hexBs
                    "d8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa015820ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccff"
        it "round-trips through Plutus Data" $
            fromBuiltinData (toBuiltinData goldenTombstone)
                `shouldBe` Just goldenTombstone

    describe "convict output shape (Convict 6)" $ do
        it "valid: Tombstone + token + correct record" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictOutputPredicate tip ev (tombstoneOut tip ev True Tombstone)
                    `shouldBe` Right ()

        -- F13: convict output missing the token.
        it "F13: missing token -> CoMissingToken" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictOutputPredicate tip ev (tombstoneOut tip ev False Tombstone)
                    `shouldBe` Left CoMissingToken

        -- F13: convict output carrying a checkpoint datum, not the record.
        it "F13: wrong record -> CoWrongRecord" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictOutputPredicate
                    tip
                    ev
                    (ContinuingOutput Tombstone True (CheckpointOutput tip))
                    `shouldBe` Left CoWrongRecord

        -- F13: convict output at a non-tombstone role.
        it "F13: non-tombstone role -> CoNotTombstone" $
            withBuilt (convictSetup fork) $ \(tip, ev) ->
                convictOutputPredicate tip ev (tombstoneOut tip ev True Active)
                    `shouldBe` Left CoNotTombstone

    describe "freeze output shape (Freeze 4)" $ do
        it "valid: Frozen + token + unchanged datum" $
            withBuilt (freezeSetup lagFx (Just "rot_witness_receipts")) $ \(tip, _) ->
                freezeOutputPredicate tip (checkpointOut tip True Frozen)
                    `shouldBe` Right ()

        -- F12: freeze output at a non-frozen role.
        it "F12: non-frozen role -> FoNotFrozen" $
            withBuilt (freezeSetup lagFx (Just "rot_witness_receipts")) $ \(tip, _) ->
                freezeOutputPredicate tip (checkpointOut tip True Active)
                    `shouldBe` Left FoNotFrozen

        -- F12: freeze output with a mutated datum.
        it "F12: mutated datum -> FoDatumChanged" $
            withBuilt (freezeSetup lagFx (Just "rot_witness_receipts")) $ \(tip, _) ->
                freezeOutputPredicate
                    tip
                    ( ContinuingOutput
                        Frozen
                        True
                        (CheckpointOutput tip{cdNativeSn = cdNativeSn tip + 1})
                    )
                    `shouldBe` Left FoDatumChanged

-- ---------------------------------------------------------------------------
-- Output-shape + tombstone fixtures/helpers
-- ---------------------------------------------------------------------------

-- | A fixed synthetic conviction record for the byte-parity golden.
goldenTombstone :: TombstoneV1
goldenTombstone = TombstoneV1 (BS.replicate 32 0xaa) 1 (BS.replicate 32 0xcc)

-- | The tombstone continuing-output a valid conviction writes.
tombstoneOut ::
    CheckpointDatumV1 -> EventEvidence -> Bool -> AddressRole -> ContinuingOutput
tombstoneOut tip ev hasTok role =
    ContinuingOutput
        role
        hasTok
        (TombstoneOutput (TombstoneV1 (cdCesrAid tip) (cdNativeSn tip) (eeSaid ev)))

-- | A checkpoint continuing-output carrying the tip datum unchanged.
checkpointOut :: CheckpointDatumV1 -> Bool -> AddressRole -> ContinuingOutput
checkpointOut tip hasTok role = ContinuingOutput role hasTok (CheckpointOutput tip)

-- | Decode a hex literal, erroring on malformed input.
hexBs :: Text -> ByteString
hexBs = either error id . decodeHex

-- ---------------------------------------------------------------------------
-- Scenario builders (tip datum + evidence from a fixture)
-- ---------------------------------------------------------------------------

-- | fork conviction: tip = rot_recorded state, evidence = rot_conflict.
convictSetup :: Value -> Either String (CheckpointDatumV1, EventEvidence)
convictSetup fx = do
    tip <- tipFrom fx "rot_recorded" 1
    ev <- evidenceFrom fx "rot_conflict" "rot_conflict_sigs" Nothing
    pure (tip, ev)

{- | Witnessed fork conviction: tip = the witnessed rot_recorded state (witness
set from the icp, since a rotation does not restate @b@); evidence = the
witness-receipted rot_conflict.
-}
forkWitnessedConvictSetup ::
    Value -> Either String (CheckpointDatumV1, EventEvidence)
forkWitnessedConvictSetup fx = do
    tip <- tipFromWitnessed fx "rot_recorded" "icp" 1
    ev <-
        evidenceFrom
            fx
            "rot_conflict"
            "rot_conflict_sigs"
            (Just "rot_conflict_witness_receipts")
    pure (tip, ev)

{- | F3b: the same witnessed tip, but evidence = the AID's OWN honest
rot_recorded (with its own witness receipts) — must not be a conflict.
-}
forkWitnessedHonestSetup ::
    Value -> Either String (CheckpointDatumV1, EventEvidence)
forkWitnessedHonestSetup fx = do
    tip <- tipFromWitnessed fx "rot_recorded" "icp" 1
    ev <-
        evidenceFrom
            fx
            "rot_recorded"
            "rot_recorded_sigs"
            (Just "rot_recorded_witness_receipts")
    pure (tip, ev)

-- | F3 conviction: tip = the state the rot reflects, evidence = that same rot.
honestConvictSetup :: Value -> Either String (CheckpointDatumV1, EventEvidence)
honestConvictSetup fx = do
    tip <- tipFrom fx "rot" 1
    ev <- evidenceFrom fx "rot" "rot_sigs" Nothing
    pure (tip, ev)

-- | Freeze: tip = the icp state, evidence = the later rot (+ optional receipts).
freezeSetup ::
    Value -> Maybe Text -> Either String (CheckpointDatumV1, EventEvidence)
freezeSetup fx witKey = do
    tip <- tipFrom fx "icp" 0
    ev <- evidenceFrom fx "rot" "rot_sigs" witKey
    pure (tip, ev)

-- | Build the tip datum a fixture event reflects (@cur = k@, @next = n@, ...).
tipFrom :: Value -> Text -> Integer -> Either String CheckpointDatumV1
tipFrom fx evKey seqNo = do
    de <- decodeEvent fx evKey
    pure
        CheckpointDatumV1
            { cdCesrAid = deAid de
            , cdCurKeys = deKeys de
            , cdCurThreshold = deKt de
            , cdNextKeys = deNext de
            , cdNextThreshold = deNt de
            , cdWitnesses = deWits de
            , cdToad = deToad de
            , cdSeq = seqNo
            , cdNativeSn = deSn de
            }

{- | Tip whose key state is @evKey@'s but whose witness set/toad come from
@witKey@ (the AID's inception): a KERI rotation carries no @b@ field, so a
witnessed AID's current witness set is inherited, not restated by the rot.
-}
tipFromWitnessed ::
    Value -> Text -> Text -> Integer -> Either String CheckpointDatumV1
tipFromWitnessed fx evKey witKey seqNo = do
    de <- decodeEvent fx evKey
    wde <- decodeEvent fx witKey
    pure
        CheckpointDatumV1
            { cdCesrAid = deAid de
            , cdCurKeys = deKeys de
            , cdCurThreshold = deKt de
            , cdNextKeys = deNext de
            , cdNextThreshold = deNt de
            , cdWitnesses = deWits wde
            , cdToad = deToad wde
            , cdSeq = seqNo
            , cdNativeSn = deSn de
            }

-- | Build evidence from a fixture event plus its controller/witness sig arrays.
evidenceFrom ::
    Value -> Text -> Text -> Maybe Text -> Either String EventEvidence
evidenceFrom fx evKey ctrlKey witKey = do
    de <- decodeEvent fx evKey
    ctrl <- sigList fx ctrlKey
    wit <- maybe (Right []) (sigList fx) witKey
    pure
        EventEvidence
            { eeEventBytes = deBytes de
            , eeType = deType de
            , eeNativeSn = deSn de
            , eeCesrAid = deAid de
            , eeSaid = deSaid de
            , eeRevealedKeys = deKeys de
            , eeNextKeys = deNext de
            , eeCurThreshold = deKt de
            , eeNextThreshold = deNt de
            , eeWitnesses = deWits de
            , eeToad = deToad de
            , eeCtrlSigs = ctrl
            , eeWitSigs = wit
            }

-- ---------------------------------------------------------------------------
-- Fixture decoding (KERI ked -> typed fields)
-- ---------------------------------------------------------------------------

-- | An event's fields, decoded from the fixture JSON.
data DecodedEvent = DecodedEvent
    { deBytes :: ByteString
    , deType :: ByteString
    , deSn :: Integer
    , deAid :: ByteString
    , deSaid :: ByteString
    , deKeys :: [ByteString]
    , deNext :: [ByteString]
    , deKt :: Threshold
    , deNt :: Threshold
    , deWits :: [ByteString]
    , deToad :: Integer
    }

decodeEvent :: Value -> Text -> Either String DecodedEvent
decodeEvent fx evKey = do
    ev <- note (evKey <> " missing") (lookupKey evKey fx)
    ked <- note (evKey <> ".ked missing") (lookupKey "ked" ev)
    bytes <- decodeHex =<< textField ev "raw_hex"
    ty <- TE.encodeUtf8 <$> textField ked "t"
    sn <- hexIntField ked "s"
    aid <- digestRaw =<< textField ked "i"
    said <- digestRaw =<< textField ev "said"
    keys <- traverse verkeyRaw =<< textArrayField ked "k"
    next <- traverse digestRaw =<< textArrayField ked "n"
    kt <- thresholdField ked "kt"
    nt <- thresholdField ked "nt"
    wits <- traverse verkeyRaw =<< textArrayField ked "b"
    toad <- hexIntField ked "bt"
    pure
        DecodedEvent
            { deBytes = bytes
            , deType = ty
            , deSn = sn
            , deAid = aid
            , deSaid = said
            , deKeys = keys
            , deNext = next
            , deKt = kt
            , deNt = nt
            , deWits = wits
            , deToad = toad
            }

-- | @(index, raw signature)@ pairs from a fixture sig array.
sigList :: Value -> Text -> Either String [(Int, ByteString)]
sigList fx key = do
    arr <- arrayField fx key
    forM arr $ \entry -> do
        idx <- intField entry "index"
        sig <- decodeHex =<< textField entry "sig_hex"
        pure (fromInteger idx, sig)

{- | Parse a KERI threshold: a hex string (@Unweighted@) or a fraction list
(a single @Weighted@ clause).
-}
thresholdField :: Value -> Text -> Either String Threshold
thresholdField ked key = do
    v <- note (key <> " missing") (lookupKey key ked)
    case v of
        String t -> Unweighted <$> hexInt t
        Array a -> Weighted . pure <$> traverse weightVal (toList a)
        _ -> Left (T.unpack key <> ": threshold is not a string or array")

weightVal :: Value -> Either String Weight
weightVal (String t) = case T.splitOn "/" t of
    [num] -> flip Weight 1 <$> readDecimal num
    [num, den] -> Weight <$> readDecimal num <*> readDecimal den
    _ -> Left ("malformed weight: " <> T.unpack t)
weightVal _ = Left "weight is not a string"

-- | Read a KERI hex-string integer (@s@, @bt@, integer @kt@/@nt@).
hexIntField :: Value -> Text -> Either String Integer
hexIntField ked key = hexInt =<< textField ked key

hexInt :: Text -> Either String Integer
hexInt t = case readHex (T.unpack t) :: [(Integer, String)] of
    [(n, "")] -> Right n
    _ -> Left ("malformed hex integer: " <> T.unpack t)

readDecimal :: Text -> Either String Integer
readDecimal t =
    maybe (Left ("malformed integer: " <> T.unpack t)) Right (readMaybe (T.unpack t))

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- | Run a scenario builder, failing the example with its diagnostic on 'Left'.
withBuilt :: Either String a -> (a -> Expectation) -> Expectation
withBuilt (Left err) _ = expectationFailure err
withBuilt (Right x) f = f x

-- | Flip the low bit of the first byte (a minimal, total mutation).
flip1 :: ByteString -> ByteString
flip1 b = case BS.uncons b of
    Just (h, t) -> BS.cons (h `xor` 1) t
    Nothing -> b

-- ---------------------------------------------------------------------------
-- T116-S1: generator-emitted offsets and byte-preservation baselines
-- ---------------------------------------------------------------------------

data EnforcementFixture = EnforcementFixture
    { efName :: Text
    , efFixture :: Value
    , efEvents :: [Text]
    , efSignatures :: [Text]
    , efFingerprint :: ByteString
    }

enforcementFixtureCfgs :: Value -> Value -> Value -> [EnforcementFixture]
enforcementFixtureCfgs fork forkW lagFx =
    [ EnforcementFixture
        "fork"
        fork
        ["icp", "rot_recorded", "rot_conflict"]
        ["icp_sigs", "rot_recorded_sigs", "rot_conflict_sigs"]
        (hexBs "9b3ab24cd28b3ebea6b1291565dcec5eddd7ee73239904e42d5d7b39a5bcca62")
    , EnforcementFixture
        "fork_witnessed"
        forkW
        ["icp", "rot_recorded", "rot_conflict"]
        [ "icp_sigs"
        , "rot_recorded_sigs"
        , "rot_recorded_witness_receipts"
        , "rot_conflict_sigs"
        , "rot_conflict_witness_receipts"
        ]
        (hexBs "e1b4cb43f54ba441d6ea3fd7e79d57ace6ba232e482d9fa5826af7e16945eace")
    , EnforcementFixture
        "lag"
        lagFx
        ["icp", "rot"]
        ["icp_sigs", "rot_sigs", "rot_witness_receipts"]
        (hexBs "59e617d3f891664757e70fec30eecbb3a616df977081b9c9908c22c2f4a8d236")
    ]

checkEnforcementOffsets :: [Text] -> Value -> Expectation
checkEnforcementOffsets eventKeys fx =
    withBuilt
        ( forM_
            eventKeys
            ( \eventKey -> do
                event <- note (eventKey <> " missing") (lookupKey eventKey fx)
                ked <- note (eventKey <> ".ked missing") (lookupKey "ked" event)
                raw <- decodeHex =<< textField event "raw_hex"
                offsets <- note (eventKey <> ".offsets missing") (lookupKey "offsets" event)
                forM_ ["t", "i", "s", "d", "kt", "nt", "bt"] $ \key -> do
                    offset <- intField offsets key
                    expected <-
                        TE.encodeUtf8
                            <$> if key == "d"
                                then textField event "said"
                                else textField ked key
                    sliceAt eventKey key raw offset expected
                forM_ ["k", "n", "b"] $ \key -> do
                    offsetsForKey <- intArrayField offsets key
                    expected <- map TE.encodeUtf8 <$> textArrayField ked key
                    unless (length offsetsForKey == length expected) $
                        Left (T.unpack (eventKey <> "." <> key <> ": offset count mismatch"))
                    forM_ (zip offsetsForKey expected) $
                        uncurry (sliceAt eventKey key raw)
            )
        )
        (const (pure ()))

sliceAt :: Text -> Text -> ByteString -> Integer -> ByteString -> Either String ()
sliceAt eventKey key raw offset expected = do
    let start = fromInteger offset
    unless (offset >= 0 && start + BS.length expected <= BS.length raw) $
        Left (T.unpack (eventKey <> "." <> key <> ": offset out of bounds"))
    unless (BS.take (BS.length expected) (BS.drop start raw) == expected) $
        Left (T.unpack (eventKey <> "." <> key <> ": offset slice mismatch"))

fixtureArtifactFingerprint :: [Text] -> [Text] -> Value -> Either String ByteString
fixtureArtifactFingerprint eventKeys sigKeys fx = do
    rawEvents <- forM eventKeys $ \key -> do
        event <- note (key <> " missing") (lookupKey key fx)
        TE.encodeUtf8 <$> textField event "raw_hex"
    sigs <- concat <$> forM sigKeys (textArrayFieldFor fx)
    pure (digest (Proxy :: Proxy Blake2b_256) (BS.concat (rawEvents <> map TE.encodeUtf8 sigs)))

textArrayFieldFor :: Value -> Text -> Either String [Text]
textArrayFieldFor fx key = do
    entries <- arrayField fx key
    traverse (`textField` "sig_hex") entries
