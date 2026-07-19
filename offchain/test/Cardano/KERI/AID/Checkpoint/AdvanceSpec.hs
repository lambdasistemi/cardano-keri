{- |
Module      : Cardano.KERI.AID.Checkpoint.AdvanceSpec
Description : #115 S4 pure advance predicate over keripy fixtures

Fixture-driven hspec for "Cardano.KERI.AID.Checkpoint.Advance": the pure
advance predicate (message reconstruction + eq1-eq8\/W1-W3, AE1-AE10
event binding, the incoming-set witness receipt gate).

Every honest artifact comes from the committed @advance.json@ keripy
bundle (#115 S1): the witnessed\/keep\/downgrade rotation family,
per-field offsets, and signer seeds. Controller signatures are produced
HERE from the exported @rotation_current@ seeds, over the reconstructed
'AdvanceMessage' canonical-CBOR preimage — never over the KERI event
bytes (the bundle's own @rot_sigs@ sign @event_raw@ and MUST fail the
controller-evidence gate). Incoming-set witness receipts, by contrast,
sign @event_raw@ (O1) — the bundle's own @rot_witness_receipts@ are
used directly, already indexed into the W3-derived incoming set.

Adversarial vectors are deterministic constructions over the honest
artifacts (offset misdirection, delta malformations, stolen\/
substituted controller evidence, receipt-index games), per the A-001
condition-1 offset-misdirection family and the epic's incoming-set
witness ruling.
-}
module Cardano.KERI.AID.Checkpoint.AdvanceSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEventError (..),
    AdvanceEvidence (..),
    AdvancePredicateError (..),
    advancePredicate,
    reconstructAdvanceMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    DatumError (..),
    canonicalCbor,
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
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError (..),
    AdvanceMessage,
    SpentCheckpoint (..),
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.Aeson (Value (..))
import Data.Bifunctor (second)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (
    Expectation,
    Spec,
    SpecWith,
    beforeAll,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- ---------------------------------------------------------------
-- Test spent-checkpoint plumbing (eq1-eq5 irrelevant to this slice)
-- ---------------------------------------------------------------

testNetwork :: Integer
testNetwork = 1

testPolicy :: ByteString
testPolicy = BS.replicate 28 0xCC

testSpentTxid :: ByteString
testSpentTxid = BS.replicate 32 0xD1

-- ---------------------------------------------------------------
-- Numeral / threshold JSON parsing (advance.json ked shapes)
-- ---------------------------------------------------------------

parseHexInt :: Text -> Either String Integer
parseHexInt = parseDigits 16 hexDigit
  where
    hexDigit c
        | isDigit c = Just (toInteger (fromEnum c - 48))
        | c >= 'a' && c <= 'f' = Just (toInteger (fromEnum c - 87))
        | otherwise = Nothing

parseDecInt :: Text -> Either String Integer
parseDecInt = parseDigits 10 decDigit
  where
    decDigit c
        | isDigit c = Just (toInteger (fromEnum c - 48))
        | otherwise = Nothing

parseDigits ::
    Integer -> (Char -> Maybe Integer) -> Text -> Either String Integer
parseDigits base digit t
    | T.null t = Left "empty numeral"
    | otherwise = T.foldl' step (Right 0) t
  where
    step acc c = do
        n <- acc
        case digit c of
            Just d -> Right (n * base + d)
            Nothing -> Left (T.unpack t <> ": not a numeral")

parseFraction :: Text -> Either String Weight
parseFraction t = case T.splitOn "/" t of
    [n] -> (`Weight` 1) <$> parseDecInt n
    [n, d] -> Weight <$> parseDecInt n <*> parseDecInt d
    _ -> Left (T.unpack t <> ": not a fraction string")

-- | ked threshold: hex string, or fraction-string weighted array.
thresholdOf :: Value -> Text -> Either String Threshold
thresholdOf ked f = do
    v <- note (f <> " missing") (lookupKey f ked)
    case v of
        String t -> Unweighted <$> parseHexInt t
        Array xs ->
            Weighted . pure <$> traverse asWeight (toList xs)
        _ -> Left (T.unpack f <> ": not a threshold value")
  where
    asWeight (String t) = parseFraction t
    asWeight _ = Left (T.unpack f <> ": weight is not a string")

-- ---------------------------------------------------------------
-- Fixture case: spent context + created datum + honest evidence
-- ---------------------------------------------------------------

-- | One advance sub-fixture, lifted into predicate inputs.
data AdvCase = AdvCase
    { acRaw :: ByteString
    -- ^ @rot.raw_hex@ decoded — the KERI serialization.
    , acSpent :: SpentCheckpoint
    -- ^ The @OLD@ spent context implied by the icp event.
    , acCreated :: CheckpointDatumV1
    -- ^ The @NEW@ successor datum implied by the rot event.
    , acEvidence :: AdvanceEvidence
    -- ^ Honest offsets + fresh preimage signatures + fixture receipts.
    , acNewSet :: [ByteString]
    -- ^ The W3-derived incoming witness set.
    , acOldWitnesses :: [ByteString]
    -- ^ @icp.ked.b@ — the outgoing witness set.
    , acSurvivors :: [ByteString]
    -- ^ The uncut outgoing witnesses, in spent order.
    , acRotSigners :: [SignKeyDSIGN Ed25519DSIGN]
    -- ^ @NEW.cur_keys@ signing keys (@rotation_current@ seeds).
    , acIcpSigners :: [SignKeyDSIGN Ed25519DSIGN]
    -- ^ @OLD@'s own current-key signing keys (@inception_current@).
    , acIcpKeys :: [ByteString]
    -- ^ The raw @OLD@ current verkeys (uncommitted as a successor board).
    , acEventRawCtrlSigs :: [(Int, ByteString)]
    -- ^ The bundle's own KERI signatures over @event_raw@ (@rot_sigs@).
    , acOldWitnessSigners :: [(ByteString, SignKeyDSIGN Ed25519DSIGN)]
    -- ^ @(raw verkey, signer)@ for every outgoing witness, in old order.
    , acOffP :: Int
    -- ^ Offset of the unchecked @p@ (prior-event SAID) region.
    , acOffD :: Int
    -- ^ Offset of the unchecked @d@ (this event's own SAID) region.
    , acOffA :: Int
    -- ^ Offset of the unchecked @a@ (anchored seals) region.
    }

-- | Build the 'AdvCase' of a sub-fixture.
advCase :: Value -> Text -> Either String AdvCase
advCase doc key = do
    sub <- field doc key
    icp <- field sub "icp"
    rot <- field sub "rot"
    icpKed <- field icp "ked"
    rotKed <- field rot "ked"
    raw <- decodeHex =<< textField rot "raw_hex"
    aid <- digestRaw =<< textField icpKed "i"
    icpKeys <- traverse verkeyRaw =<< textArrayField icpKed "k"
    oldWitnesses <- traverse verkeyRaw =<< textArrayField icpKed "b"
    icpNext <- traverse digestRaw =<< textArrayField icpKed "n"
    icpNextThr <- thresholdOf icpKed "nt"
    cuts <- traverse verkeyRaw =<< textArrayField rotKed "br"
    adds <- traverse verkeyRaw =<< textArrayField rotKed "ba"
    rotKeys <- traverse verkeyRaw =<< textArrayField rotKed "k"
    rotThr <- thresholdOf rotKed "kt"
    rotNext <- traverse digestRaw =<< textArrayField rotKed "n"
    rotNextThr <- thresholdOf rotKed "nt"
    toad <- parseHexInt =<< textField rotKed "bt"
    offs <- field sub "offsets"
    offT <- off offs "t"
    offI <- off offs "i"
    offS <- off offs "s"
    offKt <- off offs "kt"
    offNt <- off offs "nt"
    offBt <- off offs "bt"
    offK <- offList offs "k"
    offN <- offList offs "n"
    offBr <- offList offs "br"
    offBa <- offList offs "ba"
    seeds <- field sub "signer_seeds"
    rotSigners <- map mkSigner <$> seedList seeds "rotation_current"
    icpSigners <- map mkSigner <$> seedList seeds "inception_current"
    oldWitSigners <- map mkSigner <$> seedList seeds "witness_outgoing"
    eventRawCtrlSigs <- indexedSigs sub "rot_sigs"
    honestReceipts <- indexedSigs sub "rot_witness_receipts"
    offP <- off offs "p"
    saidText <- textField rot "said"
    offD <-
        note
            "d offset not found in raw bytes"
            (findSubstring (TE.encodeUtf8 saidText) raw)
    offA <-
        note
            "a offset not found in raw bytes"
            (fmap (+ 5) (findSubstring "\"a\":[" raw))
    let survivors = filter (`notElem` cuts) oldWitnesses
        newSet = survivors <> adds
        asset = deriveAidAssetName aid
        sc =
            SpentCheckpoint
                { scNetworkId = testNetwork
                , scPolicyId = testPolicy
                , scAidAssetName = asset
                , scTxid = testSpentTxid
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
        msg = reconstructAdvanceMessage sc created cuts adds
        evidence =
            AdvanceEvidence
                { aeEventBytes = raw
                , aeOffT = offT
                , aeOffI = offI
                , aeOffS = offS
                , aeOffK = offK
                , aeOffKt = offKt
                , aeOffN = offN
                , aeOffNt = offNt
                , aeOffBr = offBr
                , aeOffBa = offBa
                , aeOffBt = offBt
                , aeWitCut = cuts
                , aeWitAdd = adds
                , aeCtrlSigs = signAll msg rotSigners
                , aeWitReceipts = honestReceipts
                }
    pure
        AdvCase
            { acRaw = raw
            , acSpent = sc
            , acCreated = created
            , acEvidence = evidence
            , acNewSet = newSet
            , acOldWitnesses = oldWitnesses
            , acSurvivors = survivors
            , acRotSigners = rotSigners
            , acIcpSigners = icpSigners
            , acIcpKeys = icpKeys
            , acEventRawCtrlSigs = eventRawCtrlSigs
            , acOldWitnessSigners = zip oldWitnesses oldWitSigners
            , acOffP = offP
            , acOffD = offD
            , acOffA = offA
            }
  where
    field v k = note (k <> " missing") (lookupKey k v)
    off o f = fromIntegral <$> intField o f
    offList o f = map fromIntegral <$> intArrayField o f

-- | Run a check against a built fixture case, failing on load error.
withCase :: Value -> Text -> (AdvCase -> Expectation) -> Expectation
withCase fx key k = case advCase fx key of
    Left err -> expectationFailure err
    Right c -> k c

-- | Shorthand: run the predicate on a case's own honest evidence.
runAdv :: AdvCase -> Either AdvancePredicateError ()
runAdv c = advancePredicate (acSpent c) (acCreated c) (acEvidence c)

-- | Shorthand: run the predicate on a case's datum with substitute evidence.
runAdvWith :: AdvCase -> AdvanceEvidence -> Either AdvancePredicateError ()
runAdvWith c = advancePredicate (acSpent c) (acCreated c)

-- ---------------------------------------------------------------
-- Harness helpers
-- ---------------------------------------------------------------

-- | The exported seed hexes of @signer_seeds.<branch>@.
seedList :: Value -> Text -> Either String [ByteString]
seedList seeds branch = do
    entries <- arrayField seeds branch
    traverse (\e -> decodeHex =<< textField e "seed_hex") entries

-- | @(index, raw sig)@ pairs of a bundle's own signature array.
indexedSigs :: Value -> Text -> Either String [(Int, ByteString)]
indexedSigs sub fieldKey = do
    entries <- arrayField sub fieldKey
    traverse entrySig entries
  where
    entrySig e = do
        idx <- intField e "index"
        sig <- decodeHex =<< textField e "sig_hex"
        pure (fromIntegral idx, sig)

-- | An Ed25519 signing key from a 32-byte exported seed.
mkSigner :: ByteString -> SignKeyDSIGN Ed25519DSIGN
mkSigner seed = genKeyDSIGN (mkSeedFromBytes seed)

-- | Raw 64-byte Ed25519 signature over a message.
signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver sk msg = rawSerialiseSigDSIGN (signDSIGN () msg sk)

-- | Indexed signatures of all given signers over an 'AdvanceMessage' preimage.
signAll ::
    AdvanceMessage -> [SignKeyDSIGN Ed25519DSIGN] -> [(Int, ByteString)]
signAll msg signers =
    [(j, signOver sk preimage) | (j, sk) <- zip [0 ..] signers]
  where
    preimage = canonicalCbor msg

-- | The signer of a known raw verkey in an @(verkey, signer)@ association.
signerFor ::
    [(ByteString, SignKeyDSIGN Ed25519DSIGN)] ->
    ByteString ->
    SignKeyDSIGN Ed25519DSIGN
signerFor assocs key = case lookup key assocs of
    Just sk -> sk
    Nothing -> error "signerFor: key not found in fixture seed export"

-- | Flip the first byte of a signature (a corrupted-but-shaped mutation).
flipByte :: ByteString -> ByteString
flipByte bs = case BS.uncons bs of
    Just (b, rest) -> BS.cons (255 - b) rest
    Nothing -> bs

-- | Total head for fixture lists the bundle guarantees non-empty.
first1 :: [a] -> a
first1 (x : _) = x
first1 [] = error "fixture list unexpectedly empty"

-- | The offset of the first occurrence of @needle@ in @haystack@, if any.
findSubstring :: ByteString -> ByteString -> Maybe Int
findSubstring needle haystack = go 0
  where
    n = BS.length needle
    go i
        | i + n > BS.length haystack = Nothing
        | needle `BS.isPrefixOf` BS.drop i haystack = Just i
        | otherwise = go (i + 1)

-- ---------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------

spec :: Spec
spec =
    describe "Advance - #115 S4 pure predicate (keripy oracle)" $
        beforeAll (loadFixture "advance.json") $ do
            positives
            eventBindingNegatives
            misdirectionFamily
            controllerEvidenceNegatives
            deltaMalformations
            receiptQuorumNegatives

-- ---------------------------------------------------------------
-- Positives
-- ---------------------------------------------------------------

positives :: SpecWith Value
positives =
    describe "positives: honest full-evidence packages" $ do
        it "adv_wit_2key: witnessed cut+add accepted" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdv c `shouldBe` Right ()
        it "adv_wit_7key: GLEIF-scale witnessed cut+add accepted" $ \fx ->
            withCase fx "adv_wit_7key" $ \c ->
                runAdv c `shouldBe` Right ()
        it "adv_keep: no-delta rotation accepted; witnesses unchanged" $
            \fx -> withCase fx "adv_keep" $ \c -> do
                runAdv c `shouldBe` Right ()
                cdWitnesses (acCreated c) `shouldBe` acOldWitnesses c
        it "adv_downgrade: cuts every witness; toad=0, zero receipts" $
            \fx -> withCase fx "adv_downgrade" $ \c -> do
                runAdv c `shouldBe` Right ()
                cdWitnesses (acCreated c) `shouldBe` []
                cdToad (acCreated c) `shouldBe` 0
                aeWitReceipts (acEvidence c) `shouldSatisfy` null

-- ---------------------------------------------------------------
-- V6: AE1-AE10 event-binding negatives (one per axis)
-- ---------------------------------------------------------------

eventBindingNegatives :: SpecWith Value
eventBindingNegatives =
    describe "V6: AE1-AE10 event-binding negatives (one per axis)" $ do
        it "AE1: off_t pointed at i -> AE1EventTypeMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffT = aeOffI (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE1EventTypeMismatch)
        it "AE2: off_i shifted by one -> AE2AidMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffI = aeOffI (acEvidence c) + 1}
                    `shouldBe` Left (AdvEventBinding AE2AidMismatch)
        it "AE3: off_s pointed at t -> AE3SequenceMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffS = aeOffT (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE3SequenceMismatch)
        it "AE4: overlapping off_k spans -> AE4CurKeysMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c -> do
                let k0 = first1 (aeOffK (acEvidence c))
                runAdvWith c (acEvidence c){aeOffK = [k0, k0 + 1]}
                    `shouldBe` Left (AdvEventBinding AE4CurKeysMismatch)
        it "AE5: off_kt pointed at bt -> AE5CurThresholdMismatch" $ \fx ->
            withCase fx "adv_wit_7key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffKt = aeOffBt (acEvidence c)}
                    `shouldBe` Left
                        (AdvEventBinding AE5CurThresholdMismatch)
        it
            "AE6: off_n pointed at off_k (E vs D code) -> AE6NextKeysMismatch"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffN = aeOffK (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE6NextKeysMismatch)
        it "AE7: off_nt pointed at kt -> AE7NextThresholdMismatch" $ \fx ->
            withCase fx "adv_wit_7key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffNt = aeOffKt (acEvidence c)}
                    `shouldBe` Left
                        (AdvEventBinding AE7NextThresholdMismatch)
        it "AE8: off_br pointed at ba -> AE8WitCutMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffBr = aeOffBa (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE8WitCutMismatch)
        it "AE9: off_ba pointed at br -> AE9WitAddMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffBa = aeOffBr (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE9WitAddMismatch)
        it "AE10: off_bt pointed at kt -> AE10ToadMismatch" $ \fx ->
            withCase fx "adv_wit_7key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffBt = aeOffKt (acEvidence c)}
                    `shouldBe` Left (AdvEventBinding AE10ToadMismatch)

-- ---------------------------------------------------------------
-- A-001 condition 1: the offset-misdirection family
-- ---------------------------------------------------------------

misdirectionFamily :: SpecWith Value
misdirectionFamily =
    describe "A-001 offset-misdirection family (acceptance gate)" $ do
        it "truncated slice: off_i at the byte tail -> AE2" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeOffI = BS.length (acRaw c) - 10}
                    `shouldBe` Left (AdvEventBinding AE2AidMismatch)
        it "negative offset rejected -> AE2" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffI = -1}
                    `shouldBe` Left (AdvEventBinding AE2AidMismatch)
        it "duplicated off_k entries -> AE4" $ \fx ->
            withCase fx "adv_wit_2key" $ \c -> do
                let k0 = first1 (aeOffK (acEvidence c))
                runAdvWith c (acEvidence c){aeOffK = [k0, k0]}
                    `shouldBe` Left (AdvEventBinding AE4CurKeysMismatch)
        it "off_br pointed into off_k (B vs D code) -> AE8" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeOffBr = take 1 (aeOffK (acEvidence c))
                        }
                    `shouldBe` Left (AdvEventBinding AE8WitCutMismatch)
        it "shortened off_k (1 of 2) -> AE4CurKeysMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeOffK = take 1 (aeOffK (acEvidence c))
                        }
                    `shouldBe` Left (AdvEventBinding AE4CurKeysMismatch)
        it "shortened off_n (1 of 2) -> AE6NextKeysMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeOffN = take 1 (aeOffN (acEvidence c))
                        }
                    `shouldBe` Left (AdvEventBinding AE6NextKeysMismatch)
        it "emptied off_br (0 of 1) -> AE8WitCutMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffBr = []}
                    `shouldBe` Left (AdvEventBinding AE8WitCutMismatch)
        it "emptied off_ba (0 of 1) -> AE9WitAddMismatch" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffBa = []}
                    `shouldBe` Left (AdvEventBinding AE9WitAddMismatch)
        it "off_t redirected into the unchecked p region -> AE1" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffT = acOffP c}
                    `shouldBe` Left (AdvEventBinding AE1EventTypeMismatch)
        it "off_kt redirected into the unchecked d region -> AE5" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffKt = acOffD c}
                    `shouldBe` Left
                        (AdvEventBinding AE5CurThresholdMismatch)
        it "off_bt redirected into the unchecked a region -> AE10" $
            \fx -> withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeOffBt = acOffA c}
                    `shouldBe` Left (AdvEventBinding AE10ToadMismatch)

