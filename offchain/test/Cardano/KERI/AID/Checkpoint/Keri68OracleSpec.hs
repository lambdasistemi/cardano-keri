{- |
Module      : Cardano.KERI.AID.Checkpoint.Keri68OracleSpec
Description : Validate the merged #68 contract against the keripy oracle

Hermetic hspec that validates the SHIPPED library against the committed
keripy fixtures — "validate the past before entering the future". No keripy
at check time, only the committed JSON. Per fixture it asserts three things,
exercising the real shipped code (not a reimplementation):

  1. __O1 signature target__ — every committed signature (controller and
     witness) verifies over the event serialization @event_raw@ and does
     NOT verify over the SAID string, matching the fixture's recorded
     @signing_target == "event_raw"@.

  2. __#68 derivation vs the oracle__ — for each rotation's revealed keys,
     the real @'blake3Hash' ('qb64Verkey' rawKey)@ reproduces a member of
     the prior inception's committed next-key digest set @n@, byte-for-byte.
     This is the load-bearing E-native claim.

  3. __Negative control__ — a deliberately-wrong derivation (BLAKE2b in
     place of BLAKE3, and a bit-flipped key) does NOT match @n@, so the
     positive check provably discriminates.
-}
module Cardano.KERI.AID.Checkpoint.Keri68OracleSpec (spec) where

import Cardano.Crypto.Hash (Blake2b_256, digest)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Verkey,
 )
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (xor)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

-- | Which events and rotations to check, per committed fixture.
data FixtureCfg = FixtureCfg
    { fxFile :: FilePath
    -- ^ Fixture basename under @test/keri-fixtures/fixtures@.
    , fxSignedEvents :: [(Text, Text)]
    -- ^ @(eventKey, sigArrayKey)@ pairs whose signatures are O1-checked.
    , fxRotations :: [Text]
    -- ^ Event keys whose revealed @k@ must derive into the inception's @n@.
    }

-- | The inception event key; the sole source of the committed @n@ digest set.
inceptionKey :: Text
inceptionKey = "icp"

fixtureCfgs :: [FixtureCfg]
fixtureCfgs =
    [ FixtureCfg
        "honest_2key.json"
        [("icp", "icp_sigs"), ("rot", "rot_sigs")]
        ["rot"]
    , FixtureCfg
        "honest_7key.json"
        [("icp", "icp_sigs"), ("rot", "rot_sigs")]
        ["rot"]
    , FixtureCfg
        "fork.json"
        [ ("icp", "icp_sigs")
        , ("rot_recorded", "rot_recorded_sigs")
        , ("rot_conflict", "rot_conflict_sigs")
        ]
        ["rot_recorded", "rot_conflict"]
    , FixtureCfg
        "lag.json"
        [ ("icp", "icp_sigs")
        , ("rot", "rot_sigs")
        , ("rot", "rot_witness_receipts")
        ]
        ["rot"]
    ]

spec :: Spec
spec =
    describe "Keri68Oracle - validate the #68 past against the keripy oracle" $
        forM_ fixtureCfgs $ \cfg -> do
            fx <- runIO (loadFixture (fxFile cfg))
            describe (fxFile cfg) $ do
                describe "O1: signatures verify over event_raw, not the SAID" $
                    forM_ (fxSignedEvents cfg) $ \signed@(evKey, sigKey) ->
                        it (T.unpack evKey <> " / " <> T.unpack sigKey) $
                            o1Check fx signed `shouldBe` Right ()
                describe "#68 derivation reproduces keripy's committed n" $
                    forM_ (fxRotations cfg) $ \rotKey ->
                        it (T.unpack rotKey) $
                            derivationCheck fx rotKey `shouldBe` Right ()
                describe "negative control: a wrong derivation does not match n" $
                    forM_ (fxRotations cfg) $ \rotKey ->
                        it (T.unpack rotKey) $
                            negativeControl fx rotKey `shouldBe` Right ()

-- ---------------------------------------------------------------------------
-- The three checks (pure; a Left carries a diagnostic, Right () means pass)
-- ---------------------------------------------------------------------------

-- | O1: every signature over @evKey@ verifies over @event_raw@ and not the SAID.
o1Check :: Value -> (Text, Text) -> Either String ()
o1Check fx (evKey, sigKey) = do
    ev <- note (evKey <> " missing") (lookupKey evKey fx)
    eventBytes <- decodeHex =<< textField ev "raw_hex"
    saidBytes <- TE.encodeUtf8 <$> textField ev "said"
    sigs <- arrayField fx sigKey
    forM_ (zip [0 :: Int ..] sigs) $ \(i, sigV) -> do
        vkRaw <- verkeyRaw =<< textField sigV "signer_verkey_qb64"
        sigBytes <- decodeHex =<< textField sigV "sig_hex"
        let at = T.unpack sigKey <> "[" <> show i <> "]"
        unless (verifyEd25519 vkRaw eventBytes sigBytes) $
            Left (at <> ": does not verify over event_raw")
        when (verifyEd25519 vkRaw saidBytes sigBytes) $
            Left (at <> ": unexpectedly verifies over the SAID")

