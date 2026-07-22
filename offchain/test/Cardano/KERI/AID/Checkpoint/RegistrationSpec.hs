{- |
Module      : Cardano.KERI.AID.Checkpoint.RegistrationSpec
Description : #114 S2 pure registration predicate over keripy fixtures

Fixture-driven hspec for "Cardano.KERI.AID.Checkpoint.Registration":
the pure R3\/R4\/R6\/R7\/R8 registration predicate, the E1-E9
event-binding slice checks, the canonical @kt@\/@nt@\/@bt@
re-spelling, the @B@-code witness qb64, and the proof-token name.

Every honest artifact comes from the committed @registration.json@
keripy bundle (#114 S1): events, per-field offsets, event-own
controller signatures, and witness receipts. Both signature families
authenticate the exact event bytes.

Adversarial vectors are deterministic constructions over the honest
artifacts (mutated datums and misdirected offsets),
per the A-001 QB condition-1 offset-misdirection family. The
@reg_oversize@ H1 length tier is S4 scope (the hash-proof policy);
the pure predicate carries no length guard.
-}
module Cardano.KERI.AID.Checkpoint.RegistrationSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    DatumError (..),
    blake2b_256,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
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
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    InceptionError (..),
    RegistrationError (..),
    RegistrationEvidence (..),
    proofTokenName,
    qb64WitnessVerkey,
    registrationDepositFloor,
    registrationPredicate,
    respellHex,
    respellThreshold,
    validRegistrationDeposit,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
 )
import Data.Aeson (Value (..))
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
-- Test deployment contexts
-- ---------------------------------------------------------------

-- | The canonical registration deployment values.
ctx0 :: DeploymentContext
ctx0 =
    DeploymentContext
        { dcMinAda = 2_000_000
        , dcDReg = 1_000_000_000
        }

-- | An honest state-output lovelace comfortably above the floor.
funded :: Integer
funded = dcMinAda ctx0 + dcDReg ctx0

-- ---------------------------------------------------------------
-- Fixture case: datum + honest evidence
-- ---------------------------------------------------------------

-- | One registration sub-fixture, lifted into predicate inputs.
data RegCase = RegCase
    { rcRaw :: ByteString
    -- ^ @event.raw_hex@ decoded — the KERI serialization.
    , rcDatum :: CheckpointDatumV1
    -- ^ The genesis datum implied by the event's own key-state.
    , rcEvidence :: RegistrationEvidence
    -- ^ Honest offsets, event-own signatures, and witness receipts.
    , rcOldMessageSigs :: [(Int, ByteString)]
    -- ^ Obsolete signatures over the reconstructed InceptionMessage target.
    , rcWitnessReceipts :: [(Int, ByteString)]
    -- ^ The bundle's indexed witness receipts over @event_raw@.
    }

-- | Build the 'RegCase' of a sub-fixture.
regCase :: Value -> Text -> Either String RegCase
regCase fx key = do
    sub <- note (key <> " missing") (lookupKey key fx)
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    raw <- decodeHex =<< textField ev "raw_hex"
    ked <- note (key <> ".event.ked missing") (lookupKey "ked" ev)
    aid <- digestRaw =<< textField ked "i"
    ks <- traverse verkeyRaw =<< textArrayField ked "k"
    ns <- traverse digestRaw =<< textArrayField ked "n"
    ws <- traverse verkeyRaw =<< textArrayField ked "b"
    kt <- thresholdOf ked "kt"
    nt <- thresholdOf ked "nt"
    bt <- parseHexInt =<< textField ked "bt"
    offs <- note (key <> ".offsets missing") (lookupKey "offsets" sub)
    offT <- off offs "t"
    offI <- off offs "i"
    offS <- off offs "s"
    offKt <- off offs "kt"
    offNt <- off offs "nt"
    offBt <- off offs "bt"
    offK <- offList offs "k"
    offN <- offList offs "n"
    offB <- offList offs "b"
    eventSigs <- committedSigs sub "event_sigs"
    witnessReceipts <- optionalCommittedSigs sub "witness_receipts"
    obsoleteSigs <- oldMessageSigs
    let datum =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = ks
                , cdCurThreshold = kt
                , cdNextKeys = ns
                , cdNextThreshold = nt
                , cdWitnesses = ws
                , cdToad = bt
                , cdSeq = 0
                , cdNativeSn = 0
                }
    pure
        RegCase
            { rcRaw = raw
            , rcDatum = datum
            , rcEvidence =
                RegistrationEvidence
                    { reEventBytes = raw
                    , reOffT = offT
                    , reOffI = offI
                    , reOffS = offS
                    , reOffK = offK
                    , reOffKt = offKt
                    , reOffN = offN
                    , reOffNt = offNt
                    , reOffB = offB
                    , reOffBt = offBt
                    , reCtrlSigs = eventSigs
                    , reWitReceipts = witnessReceipts
                    }
            , rcOldMessageSigs = obsoleteSigs
            , rcWitnessReceipts = witnessReceipts
            }
  where
    off o f = fromIntegral <$> intField o f
    offList o f = map fromIntegral <$> intArrayField o f

