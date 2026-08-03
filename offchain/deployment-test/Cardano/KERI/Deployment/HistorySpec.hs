{- |
Module      : Cardano.KERI.Deployment.HistorySpec
Description : #220 Slice 1 oracle for witnessed key-history judgment

Fixtures here are genuine KERI\/CESR bytes: real @KERI10JSON@ framing, real
Blake3 self-addressing digests over the exact blanked-and-refilled event
bytes, and real CESR indexed-signature attachment groups (the same
2-character-code \"small variant\" encoding
'Cardano.KERI.Deployment.KEL' consumes for real keripy exports), built with
deterministic Ed25519 keys and genuine signatures — not a synthetic
stand-in wire format.
-}
module Cardano.KERI.Deployment.HistorySpec (spec) where

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
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.Deployment.History (
    ChainComparison (..),
    CoverageMode (..),
    DuplicityFinding (..),
    EstablishmentState (..),
    ExitClass (..),
    SampleFailure (..),
    Verdict (..),
    VerifiedHistory,
    covFull,
    exitCode,
    judgeVerdict,
    verifyHistory,
    vhHead,
 )
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Numeric (showHex)
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------
-- Deterministic key material
-- ---------------------------------------------------------

seedKey :: Word -> SignKeyDSIGN Ed25519DSIGN
seedKey tag =
    genKeyDSIGN (mkSeedFromBytes (BS.cons (fromIntegral tag) (BS.replicate 31 0x00)))

pubOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
pubOf sk = rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN sk)

signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver sk msg = rawSerialiseSigDSIGN (signDSIGN () msg sk)

qb64KeyText :: ByteString -> Text
qb64KeyText = TE.decodeUtf8 . qb64Verkey

qb64DigestText :: ByteString -> Text
qb64DigestText = TE.decodeUtf8 . qb64Aid

nextDigestOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
nextDigestOf = blake3Hash . qb64Verkey . pubOf

hexOf :: Integer -> Text
hexOf n = T.pack (showHex n "")

-- ---------------------------------------------------------
-- CESR indexed-signature encoding (inverse of the decode in History.hs /
-- KEL.hs: builds the genuine 2-char-code + 86-char "small variant" token)
-- ---------------------------------------------------------

decodeBase64Digit :: Word8 -> Either String Int
decodeBase64Digit byte
    | byte >= 0x41 && byte <= 0x5a = pure (fromIntegral byte - 0x41)
    | byte >= 0x61 && byte <= 0x7a = pure (fromIntegral byte - 0x61 + 26)
    | byte >= 0x30 && byte <= 0x39 = pure (fromIntegral byte - 0x30 + 52)
    | byte == 0x2d = pure 62
    | byte == 0x5f = pure 63
    | otherwise = Left "invalid base64 digit"

encodeBase64Digit :: Int -> Word8
encodeBase64Digit value
    | value >= 0 && value < 26 = fromIntegral value + 0x41
    | value < 52 = fromIntegral value - 26 + 0x61
    | value < 62 = fromIntegral value - 52 + 0x30
    | value == 62 = 0x2d
    | value == 63 = 0x5f
    | otherwise = error "invalid base64 digit value"

mustDecode :: Word8 -> Int
mustDecode byte = either error id (decodeBase64Digit byte)

{- | Encode one 64-byte Ed25519 signature at the given index into the
88-character CESR "small variant" indexed-signature token: exact inverse
of the decode this codebase already relies on for real keripy exports.
-}
encodeIndexedSignature :: Int -> ByteString -> ByteString
encodeIndexedSignature index sig =
    BS.cons 0x41 (BS.cons (encodeBase64Digit index) (BS.pack dataChars))
  where
    stdDigits = map mustDecode (BS.unpack (convertToBase Base64URLUnpadded sig))
    top4 0 = 0
    top4 i = stdDigits !! (i - 1) .&. 0xF
    encodedDigits =
        [ (top4 i `shiftL` 2) .|. (stdDigits !! i `shiftR` 4)
        | i <- [0 .. length stdDigits - 1]
        ]
    dataChars = map encodeBase64Digit encodedDigits

counter2 :: ByteString -> Int -> ByteString
counter2 code n = code <> BS.pack [encodeBase64Digit (n `div` 64), encodeBase64Digit (n `mod` 64)]

