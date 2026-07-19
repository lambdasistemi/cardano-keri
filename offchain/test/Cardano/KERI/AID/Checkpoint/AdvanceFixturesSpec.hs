{- |
Module      : Cardano.KERI.AID.Checkpoint.AdvanceFixturesSpec
Description : Ground-truth checks for the #115 witness-rotation fixtures

Hermetic checks over the committed @advance.json@ keripy bundle.  The tests
derive the incoming witness set from the inception's @b@ and rotation's
@br@/@ba@ fields, then prove controller signatures and incoming-set witness
receipts cover the exact event bytes.
-}
module Cardano.KERI.AID.Checkpoint.AdvanceFixturesSpec (spec) where

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
import Data.Char (isDigit)
import Data.Foldable (toList)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (Spec, beforeAll, describe, it, shouldBe)

data AdvanceFixture = AdvanceFixture
    { afKey :: Text
    , afIcpKeys :: Int
    , afRotKeys :: Int
    , afOldWitnesses :: Int
    , afCuts :: Int
    , afAdds :: Int
    , afToad :: Text
    , afReceipts :: Int
    }

advanceFixtures :: [AdvanceFixture]
advanceFixtures =
    [ AdvanceFixture "adv_wit_2key" 2 2 3 1 1 "2" 2
    , AdvanceFixture "adv_wit_7key" 7 3 3 1 1 "2" 2
    , AdvanceFixture "adv_downgrade" 2 2 3 3 0 "0" 0
    , AdvanceFixture "adv_keep" 2 2 3 0 0 "2" 2
    ]

spec :: Spec
spec =
    describe "AdvanceFixtures - #115 S1 keripy witness rotations" $
        beforeAll (loadFixture "advance.json") $ do
            describe "family completeness and event shapes" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkShape fx cfg `shouldBe` Right ()
            describe "raw_len is ground truth for both events" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkRawLengths fx cfg `shouldBe` Right ()
            describe "rotation offsets reproduce t/i/s/k/kt/n/nt/p/br/ba/bt" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkOffsets fx cfg `shouldBe` Right ()
            describe "controller and witness seeds derive the exported keys" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkSeeds fx cfg `shouldBe` Right ()
            describe "controller signatures cover exact event raw bytes" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkControllerSignatures fx cfg `shouldBe` Right ()
            describe "witness receipts cover raw bytes at incoming-set indices" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkWitnessReceipts fx cfg `shouldBe` Right ()
            it "adv_downgrade cuts every witness, sets bt=0, and has zero receipts" $ \fx ->
                checkDowngrade fx `shouldBe` Right ()

checkShape :: Value -> AdvanceFixture -> Either String ()
checkShape fx cfg = do
    sub <- subFixture fx cfg
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    textField icpKed "t" >>= expectEqual "icp.ked.t" "icp"
    textField rotKed "t" >>= expectEqual "rot.ked.t" "rot"
    icpSaid <- textField icp "said"
    textField rotKed "p" >>= expectEqual "rot.ked.p" icpSaid
    expectCount "icp.ked.k" (afIcpKeys cfg) =<< textArrayField icpKed "k"
    expectCount "rot.ked.k" (afRotKeys cfg) =<< textArrayField rotKed "k"
    old <- textArrayField icpKed "b"
    cuts <- textArrayField rotKed "br"
    adds <- textArrayField rotKed "ba"
    expectCount "icp.ked.b" (afOldWitnesses cfg) old
    textField icpKed "bt" >>= expectEqual "icp.ked.bt" "2"
    expectCount "rot.ked.br" (afCuts cfg) cuts
    expectCount "rot.ked.ba" (afAdds cfg) adds
    textField rotKed "bt" >>= expectEqual "rot.ked.bt" (afToad cfg)
    when (afKey cfg == "adv_wit_2key") $
        unless (cuts == take 1 old) $
            Left "adv_wit_2key: rot.ked.br does not cut witness 0"
    incoming <- deriveIncoming old cuts adds
    let toad = readHex (afToad cfg)
    unless ((toad == 0 && null incoming) || (toad > 0 && toad <= length incoming)) $
        Left (at cfg <> ": bt is not valid for the derived incoming witness set")
    when (afKey cfg == "adv_wit_7key") $ do
        expectWeighted "icp.ked.kt" 7 =<< field icpKed "kt"
        expectWeighted "rot.ked.kt" 3 =<< field rotKed "kt"
        expectCount "icp.ked.n" 7 =<< textArrayField icpKed "n"
        expectCount "rot.ked.n" 7 =<< textArrayField rotKed "n"
    when (afKey cfg /= "adv_wit_7key") $ do
        textField icpKed "kt" >>= expectEqual "icp.ked.kt" "2"
        textField rotKed "kt" >>= expectEqual "rot.ked.kt" "2"