-- | Run a check against a built fixture case, failing on load error.
withCase ::
    Value -> Text -> (RegCase -> Expectation) -> Expectation
withCase fx key k = case regCase fx key of
    Left err -> expectationFailure err
    Right c -> k c

-- ---------------------------------------------------------------
-- Harness helpers
-- ---------------------------------------------------------------

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

-- | Parse a KERI fraction string (@\"1\/2\"@, @\"1\"@) to a 'Weight'.
parseFraction :: Text -> Either String Weight
parseFraction t = case T.splitOn "/" t of
    [n] -> (`Weight` 1) <$> parseDecInt n
    [n, d] -> Weight <$> parseDecInt n <*> parseDecInt d
    _ -> Left (T.unpack t <> ": not a fraction string")

-- | Parse a decimal integer text.
parseDecInt :: Text -> Either String Integer
parseDecInt = parseDigits 10 decDigit
  where
    decDigit c
        | isDigit c = Just (toInteger (fromEnum c - 48))
        | otherwise = Nothing

-- | Parse a lowercase-hex integer text (keripy @{:x}@ spelling).
parseHexInt :: Text -> Either String Integer
parseHexInt = parseDigits 16 hexDigit
  where
    hexDigit c
        | isDigit c = Just (toInteger (fromEnum c - 48))
        | c >= 'a' && c <= 'f' = Just (toInteger (fromEnum c - 87))
        | otherwise = Nothing

-- | Fold digits of a positional numeral, rejecting empty\/foreign.
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

-- | One committed indexed-signature array as @(index, raw sig)@.
committedSigs :: Value -> Text -> Either String [(Int, ByteString)]
committedSigs sub field = do
    entries <- arrayOf sub field
    traverse entrySig entries
  where
    entrySig e = do
        idx <- intField e "index"
        sig <- decodeHex =<< textField e "sig_hex"
        pure (fromIntegral idx, sig)

-- | An indexed-signature array which is absent for unwitnessed fixtures.
optionalCommittedSigs :: Value -> Text -> Either String [(Int, ByteString)]
optionalCommittedSigs sub field = case lookupKey field sub of
    Nothing -> Right []
    Just _ -> committedSigs sub field

-- | Require an array field (loader-style drilling).
arrayOf :: Value -> Text -> Either String [Value]
arrayOf v f = case lookupKey f v of
    Just (Array xs) -> Right (toList xs)
    _ -> Left (T.unpack f <> " missing or not an array")

{- | The previously committed signatures over the deleted
@InceptionMessage@ target. They remain only as adversarial bytes proving
that the old authorization layer no longer verifies; no private signing
material or obsolete preimage implementation is retained.
-}
oldMessageSigs :: Either String [(Int, ByteString)]
oldMessageSigs =
    traverse
        decodeIndexed
        [
            ( 0
            , "46e283ba1a98eb2a3aeb950d0479f19289523e2d8783b1c1ee08981639a918cf4a09132b2bd9c5dbbd368c396beaf357939b362a65b3c03413c58bf2ad3db809"
            )
        ,
            ( 1
            , "6c6f4dff51ca178184bc250effd5b0146f65305cb50b81600fcf1bd3d92e8c4e68f04c159399d002f0f016d9e1891f0e18571208af58dc9774ae02ded7e6b901"
            )
        ]
  where
    decodeIndexed (idx, sig) = do
        raw <- decodeHex sig
        pure (idx, raw)

-- | Shorthand: run the predicate on a case under 'ctx0' / 'funded'.
runReg :: RegCase -> Either RegistrationError ()
runReg c = registrationPredicate ctx0 (rcDatum c) funded (rcEvidence c)

-- ---------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------

spec :: Spec
spec =
    describe "Registration - #114 S2 pure predicate (keripy oracle)" $
        beforeAll (loadFixture "registration.json") $ do
            positives
            genesisAndSchema
            sliceNegatives
            signatureNegatives
            receiptNegatives
            depositNegatives
            deploymentFloor
            misdirectionFamily
            proofToken
            respelling
            witnessQb64

-- ---------------------------------------------------------------
-- Positives
-- ---------------------------------------------------------------

positives :: SpecWith Value
positives =
    describe "positives: honest full-evidence packages" $ do
        it "reg_witnessed (3-wit toad-2) is accepted" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                runReg c `shouldBe` Right ()
        it "reg_weighted (fractional kt) is accepted" $ \fx ->
            withCase fx "reg_weighted" $ \c ->
                runReg c `shouldBe` Right ()
        it "owner replay: same package re-validates identically" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                (runReg c, runReg c)
                    `shouldBe` (Right (), Right ())
        it "deposit boundary: exactly min_ada + d_reg passes" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    (dcMinAda ctx0 + dcDReg ctx0)
                    (rcEvidence c)
                    `shouldBe` Right ()

-- ---------------------------------------------------------------
-- R3 genesis / R4 schema
-- ---------------------------------------------------------------

genesisAndSchema :: SpecWith Value
genesisAndSchema =
    describe "R3 genesis datum / R4 schema predicate" $ do
        it "seq /= 0 -> R3GenesisDatumMismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c){cdSeq = 1}
                    funded
                    (rcEvidence c)
                    `shouldBe` Left R3GenesisDatumMismatch
        it "native_sn /= 0 -> R4 InceptionNativeSnNonZero" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c){cdNativeSn = 1}
                    funded
                    (rcEvidence c)
                    `shouldBe` Left
                        (R4InceptionInvalid InceptionNativeSnNonZero)

