{- |
Module      : Cardano.KERI.AID.Checkpoint.RegistrationFixturesSpec
Description : Ground-truth checks for the #114 registration fixture family

Hermetic hspec over the committed @registration.json@ keripy bundle (#114
S1). keripy is the oracle: every event, signature, offset, and seed in the
bundle is generator-emitted; this spec proves the committed artifacts carry
the ground truth the registration path (E1-E9 slice checks, R7 signatures)
is later tested against:

  1. __Family completeness__ — the seven sub-fixtures (@reg_witnessed@,
     @reg_weighted@, @reg_dip@, @reg_drt@, @reg_oversize@, @reg_2key@,
     @reg_7key@) are present with event record, signatures, per-field
     offsets, and signer seeds; event types and shapes (3-wit toad-2,
     weighted @kt@, delegation, unwitnessed 2-key, unwitnessed
     GLEIF-shaped 7-key) match.

  2. __Size tiering__ — @reg_oversize@ exceeds the 1024-byte single-chunk
     boundary (H1 rejection material); every other event fits within it.

  3. __Offset ground truth__ — slicing @raw_hex@ at each exported offset
     reproduces the field bytes recorded in @ked@ (the E1-E9 oracle):
     string values as their unquoted content, weighted thresholds as the
     full compact-JSON array, per the generator's documented convention.

  4. __Signer-seed export__ — each exported Ed25519 seed derives (via the
     real DSIGN key generation) the fixture's qb64 verkey; current seeds
     match @ked.k@, next seeds digest (real blake3 over qb64) into @ked.n@.

  5. __O1__ — every committed signature verifies over @event_raw@, not the
     SAID (same discipline as @Keri68OracleSpec@).
-}
module Cardano.KERI.AID.Checkpoint.RegistrationFixturesSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseVerKeyDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Verkey)
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
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (Spec, beforeAll, describe, it, shouldBe)

-- | One expected sub-fixture of the registration family.
data RegFixture = RegFixture
    { rfKey :: Text
    -- ^ Sub-fixture key in @registration.json@.
    , rfEventType :: Text
    -- ^ Expected @ked.t@ (@icp@ / @dip@ / @drt@).
    , rfOversize :: Bool
    -- ^ Whether the event must exceed the 1024-byte chunk boundary.
    }

regFixtures :: [RegFixture]
regFixtures =
    [ RegFixture "reg_witnessed" "icp" False
    , RegFixture "reg_weighted" "icp" False
    , RegFixture "reg_dip" "dip" False
    , RegFixture "reg_drt" "drt" False
    , RegFixture "reg_oversize" "icp" True
    , RegFixture "reg_2key" "icp" False
    , RegFixture "reg_7key" "icp" False
    ]

spec :: Spec
spec =
    describe "RegistrationFixtures - #114 S1 keripy registration family" $
        beforeAll (loadFixture "registration.json") $ do
            describe "family completeness" $ do
                forM_ regFixtures $ \rf ->
                    it (T.unpack (rfKey rf) <> " carries event, sigs, offsets, seeds") $ \fx ->
                        checkCompleteness fx rf `shouldBe` Right ()
                it "reg_witnessed is the 3-witness toad-2 shape" $ \fx ->
                    checkWitnessedShape fx `shouldBe` Right ()
                it "reg_weighted has a fractionally-weighted kt" $ \fx ->
                    checkWeightedShape fx `shouldBe` Right ()
                it "reg_2key is the unwitnessed 2-key kt-2 shape" $ \fx ->
                    checkTwoKeyShape fx `shouldBe` Right ()
                it "reg_7key is the unwitnessed GLEIF-shaped 7-key board" $ \fx ->
                    checkSevenKeyShape fx `shouldBe` Right ()
                forM_ (["reg_dip", "reg_drt"] :: [Text]) $ \key ->
                    it (T.unpack key <> " records its delegator") $ \fx ->
                        checkDelegated fx key `shouldBe` Right ()
            describe "size tiering at the 1024-byte single-chunk boundary" $
                forM_ regFixtures $ \rf ->
                    it (T.unpack (rfKey rf) <> sizeLabel rf) $ \fx ->
                        checkSize fx rf `shouldBe` Right ()
            describe "offset ground truth: slices reproduce the ked field bytes" $
                forM_ regFixtures $ \rf ->
                    it (T.unpack (rfKey rf)) $ \fx ->
                        checkOffsets fx rf `shouldBe` Right ()
            describe "signer-seed export consistency" $
                forM_ regFixtures $ \rf ->
                    it (T.unpack (rfKey rf)) $ \fx ->
                        checkSeeds fx rf `shouldBe` Right ()
            describe "O1: signatures verify over event_raw, not the SAID" $
                forM_ regFixtures $ \rf ->
                    it (T.unpack (rfKey rf)) $ \fx ->
                        checkSigs fx rf `shouldBe` Right ()
  where
    sizeLabel rf = if rfOversize rf then " raw_len > 1024" else " raw_len <= 1024"