sigGroup :: ByteString -> [(Int, ByteString)] -> ByteString
sigGroup code sigs =
    counter2 code (length sigs) <> BS.concat [encodeIndexedSignature i s | (i, s) <- sigs]

attachmentSection :: [(Int, ByteString)] -> [(Int, ByteString)] -> ByteString
attachmentSection ctrlSigs witSigs =
    counter2 "-V" (BS.length body `div` 4) <> body
  where
    body = sigGroup "-A" ctrlSigs <> sigGroup "-B" witSigs

-- ---------------------------------------------------------
-- KERI10JSON message framing
-- ---------------------------------------------------------

placeholder44 :: Text
placeholder44 = T.replicate 44 "#"

{- | Wrap an inner object body (without the leading '{' or the version
field) into a complete, correctly self-sized @KERI10JSON@ message.
-}
frameMessage :: Text -> ByteString
frameMessage innerFields =
    let sized :: Int -> ByteString
        sized len =
            TE.encodeUtf8 $
                "{\"v\":\"KERI10JSON"
                    <> T.justifyRight 6 '0' (T.pack (showHex len ""))
                    <> "_\","
                    <> innerFields
     in sized (BS.length (sized 0))

buildFrame :: Text -> [(Int, ByteString)] -> [(Int, ByteString)] -> ByteString
buildFrame innerFields ctrlSigs witSigs =
    let message = frameMessage innerFields
     in message <> attachmentSection ctrlSigs witSigs

assembleStream :: [ByteString] -> ByteString
assembleStream = BS.concat

mustVerify :: ByteString -> VerifiedHistory
mustVerify stream = either error id (verifyHistory stream)

isRight' :: Either String a -> Bool
isRight' (Right _) = True
isRight' (Left _) = False

isFound :: DuplicityFinding -> Bool
isFound DuplicityNone = False
isFound (DuplicityFound _) = True

joinKeys :: [ByteString] -> Text
joinKeys keys = T.intercalate "," [T.concat ["\"", qb64KeyText k, "\""] | k <- keys]

joinDigests :: [ByteString] -> Text
joinDigests digests = T.intercalate "," [T.concat ["\"", qb64DigestText d, "\""] | d <- digests]

-- ---------------------------------------------------------
-- Chain-building scenario state
-- ---------------------------------------------------------

data ChainState = ChainState
    { csAidRaw :: !ByteString
    , csAidText :: !Text
    , csPriorRaw :: !ByteString
    , csSn :: !Integer
    , csCurKeys :: ![SignKeyDSIGN Ed25519DSIGN]
    , csCurThr :: !Integer
    , csNextKeys :: ![SignKeyDSIGN Ed25519DSIGN]
    , csNextThr :: !Integer
    , csWitnesses :: ![SignKeyDSIGN Ed25519DSIGN]
    , csToad :: !Integer
    }

mkIcp ::
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [Int] ->
    [Int] ->
    (ByteString, ChainState)
mkIcp curKeys curThr nextKeys nextThr witnesses toad signerIdxs witSignerIdxs =
    (buildFrame innerFinal ctrlSigs witSigs, state)
  where
    curPub = map pubOf curKeys
    nextDigests = map nextDigestOf nextKeys
    witPub = map pubOf witnesses
    innerPlaceholder =
        T.concat
            [ "\"t\":\"icp\",\"d\":\""
            , placeholder44
            , "\",\"i\":\""
            , placeholder44
            , "\",\"s\":\"0\",\"kt\":\""
            , hexOf curThr
            , "\",\"k\":["
            , joinKeys curPub
            , "],\"nt\":\""
            , hexOf nextThr
            , "\",\"n\":["
            , joinDigests nextDigests
            , "],\"bt\":\""
            , hexOf toad
            , "\",\"b\":["
            , joinKeys witPub
            , "]}"
            ]
    placeholderMessage = frameMessage innerPlaceholder
    aidRaw = blake3Hash placeholderMessage
    aidText = qb64DigestText aidRaw
    innerFinal =
        T.replace placeholder44 aidText innerPlaceholder
    finalMessage = frameMessage innerFinal
    ctrlSigs = [(i, signOver (curKeys !! i) finalMessage) | i <- signerIdxs]
    witSigs = [(i, signOver (witnesses !! i) finalMessage) | i <- witSignerIdxs]
    state =
        ChainState
            { csAidRaw = aidRaw
            , csAidText = aidText
            , csPriorRaw = aidRaw
            , csSn = 0
            , csCurKeys = curKeys
            , csCurThr = curThr
            , csNextKeys = nextKeys
            , csNextThr = nextThr
            , csWitnesses = witnesses
            , csToad = toad
            }