-- ---------------------------------------------------------------
-- R6: per-slice E1-E9 negatives
-- ---------------------------------------------------------------

sliceNegatives :: SpecWith Value
sliceNegatives =
    describe "R6 slice checks: one rejection per E1-E9 axis" $ do
        it "E1: reg_dip rejected -> E1EventTypeMismatch" $ \fx ->
            withCase fx "reg_dip" $ \c ->
                runReg c `shouldBe` Left E1EventTypeMismatch
        it "E1: reg_drt rejected -> E1EventTypeMismatch" $ \fx ->
            withCase fx "reg_drt" $ \c ->
                runReg c `shouldBe` Left E1EventTypeMismatch
        it "E2: crossed AID in the datum -> E2AidMismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                withCase fx "reg_weighted" $ \other -> do
                    let d =
                            (rcDatum c)
                                { cdCesrAid =
                                    cdCesrAid (rcDatum other)
                                }
                    registrationPredicate
                        ctx0
                        d
                        funded
                        (rcEvidence c)
                        `shouldBe` Left E2AidMismatch
        it "E3: off_s pointed at t -> E3SequenceMismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffS = reOffT (rcEvidence c)
                        }
                    `shouldBe` Left E3SequenceMismatch
        it "E4: squat - attacker keys over victim bytes" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                withCase fx "reg_weighted" $ \other -> do
                    let d =
                            (rcDatum c)
                                { cdCurKeys =
                                    take 2 (cdCurKeys (rcDatum other))
                                }
                    registrationPredicate
                        ctx0
                        d
                        funded
                        (rcEvidence c)
                        `shouldBe` Left E4CurKeysMismatch
        it "E5: restated unweighted kt -> E5 mismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c){cdCurThreshold = Unweighted 1}
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E5CurThresholdMismatch
        it "E5: mutated weighted clause -> E5 mismatch" $ \fx ->
            withCase fx "reg_weighted" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                        { cdCurThreshold =
                            Weighted
                                [
                                    [ Weight 1 3
                                    , Weight 1 4
                                    , Weight 1 4
                                    ]
                                ]
                        }
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E5CurThresholdMismatch
        it "E6: substituted next digest -> E6 mismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                        { cdNextKeys =
                            flipFirst (cdNextKeys (rcDatum c))
                        }
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E6NextKeysMismatch
        it "E7: restated nt -> E7 mismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c){cdNextThreshold = Unweighted 1}
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E7NextThresholdMismatch
        it "E8: substituted witness verkey -> E8 mismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                        { cdWitnesses =
                            flipFirst (cdWitnesses (rcDatum c))
                        }
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E8WitnessesMismatch
        it "E8: witness count mismatch -> E8 mismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                        { cdWitnesses =
                            drop 1 (cdWitnesses (rcDatum c))
                        }
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E8WitnessesMismatch
        it "E9: restated toad -> E9ToadMismatch" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c){cdToad = 1}
                    funded
                    (rcEvidence c)
                    `shouldBe` Left E9ToadMismatch

