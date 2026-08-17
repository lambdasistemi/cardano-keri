{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindAdversarialSpec
Description : #291 INV-BIND eight-row pre-repair adversarial proofs

Permanent RED-first proofs for the frozen selectors. Each row asserts
that the current offset binder rejects a crafted event. Production
decoders are unchanged, so the binder still accepts and the suite is
intended RED. Malformed rows are signed by the committed @reg_2key@
current-key seeds; those signatures must verify as the event
controllers before a legacy accept is counted.
-}
module Cardano.KERI.AID.Checkpoint.InvBindAdversarialSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Advance qualified as Advance
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
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
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Registration qualified as Registration
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    evaluate,
 )
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word8)
import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
 )

-- | How one row was observed against the unfixed binder.
data Observation
    = -- | Signature verified and the current binder accepted.
      LegacyAccept
    | -- | Intended: the binder rejected the crafted event.
      Rejected
    | -- | Setup, signature, or unrelated binder failure.
      WrongReason
    deriving stock (Show, Eq)

-- | One named adversarial row.
data Row = Row
    { rowId :: Text
    , rowObservation :: Observation
    }

{- | Eight INV-BIND adversarial rows under the frozen Hspec selector. -}
spec :: Spec
spec = describe "#291 INV-BIND adversarial" $ do
    rows <- runIO buildRows
    runIO $ putStrLn (renderCanFail rows)
    mapM_ rejectExample rows

-- | One @it@ that requires the crafted event to be rejected.
rejectExample :: Row -> Spec
rejectExample row =
    it (T.unpack (rowId row) <> " is rejected") $
        rowObservation row `shouldBe` Rejected

-- | Load sealed grind rows and transform committed @reg_2key@.
buildRows :: IO [Row]
buildRows = do
    meta <- loadFixture "inv_bind_adversarial.json"
    baseFx <- loadFixture "registration.json"
    let rows = do
            dip <- grindReg meta "FX291-GRIND-DIP"
            drt <- grindAdv meta "FX291-GRIND-DRT"
            icp <- reg2key baseFx
            let malformedRows =
                    [ versionSize icp
                    , trailing icp
                    , duplicate icp
                    , reordered meta icp
                    , delimiter icp
                    , unknown icp
                    ]
            Right (dip : drt : malformedRows)
    case rows of
        Left err -> fail err
        Right xs -> pure xs

-- | FX291-GRIND-DIP against registration 'eventBinding'.
grindReg :: Value -> Text -> Either String Row
grindReg meta key = do
    sub <- require key meta
    raw <- decodeHex =<< textField sub "raw_hex"
    aid <- decodeHex =<< textField sub "aid_hex"
    cur <- decodeHex =<< textField sub "current_key_hex"
    nxt <- decodeHex =<< textField sub "next_digest_hex"
    sig <- decodeHex =<< textField sub "sig_hex"
    forged <- fromIntegral <$> intField sub "forged_off_t"
    offs <- require "offsets" sub
    ev <-
        regEvidence
            raw
            forged
            offs
            [(0, sig)]
    let d =
            genesis
                aid
                [cur]
                (Unweighted 1)
                [nxt]
                (Unweighted 1)
        sigOk = verifyEd25519 cur raw sig
        bound = Registration.eventBinding d ev
    pure (Row key (classify sigOk bound))

-- | FX291-GRIND-DRT against advance 'eventBinding'.
grindAdv :: Value -> Text -> Either String Row
grindAdv meta key = do
    sub <- require key meta
    raw <- decodeHex =<< textField sub "raw_hex"
    aid <- decodeHex =<< textField sub "aid_hex"
    cur <- decodeHex =<< textField sub "current_key_hex"
    nxt <- decodeHex =<< textField sub "next_digest_hex"
    sig <- decodeHex =<< textField sub "sig_hex"
    forged <- fromIntegral <$> intField sub "forged_off_t"
    offs <- require "offsets" sub
    ev <- advEvidence raw forged offs [(0, sig)]
    let d =
            ( genesis
                aid
                [cur]
                (Unweighted 1)
                [nxt]
                (Unweighted 1)
            )
                { cdSeq = 1
                , cdNativeSn = 1
                }
        sigOk = verifyEd25519 cur raw sig
        bound = Advance.eventBinding d ev
    pure (Row key (classify sigOk bound))

-- | One @reg_2key@ current-key controller (index, seed, raw verkey).
data Controller = Controller
    { cIndex :: Int
    , cSeed :: ByteString
    , cVerkey :: ByteString
    }

-- | Committed @reg_2key@ plus honest registration evidence.
data IcpBase = IcpBase
    { ibRaw :: ByteString
    , ibDatum :: CheckpointDatumV1
    , ibEvidence :: RegistrationEvidence
    , ibControllers :: [Controller]
    }