-- ---------------------------------------------------------------
-- V5: controller-evidence negatives (folded into eq6 by advanceEqualities)
-- ---------------------------------------------------------------

controllerEvidenceNegatives :: SpecWith Value
controllerEvidenceNegatives =
    describe "V5: controller-evidence negatives (eq6)" $ do
        it
            "bad index: ctrl_sigs index out of range -> Eq6CurrentQuorumUnsatisfied"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                let (_, sig) = first1 (aeCtrlSigs (acEvidence c))
                 in runAdvWith c (acEvidence c){aeCtrlSigs = [(99, sig)]}
                        `shouldBe` Left
                            (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied)
        it
            "wrong preimage: KERI event_raw sigs MUST fail -> Eq6CurrentQuorumUnsatisfied"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeCtrlSigs = acEventRawCtrlSigs c}
                    `shouldBe` Left
                        (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied)
        it "below threshold: 1 of kt=2 -> Eq6CurrentQuorumUnsatisfied" $
            \fx -> withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeCtrlSigs = take 1 (aeCtrlSigs (acEvidence c))
                        }
                    `shouldBe` Left
                        (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied)
        it
            "stolen full spent-current quorum (icp keys) cannot rotate -> Eq6CurrentQuorumUnsatisfied"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                let msg =
                        reconstructAdvanceMessage
                            (acSpent c)
                            (acCreated c)
                            (aeWitCut (acEvidence c))
                            (aeWitAdd (acEvidence c))
                    stolen = signAll msg (acIcpSigners c)
                 in runAdvWith c (acEvidence c){aeCtrlSigs = stolen}
                        `shouldBe` Left
                            (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied)
        it
            "substituted successor evidence (uncommitted board) -> Eq6PriorNextQuorumUnsatisfied"
            $ \fx -> withCase fx "adv_wit_2key" $ \c -> do
                let substituted = (acCreated c){cdCurKeys = acIcpKeys c}
                    msg =
                        reconstructAdvanceMessage
                            (acSpent c)
                            substituted
                            (aeWitCut (acEvidence c))
                            (aeWitAdd (acEvidence c))
                    sigs = signAll msg (acIcpSigners c)
                advancePredicate
                    (acSpent c)
                    substituted
                    (acEvidence c){aeCtrlSigs = sigs}
                    `shouldBe` Left
                        (AdvMessageInvalid Eq6PriorNextQuorumUnsatisfied)