-- | Total head for fixture lists the bundle guarantees non-empty.
first1 :: [a] -> a
first1 (x : _) = x
first1 [] = error "fixture list unexpectedly empty"

-- | Flip one bit of the first entry (a 32-byte-preserving mutation).
flipFirst :: [ByteString] -> [ByteString]
flipFirst [] = []
flipFirst (x : xs) = BS.cons (BS.head x `xor255`) (BS.tail x) : xs
  where
    xor255 b = 255 - b

-- | Flip the final byte without disturbing any E1-E9 field slice.
flipLast :: ByteString -> ByteString
flipLast raw
    | BS.null raw = raw
    | otherwise = BS.init raw <> BS.singleton (255 - BS.last raw)

-- | Flip one signature byte while preserving its 64-byte shape.
flipSignature :: ByteString -> ByteString
flipSignature sig
    | BS.null sig = sig
    | otherwise = BS.cons (255 - BS.head sig) (BS.tail sig)

-- ---------------------------------------------------------------
-- R7: signature negatives
-- ---------------------------------------------------------------

signatureNegatives :: SpecWith Value
signatureNegatives =
    describe "R7 controller signatures over exact event bytes" $ do
        it "event-own controller signatures are accepted" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                    `shouldBe` Right ()
        it "old InceptionMessage-only signatures reject -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reCtrlSigs = rcOldMessageSigs c
                        }
                    `shouldBe` Left R7QuorumUnsatisfied
        it "below threshold: 1 of kt=2 -> R7 unsatisfied" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reCtrlSigs =
                            take 1 (reCtrlSigs (rcEvidence c))
                        }
                    `shouldBe` Left R7QuorumUnsatisfied
        it "negative controller index fails closed -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (_idx, sig) = first1 (reCtrlSigs (rcEvidence c))
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reCtrlSigs =
                                (-1, sig)
                                    : drop 1 (reCtrlSigs (rcEvidence c))
                            }
                        `shouldBe` Left R7QuorumUnsatisfied
        it "out-of-range controller index fails closed -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (_idx, sig) = first1 (reCtrlSigs (rcEvidence c))
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reCtrlSigs =
                                (99, sig)
                                    : drop 1 (reCtrlSigs (rcEvidence c))
                            }
                        `shouldBe` Left R7QuorumUnsatisfied
        it "bad controller signature fails -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (idx, sig) = first1 (reCtrlSigs (rcEvidence c))
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reCtrlSigs =
                                (idx, flipSignature sig)
                                    : drop 1 (reCtrlSigs (rcEvidence c))
                            }
                        `shouldBe` Left R7QuorumUnsatisfied
        it "below weighted threshold: 2 of 3 quarters" $ \fx ->
            withCase fx "reg_weighted" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reCtrlSigs =
                            drop 1 (reCtrlSigs (rcEvidence c))
                        }
                    `shouldBe` Left R7QuorumUnsatisfied
        it "duplicated index does not stack -> R7 unsatisfied" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reCtrlSigs =
                            replicate
                                2
                                (first1 (reCtrlSigs (rcEvidence c)))
                        }
                    `shouldBe` Left R7QuorumUnsatisfied
        it "wrong controller keys over event bytes -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                case reCtrlSigs (rcEvidence c) of
                    (idx0, sig0) : (idx1, sig1) : _ ->
                        registrationPredicate
                            ctx0
                            (rcDatum c)
                            funded
                            (rcEvidence c)
                                { reCtrlSigs =
                                    [(idx0, sig1), (idx1, sig0)]
                                }
                            `shouldBe` Left R7QuorumUnsatisfied
                    _ -> expectationFailure "expected two controller signatures"
        it "controller signatures crossed onto different event bytes -> R7" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c){reEventBytes = flipLast (rcRaw c)}
                    `shouldBe` Left R7QuorumUnsatisfied