-- ---------------------------------------------------------------------------
-- The checks (pure; a Left carries a diagnostic, Right () means pass)
-- ---------------------------------------------------------------------------

{- | The sub-fixture, its event record, sigs, offsets, and seeds all exist;
@raw_len@ matches the decoded bytes; the event type and the seed counts
match the ked.
-}
checkCompleteness :: Value -> RegFixture -> Either String ()
checkCompleteness fx rf = do
    let key = rfKey rf
    sub <- subFixture fx key
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    raw <- decodeHex =<< textField ev "raw_hex"
    len <- intField ev "raw_len"
    unless (fromIntegral len == BS.length raw) $
        Left (T.unpack key <> ": raw_len does not match raw_hex")
    _ <- textField ev "said"
    _ <- textField ev "pre"
    ked <- note (key <> ".event.ked missing") (lookupKey "ked" ev)
    t <- textField ked "t"
    unless (t == rfEventType rf) $
        Left (T.unpack key <> ": event type " <> T.unpack t <> " /= " <> T.unpack (rfEventType rf))
    sigs <- arrayField sub "event_sigs"
    when (null sigs) $ Left (T.unpack key <> ": event_sigs is empty")
    _ <- note (key <> ".offsets missing") (lookupKey "offsets" sub)
    seeds <- note (key <> ".signer_seeds missing") (lookupKey "signer_seeds" sub)
    kQ <- textArrayField ked "k"
    nQ <- textArrayField ked "n"
    cur <- arrayField seeds "current"
    nxt <- arrayField seeds "next"
    unless (length cur == length kQ) $
        Left (T.unpack key <> ": current seed count /= ked.k count")
    unless (length nxt == length nQ) $
        Left (T.unpack key <> ": next seed count /= ked.n count")

-- | The parent-acceptance witnessed shape: 3 witnesses, toad 2.
checkWitnessedShape :: Value -> Either String ()
checkWitnessedShape fx = do
    ked <- kedOf fx "reg_witnessed"
    wits <- textArrayField ked "b"
    unless (length wits == 3) $
        Left ("reg_witnessed: expected 3 witnesses, got " <> show (length wits))
    bt <- textField ked "bt"
    unless (bt == "2") $
        Left ("reg_witnessed: expected toad 2, got " <> T.unpack bt)

-- | E5 material: the weighted fixture's kt is a fraction-string array.
checkWeightedShape :: Value -> Either String ()
checkWeightedShape fx = do
    ked <- kedOf fx "reg_weighted"
    kt <- note "reg_weighted: kt missing" (lookupKey "kt" ked)
    case kt of
        Array _ -> Right ()
        _ -> Left "reg_weighted: kt is not a fractionally-weighted array"

{- | The true unwitnessed 2-key shape (A-003\/T114-S5a): 2 keys,
unweighted @kt@ 2, no witnesses, toad 0 — the S5 2-key measurement
subject.
-}
checkTwoKeyShape :: Value -> Either String ()
checkTwoKeyShape fx = do
    ked <- kedOf fx "reg_2key"
    ks <- textArrayField ked "k"
    unless (length ks == 2) $
        Left ("reg_2key: expected 2 keys, got " <> show (length ks))
    kt <- textField ked "kt"
    unless (kt == "2") $
        Left ("reg_2key: expected kt 2, got " <> T.unpack kt)
    wits <- textArrayField ked "b"
    unless (null wits) $
        Left ("reg_2key: expected no witnesses, got " <> show (length wits))
    bt <- textField ked "bt"
    unless (bt == "0") $
        Left ("reg_2key: expected toad 0, got " <> T.unpack bt)

