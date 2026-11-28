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

import Cardano.KERI.AID.Checkpoint.Datum (KeyStateView (..), QualifiedIdentity (..))
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationEvidence (..),
    proofTokenName,
    registrationPredicateOver,
 )
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
import Cardano.KERI.Deployment.KEL qualified as KEL
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.Script (
    Observers (..),
    ScriptArtifact (..),
    scriptHashBytes,
 )
import Control.Monad (forM_, unless)
import Crypto.Hash (Digest, SHA256, hash)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.List (isInfixOf)
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 (ExBudget (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
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

-- | An export as the builder reads it: the registration builder's `parseInceptionExport`, the entry point of the normal booking.
readExport :: FilePath -> String -> IO Export
readExport dir name = tryExport dir name >>= either fail pure

-- | The same, with the builder's refusal of the export returned.
tryExport :: FilePath -> String -> IO (Either String Export)
tryExport dir name = do
    bytes <- BS.readFile (dir <> "/" <> name <> ".cesr")
    sums <- BS.readFile (dir <> "/SHA256SUMS")
    let digestHex = BS8.pack (show (hash bytes :: Digest SHA256))
        recorded = [h | l <- BS8.lines sums, [h, f] <- [BS8.words l], f == BS8.pack (name <> ".cesr")]
    unless (recorded == [digestHex]) (fail (name <> ": the export differs from its recorded SHA-256"))
    pure $ do
        parsed <- either (\e -> Left (name <> ": " <> e)) Right (KEL.parseInceptionExport bytes)
        let evidence = KEL.inceptionEvidence parsed
            QualifiedIdentity identifier keys = KEL.inceptionQualified parsed
        pure
            Export
                { exName = name
                , exBody = reEventBytes evidence
                , exSignatures = reCtrlSigs evidence
                , exInception =
                    Inception
                        { inceptionView = KEL.inceptionDatum parsed
                        , inceptionEvidence = evidence
                        , inceptionIdentifier = identifier
                        , inceptionKeys = keys
                        }
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
    either (const False) (const True) $
        registrationPredicateOver
            (DeploymentContext 2_000_000 1_000_000_000)
            (QualifiedIdentity (inceptionIdentifier i) (inceptionKeys i))
            (inceptionView i)
            1_009_000_003
            (inceptionEvidence i)

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

fittingNames :: [String]
fittingNames = ["anchors-00", "anchors-01", "anchors-02", "anchors-04", "anchors-08", "anchors-10", "anchors-12", "anchors-13"]

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
                    attempt <- tryExport dir name
                    case attempt of
                        Left refusal -> do
                            putStrLn ("RECEIPT\t" <> name <> "\tsweep\tbuilder-refused-at-export-parse\t" <> refusal)
                            refusal `shouldSatisfy` isInfixOf "ErrLengthBound"
                            pure (name, Nothing)
                        Right export -> do
                            let o = outcomeOf scripts (exInception export)
                            receipt name ("sweep body=" <> show (BS.length (exBody export))) o
                            pure (name, Just (BS.length (exBody export), oMirror o, isRight' (oProof o), isRight' (oAttestation o)))
                )
                sweep
        forM_ verdicts $ \(name, v) -> case v of
            Just (size, m, p, a) -> (name, size <= 1024, m, p, a) `shouldBe` (name, True, True, True, True)
            Nothing -> name `shouldSatisfy` (`notElem` fittingNames)
        let fitting = [n | (n, Just _) <- verdicts]
        fitting `shouldBe` fittingNames