-- ---------------------------------------------------------------
-- Witness receipts over exact event bytes
-- ---------------------------------------------------------------

receiptNegatives :: SpecWith Value
receiptNegatives =
    describe "R7 witness receipts over exact event bytes" $ do
        it "witnessed inception accepts its indexed receipt quorum" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                runReg c `shouldBe` Right ()
        it "receipt-free witnessed inception rejects" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c){reWitReceipts = []}
                    `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "below toad receipt set rejects" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reWitReceipts = take 1 (rcWitnessReceipts c)
                        }
                    `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "duplicate receipt index counts once" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reWitReceipts = replicate 2 (first1 (rcWitnessReceipts c))
                        }
                    `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "negative receipt index fails closed" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (_idx, sig) = first1 (rcWitnessReceipts c)
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reWitReceipts =
                                (-1, sig) : drop 1 (rcWitnessReceipts c)
                            }
                        `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "out-of-range receipt index fails closed" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (_idx, sig) = first1 (rcWitnessReceipts c)
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reWitReceipts =
                                (99, sig) : drop 1 (rcWitnessReceipts c)
                            }
                        `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "wrong witness keys over event bytes reject" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reWitReceipts = reCtrlSigs (rcEvidence c)
                        }
                    `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "bad witness receipt signature rejects" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                let (idx, sig) = first1 (rcWitnessReceipts c)
                 in registrationPredicate
                        ctx0
                        (rcDatum c)
                        funded
                        (rcEvidence c)
                            { reWitReceipts =
                                (idx, flipSignature sig)
                                    : drop 1 (rcWitnessReceipts c)
                            }
                        `shouldBe` Left R7WitnessQuorumUnsatisfied
        it "toad=0 requires a literally empty receipt list" $ \fx ->
            withCase fx "reg_2key" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reWitReceipts = [(0, BS.replicate 64 0)]
                        }
                    `shouldBe` Left R7WitnessQuorumUnsatisfied

-- ---------------------------------------------------------------
-- R8: deposit arithmetic
-- ---------------------------------------------------------------

depositNegatives :: SpecWith Value
depositNegatives =
    describe "R8 deposit floor" $
        it "one lovelace short -> R8DepositBelowMinimum" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    (dcMinAda ctx0 + dcDReg ctx0 - 1)
                    (rcEvidence c)
                    `shouldBe` Left R8DepositBelowMinimum

