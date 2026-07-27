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
import Data.List (nub, sort)
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
    , afNote :: Text
    }

{- | The exact label carried by the binding seven-valid worst-case row.  It is
quoted here verbatim so a renamed or re-noted row fails loudly rather than
silently inheriting the partial row's weaker claim.
-}
sevenValidNote :: Text
sevenValidNote =
    "GLEIF-root seven-valid-signature worst-case Advance with witness cut/add"

-- | The exact label carried by the supporting partial 3-of-7 row.
partialSevenNote :: Text
partialSevenNote = "GLEIF-root partial 3-of-7 reveal with witness cut/add"

advanceFixtures :: [AdvanceFixture]
advanceFixtures =
    [ AdvanceFixture
        "adv_wit_2key"
        2
        2
        3
        1
        1
        "2"
        2
        "2-key witnessed rotation cutting witness 0 and adding witness 3"
    , AdvanceFixture "adv_wit_7key" 7 3 3 1 1 "2" 2 partialSevenNote
    , AdvanceFixture "adv_wit_7key_full" 7 7 3 1 1 "2" 2 sevenValidNote
    , AdvanceFixture
        "adv_downgrade"
        2
        2
        3
        3
        0
        "0"
        0
        "all witnesses cut, bt=0, and zero receipts"
    , AdvanceFixture
        "adv_keep"
        2
        2
        3
        0
        0
        "2"
        2
        "no witness delta; threshold receipts from the unchanged set"
    ]

{- | The two GLEIF-root 7-key rows.  Both carry a weighted @1/3@-clause
threshold family; they differ in how many of the seven committed next keys the
rotation actually reveals.
-}
isGleifRootFamily :: AdvanceFixture -> Bool
isGleifRootFamily cfg = afIcpKeys cfg == 7

-- | The binding seven-valid worst-case row.
sevenValidKey :: Text
sevenValidKey = "adv_wit_7key_full"

-- | The supporting partial 3-of-7 row.
partialSevenKey :: Text
partialSevenKey = "adv_wit_7key"

spec :: Spec
spec =
    describe "Advance fixtures - #115 S1 keripy witness rotations" $
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
            describe "each row carries its exact committed label" $
                forM_ advanceFixtures $ \cfg ->
                    it (T.unpack (afKey cfg)) $ \fx ->
                        checkNote fx cfg `shouldBe` Right ()
            it "adv_downgrade cuts every witness, sets bt=0, and has zero receipts" $ \fx ->
                checkDowngrade fx `shouldBe` Right ()
            describe "adv_wit_7key_full is the honest seven-valid worst case" $ do
                it "reveals all seven committed next keys with seven valid controller signatures" $ \fx ->
                    checkSevenValidReveal fx `shouldBe` Right ()
                it "keeps the exact witness cut/add, toad, receipts, and SAID lineage" $ \fx ->
                    checkSevenValidWitnessing fx `shouldBe` Right ()
                it "carries deterministic seed material for every signer group" $ \fx ->
                    checkSevenValidSeeds fx `shouldBe` Right ()
                it "is substantively distinct from the partial 3-of-7 adv_wit_7key row" $ \fx ->
                    checkSevenValidDistinctness fx `shouldBe` Right ()

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
    if isGleifRootFamily cfg
        then do
            expectWeighted "icp.ked.kt" 7 =<< field icpKed "kt"
            expectWeighted "rot.ked.kt" (afRotKeys cfg) =<< field rotKed "kt"
            expectCount "icp.ked.n" 7 =<< textArrayField icpKed "n"
            expectCount "rot.ked.n" 7 =<< textArrayField rotKed "n"
        else do
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
    let cfg =
            AdvanceFixture
                "adv_downgrade"
                2
                2
                3
                3
                0
                "0"
                0
                "all witnesses cut, bt=0, and zero receipts"
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

{- | Every row states its own label.  The binding seven-valid row and the
supporting partial row must never share or swap labels, so the stronger
worst-case claim cannot silently migrate onto the weaker measurement.
-}
checkNote :: Value -> AdvanceFixture -> Either String ()
checkNote fx cfg = do
    sub <- subFixture fx cfg
    textField sub "note" >>= expectEqual (at cfg <> ".note") (afNote cfg)

