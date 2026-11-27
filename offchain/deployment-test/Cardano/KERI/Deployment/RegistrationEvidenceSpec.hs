{- |
Module      : Cardano.KERI.Deployment.RegistrationEvidenceSpec
Description : The offset-free registration evidence, built from signed bytes alone

Three inceptions of an independent structural reference (a key-derived prefix
whose digest differs from its identifier, a self-addressing prefix with a
three-signature quorum, and the two-key positive) go through the production
builder, the hash-proof redeemers and the registration predicate. The controls
change one datum field, or the spelling of the sequence number, and require the
named refusal.
-}
module Cardano.KERI.Deployment.RegistrationEvidenceSpec (spec) where

import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (KeyStateView (..))
import Cardano.KERI.AID.Checkpoint.InceptionPrefix (PrefixKind (..))
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationError (..),
    RegistrationEvidence (..),
    proofTokenName,
    registrationPredicate,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    hashProofBurnData,
    hashProofMintData,
    registrationEvidenceData,
 )
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    parseInceptionExport,
 )
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (shiftR, (.&.))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

-- | One reference inception: signed bytes, signatures and the values the reference states.
data Reference = Reference
    { refId :: !Text
    , refEvent :: !ByteString
    , refCtrlSigs :: ![(Int, ByteString)]
    , refIdentifier :: !Text
    , refSaid :: !Text
    , refProofName :: !ByteString
    , refMint :: !(ByteString, ByteString)
    }

spec :: Spec
spec = describe "offset-free registration evidence" $ do
    describe "the reference inceptions through the production builder" $ do
        it "builds the three-field evidence, the proof name and the redeemers the reference states" $ do
            refs <- loadReferences
            mapM_ checkReference refs
        it "keeps the identifier and the event's own digest apart for a key-derived prefix" $ do
            refs <- loadReferences
            export <- exportOf (pick "I01" refs)
            inceptionKind export `shouldBe` BasicPrefix True
            BS.length (inceptionDigest export) `shouldBe` 32
            (cdCesrAid (inceptionDatum export) == inceptionDigest export) `shouldBe` False
        it "binds a self-addressing prefix to the digest of its own event" $ do
            refs <- loadReferences
            export <- exportOf (pick "I02" refs)
            inceptionKind export `shouldBe` SelfAddressingPrefix
            cdCesrAid (inceptionDatum export) `shouldBe` inceptionDigest export
        it "accepts each reference inception under the registration predicate" $ do
            refs <- loadReferences
            mapM_
                ( \r -> do
                    export <- exportOf r
                    registrationPredicate
                        context
                        (inceptionDatum export)
                        1_007_000_000
                        (inceptionEvidence export)
                        `shouldBe` Right ()
                )
                refs
    describe "a datum that disagrees with the signed bytes in one field is refused by name" $ do
        let refused name what mutate expected =
                it (name <> ": " <> what) $ do
                    refs <- loadReferences
                    export <- exportOf (pick (T.pack name) refs)
                    registrationPredicate
                        context
                        (mutate (inceptionDatum export))
                        1_007_000_000
                        (inceptionEvidence export)
                        `shouldBe` Left expected
        refused "pos_2key" "identifier" (\d -> d{cdCesrAid = BS.map (+ 1) (cdCesrAid d)}) E2AidMismatch
        refused "pos_2key" "current keys" (\d -> d{cdCurKeys = reverse (cdCurKeys d)}) E4CurKeysMismatch
        refused "pos_2key" "current threshold" (\d -> d{cdCurThreshold = other (cdCurThreshold d)}) E5CurThresholdMismatch
        refused "pos_2key" "next keys" (\d -> d{cdNextKeys = map (BS.map (+ 1)) (cdNextKeys d)}) E6NextKeysMismatch
        refused "pos_2key" "next threshold" (\d -> d{cdNextThreshold = other (cdNextThreshold d)}) E7NextThresholdMismatch
        refused "pos_2key" "witnesses" (\d -> d{cdWitnesses = [BS.replicate 32 7]}) E8WitnessesMismatch
        refused "pos_2key" "witness threshold" (\d -> d{cdToad = 1}) E9ToadMismatch
    describe "the sequence number is the canonical spelling" $ do
        -- a key-derived prefix is not a digest of the body, so the spelling is the only difference
        let spelled replacement =
                it ("s = " <> show replacement <> " is refused as a sequence mismatch") $ do
                    refs <- loadReferences
                    let r = pick "I01" refs
                    export <- exportOf r
                    let evidence =
                            (inceptionEvidence export)
                                { reEventBytes = respell (refEvent r) "\"s\":\"0\"" ("\"s\":\"" <> replacement <> "\"")
                                }
                    registrationPredicate
                        context
                        (inceptionDatum export)
                        1_007_000_000
                        evidence
                        `shouldBe` Left E3SequenceMismatch
        mapM_ spelled ["00", "0x0", "", "1", "A"]
        it "a respelled body of a self-addressing prefix is refused earlier, as not derived" $ do
            refs <- loadReferences
            let r = pick "pos_2key" refs
            export <- exportOf r
            registrationPredicate
                context
                (inceptionDatum export)
                1_007_000_000
                (inceptionEvidence export){reEventBytes = respell (refEvent r) "\"s\":\"0\"" "\"s\":\"00\""}
                `shouldBe` Left E2AidMismatch
  where
    context = DeploymentContext{dcMinAda = 2_000_000, dcDReg = 1_000_000_000}
    other (Unweighted n) = Unweighted (n + 1)
    other t = t