checkRawLengths :: Value -> AdvanceFixture -> Either String ()
checkRawLengths fx cfg = do
    sub <- subFixture fx cfg
    forM_ (["icp", "rot"] :: [Text]) $ \eventKey -> do
        ev <- eventOf sub eventKey
        raw <- decodeHex =<< textField ev "raw_hex"
        rawLen <- intField ev "raw_len"
        unless (fromIntegral rawLen == BS.length raw) $
            Left (at cfg <> "." <> T.unpack eventKey <> ": raw_len /= decoded raw_hex length")

checkOffsets :: Value -> AdvanceFixture -> Either String ()
checkOffsets fx cfg = do
    sub <- subFixture fx cfg
    rot <- eventOf sub "rot"
    raw <- decodeHex =<< textField rot "raw_hex"
    ked <- kedOf rot
    offsets <- field sub "offsets"
    forM_ (["t", "i", "s", "p", "bt"] :: [Text]) $ \key -> do
        expected <- TE.encodeUtf8 <$> textField ked key
        off <- intField offsets key
        sliceCheck (at cfg <> ".rot.ked." <> T.unpack key) raw off expected
    forM_ (["kt", "nt"] :: [Text]) $ \key -> do
        expected <- respellThreshold key =<< field ked key
        off <- intField offsets key
        sliceCheck (at cfg <> ".rot.ked." <> T.unpack key) raw off expected
    forM_ (["k", "n", "br", "ba"] :: [Text]) $ \key -> do
        expected <- textArrayField ked key
        offs <- intArrayField offsets key
        unless (length offs == length expected) $
            Left (at cfg <> ".rot.ked." <> T.unpack key <> ": offset count mismatch")
        forM_ (zip3 [0 :: Int ..] offs expected) $ \(j, off, item) ->
            sliceCheck
                (at cfg <> ".rot.ked." <> T.unpack key <> "[" <> show j <> "]")
                raw
                off
                (TE.encodeUtf8 item)

checkSeeds :: Value -> AdvanceFixture -> Either String ()
checkSeeds fx cfg = do
    sub <- subFixture fx cfg
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    seeds <- field sub "signer_seeds"
    checkSeedKeys seeds "inception_current" =<< textArrayField icpKed "k"
    rotKeys <- textArrayField rotKed "k"
    checkSeedKeys seeds "rotation_current" rotKeys
    checkNextSeeds seeds "rotation_next" =<< textArrayField rotKed "n"
    checkSeedKeys seeds "witness_outgoing" =<< textArrayField icpKed "b"
    checkSeedKeys seeds "witness_added" =<< textArrayField rotKed "ba"
    committed <- traverse digestRaw =<< textArrayField icpKed "n"
    forM_ rotKeys $ \key -> do
        raw <- verkeyRaw key
        unless (blake3Hash (qb64Verkey raw) `elem` committed) $
            Left (at cfg <> ": rotation current key is not committed by icp.ked.n")

checkControllerSignatures :: Value -> AdvanceFixture -> Either String ()
checkControllerSignatures fx cfg = do
    sub <- subFixture fx cfg
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    icpKeys <- textArrayField icpKed "k"
    rotKeys <- textArrayField rotKed "k"
    expectCount "icp_sigs" (length icpKeys) =<< arrayField sub "icp_sigs"
    expectCount "rot_sigs" (length rotKeys) =<< arrayField sub "rot_sigs"
    checkSignatures sub icp "icp_sigs" "controller" icpKeys
    checkSignatures sub rot "rot_sigs" "controller" rotKeys