{- | The unwitnessed GLEIF-shaped 7-key board (A-003\/T114-S5a): 7
fractionally-weighted keys, no witnesses — the S5 7-key measurement
subject; must fit the 1024-byte tier ('checkSize' enforces the size).
-}
checkSevenKeyShape :: Value -> Either String ()
checkSevenKeyShape fx = do
    ked <- kedOf fx "reg_7key"
    ks <- textArrayField ked "k"
    unless (length ks == 7) $
        Left ("reg_7key: expected 7 keys, got " <> show (length ks))
    kt <- note "reg_7key: kt missing" (lookupKey "kt" ked)
    case kt of
        Array xs ->
            unless (length xs == 7) $
                Left
                    ( "reg_7key: expected a 7-clause weighted kt, got "
                        <> show (length xs)
                    )
        _ -> Left "reg_7key: kt is not a fractionally-weighted array"
    wits <- textArrayField ked "b"
    unless (null wits) $
        Left ("reg_7key: expected no witnesses, got " <> show (length wits))
    bt <- textField ked "bt"
    unless (bt == "0") $
        Left ("reg_7key: expected toad 0, got " <> T.unpack bt)

-- | E1 material: the delegated events record which AID delegates them.
checkDelegated :: Value -> Text -> Either String ()
checkDelegated fx key = do
    sub <- subFixture fx key
    dp <- textField sub "delegator_pre"
    when (T.null dp) $ Left (T.unpack key <> ": delegator_pre is empty")

-- | H1 material: oversize breaches the one-chunk boundary, the rest fit.
checkSize :: Value -> RegFixture -> Either String ()
checkSize fx rf = do
    let key = rfKey rf
    ev <- eventOf fx key
    len <- intField ev "raw_len"
    if rfOversize rf
        then
            unless (len > 1024) $
                Left (T.unpack key <> ": raw_len " <> show len <> " is not > 1024")
        else
            unless (len <= 1024) $
                Left (T.unpack key <> ": raw_len " <> show len <> " exceeds 1024")

{- | E1-E9 oracle: the slice at each exported offset reproduces the ked
value bytes (unquoted string content; weighted thresholds as the full
compact-JSON array; element-wise with count parity for @k@\/@n@\/@b@).
-}
checkOffsets :: Value -> RegFixture -> Either String ()
checkOffsets fx rf = do
    let key = rfKey rf
    sub <- subFixture fx key
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    raw <- decodeHex =<< textField ev "raw_hex"
    ked <- note (key <> ".event.ked missing") (lookupKey "ked" ev)
    offs <- note (key <> ".offsets missing") (lookupKey "offsets" sub)
    forM_ (["t", "i", "s", "bt"] :: [Text]) $ \f -> do
        expected <- TE.encodeUtf8 <$> textField ked f
        off <- intField offs f
        sliceCheck (ctx key f) raw off expected
    forM_ (["kt", "nt"] :: [Text]) $ \f -> do
        v <- note (key <> ".event.ked." <> f <> " missing") (lookupKey f ked)
        expected <- respellThreshold f v
        off <- intField offs f
        sliceCheck (ctx key f) raw off expected
    forM_ (["k", "n", "b"] :: [Text]) $ \f -> do
        elems <- textArrayField ked f
        eoffs <- intArrayField offs f
        unless (length eoffs == length elems) $
            Left
                ( ctx key f
                    <> ": offset count "
                    <> show (length eoffs)
                    <> " /= ked element count "
                    <> show (length elems)
                )
        forM_ (zip3 [0 :: Int ..] eoffs elems) $ \(j, off, e) ->
            sliceCheck (ctx key f <> "[" <> show j <> "]") raw off (TE.encodeUtf8 e)
  where
    ctx key f = T.unpack key <> ".ked." <> T.unpack f

{- | The exported seeds derive the exported verkeys via real DSIGN keygen;
current verkeys are the event's own @k@; next verkeys digest into @n@.
-}
checkSeeds :: Value -> RegFixture -> Either String ()
checkSeeds fx rf = do
    let key = rfKey rf
    sub <- subFixture fx key
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    ked <- note (key <> ".event.ked missing") (lookupKey "ked" ev)
    seeds <- note (key <> ".signer_seeds missing") (lookupKey "signer_seeds" sub)
    kQ <- textArrayField ked "k"
    nQ <- textArrayField ked "n"
    cur <- arrayField seeds "current"
    nxt <- arrayField seeds "next"
    unless (length cur == length kQ) $
        Left (T.unpack key <> ": current seed count /= ked.k count")
    unless (length nxt == length nQ) $
        Left (T.unpack key <> ": next seed count /= ked.n count")
    forM_ (zip3 [0 :: Int ..] cur kQ) $ \(j, entry, kq) -> do
        let at = T.unpack key <> ".signer_seeds.current[" <> show j <> "]"
        (seedRaw, vkQ) <- seedEntry at entry
        unless (vkQ == kq) $
            Left (at <> ": verkey_qb64 does not match ked.k")
        vkRaw <- verkeyRaw vkQ
        unless (deriveVerkey seedRaw == vkRaw) $
            Left (at <> ": seed does not derive the exported verkey")
    forM_ (zip3 [0 :: Int ..] nxt nQ) $ \(j, entry, nq) -> do
        let at = T.unpack key <> ".signer_seeds.next[" <> show j <> "]"
        (seedRaw, vkQ) <- seedEntry at entry
        vkRaw <- verkeyRaw vkQ
        unless (deriveVerkey seedRaw == vkRaw) $
            Left (at <> ": seed does not derive the exported verkey")
        nDig <- digestRaw nq
        unless (blake3Hash (qb64Verkey vkRaw) == nDig) $
            Left (at <> ": derived verkey does not digest into ked.n")