mkRot ::
    ChainState ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Integer ->
    [Int] ->
    [Int] ->
    (ByteString, ChainState)
mkRot state curKeys curThr nextKeys nextThr cuts adds toad signerIdxs witSignerIdxs =
    (buildFrame innerFinal ctrlSigs witSigs, state')
  where
    newSn = csSn state + 1
    curPub = map pubOf curKeys
    nextDigests = map nextDigestOf nextKeys
    cutsPub = map pubOf cuts
    addsPub = map pubOf adds
    innerPlaceholder =
        T.concat
            [ "\"t\":\"rot\",\"d\":\""
            , placeholder44
            , "\",\"i\":\""
            , csAidText state
            , "\",\"s\":\""
            , hexOf newSn
            , "\",\"p\":\""
            , qb64DigestText (csPriorRaw state)
            , "\",\"kt\":\""
            , hexOf curThr
            , "\",\"k\":["
            , joinKeys curPub
            , "],\"nt\":\""
            , hexOf nextThr
            , "\",\"n\":["
            , joinDigests nextDigests
            , "],\"bt\":\""
            , hexOf toad
            , "\",\"br\":["
            , joinKeys cutsPub
            , "],\"ba\":["
            , joinKeys addsPub
            , "]}"
            ]
    placeholderMessage = frameMessage innerPlaceholder
    digestRaw = blake3Hash placeholderMessage
    digestText = qb64DigestText digestRaw
    innerFinal = T.replace placeholder44 digestText innerPlaceholder
    finalMessage = frameMessage innerFinal
    ctrlSigs = [(i, signOver (curKeys !! i) finalMessage) | i <- signerIdxs]
    surviving = filter (\w -> pubOf w `notElem` cutsPub) (csWitnesses state)
    incoming = surviving <> adds
    witSigs = [(i, signOver (incoming !! i) finalMessage) | i <- witSignerIdxs]
    state' =
        state
            { csPriorRaw = digestRaw
            , csSn = newSn
            , csCurKeys = curKeys
            , csCurThr = curThr
            , csNextKeys = nextKeys
            , csNextThr = nextThr
            , csWitnesses = incoming
            , csToad = toad
            }

mkIxn :: ChainState -> [Int] -> [Int] -> (ByteString, ChainState)
mkIxn state signerIdxs witSignerIdxs =
    (buildFrame innerFinal ctrlSigs witSigs, state')
  where
    newSn = csSn state + 1
    innerPlaceholder =
        T.concat
            [ "\"t\":\"ixn\",\"d\":\""
            , placeholder44
            , "\",\"i\":\""
            , csAidText state
            , "\",\"s\":\""
            , hexOf newSn
            , "\",\"p\":\""
            , qb64DigestText (csPriorRaw state)
            , "\"}"
            ]
    placeholderMessage = frameMessage innerPlaceholder
    digestRaw = blake3Hash placeholderMessage
    digestText = qb64DigestText digestRaw
    innerFinal = T.replace placeholder44 digestText innerPlaceholder
    finalMessage = frameMessage innerFinal
    ctrlSigs = [(i, signOver (csCurKeys state !! i) finalMessage) | i <- signerIdxs]
    witSigs = [(i, signOver (csWitnesses state !! i) finalMessage) | i <- witSignerIdxs]
    state' = state{csPriorRaw = digestRaw, csSn = newSn}

-- Three witnesses, toad = 2, a single 1-of-1 controller key with one next
-- key committed — the spec's committed three-witness identity shape.
kCtrl0, kCtrl1, kWitA, kWitB, kWitC :: SignKeyDSIGN Ed25519DSIGN
kCtrl0 = seedKey 1
kCtrl1 = seedKey 2
kWitA = seedKey 10
kWitB = seedKey 11
kWitC = seedKey 12

genuineIcp :: (ByteString, ChainState)
genuineIcp = mkIcp [kCtrl0] 1 [kCtrl1] 1 [kWitA, kWitB, kWitC] 2 [0] [0, 1, 2]

genuineRot :: ChainState -> (ByteString, ChainState)
genuineRot st = mkRot st [kCtrl1] 1 [kCtrl0] 1 [] [] 2 [0] [0, 1, 2]

tamperMiddleByte :: ByteString -> ByteString
tamperMiddleByte bs =
    BS.take mid bs <> BS.singleton (BS.index bs mid + 1) <> BS.drop (mid + 1) bs
  where
    mid = BS.length bs `div` 2

spec :: Spec
spec = describe "#220 Slice 1" $ do
    describe "multi-event lineage verification" $ do
        it "verifies a genuine inception, rotation, and interaction lineage" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, st2) = genuineRot st1
                (ixnFrame, _st3) = mkIxn st2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame, ixnFrame]
                vh = mustVerify stream
                rotOnly = mustVerify (assembleStream [icpFrame, rotFrame])
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead rotOnly))
            -- The trailing ixn advances native lineage; the comparison head
            -- stays the rotation's establishment, so the checkpoint that
            -- matches the rotation is still exactly current.
            verdictComparison verdict `shouldBe` Just ChainCurrent
            verdictClass verdict `shouldBe` Affirmative

        it "verifies more than one rotation in sequence" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, st2) = genuineRot st1
                (rot2Frame, _st3) = mkRot st2 [kCtrl0] 1 [kCtrl1] 1 [] [] 2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame, rot2Frame]
            verifyHistory stream `shouldSatisfy` isRight'

        it "verifies a rotation and a second interaction following an ixn" $ do
            -- The establishment head does not advance on ixn, but native
            -- sequence continuity must still be checked against the latest
            -- event, not the (unchanged) head.
            let (icpFrame, st1) = genuineIcp
                (rotFrame, st2) = genuineRot st1
                (ixn1Frame, st3) = mkIxn st2 [0] [0, 1, 2]
                (ixn2Frame, _st4) = mkIxn st3 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame, ixn1Frame, ixn2Frame]
            verifyHistory stream `shouldSatisfy` isRight'

        it "verifies a rotation following an interaction" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, st2) = genuineRot st1
                (ixnFrame, st3) = mkIxn st2 [0] [0, 1, 2]
                (rot2Frame, _st4) = mkRot st3 [kCtrl0] 1 [kCtrl1] 1 [] [] 2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame, ixnFrame, rot2Frame]
            verifyHistory stream `shouldSatisfy` isRight'

        it "verifies a weighted (fractional) controller threshold" $ do
            let curKeys = [kCtrl0, kCtrl1]
                curPub = map pubOf curKeys
                nextDigests = [nextDigestOf kWitA]
                innerPlaceholder =
                    T.concat
                        [ "\"t\":\"icp\",\"d\":\""
                        , placeholder44
                        , "\",\"i\":\""
                        , placeholder44
                        , "\",\"s\":\"0\",\"kt\":[[\"1/2\",\"1/2\"]],\"k\":["
                        , joinKeys curPub
                        , "],\"nt\":\"1\",\"n\":["
                        , joinDigests nextDigests
                        , "],\"bt\":\"0\",\"b\":[]}"
                        ]
                placeholderMessage = frameMessage innerPlaceholder
                aidRaw = blake3Hash placeholderMessage
                aidText = qb64DigestText aidRaw
                innerFinal = T.replace placeholder44 aidText innerPlaceholder
                finalMessage = frameMessage innerFinal
                bothSigned = [(i, signOver (curKeys !! i) finalMessage) | i <- [0, 1]]
                onlyOneSigned = [(0, signOver kCtrl0 finalMessage)]
                streamComplete = assembleStream [finalMessage <> attachmentSection bothSigned []]
                streamPartial = assembleStream [finalMessage <> attachmentSection onlyOneSigned []]
            verifyHistory streamComplete `shouldSatisfy` isRight'
            verifyHistory streamPartial `shouldSatisfy` isLeft

        it "rejects a wrong AID on a later event" $ do
            let (icpFrame, st1) = genuineIcp
                bogusAid = blake3Hash "not the real AID"
                (rotFrame, _) = genuineRot st1{csAidText = qb64DigestText bogusAid}
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects a wrong prior digest" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _) = genuineRot st1{csPriorRaw = blake3Hash "not the real prior"}
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects a wrong native sequence" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _) = genuineRot st1{csSn = 5}
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects a bad next-key commitment" $ do
            let (icpFrame, st1) = genuineIcp
                -- Reveal an unrelated key instead of the committed next key.
                (rotFrame, _) = mkRot st1 [kWitA] 1 [kCtrl0] 1 [] [] 2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects under-signed controller signatures" $ do
            let (icpFrame, _) = mkIcp [kCtrl0, kCtrl1] 2 [kCtrl0] 1 [kWitA, kWitB, kWitC] 2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects an invalid witness delta" $ do
            let (icpFrame, st1) = genuineIcp
                -- Cut a witness that was never declared.
                (rotFrame, _) = mkRot st1 [kCtrl1] 1 [kCtrl0] 1 [kCtrl0] [] 2 [0] [0, 1]
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects a rotation adding a witness that is already surviving" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _) = mkRot st1 [kCtrl1] 1 [kCtrl0] 1 [] [kWitA] 2 [0] [0, 1, 2]
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects a rotation adding the same witness twice" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _) =
                    mkRot st1 [kCtrl1] 1 [kCtrl0] 1 [kWitA, kWitB, kWitC] [kWitA, kWitA] 2 [0] [0, 1]
                stream = assembleStream [icpFrame, rotFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects receipts below toad" $ do
            let (icpFrame, _) = mkIcp [kCtrl0] 1 [kCtrl1] 1 [kWitA, kWitB, kWitC] 2 [0] [0]
                stream = assembleStream [icpFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects an inception declaring a duplicate witness" $ do
            -- Declared witnesses [A, A, B], receipted only at indices
            -- [0, 1] — both of which resolve to A. Without the distinct-
            -- witness guard, A's own signature at two indices would
            -- satisfy toad = 2 by itself; the guard must reject before
            -- that receipt-inflation is ever reachable.
            let (icpFrame, _) = mkIcp [kCtrl0] 1 [kCtrl1] 1 [kWitA, kWitA, kWitB] 2 [0] [0, 1]
                stream = assembleStream [icpFrame]
            verifyHistory stream `shouldSatisfy` isLeft

        it "forged history is rejected (SAID control)" $ do
            let (icpFrame, _) = genuineIcp
                forged = tamperMiddleByte icpFrame
                stream = assembleStream [forged]
            verifyHistory stream `shouldSatisfy` isLeft

        it "forged history is rejected (signature control)" $ do
            -- SAID-self-consistent: the digest genuinely binds these exact
            -- bytes. Only the controller signature is wrong (signed by a
            -- key outside the declared current keys), so only the
            -- signature-threshold check can catch it.
            let curPub = [pubOf kCtrl0]
                nextDigests = [nextDigestOf kCtrl1]
                witPub = map pubOf [kWitA, kWitB, kWitC]
                innerPlaceholder =
                    T.concat
                        [ "\"t\":\"icp\",\"d\":\""
                        , placeholder44
                        , "\",\"i\":\""
                        , placeholder44
                        , "\",\"s\":\"0\",\"kt\":\"1\",\"k\":["
                        , joinKeys curPub
                        , "],\"nt\":\"1\",\"n\":["
                        , joinDigests nextDigests
                        , "],\"bt\":\"2\",\"b\":["
                        , joinKeys witPub
                        , "]}"
                        ]
                placeholderMessage = frameMessage innerPlaceholder
                aidRaw = blake3Hash placeholderMessage
                aidText = qb64DigestText aidRaw
                innerFinal = T.replace placeholder44 aidText innerPlaceholder
                finalMessage = frameMessage innerFinal
                wrongCtrlSigs = [(0, signOver kWitA finalMessage)]
                witSigs = [(i, signOver w finalMessage) | (i, w) <- zip [0 ..] [kWitA, kWitB, kWitC]]
                stream = assembleStream [finalMessage <> attachmentSection wrongCtrlSigs witSigs]
            verifyHistory stream `shouldSatisfy` isLeft

        it "truncated history is rejected" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _) = genuineRot st1
                stream = assembleStream [icpFrame, rotFrame]
                truncated = BS.take (BS.length stream - 20) stream
            verifyHistory stream `shouldSatisfy` isRight'
            verifyHistory truncated `shouldSatisfy` isLeft

        it "rejects trailing material after the last complete event" $ do
            let (icpFrame, _) = genuineIcp
                stream = assembleStream [icpFrame]
                withTrailingGarbage = stream <> BS.pack [0xde, 0xad, 0xbe, 0xef]
            verifyHistory stream `shouldSatisfy` isRight'
            verifyHistory withTrailingGarbage `shouldSatisfy` isLeft

        it "rejects an unsupported event type" $ do
            let (icpFrame, st1) = genuineIcp
                innerPlaceholder =
                    T.concat
                        [ "\"t\":\"drt\",\"d\":\""
                        , placeholder44
                        , "\",\"i\":\""
                        , csAidText st1
                        , "\",\"s\":\"1\",\"p\":\""
                        , qb64DigestText (csPriorRaw st1)
                        , "\"}"
                        ]
                placeholderMessage = frameMessage innerPlaceholder
                digestRaw = blake3Hash placeholderMessage
                innerFinal = T.replace placeholder44 (qb64DigestText digestRaw) innerPlaceholder
                finalMessage = frameMessage innerFinal
                sigs = [(0, signOver kCtrl0 finalMessage)]
                stream = assembleStream [icpFrame, finalMessage <> attachmentSection sigs []]
            verifyHistory stream `shouldSatisfy` isLeft

        it "rejects an interaction event with no witness receipts" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, st2) = genuineRot st1
                -- Sign the interaction with the controller key only; supply
                -- no witness receipts even though toad = 2 is in force.
                (ixnFrame, _) = mkIxn st2 [0] []
                stream = assembleStream [icpFrame, rotFrame, ixnFrame]
            verifyHistory stream `shouldSatisfy` isLeft

    describe "currency quorum and coverage" $ do
        it "3/3 witnesses is affirmative with unqualified duplicity none" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` Affirmative
            exitCode (verdictClass verdict) `shouldBe` 0
            verdictDuplicity verdict `shouldBe` DuplicityNone
            covFull (verdictCoverage verdict) `shouldBe` True

        it "2/3 remains current and rejects accidental unanimity" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitB, Right vh)
                    , (pubOf kWitC, Left Unreachable)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` Affirmative
            exitCode (verdictClass verdict) `shouldBe` 0
            covFull (verdictCoverage verdict) `shouldBe` False

        it "1/3 cannot answer currency" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitB, Left Unreachable)
                    , (pubOf kWitC, Left Unreachable)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` CannotAnswer
            exitCode (verdictClass verdict) `shouldBe` 2

        it "2/3 under require-full-coverage cannot answer" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitB, Right vh)
                    , (pubOf kWitC, Left Unreachable)
                    ]
                verdict = judgeVerdict 2 RequireFullCoverage declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` CannotAnswer
            exitCode (verdictClass verdict) `shouldBe` 2

        it "a witness answering twice does not satisfy quorum by itself" $ do
            -- Only one distinct witness ever answered; a sample-counting
            -- bug that fails to dedup by witness identity would otherwise
            -- see two entries and wrongly reach toad = 2.
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf kWitA, Right vh), (pubOf kWitA, Right vh)]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` CannotAnswer

        it "a duplicated witness sample does not inflate full coverage" $ do
            -- Two genuinely distinct witnesses (A, B) meet toad = 2 and the
            -- currency remains affirmative, but full coverage must stay
            -- false: C never answered, and A answering twice must not be
            -- double-counted toward the declared-witness universe.
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitA, Right vh)
                    , (pubOf kWitB, Right vh)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` Affirmative
            covFull (verdictCoverage verdict) `shouldBe` False

        it "a sample from an undeclared witness does not count" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitC, Right vh)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` CannotAnswer

        it "a rejected sample does not count toward quorum and reports cannot-answer" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vh)
                    , (pubOf kWitB, Left (RejectedHistory "forged"))
                    , (pubOf kWitC, Left MalformedReply)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictClass verdict `shouldBe` CannotAnswer
            exitCode (verdictClass verdict) `shouldBe` 2

    describe "chain comparison" $ do
        it "checkpoint exact match is current" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vh))
            verdictComparison verdict `shouldBe` Just ChainCurrent

        it "checkpoint matching a stale ancestor is negative" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _st2) = genuineRot st1
                stream = assembleStream [icpFrame, rotFrame]
                icpOnly = mustVerify (assembleStream [icpFrame])
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead icpOnly))
            verdictComparison verdict `shouldBe` Just ChainStale
            verdictClass verdict `shouldBe` Negative
            exitCode (verdictClass verdict) `shouldBe` 1

        it "checkpoint absent from quorum-agreed history is negative" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples Nothing
            verdictComparison verdict `shouldBe` Just ChainUnrecorded
            exitCode (verdictClass verdict) `shouldBe` 1

        it "checkpoint mismatch is negative" $ do
            let (icpFrame, st1) = genuineIcp
                (rotFrame, _st2) = genuineRot st1
                stream = assembleStream [icpFrame, rotFrame]
                vh = mustVerify stream
                (otherIcpFrame, _) = mkIcp [kWitA] 1 [kWitB] 1 [kWitA, kWitB, kWitC] 2 [0] [0, 1, 2]
                otherVh = mustVerify (assembleStream [otherIcpFrame])
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead otherVh))
            verdictComparison verdict `shouldBe` Just ChainMismatch
            exitCode (verdictClass verdict) `shouldBe` 1

        it "a checkpoint differing in exactly one field is a mismatch" $ do
            let (icpFrame, _st) = genuineIcp
                stream = assembleStream [icpFrame]
                vh = mustVerify stream
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples = [(pubOf w, Right vh) | w <- [kWitA, kWitB, kWitC]]
                differingCheckpoint = (vhHead vh){esToad = esToad (vhHead vh) + 1}
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just differingCheckpoint)
            verdictComparison verdict `shouldBe` Just ChainMismatch
            exitCode (verdictClass verdict) `shouldBe` 1

    describe "duplicity" $ do
        it "planted valid duplicity is detected" $ do
            let (icpFrame, st1) = genuineIcp
                (rotA, _) = genuineRot st1
                (rotB, _) = mkRot st1 [kCtrl1] 1 [kWitA] 1 [] [] 2 [0] [0, 1, 2]
                streamA = assembleStream [icpFrame, rotA]
                streamB = assembleStream [icpFrame, rotB]
                vhA = mustVerify streamA
                vhB = mustVerify streamB
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vhA)
                    , (pubOf kWitB, Right vhB)
                    , (pubOf kWitC, Left Unreachable)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vhA))
            verdictClass verdict `shouldBe` Negative
            exitCode (verdictClass verdict) `shouldBe` 1
            verdictDuplicity verdict `shouldSatisfy` isFound

        it "different AIDs at the same native sequence are not duplicity" $ do
            -- Two distinct, unrelated identities each at native sequence 0
            -- must never be reported as a fork of one another.
            let (icpFrameA, _) = genuineIcp
                (icpFrameB, _) = mkIcp [kWitA] 1 [kWitB] 1 [kWitA, kWitB, kWitC] 2 [0] [0, 1, 2]
                vhA = mustVerify (assembleStream [icpFrameA])
                vhB = mustVerify (assembleStream [icpFrameB])
                declared = map pubOf [kWitA, kWitB, kWitC]
                samples =
                    [ (pubOf kWitA, Right vhA)
                    , (pubOf kWitB, Right vhB)
                    , (pubOf kWitC, Left Unreachable)
                    ]
                verdict = judgeVerdict 2 QuorumOnly declared samples (Just (vhHead vhA))
            verdictDuplicity verdict `shouldBe` DuplicityNone

    describe "genuine keripy 1.3.5 export conformance" $ do
        it "verifies the committed real kli-export 2-of-5 rotation stream" $ do
            path <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
            bytes <- BS.readFile path
            case verifyHistory bytes of
                Left err -> fail err
                Right vh -> esCurThreshold (vhHead vh) `shouldBe` Unweighted 2