checkWitnessReceipts :: Value -> AdvanceFixture -> Either String ()
checkWitnessReceipts fx cfg = do
    sub <- subFixture fx cfg
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    old <- textArrayField icpKed "b"
    cuts <- textArrayField rotKed "br"
    adds <- textArrayField rotKed "ba"
    incoming <- deriveIncoming old cuts adds
    receipts <- arrayField sub "rot_witness_receipts"
    expectCount "rot_witness_receipts" (afReceipts cfg) receipts
    checkSignatures sub rot "rot_witness_receipts" "witness" incoming

checkDowngrade :: Value -> Either String ()
checkDowngrade fx = do
    let cfg = AdvanceFixture "adv_downgrade" 2 2 3 3 0 "0" 0
    sub <- subFixture fx cfg
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    old <- textArrayField icpKed "b"
    rotKed <- kedOf rot
    cuts <- textArrayField rotKed "br"
    adds <- textArrayField rotKed "ba"
    unless (cuts == old) $ Left "adv_downgrade: br does not cut every outgoing witness in order"
    unless (null adds) $ Left "adv_downgrade: ba is not empty"
    textField rotKed "bt" >>= expectEqual "adv_downgrade.rot.ked.bt" "0"
    receipts <- arrayField sub "rot_witness_receipts"
    unless (null receipts) $ Left "adv_downgrade: receipts are not empty"

checkSeedKeys :: Value -> Text -> [Text] -> Either String ()
checkSeedKeys seeds group expected = do
    entries <- arrayField seeds group
    expectCount (T.unpack group) (length expected) entries
    forM_ (zip3 [0 :: Int ..] entries expected) $ \(j, entry, expectedKey) -> do
        (seed, exportedKey) <- seedEntry (T.unpack group <> "[" <> show j <> "]") entry
        unless (exportedKey == expectedKey) $
            Left (T.unpack group <> "[" <> show j <> "]: exported verkey mismatch")
        raw <- verkeyRaw exportedKey
        unless (deriveVerkey seed == raw) $
            Left (T.unpack group <> "[" <> show j <> "]: seed does not derive verkey")

checkNextSeeds :: Value -> Text -> [Text] -> Either String ()
checkNextSeeds seeds group expectedDigests = do
    entries <- arrayField seeds group
    expectCount (T.unpack group) (length expectedDigests) entries
    forM_ (zip3 [0 :: Int ..] entries expectedDigests) $ \(j, entry, expectedDigest) -> do
        (seed, exportedKey) <- seedEntry (T.unpack group <> "[" <> show j <> "]") entry
        raw <- verkeyRaw exportedKey
        unless (deriveVerkey seed == raw) $
            Left (T.unpack group <> "[" <> show j <> "]: seed does not derive verkey")
        digest <- digestRaw expectedDigest
        unless (blake3Hash (qb64Verkey raw) == digest) $
            Left (T.unpack group <> "[" <> show j <> "]: verkey does not digest into rot.ked.n")

checkSignatures :: Value -> Value -> Text -> Text -> [Text] -> Either String ()
checkSignatures sub event sigKey expectedKind indexedKeys = do
    raw <- decodeHex =<< textField event "raw_hex"
    said <- TE.encodeUtf8 <$> textField event "said"
    sigs <- arrayField sub sigKey
    indices <- traverse (intFieldAt "index") sigs
    unless (length indices == length (nub indices)) $
        Left (T.unpack sigKey <> ": duplicate signature indices")
    forM_ (zip [0 :: Int ..] sigs) $ \(j, sig) -> do
        let sigAt = T.unpack sigKey <> "[" <> show j <> "]"
        textField sig "kind" >>= expectEqual (sigAt <> ".kind") expectedKind
        textField sig "signing_target" >>= expectEqual (sigAt <> ".signing_target") "event_raw"
        index <- intField sig "index"
        when (index < 0 || fromIntegral index >= length indexedKeys) $
            Left (sigAt <> ": index is outside the indexed key set")
        signer <- textField sig "signer_verkey_qb64"
        unless (signer == indexedKeys !! fromIntegral index) $
            Left (sigAt <> ": signer does not identify its indexed key")
        keyRaw <- verkeyRaw signer
        sigRaw <- decodeHex =<< textField sig "sig_hex"
        unless (verifyEd25519 keyRaw raw sigRaw) $
            Left (sigAt <> ": signature does not verify over event raw")
        when (verifyEd25519 keyRaw said sigRaw) $
            Left (sigAt <> ": signature unexpectedly verifies over the SAID")