-- | Load the published @reg_2key@ icp used as the malformed base.
reg2key :: Value -> Either String IcpBase
reg2key fx = do
    sub <- require "reg_2key" fx
    ev <- require "event" sub
    raw <- decodeHex =<< textField ev "raw_hex"
    ked <- require "ked" ev
    aid <- digestRaw =<< textField ked "i"
    ks <- traverse verkeyRaw =<< textArrayField ked "k"
    ns <- traverse digestRaw =<< textArrayField ked "n"
    offs <- require "offsets" sub
    offT <- fromIntegral <$> intField offs "t"
    ctrls <- loadControllers sub
    evidence <- regEvidence raw offT offs []
    let d =
            genesis
                aid
                ks
                (Unweighted 2)
                ns
                (Unweighted 2)
    pure
        IcpBase
            { ibRaw = raw
            , ibDatum = d
            , ibEvidence = evidence
            , ibControllers = ctrls
            }

-- | Load @reg_2key.signer_seeds.current@ in index order.
loadControllers :: Value -> Either String [Controller]
loadControllers sub = do
    seeds <- require "signer_seeds" sub
    entries <- arrayField seeds "current"
    traverse one (zip [0 ..] entries)
  where
    one (i, e) = do
        seed <- decodeHex =<< textField e "seed_hex"
        vk <- verkeyRaw =<< textField e "verkey_qb64"
        Right
            Controller
                { cIndex = i
                , cSeed = seed
                , cVerkey = vk
                }

-- | Declared KERI size disagrees with the complete byte length.
versionSize :: IcpBase -> Row
versionSize b =
    malformed
        "FX291-VERSION-SIZE"
        b
        (patchVersion (ibRaw b) "000188")
        (ibEvidence b)

-- | A valid event followed by one unparsed byte.
trailing :: IcpBase -> Row
trailing b =
    malformed
        "FX291-TRAILING"
        b
        (ibRaw b <> "!")
        (ibEvidence b)

-- | Duplicate @s@; legacy @off_s@ keeps the favorable @0@.
duplicate :: IcpBase -> Row
duplicate b =
    malformed
        "FX291-DUPLICATE"
        b
        (patchVersion (appendBeforeEnd (ibRaw b) ",\"s\":\"1\"") "000191")
        (ibEvidence b)

-- | Valid field spellings in non-canonical order.
reordered :: Value -> IcpBase -> Row
reordered meta b =
    case decodeHex =<< textField sub "raw_hex" of
        Right raw ->
            malformed
                "FX291-REORDERED"
                b
                raw
                ( (ibEvidence b)
                    { reOffT = 132
                    , reOffI = 81
                    }
                )
        Left _ ->
            Row "FX291-REORDERED" WrongReason
  where
    sub = case lookupKey "FX291-REORDERED" meta of
        Just v -> v
        Nothing -> meta

-- | One framing delimiter replaced; value spans stay put.
delimiter :: IcpBase -> Row
delimiter b =
    malformed
        "FX291-DELIMITER"
        b
        (replaceAt (ibRaw b) 34 0x3b)
        (ibEvidence b)

-- | Extra unknown top-level field; honest spans recomputed as no-ops.
unknown :: IcpBase -> Row
unknown b =
    malformed
        "FX291-UNKNOWN"
        b
        (patchVersion (appendBeforeEnd (ibRaw b) ",\"zz\":\"0\"") "000192")
        (ibEvidence b)

{- | Sign the exact bytes with both @reg_2key@ controllers, require
key/signature/threshold binding, then observe 'eventBinding'.
-}
malformed
    :: Text
    -> IcpBase
    -> ByteString
    -> RegistrationEvidence
    -> Row
malformed name b raw ev0 =
    let d = ibDatum b
        ctrls = ibControllers b
        sigs =
            [ (cIndex c, signExact (cSeed c) raw)
            | c <- ctrls
            ]
        ev =
            ev0
                { reEventBytes = raw
                , reCtrlSigs = sigs
                }
        keysOk = controllersMatchDatum d ctrls
        sigsOk = controllerSigsOk d raw sigs
        threshOk =
            evaluate
                (cdCurThreshold d)
                (length (cdCurKeys d))
                (verifiedPositions d raw sigs)
        bound = Registration.eventBinding d ev
     in Row name (classify (keysOk && sigsOk && threshOk) bound)

-- | Signature and key binding must hold before a legacy accept counts.
classify :: Bool -> Either e () -> Observation
classify False _ = WrongReason
classify True (Right ()) = LegacyAccept
classify True (Left _) = Rejected

-- | Derived VKs equal the committed qb64 keys and the datum order.
controllersMatchDatum
    :: CheckpointDatumV1 -> [Controller] -> Bool
controllersMatchDatum d ctrls =
    length ctrls == length (cdCurKeys d)
        && and
            [ cIndex c == i
                && cVerkey c == expected
                && derivedVerkey (cSeed c) == expected
            | (i, expected, c) <-
                zip3 [0 ..] (cdCurKeys d) ctrls
            ]

-- | Each indexed controller signature verifies over the exact bytes.
controllerSigsOk
    :: CheckpointDatumV1
    -> ByteString
    -> [(Int, ByteString)]
    -> Bool