{- | The binding row's controller side: seven committed next keys, all seven
revealed as rotation current keys, and seven indexed controller signatures
that verify over the exact rotation raw event bytes.
-}
checkSevenValidReveal :: Value -> Either String ()
checkSevenValidReveal fx = do
    sub <- sevenValidRow fx
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    icpKeys <- textArrayField icpKed "k"
    expectCount "adv_wit_7key_full.icp.ked.k" 7 icpKeys
    expectWeighted "adv_wit_7key_full.icp.ked.kt" 7 =<< field icpKed "kt"
    expectWeighted "adv_wit_7key_full.icp.ked.nt" 7 =<< field icpKed "nt"
    committedTexts <- textArrayField icpKed "n"
    expectCount "adv_wit_7key_full.icp.ked.n" 7 committedTexts
    committed <- traverse digestRaw committedTexts
    rotKeys <- textArrayField rotKed "k"
    expectCount "adv_wit_7key_full.rot.ked.k" 7 rotKeys
    expectWeighted "adv_wit_7key_full.rot.ked.kt" 7 =<< field rotKed "kt"
    expectWeighted "adv_wit_7key_full.rot.ked.nt" 7 =<< field rotKed "nt"
    expectCount "adv_wit_7key_full.rot.ked.n" 7 =<< textArrayField rotKed "n"
    unless (length (nub rotKeys) == 7) $
        Left "adv_wit_7key_full: rotation current keys are not seven distinct keys"
    revealed <-
        traverse (fmap (blake3Hash . qb64Verkey) . verkeyRaw) rotKeys
    unless (sort revealed == sort committed) $
        Left
            ( "adv_wit_7key_full: the rotation does not reveal exactly the "
                <> "seven keys committed by icp.ked.n"
            )
    -- Seven indexed controller signatures, one per revealed current key,
    -- each over the exact rotation raw bytes and never over the SAID.
    rotRaw <- decodeHex =<< textField rot "raw_hex"
    rotSaid <- TE.encodeUtf8 <$> textField rot "said"
    sigs <- arrayField sub "rot_sigs"
    expectCount "adv_wit_7key_full.rot_sigs" 7 sigs
    indices <- traverse (intFieldAt "index") sigs
    unless (sort indices == [0 .. 6]) $
        Left "adv_wit_7key_full.rot_sigs: indices are not exactly 0..6"
    forM_ (zip [0 :: Int ..] sigs) $ \(j, sig) -> do
        let sigAt = "adv_wit_7key_full.rot_sigs[" <> show j <> "]"
        textField sig "kind" >>= expectEqual (sigAt <> ".kind") "controller"
        textField sig "signing_target"
            >>= expectEqual (sigAt <> ".signing_target") "event_raw"
        index <- intField sig "index"
        signer <- textField sig "signer_verkey_qb64"
        unless (signer == rotKeys !! fromIntegral index) $
            Left (sigAt <> ": signer does not identify its indexed current key")
        keyRaw <- verkeyRaw signer
        sigRaw <- decodeHex =<< textField sig "sig_hex"
        unless (verifyEd25519 keyRaw rotRaw sigRaw) $
            Left (sigAt <> ": signature does not verify over the exact rot raw bytes")
        when (verifyEd25519 keyRaw rotSaid sigRaw) $
            Left (sigAt <> ": signature unexpectedly verifies over the SAID")
    -- The inception side stays fully signed too.
    expectCount "adv_wit_7key_full.icp_sigs" 7 =<< arrayField sub "icp_sigs"

{- | The binding row's witnessing side: the exact one-cut/one-add delta over a
three-witness inception, an unchanged toad, two incoming-indexed receipts over
the exact rotation raw bytes, and the icp -> rot SAID chain.
-}
checkSevenValidWitnessing :: Value -> Either String ()
checkSevenValidWitnessing fx = do
    sub <- sevenValidRow fx
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    textField icpKed "t" >>= expectEqual "adv_wit_7key_full.icp.ked.t" "icp"
    textField rotKed "t" >>= expectEqual "adv_wit_7key_full.rot.ked.t" "rot"
    textField icpKed "s" >>= expectEqual "adv_wit_7key_full.icp.ked.s" "0"
    textField rotKed "s" >>= expectEqual "adv_wit_7key_full.rot.ked.s" "1"
    -- SAID lineage: the rotation's prior digest is the inception's SAID, and
    -- each event's SAID occurs verbatim in its own raw serialization.
    icpSaid <- textField icp "said"
    textField rotKed "p" >>= expectEqual "adv_wit_7key_full.rot.ked.p" icpSaid
    forM_ ([("icp", icp), ("rot", rot)] :: [(String, Value)]) $ \(name, ev) -> do
        raw <- decodeHex =<< textField ev "raw_hex"
        said <- TE.encodeUtf8 <$> textField ev "said"
        unless (said `BS.isInfixOf` raw) $
            Left ("adv_wit_7key_full." <> name <> ": SAID is absent from its raw event")
    old <- textArrayField icpKed "b"
    cuts <- textArrayField rotKed "br"
    adds <- textArrayField rotKed "ba"
    expectCount "adv_wit_7key_full.icp.ked.b" 3 old
    expectCount "adv_wit_7key_full.rot.ked.br" 1 cuts
    expectCount "adv_wit_7key_full.rot.ked.ba" 1 adds
    unless (cuts == take 1 old) $
        Left "adv_wit_7key_full: rot.ked.br does not cut witness 0"
    textField icpKed "bt" >>= expectEqual "adv_wit_7key_full.icp.ked.bt" "2"
    textField rotKed "bt" >>= expectEqual "adv_wit_7key_full.rot.ked.bt" "2"
    incoming <- deriveIncoming old cuts adds
    expectCount "adv_wit_7key_full incoming witness set" 3 incoming
    receipts <- arrayField sub "rot_witness_receipts"
    expectCount "adv_wit_7key_full.rot_witness_receipts" 2 receipts
    receiptIndices <- traverse (intFieldAt "index") receipts
    unless (sort receiptIndices == [0, 2]) $
        Left
            ( "adv_wit_7key_full.rot_witness_receipts: indices are not the "
                <> "incoming survivor/add pair [0,2]"
            )
    checkSignatures sub rot "rot_witness_receipts" "witness" incoming