-- ---------------------------------------------------------------
-- V4 delta malformations (W1/W2/eq7/eq8)
-- ---------------------------------------------------------------

deltaMalformations :: SpecWith Value
deltaMalformations =
    describe "V4 delta malformations (W1/W2/eq7/eq8)" $ do
        it "duplicate cut -> EqW1CutInvalid" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                let cut = first1 (aeWitCut (acEvidence c))
                 in runAdvWith c (acEvidence c){aeWitCut = [cut, cut]}
                        `shouldBe` Left (AdvMessageInvalid EqW1CutInvalid)
        it "cut of a non-member witness -> EqW1CutInvalid" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeWitCut = aeWitAdd (acEvidence c)}
                    `shouldBe` Left (AdvMessageInvalid EqW1CutInvalid)
        it "duplicate add -> EqW2AddInvalid" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                let add = first1 (aeWitAdd (acEvidence c))
                 in runAdvWith c (acEvidence c){aeWitAdd = [add, add]}
                        `shouldBe` Left (AdvMessageInvalid EqW2AddInvalid)
        it "add already present among survivors -> EqW2AddInvalid" $
            \fx -> withCase fx "adv_wit_2key" $ \c ->
                let survivor = first1 (acSurvivors c)
                 in runAdvWith c (acEvidence c){aeWitAdd = [survivor]}
                        `shouldBe` Left (AdvMessageInvalid EqW2AddInvalid)
        it "cut/add overlap -> EqW2AddInvalid" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c){aeWitAdd = aeWitCut (acEvidence c)}
                    `shouldBe` Left (AdvMessageInvalid EqW2AddInvalid)
        it
            "derived-set mismatch (datum keeps outgoing set) -> Eq7CreatedStateMismatch"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                advancePredicate
                    (acSpent c)
                    (acCreated c){cdWitnesses = acOldWitnesses c}
                    (acEvidence c)
                    `shouldBe` Left
                        (AdvMessageInvalid Eq7CreatedStateMismatch)
        it
            "wrong survivor order (adds before survivors) -> Eq7CreatedStateMismatch"
            $ \fx -> withCase fx "adv_wit_2key" $ \c ->
                let wrongOrder =
                        aeWitAdd (acEvidence c) <> acSurvivors c
                 in advancePredicate
                        (acSpent c)
                        (acCreated c){cdWitnesses = wrongOrder}
                        (acEvidence c)
                        `shouldBe` Left
                            (AdvMessageInvalid Eq7CreatedStateMismatch)
        it "toad out of bounds -> Eq8CreatedIllFormed ToadRange" $ \fx ->
            withCase fx "adv_wit_2key" $ \c -> do
                let badToad = toInteger (length (acNewSet c)) + 5
                    created = (acCreated c){cdToad = badToad}
                    msg =
                        reconstructAdvanceMessage
                            (acSpent c)
                            created
                            (aeWitCut (acEvidence c))
                            (aeWitAdd (acEvidence c))
                    sigs = signAll msg (acRotSigners c)
                advancePredicate
                    (acSpent c)
                    created
                    (acEvidence c){aeCtrlSigs = sigs}
                    `shouldBe` Left
                        (AdvMessageInvalid (Eq8CreatedIllFormed ToadRange))

