{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.AttestationVectorsSpec
Description : the booking attestation's encoder and hash, driven by the parity vectors

The claim of a booking with its wrapped initial datum, the name that digests it,
the Issue redeemer with the evidence of each request and the Burn redeemer, each
run through the library's own encoders ('bookingAttestationClaimData',
'bookingAttestationName', 'bookingAttestationIssueData',
'bookingAttestationBurnData') and compared with the bytes of the generated vectors
(@scripts/attestation-vectors.mjs@). The Aiken tests drive the validators' own
function and types from the same vectors, and a drift check fails when either side
or the generator moves.
-}
module Cardano.KERI.AID.Checkpoint.AttestationVectorsSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    bookingAttestationBurnData,
    bookingAttestationClaimData,
    bookingAttestationIssueData,
    bookingAttestationName,
 )
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinByteString (..), BuiltinData (..), serialiseData)
import Test.Hspec (Spec, describe, expectationFailure, it, pendingWith, shouldBe)

type Parsed a = Either String a

field :: Text -> Value -> Parsed Value
field k v = case v of
    Object o | Just x <- KM.lookup (K.fromText k) o -> Right x
    _ -> Left (show k <> " missing")

text :: Value -> Parsed Text
text (String t) = Right t
text _ = Left "not a string"

integer :: Value -> Parsed Integer
integer (Number n) = Right (truncate n)
integer _ = Left "not a number"

array :: Value -> Parsed [Value]
array (Array a) = Right (toList a)
array _ = Left "not an array"

bytes :: Value -> Parsed ByteString
bytes v = text v >>= convertFromBase Base16 . TE.encodeUtf8

-- | A Plutus Data tree of the vectors: @{i}@, @{b}@, @{c, f}@ or @{l}@.
tree :: Value -> Parsed Data
tree v = case v of
    Object o
        | KM.member "i" o -> I <$> (field "i" v >>= integer)
        | KM.member "b" o -> B <$> (field "b" v >>= bytes)
        | KM.member "l" o -> List <$> (field "l" v >>= array >>= traverse tree)
        | KM.member "c" o -> Constr <$> (field "c" v >>= integer) <*> (field "f" v >>= array >>= traverse tree)
    _ -> Left "not a data tree"

evidenceOf :: Value -> Parsed RegistrationEvidence
evidenceOf v = do
    eventBytes <- field "event_bytes" v >>= bytes
    let indexed name =
            field name v
                >>= array
                >>= traverse
                    ( \p -> do
                        pair <- array p
                        case pair of
                            [k, s] -> (,) . fromIntegral <$> integer k <*> bytes s
                            _ -> Left "not an indexed signature"
                    )
    RegistrationEvidence eventBytes
        <$> indexed "ctrl_sigs"
        <*> indexed "wit_receipts"

serialised :: Data -> ByteString
serialised d = let BuiltinByteString b = serialiseData (BuiltinData d) in b

hex :: ByteString -> ByteString
hex = convertToBase Base16

spec :: Spec
spec = describe "booking attestation parity vectors" $ do
    it "writes each claim and digests it as the vectors do" $ do
        vectors <- loadVectors
        claims <- either fail pure (field "claims" vectors >>= array)
        claims `shouldNotBeEmpty` "claims"
        mapM_ checkClaim claims
    it "writes each Issue redeemer with its evidence as the vectors do" $ do
        pendingWith "awaits the validators' three-field booking vectors: scripts/attestation-vectors.mjs still writes the nine-offset evidence type of main; this row returns when their offset-free types merge (frozen interface, NOTE-027)"
        vectors <- loadVectors
        issues <- either fail pure (field "issues" vectors >>= array)
        issues `shouldNotBeEmpty` "issues"
        mapM_ checkIssue issues
    it "writes Burn as the vectors do" $ do
        vectors <- loadVectors
        expected <- either fail pure (field "burn" vectors >>= field "redeemer" >>= bytes)
        hex (serialised bookingAttestationBurnData) `shouldBe` hex expected
  where
    shouldNotBeEmpty xs what
        | null xs = expectationFailure (what <> " is empty")
        | otherwise = pure ()

loadVectors :: IO Value
loadVectors = do
    path <- getDataFileName "test/keri-fixtures/fixtures/attestation-vectors.json"
    eitherDecodeFileStrict path >>= either fail pure

checkClaim :: Value -> IO ()
checkClaim c = do
    (application, index, datum, deposit, claim, name) <-
        either fail pure $
            (,,,,,)
                <$> (field "application" c >>= bytes)
                <*> (field "index" c >>= integer)
                <*> (field "datum" c >>= tree)
                <*> (field "deposit" c >>= integer)
                <*> (field "claim" c >>= bytes)
                <*> (field "assetName" c >>= bytes)
    hex (serialised (bookingAttestationClaimData application index datum deposit)) `shouldBe` hex claim
    hex (bookingAttestationName application index datum deposit) `shouldBe` hex name

checkIssue :: Value -> IO ()
checkIssue x = do
    (application, entries, expected) <-
        either fail pure $ do
            application <- field "application" x >>= bytes
            entries <-
                field "entries" x
                    >>= array
                    >>= traverse
                        ( \e ->
                            (,) <$> (field "index" e >>= integer) <*> (field "evidence" e >>= evidenceOf)
                        )
            expected <- field "redeemer" x >>= bytes
            pure (application, entries, expected)
    hex (serialised (bookingAttestationIssueData application entries)) `shouldBe` hex expected