deploymentFloor :: SpecWith Value
deploymentFloor =
    describe "deployment d_reg mechanical floor" $ do
        it "pins the generated boundary values" $ \_fx -> do
            registrationDepositFloor `shouldBe` 5_000_000
            validRegistrationDeposit registrationDepositFloor `shouldBe` True
            validRegistrationDeposit (registrationDepositFloor - 1) `shouldBe` False
        it "4,999,999 rejects even when the output meets the applied bond" $ \fx ->
            withCase fx "reg_witnessed" $ \c -> do
                let invalidCtx = ctx0{dcDReg = registrationDepositFloor - 1}
                registrationPredicate
                    invalidCtx
                    (rcDatum c)
                    (dcMinAda invalidCtx + dcDReg invalidCtx)
                    (rcEvidence c)
                    `shouldBe` Left DRegBelowMinimum

-- ---------------------------------------------------------------
-- A-001 QB condition 1: the offset-misdirection family
-- ---------------------------------------------------------------

misdirectionFamily :: SpecWith Value
misdirectionFamily =
    describe "A-001 offset-misdirection family (acceptance gate)" $ do
        it "wrong offset: off_i shifted by one -> E2" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffI = reOffI (rcEvidence c) + 1
                        }
                    `shouldBe` Left E2AidMismatch
        it "overlapping spans: off_k[1] = off_k[0] + 1 -> E4" $
            \fx -> withCase fx "reg_witnessed" $ \c -> do
                let k0 = first1 (reOffK (rcEvidence c))
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c){reOffK = [k0, k0 + 1]}
                    `shouldBe` Left E4CurKeysMismatch
        it "off_k pointed into n entries (D vs E code) -> E4" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffK = reOffN (rcEvidence c)
                        }
                    `shouldBe` Left E4CurKeysMismatch
        it "off_k pointed into b entries (D vs B code) -> E4" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffK =
                            take 2 (reOffB (rcEvidence c))
                        }
                    `shouldBe` Left E4CurKeysMismatch
        it "off_i pointed at a k entry (E vs D code) -> E2" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffI =
                            first1 (reOffK (rcEvidence c))
                        }
                    `shouldBe` Left E2AidMismatch
        it "off_b pointed at k entries (B vs D code) -> E8" $
            \fx -> withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffB =
                            reOffK (rcEvidence c)
                                <> drop
                                    2
                                    (reOffB (rcEvidence c))
                        }
                    `shouldBe` Left E8WitnessesMismatch
        it "truncated slice: off_i at the byte tail -> E2" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffI = BS.length (rcRaw c) - 10
                        }
                    `shouldBe` Left E2AidMismatch
        it "truncated slice: last off_k at the tail -> E4" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c)
                        { reOffK =
                            take
                                1
                                (reOffK (rcEvidence c))
                                <> [BS.length (rcRaw c) - 20]
                        }
                    `shouldBe` Left E4CurKeysMismatch
        it "negative offset rejected -> E2" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                registrationPredicate
                    ctx0
                    (rcDatum c)
                    funded
                    (rcEvidence c){reOffI = -1}
                    `shouldBe` Left E2AidMismatch
        it "duplicated offsets duplicate the key -> R4 F18" $ \fx ->
            withCase fx "reg_witnessed" $ \c -> do
                let k0raw = first1 (cdCurKeys (rcDatum c))
                    k0off = first1 (reOffK (rcEvidence c))
                    d = (rcDatum c){cdCurKeys = [k0raw, k0raw]}
                registrationPredicate
                    ctx0
                    d
                    funded
                    (rcEvidence c)
                        { reOffK = [k0off, k0off]
                        }
                    `shouldBe` Left
                        ( R4InceptionInvalid
                            ( InceptionIllFormed
                                ( ThresholdIllFormed
                                    DuplicateKey
                                )
                            )
                        )

-- ---------------------------------------------------------------
-- R5 (name derivation only in S2): the proof-token name
-- ---------------------------------------------------------------