-- ---------------------------------------------------------------
-- V7: incoming-set witness receipt-quorum negatives
-- ---------------------------------------------------------------

receiptQuorumNegatives :: SpecWith Value
receiptQuorumNegatives =
    describe "V7: incoming-set witness receipt-quorum negatives" $ do
        it "receipt-free advance rejected (toad=2, no receipts)" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith c (acEvidence c){aeWitReceipts = []}
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "below-toad receipts: 1 of 2 rejected" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeWitReceipts =
                            take 1 (aeWitReceipts (acEvidence c))
                        }
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "bad/out-of-range receipt index does not count" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                let r0 = first1 (aeWitReceipts (acEvidence c))
                 in runAdvWith
                        c
                        (acEvidence c){aeWitReceipts = [r0, (99, snd r0)]}
                        `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "bad receipt signature does not count" $ \fx ->
            withCase fx "adv_wit_2key" $ \c -> do
                let receipts = aeWitReceipts (acEvidence c)
                    r0 = first1 receipts
                    r1 = receipts !! 1
                    corrupted = second flipByte r1
                runAdvWith
                    c
                    (acEvidence c){aeWitReceipts = [r0, corrupted]}
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "duplicate receipt index counts once" $ \fx ->
            withCase fx "adv_wit_2key" $ \c ->
                let r0 = first1 (aeWitReceipts (acEvidence c))
                 in runAdvWith c (acEvidence c){aeWitReceipts = [r0, r0]}
                        `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it
            "wrong-member index: a valid sig at a different in-range index does not count"
            $ \fx -> withCase fx "adv_wit_2key" $ \c -> do
                let receipts = aeWitReceipts (acEvidence c)
                    r0 = first1 receipts
                    r1 = receipts !! 1
                    relabeled = (1, snd r0)
                runAdvWith
                    c
                    (acEvidence c){aeWitReceipts = [relabeled, r1]}
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "receipt by a cut witness never counts at any index" $
            \fx -> withCase fx "adv_wit_2key" $ \c -> do
                let cutKey = first1 (aeWitCut (acEvidence c))
                    cutSigner = signerFor (acOldWitnessSigners c) cutKey
                    cutSig = signOver cutSigner (acRaw c)
                    attempts =
                        [ (idx, cutSig)
                        | idx <- [0 .. length (acNewSet c) - 1]
                        ]
                runAdvWith c (acEvidence c){aeWitReceipts = attempts}
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it "outgoing-only quorum at old board positions rejected" $
            \fx -> withCase fx "adv_wit_2key" $ \c -> do
                let attempts =
                        [ (idx, signOver sk (acRaw c))
                        | (idx, (_, sk)) <-
                            zip [0 ..] (acOldWitnessSigners c)
                        ]
                runAdvWith c (acEvidence c){aeWitReceipts = attempts}
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
        it
            "adv_downgrade: any supplied receipt entry rejects (toad=0 requires none)"
            $ \fx -> withCase fx "adv_downgrade" $ \c ->
                runAdvWith
                    c
                    (acEvidence c)
                        { aeWitReceipts = [(0, BS.replicate 64 0)]
                        }
                    `shouldBe` Left AdvReceiptQuorumUnsatisfied