{- | Deterministic generator provenance: every signer group exports a 32-byte
seed that derives its published verkey, and the seven next-key seeds digest
into the rotation's own next-key commitments.
-}
checkSevenValidSeeds :: Value -> Either String ()
checkSevenValidSeeds fx = do
    sub <- sevenValidRow fx
    icp <- eventOf sub "icp"
    rot <- eventOf sub "rot"
    icpKed <- kedOf icp
    rotKed <- kedOf rot
    seeds <- field sub "signer_seeds"
    checkSeedKeys seeds "inception_current" =<< textArrayField icpKed "k"
    checkSeedKeys seeds "rotation_current" =<< textArrayField rotKed "k"
    checkNextSeeds seeds "rotation_next" =<< textArrayField rotKed "n"
    checkSeedKeys seeds "witness_outgoing" =<< textArrayField icpKed "b"
    checkSeedKeys seeds "witness_added" =<< textArrayField rotKed "ba"

{- | The binding row must be a genuinely different rotation, not a relabelled
copy of the supporting partial row.  Both rows are required to exist, to keep
their own labels and reveal counts, and to differ in raw event bytes, SAID,
and revealed current-key set.  A row that differed only by a missing key would
not answer the worst-case question A-028 asks.
-}
checkSevenValidDistinctness :: Value -> Either String ()
checkSevenValidDistinctness fx = do
    full <- sevenValidRow fx
    partial <-
        note (partialSevenKey <> " missing from advance.json") (lookupKey partialSevenKey fx)
    textField full "note" >>= expectEqual "adv_wit_7key_full.note" sevenValidNote
    textField partial "note" >>= expectEqual "adv_wit_7key.note" partialSevenNote
    fullRot <- eventOf full "rot"
    partialRot <- eventOf partial "rot"
    fullCurrent <- kedTextArray fullRot "k"
    partialCurrent <- kedTextArray partialRot "k"
    expectCount "adv_wit_7key_full.rot.ked.k" 7 fullCurrent
    expectCount "adv_wit_7key.rot.ked.k" 3 partialCurrent
    expectCount "adv_wit_7key_full.rot_sigs" 7 =<< arrayField full "rot_sigs"
    expectCount "adv_wit_7key.rot_sigs" 3 =<< arrayField partial "rot_sigs"
    fullRaw <- textField fullRot "raw_hex"
    partialRaw <- textField partialRot "raw_hex"
    unless (fullRaw /= partialRaw) $
        Left "adv_wit_7key_full: rotation raw bytes are identical to the partial row"
    fullSaid <- textField fullRot "said"
    partialSaid <- textField partialRot "said"
    unless (fullSaid /= partialSaid) $
        Left "adv_wit_7key_full: rotation SAID is identical to the partial row"
    unless (fullCurrent /= partialCurrent) $
        Left "adv_wit_7key_full: revealed current-key set is identical to the partial row"
    -- The partial row reveals three of the seven committed keys; the binding
    -- row reveals all seven, so it must add exactly four further reveals.
    unless (length fullCurrent - length partialCurrent == 4) $
        Left
            ( "adv_wit_7key_full: does not add exactly the four further reveals "
                <> "that turn the partial 3-of-7 row into the seven-valid worst case"
            )

sevenValidRow :: Value -> Either String Value
sevenValidRow fx =
    note (sevenValidKey <> " missing from advance.json") (lookupKey sevenValidKey fx)

-- | Read a text array out of an event's @ked@.
kedTextArray :: Value -> Text -> Either String [Text]
kedTextArray event key = kedOf event >>= \ked -> textArrayField ked key

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
