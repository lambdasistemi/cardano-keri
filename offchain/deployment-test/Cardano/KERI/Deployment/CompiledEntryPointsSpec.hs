{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.CompiledEntryPointsSpec
Description : the compiled validators over the signed exports, beside the Haskell mirror

Every signed CESR export of the frozen fixtures (`deployment-test/fixtures/compiled`, recorded with their SHA-256) is
read as the booking it makes: the identifier, the current keys, the next commitments, the thresholds as signed and the
witnesses become the datum, the signed body and its controller signature the evidence. Three compiled entry points run
over it through the Plutus ledger evaluator, each on the applied program of the production derivation: the hash-proof
mint, the booking attestation mint and the application mint. The Haskell mirror (`registrationPredicate`) judges the same
inputs, and the two verdicts are compared case by case; every accepted evaluation prints its counted budget on a line
beginning `RECEIPT`.
-}
module Cardano.KERI.Deployment.CompiledEntryPointsSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (
    KeyStateView (..),
    QualifiedSpelling (..),
 )
import Cardano.KERI.AID.Checkpoint.Qualified (
    codeB,
    digestPayload,
    identifierPayload,
    keyPayloads,
    payloadOf,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationEvidence (..),
    proofTokenName,
    registrationPredicate,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.Deployment.AttestationBoundarySpec (
    Booking (..),
    Inception (..),
    acceptedWithBudget,
    applicationBooking,
    booking,
    derived,
    issueOf,
    mintingContext,
 )
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.Script (
    Observers (..),
    ScriptArtifact (..),
    scriptHashBytes,
 )
import Control.Monad (forM_, unless)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (Value (..), eitherDecodeStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base64URLUnpadded), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Char (digitToInt, isDigit)
import Data.Foldable (toList)
import Data.List (elemIndex)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 (ExBudget (..))
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import Text.Printf (printf)

-- ---------------------------------------------------------------------------
-- The signed exports
-- ---------------------------------------------------------------------------

fixtureDir :: IO FilePath
fixtureDir = getDataFileName "deployment-test/fixtures/compiled"

data Export = Export
    { exName :: String
    , exBody :: ByteString
    , exSignatures :: [(Int, ByteString)]
    , exInception :: Inception
    }

readExport :: FilePath -> String -> IO Export
readExport dir name = do
    bytes <- BS.readFile (dir <> "/" <> name <> ".cesr")
    sums <- BS.readFile (dir <> "/SHA256SUMS")
    let digestHex = BS8.pack (show (hash bytes :: Digest SHA256))
        recorded = [h | l <- BS8.lines sums, [h, f] <- [BS8.words l], f == BS8.pack (name <> ".cesr")]
    unless (recorded == [digestHex]) (fail (name <> ": the export differs from its recorded SHA-256"))
    either fail pure (parseExport name bytes)

parseExport :: String -> ByteString -> Either String Export
parseExport name bytes = do
    size <- hex6 (BS.take 6 (BS.drop 16 bytes))
    let body = BS.take size bytes
        attachment = BS.drop size bytes
    signatures <- indexedSignatures attachment
    let signature = signatures
    event <- eitherDecodeStrict body
    inception <- inceptionOfEvent body signatures event
    pure Export{exName = name, exBody = body, exSignatures = signature, exInception = inception}

{- | The controller signatures of an attachment group: `-V`, its size, `-A`, the count, then each indexed signature
(`A`, the index character, 86 characters of signature).
-}
indexedSignatures :: ByteString -> Either String [(Int, ByteString)]
indexedSignatures attachment = do
    unless ("-V" `BS.isPrefixOf` attachment && BS.take 2 (BS.drop 4 attachment) == "-A") (Left "the attachment is not a controller signature group")
    count <- maybeE "count" (b64 (BS8.index attachment 7))
    let body = BS.drop 8 attachment
    unless (BS.length body == 88 * (count + 0) && BS8.index attachment 6 == 'A') (Left "the attachment is not the declared count of indexed signatures")
    traverse one [BS.take 88 (BS.drop (88 * k) body) | k <- [0 .. count - 1]]
  where
    one sig = do
        unless (BS8.head sig == 'A') (Left "not an Ed25519 indexed signature")
        index <- maybeE "index" (b64 (BS8.index sig 1))
        raw <- convertFromBase Base64URLUnpadded (BS.append "AA" (BS.drop 2 sig)) :: Either String ByteString
        pure (index, BS.drop 2 raw)
    b64 c = elemIndex c (['A' .. 'Z'] <> ['a' .. 'z'] <> ['0' .. '9'] <> "-_")

hex6 :: ByteString -> Either String Int
hex6 t
    | BS.length t == 6 && BS8.all (`elem` ("0123456789abcdef" :: String)) t = Right (BS8.foldl' (\a c -> a * 16 + digitToInt c) 0 t)
    | otherwise = Left "bad version size"

field :: Text -> Value -> Either String Value
field k (Object o) | Just v <- KM.lookup (K.fromText k) o = Right v
field k _ = Left (T.unpack k <> " missing")

texts :: Value -> Either String [ByteString]
texts (Array a) = traverse one (toList a)
  where
    one (String t) = Right (TE.encodeUtf8 t)
    one _ = Left "not a string"
texts _ = Left "not an array"

str :: Value -> Either String ByteString
str (String t) = Right (TE.encodeUtf8 t)
str _ = Left "not a string"

maybeE :: String -> Maybe a -> Either String a
maybeE e = maybe (Left e) Right

-- | A threshold as signed: a hexadecimal string, a flat array of weights (one clause) or an array of clauses.
threshold :: Value -> Either String Threshold
threshold v = case v of
    String t -> Unweighted <$> hexInt (T.unpack t)
    Array a -> case toList a of
        xs@(Array _ : _) -> Weighted <$> traverse clause xs
        xs -> (\c -> Weighted [c]) <$> traverse weight xs
    _ -> Left "bad threshold"
  where
    clause (Array c) = traverse weight (toList c)
    clause _ = Left "bad clause"
    weight (String w) = case T.splitOn "/" w of
        [n] -> (`Weight` 1) <$> dec n
        [n, d] -> Weight <$> dec n <*> dec d
        _ -> Left "bad weight"
    weight _ = Left "bad weight"
    dec t = if not (T.null t) && T.all isDigit t then Right (read (T.unpack t)) else Left "bad number"

hexInt :: String -> Either String Integer
hexInt s
    | null s = Left "empty numeral"
    | otherwise = Right (foldl (\a c -> a * 16 + fromIntegral (digitToInt c)) 0 s)

inceptionOfEvent :: ByteString -> [(Int, ByteString)] -> Value -> Either String Inception
inceptionOfEvent body signatures ev = do
    identifier <- field "i" ev >>= str
    keys <- field "k" ev >>= texts
    nexts <- field "n" ev >>= texts
    witnesses <- field "b" ev >>= texts
    kt <- field "kt" ev >>= threshold
    nt <- field "nt" ev >>= threshold
    bt <- field "bt" ev >>= str >>= hexInt . BS8.unpack
    payload <- maybeE "identifier" (identifierPayload identifier)
    rawKeys <- maybeE "keys" (keyPayloads keys)
    rawNext <- maybeE "next" (traverse digestPayload nexts)
    rawWit <- maybeE "witnesses" (traverse (payloadOf [codeB]) witnesses)
    pure
        Inception
            { inceptionView =
                KeyStateView
                    { cdCesrAid = payload
                    , cdCurKeys = rawKeys
                    , cdCurThreshold = kt
                    , cdNextKeys = rawNext
                    , cdNextThreshold = nt
                    , cdWitnesses = rawWit
                    , cdToad = bt
                    , cdSeq = 0
                    , cdNativeSn = 0
                    }
            , inceptionEvidence = RegistrationEvidence{reEventBytes = body, reCtrlSigs = signatures, reWitReceipts = []}
            , inceptionIdentifier = identifier
            , inceptionKeys = keys
            }

-- ---------------------------------------------------------------------------
-- One case through the three compiled entry points and the mirror
-- ---------------------------------------------------------------------------

data Outcome = Outcome
    { oMirror :: Bool
    , oProof :: Either String ExBudget
    , oAttestation :: Either String ExBudget
    , oApplication :: Either String ExBudget
    }

mirrorVerdict :: Inception -> Bool
mirrorVerdict i =
    let view = inceptionView i
        spelling = QualifiedSpelling (inceptionIdentifier i) (inceptionKeys i)
     in either (const False) (const True) $
            registrationPredicate (DeploymentContext 2_000_000 1_000_000_000) view spelling 1_009_000_003 (inceptionEvidence i)

outcomeOf :: RegistryScripts -> Inception -> Outcome
outcomeOf scripts inception =
    Outcome
        { oMirror = mirrorVerdict inception
        , oProof = acceptedWithBudget proofArtifact proofContext
        , oAttestation = acceptedWithBudget (scriptsAttestation scripts) (bookingContext minted)
        , oApplication = acceptedWithBudget (scriptsApplication scripts) (applicationBooking scripts inception True)
        }
  where
    proofArtifact = observerHashProof (scriptsObservers scripts)
    proofPolicy = scriptHashBytes (artifactScriptHash proofArtifact)
    evidence = inceptionEvidence inception
    payload = cdCesrAid (inceptionView inception)
    proofName = proofTokenName (reEventBytes evidence) payload
    proofContext =
        mintingContext proofPolicy [] [] [(proofPolicy, [(proofName, 1)])] (Constr 0 [B (reEventBytes evidence), B payload])
    probe = booking scripts inception [] (issueOf inception)
    minted = booking scripts inception [(bookingName probe, 1)] (issueOf inception)

isRight' :: Either a b -> Bool
isRight' = either (const False) (const True)

budgetText :: Either String ExBudget -> String
budgetText (Right (ExBudget cpu mem)) = printf "accepted\t%s\t%s" (show mem) (show cpu)
budgetText (Left _) = "refused\t-\t-"

receipt :: String -> String -> Outcome -> IO ()
receipt name label o =
    putStrLn $
        "RECEIPT\t"
            <> name
            <> "\t"
            <> label
            <> "\tmirror="
            <> (if oMirror o then "accepted" else "refused")
            <> "\tproof="
            <> budgetText (oProof o)
            <> "\tattestation="
            <> budgetText (oAttestation o)
            <> "\tapplication="
            <> budgetText (oApplication o)

signed :: [String]
signed = ["i01", "i02", "b-empty", "d-empty", "d-seal", "w-exact", "w-unreduced", "w-partial"]

sweep :: [String]
sweep = ["anchors-00", "anchors-01", "anchors-02", "anchors-04", "anchors-08", "anchors-10", "anchors-12", "anchors-13", "anchors-14", "anchors-16", "anchors-32", "anchors-64"]

spec :: Spec
spec = describe "the compiled entry points over the frozen signed exports, beside the Haskell mirror" $ do
    it "accepts each signed booking at the hash-proof mint, the attestation mint and the application mint, as the mirror does" $ do
        scripts <- derived
        dir <- fixtureDir
        forM_ signed $ \name -> do
            export <- readExport dir name
            let o = outcomeOf scripts (exInception export)
            receipt name "signed" o
            (name, oMirror o, isRight' (oProof o), isRight' (oAttestation o), isRight' (oApplication o))
                `shouldBe` (name, True, True, True, True)
    it "refuses, at every compiled entry that reads the event, each signed booking whose body has its last byte changed, as the mirror does" $ do
        scripts <- derived
        dir <- fixtureDir
        forM_ signed $ \name -> do
            export <- readExport dir name
            let i = exInception export
                ev = inceptionEvidence i
                body = exBody export
                changed = BS.init body <> "~"
                o = outcomeOf scripts i{inceptionEvidence = ev{reEventBytes = changed}}
            receipt name "last-byte-changed" o
            (name, oMirror o, isRight' (oProof o), isRight' (oAttestation o)) `shouldBe` (name, False, False, False)
    it "refuses each signed booking under the controller signature of another export, at the attestation mint, as the mirror does" $ do
        scripts <- derived
        dir <- fixtureDir
        other <- readExport dir "i02"
        forM_ (filter (/= "i02") signed) $ \name -> do
            export <- readExport dir name
            let i = exInception export
                o = outcomeOf scripts i{inceptionEvidence = (inceptionEvidence i){reCtrlSigs = take 1 (exSignatures other)}}
            receipt name "other-signature" o
            (name, oMirror o, isRight' (oAttestation o)) `shouldBe` (name, False, False)
    it "reads the anchor-size sweep: the booking fits through 13 seals and the event-size bound refuses from 14, in the mirror and in the compiled programs alike" $ do
        scripts <- derived
        dir <- fixtureDir
        verdicts <-
            mapM
                ( \name -> do
                    export <- readExport dir name
                    let o = outcomeOf scripts (exInception export)
                    receipt name ("sweep body=" <> show (BS.length (exBody export))) o
                    pure (name, BS.length (exBody export), oMirror o, isRight' (oProof o), isRight' (oAttestation o))
                )
                sweep
        forM_ verdicts $ \(name, size, m, p, a) ->
            (name, m, p, a) `shouldBe` (name, size <= 1024, size <= 1024, size <= 1024)
        let fitting = [n | (n, size, _, _, _) <- verdicts, size <= 1024]
        unless (length fitting == 8) (expectationFailure ("the fitting cases: " <> show fitting))
