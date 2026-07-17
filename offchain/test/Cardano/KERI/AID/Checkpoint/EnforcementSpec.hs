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

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    ConvictError (..),
    EventEvidence (..),
    FreezeError (..),
    convictPredicate,
    freezePredicate,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    digestRaw,
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
import Control.Monad (forM)
import Data.Aeson (Value (..))
import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Numeric (readHex)
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

-- ---------------------------------------------------------------------------
-- Scenario builders (tip datum + evidence from a fixture)
-- ---------------------------------------------------------------------------

-- | fork conviction: tip = rot_recorded state, evidence = rot_conflict.
convictSetup :: Value -> Either String (CheckpointDatumV1, EventEvidence)
convictSetup fx = do
    tip <- tipFrom fx "rot_recorded" 1
    ev <- evidenceFrom fx "rot_conflict" "rot_conflict_sigs" Nothing
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