checkReference :: Reference -> IO ()
checkReference r = do
    export <- exportOf r
    let evidence = inceptionEvidence export
        datum = inceptionDatum export
    reEventBytes evidence `shouldBe` refEvent r
    reCtrlSigs evidence `shouldBe` refCtrlSigs r
    reWitReceipts evidence `shouldBe` []
    inceptionAid export `shouldBe` refIdentifier r
    qb64Aid (inceptionDigest export) `shouldBe` TE.encodeUtf8 (refSaid r)
    proofTokenName (reEventBytes evidence) (cdCesrAid datum) `shouldBe` refProofName r
    hashProofMintData (reEventBytes evidence) (cdCesrAid datum)
        `shouldBe` Constr 0 [B (fst (refMint r)), B (snd (refMint r))]
    hashProofBurnData `shouldBe` Constr 0 [B "", B ""]
    registrationEvidenceData evidence
        `shouldBe` Constr
            0
            [ B (refEvent r)
            , List [List [I (fromIntegral i), B s] | (i, s) <- refCtrlSigs r]
            , List []
            ]

exportOf :: Reference -> IO InceptionExport
exportOf r =
    either (\e -> expectationFailure e >> fail e) pure $
        parseInceptionExport (streamOf (refEvent r) (refCtrlSigs r))

pick :: Text -> [Reference] -> Reference
pick name refs = case filter ((== name) . refId) refs of
    [r] -> r
    _ -> error ("reference " <> T.unpack name <> " is not in the fixture exactly once")

loadReferences :: IO [Reference]
loadReferences = do
    path <- getDataFileName "test/keri-fixtures/fixtures/registration_reference.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        cases <- field "cases" top >>= array
        traverse one cases
  where
    one c = do
        i <- field "id" c >>= text
        event <- field "event_hex" c >>= text >>= hex
        sigs <- field "ctrl_sigs" c >>= array >>= traverse sigOf
        ident <- field "identifier" c >>= text
        said <- field "said" c >>= text
        name <- field "proof_name" c >>= text >>= hex
        mint <- field "mint_fields" c >>= array >>= traverse (text >=> hex)
        case mint of
            [e, raw] -> Right (Reference i event sigs ident said name (e, raw))
            _ -> Left "mint redeemer is not two fields"
    sigOf p = do
        pair <- array p
        case pair of
            [Number n, String s] -> (,) (truncate n) <$> hex s
            _ -> Left "not an indexed signature"
    (>=>) f g x = f x >>= g

field :: Text -> Value -> Either String Value
field k v = case v of
    Object o | Just x <- KM.lookup (K.fromText k) o -> Right x
    _ -> Left (show k <> " missing")

array :: Value -> Either String [Value]
array (Array xs) = Right (toList xs)
array _ = Left "not an array"

text :: Value -> Either String Text
text (String t) = Right t
text _ = Left "not a string"

hex :: Text -> Either String ByteString
hex = convertFromBase Base16 . TE.encodeUtf8

{- | A kli-export message: the event, its attachment group counter, and the
indexed controller signatures as 88-character CESR tokens.
-}
streamOf :: ByteString -> [(Int, ByteString)] -> ByteString
streamOf event sigs =
    event
        <> "-V"
        <> counter (1 + 22 * length sigs)
        <> "-A"
        <> counter (length sigs)
        <> BS.concat (map token sigs)
  where
    counter n = B8.pack [digit (n `shiftR` 6), digit (n .&. 63)]
    token (index, signature) =
        B8.pack ('A' : digit index : [digit (bits `shiftR` (6 * k) .&. 63) | k <- [85, 84 .. 0]])
      where
        bits = foldl (\acc b -> acc * 256 + fromIntegral b) (0 :: Integer) (BS.unpack signature)
    digit :: (Integral a) => a -> Char
    digit v =
        let n = fromIntegral v :: Int
         in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" !! n

{- | Replace one spelling in the signed bytes and keep the version string's size
field equal to the new length, so that only the spelling differs.
-}
respell :: ByteString -> ByteString -> ByteString -> ByteString
respell raw old new =
    let (before, rest) = BS.breakSubstring old raw
        edited = before <> new <> BS.drop (BS.length old) rest
        size = B8.pack (pad (showHex6 (BS.length edited)))
     in BS.take 16 edited <> size <> BS.drop 22 edited
  where
    pad s = replicate (6 - length s) '0' <> s
    showHex6 n = case n of
        0 -> "0"
        _ -> go n ""
    go 0 acc = acc
    go n acc = go (n `div` 16) ("0123456789abcdef" !! (n `mod` 16) : acc)