deriveIncoming :: [Text] -> [Text] -> [Text] -> Either String [Text]
deriveIncoming old cuts adds = do
    unless (length cuts == length (nub cuts) && all (`elem` old) cuts) $
        Left "invalid witness cuts"
    let survivors = filter (`notElem` cuts) old
    unless
        ( length adds == length (nub adds)
            && all (`notElem` cuts) adds
            && all (`notElem` survivors) adds
        )
        $ Left "invalid witness adds"
    pure (survivors <> adds)

subFixture :: Value -> AdvanceFixture -> Either String Value
subFixture fx cfg = note (afKey cfg <> " missing from advance.json") (lookupKey (afKey cfg) fx)

eventOf :: Value -> Text -> Either String Value
eventOf sub key = note (key <> " missing") (lookupKey key sub)

kedOf :: Value -> Either String Value
kedOf event = note "event.ked missing" (lookupKey "ked" event)

field :: Value -> Text -> Either String Value
field value key = note (key <> " missing") (lookupKey key value)

intFieldAt :: Text -> Value -> Either String Integer
intFieldAt = flip intField

seedEntry :: String -> Value -> Either String (ByteString, Text)
seedEntry entryAt entry = do
    seed <- decodeHex =<< textField entry "seed_hex"
    unless (BS.length seed == 32) $ Left (entryAt <> ": seed is not 32 bytes")
    key <- textField entry "verkey_qb64"
    pure (seed, key)

deriveVerkey :: ByteString -> ByteString
deriveVerkey seed =
    rawSerialiseVerKeyDSIGN
        (deriveVerKeyDSIGN (genKeyDSIGN (mkSeedFromBytes seed) :: SignKeyDSIGN Ed25519DSIGN))

respellThreshold :: Text -> Value -> Either String ByteString
respellThreshold key value = case value of
    String text -> Right (TE.encodeUtf8 text)
    Array values -> do
        parts <- traverse asText (toList values)
        Right ("[" <> BS.intercalate "," (map quoted parts) <> "]")
    _ -> Left (T.unpack key <> ": threshold is neither a string nor an array")
  where
    asText (String text) = Right text
    asText _ = Left (T.unpack key <> ": weighted threshold element is not a string")
    quoted text = "\"" <> TE.encodeUtf8 text <> "\""

sliceCheck :: String -> ByteString -> Integer -> ByteString -> Either String ()
sliceCheck sliceAt raw off expected = do
    let offset = fromIntegral off
        size = BS.length expected
    when (off < 0 || offset + size > BS.length raw) $
        Left (sliceAt <> ": offset out of bounds")
    unless (BS.take size (BS.drop offset raw) == expected) $
        Left (sliceAt <> ": slice does not reproduce ked bytes")

expectEqual :: (Eq a, Show a) => String -> a -> a -> Either String ()
expectEqual label expected actual =
    unless (actual == expected) $ Left (label <> ": expected " <> show expected <> ", got " <> show actual)

expectCount :: String -> Int -> [a] -> Either String ()
expectCount label expected actual =
    unless (length actual == expected) $
        Left (label <> ": expected " <> show expected <> ", got " <> show (length actual))

expectWeighted :: String -> Int -> Value -> Either String ()
expectWeighted label expected = \case
    Array values -> expectCount label expected (toList values)
    _ -> Left (label <> ": expected a weighted threshold array")

readHex :: Text -> Int
readHex = T.foldl' (\acc c -> acc * 16 + hexDigit c) 0
  where
    hexDigit c
        | isDigit c = fromEnum c - fromEnum '0'
        | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
        | otherwise = error "fixture threshold is not lowercase hex"

at :: AdvanceFixture -> String
at = T.unpack . afKey