{- | O1 for the registration family: every committed signature verifies
over @event_raw@ and not over the SAID.
-}
checkSigs :: Value -> RegFixture -> Either String ()
checkSigs fx rf = do
    let key = rfKey rf
    sub <- subFixture fx key
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    raw <- decodeHex =<< textField ev "raw_hex"
    saidBytes <- TE.encodeUtf8 <$> textField ev "said"
    sigs <- arrayField sub "event_sigs"
    when (null sigs) $ Left (T.unpack key <> ": event_sigs is empty")
    forM_ (zip [0 :: Int ..] sigs) $ \(j, sv) -> do
        let at = T.unpack key <> ".event_sigs[" <> show j <> "]"
        target <- textField sv "signing_target"
        unless (target == "event_raw") $
            Left (at <> ": signing_target /= event_raw")
        vk <- verkeyRaw =<< textField sv "signer_verkey_qb64"
        sigBytes <- decodeHex =<< textField sv "sig_hex"
        unless (verifyEd25519 vk raw sigBytes) $
            Left (at <> ": does not verify over event_raw")
        when (verifyEd25519 vk saidBytes sigBytes) $
            Left (at <> ": unexpectedly verifies over the SAID")

-- ---------------------------------------------------------------------------
-- Drilling and derivation helpers
-- ---------------------------------------------------------------------------

subFixture :: Value -> Text -> Either String Value
subFixture fx key = note (key <> " missing from registration.json") (lookupKey key fx)

eventOf :: Value -> Text -> Either String Value
eventOf fx key = do
    sub <- subFixture fx key
    note (key <> ".event missing") (lookupKey "event" sub)

kedOf :: Value -> Text -> Either String Value
kedOf fx key = do
    ev <- eventOf fx key
    note (key <> ".event.ked missing") (lookupKey "ked" ev)

-- | A seed-export entry: 32-byte hex seed + its qb64 verkey.
seedEntry :: String -> Value -> Either String (ByteString, Text)
seedEntry at entry = do
    seedRaw <- decodeHex =<< textField entry "seed_hex"
    unless (BS.length seedRaw == 32) $ Left (at <> ": seed is not 32 bytes")
    vkQ <- textField entry "verkey_qb64"
    pure (seedRaw, vkQ)

-- | Ed25519 verkey raw bytes derived from a 32-byte seed via real DSIGN.
deriveVerkey :: ByteString -> ByteString
deriveVerkey seed =
    rawSerialiseVerKeyDSIGN
        (deriveVerKeyDSIGN (genKeyDSIGN (mkSeedFromBytes seed) :: SignKeyDSIGN Ed25519DSIGN))

{- | The generator's threshold re-spelling: a hex string verbatim, a
weighted threshold as the full compact-JSON fraction-string array.
-}
respellThreshold :: Text -> Value -> Either String ByteString
respellThreshold f v = case v of
    String t -> Right (TE.encodeUtf8 t)
    Array xs -> do
        parts <- traverse asText (toList xs)
        Right ("[" <> BS.intercalate "," (map quoted parts) <> "]")
    _ -> Left (T.unpack f <> ": threshold is neither a string nor an array")
  where
    asText (String t) = Right t
    asText _ = Left (T.unpack f <> ": weighted threshold element is not a string")
    quoted t = "\"" <> TE.encodeUtf8 t <> "\""

-- | The slice of @raw@ at @off@ (value-content offset) equals @expected@.
sliceCheck :: String -> ByteString -> Integer -> ByteString -> Either String ()
sliceCheck what raw off expected = do
    let o = fromIntegral off
        n = BS.length expected
    when (off < 0 || o + n > BS.length raw) $
        Left (what <> ": offset " <> show off <> " out of bounds")
    unless (BS.take n (BS.drop o raw) == expected) $
        Left (what <> ": slice at " <> show off <> " does not reproduce the ked bytes")