controllerSigsOk d raw sigs =
    length sigs == length (cdCurKeys d)
        && and
            [ i == idx && verifyEd25519 k raw sig
            | ((i, sig), (idx, k)) <-
                zip sigs (zip [0 ..] (cdCurKeys d))
            ]

-- | Distinct verifying controller positions (R7 shape).
verifiedPositions
    :: CheckpointDatumV1
    -> ByteString
    -> [(Int, ByteString)]
    -> IntSet.IntSet
verifiedPositions d raw sigs =
    IntSet.fromList
        [ i
        | (i, sig) <- sigs
        , Just k <- [atMay (cdCurKeys d) i]
        , verifyEd25519 k raw sig
        ]

-- | Sign exact bytes from a 32-byte keripy seed.
signExact :: ByteString -> ByteString -> ByteString
signExact seed raw =
    rawSerialiseSigDSIGN (signDSIGN () raw (fromSeed seed))

-- | Public key derived from a 32-byte keripy seed.
derivedVerkey :: ByteString -> ByteString
derivedVerkey seed =
    rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN (fromSeed seed))

-- | @genKeyDSIGN . mkSeedFromBytes@, the tree's keripy-seed convention.
fromSeed :: ByteString -> SignKeyDSIGN Ed25519DSIGN
fromSeed = genKeyDSIGN . mkSeedFromBytes

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing

-- | Genesis datum projected from the event's own key state.
genesis
    :: ByteString
    -> [ByteString]
    -> Threshold
    -> [ByteString]
    -> Threshold
    -> CheckpointDatumV1
genesis aid cur kt nxt nt =
    CheckpointDatumV1
        { cdCesrAid = aid
        , cdCurKeys = cur
        , cdCurThreshold = kt
        , cdNextKeys = nxt
        , cdNextThreshold = nt
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

-- | Registration evidence from offsets; @off_t@ is supplied separately.
regEvidence
    :: ByteString
    -> Int
    -> Value
    -> [(Int, ByteString)]
    -> Either String RegistrationEvidence
regEvidence raw offT offs sigs = do
    offI <- fromIntegral <$> intField offs "i"
    offS <- fromIntegral <$> intField offs "s"
    offKt <- fromIntegral <$> intField offs "kt"
    offNt <- fromIntegral <$> intField offs "nt"
    offBt <- fromIntegral <$> intField offs "bt"
    offK <- map fromIntegral <$> intArrayField offs "k"
    offN <- map fromIntegral <$> intArrayField offs "n"
    offB <- offBList
    pure
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
            , reCtrlSigs = sigs
            , reWitReceipts = []
            }
  where
    offBList = case intArrayField offs "b" of
        Right xs -> Right (map fromIntegral xs)
        Left _ -> Right []

-- | Advance evidence from the sealed @drt@ offsets.
advEvidence
    :: ByteString
    -> Int
    -> Value
    -> [(Int, ByteString)]
    -> Either String AdvanceEvidence
advEvidence raw offT offs sigs = do
    offI <- fromIntegral <$> intField offs "i"
    offS <- fromIntegral <$> intField offs "s"
    offKt <- fromIntegral <$> intField offs "kt"
    offNt <- fromIntegral <$> intField offs "nt"
    offBt <- fromIntegral <$> intField offs "bt"
    offK <- map fromIntegral <$> intArrayField offs "k"
    offN <- map fromIntegral <$> intArrayField offs "n"
    pure
        AdvanceEvidence
            { aeEventBytes = raw
            , aeOffT = offT
            , aeOffI = offI
            , aeOffS = offS
            , aeOffK = offK
            , aeOffKt = offKt
            , aeOffN = offN
            , aeOffNt = offNt
            , aeOffBr = []
            , aeOffBa = []
            , aeOffBt = offBt
            , aeWitCut = []
            , aeWitAdd = []
            , aeCtrlSigs = sigs
            , aeWitReceipts = []
            }

-- | Require an object field.
require :: Text -> Value -> Either String Value
require k v = note (k <> " missing") (lookupKey k v)

-- | Overwrite the six-digit KERI declared size at byte 16.
patchVersion :: ByteString -> ByteString -> ByteString
patchVersion raw digits =
    BS.take 16 raw <> digits <> BS.drop 22 raw

-- | Insert @extra@ immediately before the final byte.
appendBeforeEnd :: ByteString -> ByteString -> ByteString
appendBeforeEnd raw extra =
    BS.take (BS.length raw - 1) raw <> extra <> BS.take 1 (BS.reverse raw)

-- | Replace one byte at a zero-based index.
replaceAt :: ByteString -> Int -> Word8 -> ByteString
replaceAt raw off byte =
    BS.take off raw <> BS.singleton byte <> BS.drop (off + 1) raw

-- | Computed CAN-FAIL marker; never a hardcoded accept count.
renderCanFail :: [Row] -> String
renderCanFail rows =
    "INV-BIND-CAN-FAIL fixtures="
        <> show (length rows)
        <> " legacy_accepts="
        <> show (count LegacyAccept)
        <> " wrong_reason="
        <> show (count WrongReason)
  where
    count obs = length (filter ((== obs) . rowObservation) rows)
