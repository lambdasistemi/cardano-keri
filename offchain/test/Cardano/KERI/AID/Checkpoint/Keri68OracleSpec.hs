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

The JSON-loading and qb64-decode helpers live in
"Cardano.KERI.AID.Checkpoint.FixtureLoader" (shared with @EnforcementSpec@).
-}
module Cardano.KERI.AID.Checkpoint.Keri68OracleSpec (spec) where

import Cardano.Crypto.Hash (Blake2b_256, digest)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Verkey)
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    digestRaw,
    loadFixture,
    lookupKey,
    note,
    textArrayField,
    textField,
    verkeyRaw,
 )
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value)
import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
-- Wrong-derivation primitives (kept local; the negative control's teeth)
-- ---------------------------------------------------------------------------

blake2b256 :: ByteString -> ByteString
blake2b256 = digest (Proxy :: Proxy Blake2b_256)

flipFirstBit :: ByteString -> ByteString
flipFirstBit b = case BS.uncons b of
    Just (h, t) -> BS.cons (h `xor` 1) t
    Nothing -> b