-- | #68: each revealed key derives (real qb64Verkey+blake3) into the icp's @n@.
derivationCheck :: Value -> Text -> Either String ()
derivationCheck fx rotKey = do
    nRaw <- committedNextDigests fx
    revealed <- revealedKeys fx rotKey
    forM_ revealed $ \keyText -> do
        rawKey <- verkeyRaw keyText
        let preimage = qb64Verkey rawKey
        -- Belt-and-suspenders: our forward encoder reproduces the fixture qb64.
        unless (preimage == TE.encodeUtf8 keyText) $
            Left (T.unpack keyText <> ": qb64Verkey does not reproduce the fixture key")
        unless (blake3Hash preimage `elem` nRaw) $
            Left (T.unpack keyText <> ": blake3(qb64Verkey key) is not a committed n digest")

-- | Negative control: BLAKE2b and a bit-flipped key must NOT match @n@.
negativeControl :: Value -> Text -> Either String ()
negativeControl fx rotKey = do
    nRaw <- committedNextDigests fx
    revealed <- revealedKeys fx rotKey
    forM_ revealed $ \keyText -> do
        rawKey <- verkeyRaw keyText
        let preimage = qb64Verkey rawKey
        when (blake2b256 preimage `elem` nRaw) $
            Left (T.unpack keyText <> ": BLAKE2b digest wrongly matches a committed n")
        let flippedDigest = blake3Hash (qb64Verkey (flipFirstBit rawKey))
        when (flippedDigest `elem` nRaw) $
            Left (T.unpack keyText <> ": bit-flipped key digest wrongly matches a committed n")

-- ---------------------------------------------------------------------------
-- Fixture field extraction
-- ---------------------------------------------------------------------------

-- | Decoded (raw 32-byte) next-key digest set committed in the inception @n@.
committedNextDigests :: Value -> Either String [ByteString]
committedNextDigests fx = do
    icp <- note (inceptionKey <> " missing") (lookupKey inceptionKey fx)
    ked <- note "icp.ked missing" (lookupKey "ked" icp)
    traverse digestRaw =<< textArrayField ked "n"

-- | The qb64 revealed keys @ked.k@ of the rotation at @rotKey@.
revealedKeys :: Value -> Text -> Either String [Text]
revealedKeys fx rotKey = do
    rot <- note (rotKey <> " missing") (lookupKey rotKey fx)
    ked <- note (rotKey <> ".ked missing") (lookupKey "ked" rot)
    textArrayField ked "k"

-- ---------------------------------------------------------------------------
-- Decoders (all built on the SHIPPED CESR parser / memory primitives)
-- ---------------------------------------------------------------------------

-- | Decode a qb64 verkey (@B@ or @D@) to its raw 32 bytes via shipped CESR.
verkeyRaw :: Text -> Either String ByteString
verkeyRaw t =
    parseFull t >>= \case
        Ed25519PublicKey raw -> Right raw
        _ -> Left (T.unpack t <> ": not an Ed25519 public key")

-- | Decode a qb64 @E@ self-addressing digest to its raw 32 bytes.
digestRaw :: Text -> Either String ByteString
digestRaw t =
    parseFull t >>= \case
        SelfAddressing raw -> Right raw
        _ -> Left (T.unpack t <> ": not a self-addressing digest")

-- | Parse exactly one CESR primitive, requiring the whole token be consumed.
parseFull :: Text -> Either String Primitive
parseFull t = case parsePrimitive (TE.encodeUtf8 t) of
    Right (p, rest)
        | BS.null rest -> Right p
        | otherwise -> Left (T.unpack t <> ": trailing bytes after primitive")
    Left err -> Left (T.unpack t <> ": " <> err)

decodeHex :: Text -> Either String ByteString
decodeHex t = convertFromBase Base16 (TE.encodeUtf8 t)

blake2b256 :: ByteString -> ByteString
blake2b256 = digest (Proxy :: Proxy Blake2b_256)

flipFirstBit :: ByteString -> ByteString
flipFirstBit b = case BS.uncons b of
    Just (h, t) -> BS.cons (h `xor` 1) t
    Nothing -> b

-- ---------------------------------------------------------------------------
-- Minimal aeson Value drilling
-- ---------------------------------------------------------------------------

loadFixture :: FilePath -> IO Value
loadFixture name = do
    path <- getDataFileName ("test/keri-fixtures/fixtures/" <> name)
    result <- eitherDecodeFileStrict path
    case result of
        Right v -> pure v
        Left err -> fail ("failed to decode " <> name <> ": " <> err)

note :: Text -> Maybe a -> Either String a
note msg = maybe (Left (T.unpack msg)) Right

lookupKey :: Text -> Value -> Maybe Value
lookupKey k value = case value of
    Object o -> KM.lookup (K.fromText k) o
    _ -> Nothing

textField :: Value -> Text -> Either String Text
textField value k = note (k <> " missing or not a string") $ do
    field <- lookupKey k value
    case field of
        String t -> Just t
        _ -> Nothing

arrayField :: Value -> Text -> Either String [Value]
arrayField value k = note (k <> " missing or not an array") $ do
    field <- lookupKey k value
    case field of
        Array a -> Just (toList a)
        _ -> Nothing

textArrayField :: Value -> Text -> Either String [Text]
textArrayField value k = do
    elems <- arrayField value k
    traverse asText elems
  where
    asText (String t) = Right t
    asText _ = Left (T.unpack k <> ": element is not a string")