proofToken :: SpecWith Value
proofToken =
    describe "proof-token name blake2b_256(bytes || aid)" $ do
        it "matches the direct digest and is 32 bytes" $ \fx ->
            withCase fx "reg_witnessed" $ \c -> do
                let aid = cdCesrAid (rcDatum c)
                    name = proofTokenName (rcRaw c) aid
                name `shouldBe` blake2b_256 (rcRaw c <> aid)
                BS.length name `shouldBe` 32
        it "binds the pair: crossed (bytes, aid) differs" $ \fx ->
            withCase fx "reg_witnessed" $ \c ->
                withCase fx "reg_weighted" $ \other -> do
                    let aid = cdCesrAid (rcDatum c)
                        aidO = cdCesrAid (rcDatum other)
                    proofTokenName (rcRaw c) aidO
                        `shouldSatisfy` ( /=
                                            proofTokenName
                                                (rcRaw c)
                                                aid
                                        )
                    proofTokenName (rcRaw c) aidO
                        `shouldSatisfy` ( /=
                                            proofTokenName
                                                (rcRaw other)
                                                aidO
                                        )

-- ---------------------------------------------------------------
-- E5/E7/E9 spelling units (fixture-grounded via the positives)
-- ---------------------------------------------------------------

respelling :: SpecWith Value
respelling =
    describe "canonical keripy re-spelling of kt/nt/bt" $ do
        it "respellHex spells keripy {:x} lowercase" $ \_fx -> do
            respellHex 0 `shouldBe` "0"
            respellHex 2 `shouldBe` "2"
            respellHex 10 `shouldBe` "a"
            respellHex 26 `shouldBe` "1a"
        it "unweighted threshold spells as hex string" $ \_fx ->
            respellThreshold (Unweighted 2) `shouldBe` "2"
        it "single weighted clause spells flat" $ \_fx ->
            respellThreshold
                ( Weighted
                    [[Weight 1 2, Weight 1 4, Weight 1 4]]
                )
                `shouldBe` "[\"1/2\",\"1/4\",\"1/4\"]"
        it "unity weight spells without a denominator" $ \_fx ->
            respellThreshold (Weighted [[Weight 1 1]])
                `shouldBe` "[\"1\"]"
        it "the weighted fixture kt slice IS the re-spelling" $
            \fx -> withCase fx "reg_weighted" $ \c -> do
                let e = rcEvidence c
                    expected =
                        respellThreshold
                            (cdCurThreshold (rcDatum c))
                BS.take
                    (BS.length expected)
                    (BS.drop (reOffKt e) (rcRaw c))
                    `shouldBe` expected

-- ---------------------------------------------------------------
-- E8 material: the B-code (non-transferable) witness qb64
-- ---------------------------------------------------------------

witnessQb64 :: SpecWith Value
witnessQb64 =
    describe "B-code witness qb64" $ do
        it "round-trips every reg_witnessed ked.b entry" $ \fx ->
            case bEntries fx of
                Left err -> expectationFailure err
                Right entries -> do
                    entries `shouldSatisfy` (not . null)
                    mapM_ bRoundTrip entries
        it "spells the B code, not D" $ \fx ->
            case bEntries fx of
                Left err -> expectationFailure err
                Right entries ->
                    mapM_
                        ( \t ->
                            BS.head (TE.encodeUtf8 t)
                                `shouldBe` 0x42
                        )
                        entries

-- | One @ked.b@ entry decodes and re-encodes to the same B-code text.
bRoundTrip :: Text -> Expectation
bRoundTrip t = do
    raw <- either fail pure (verkeyRaw t)
    qb64WitnessVerkey raw `shouldBe` TE.encodeUtf8 t

-- | The qb64 witness texts of @reg_witnessed.event.ked.b@.
bEntries :: Value -> Either String [Text]
bEntries fx = do
    sub <- note "reg_witnessed missing" (lookupKey "reg_witnessed" fx)
    ev <- note "event missing" (lookupKey "event" sub)
    ked <- note "ked missing" (lookupKey "ked" ev)
    textArrayField ked "b"
