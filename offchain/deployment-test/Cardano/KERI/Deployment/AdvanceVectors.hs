{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.AdvanceVectors
Description : the committed advance vectors as Plutus Data, and the seeds that sign them

The datums, the evidence and the signed fact of the advance vectors the independent generator reads
(`advance-split-cases.json`), as Plutus Data, and the signing seeds of the fixture bundle the depositing
rotation's intent is signed with. The applied-program and the ledger-evaluated examples build their transactions
from them.
-}
module Cardano.KERI.Deployment.AdvanceVectors (
    Vector (..),
    field,
    hexBytes,
    asText,
    loadVectorNamed,
    loadJanuaryVector,
    JanuaryExpectation (..),
    loadJanuaryExpectation,
    NestedSeal (..),
    loadNestedSeal,
    loadTrailingPair,
    loadScalarPair,
    loadTextPair,
    loadVector,
    Seeds (..),
    loadSeeds,
    signedBy,
) where

import Control.Monad ((>=>))
import Crypto.Error (CryptoFailable (..))
import Crypto.PubKey.Ed25519 qualified as Ed25519
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray qualified as BA
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))

-- ---------------------------------------------------------------------------
-- The committed advance vectors, as Plutus Data
-- ---------------------------------------------------------------------------

data Vector = Vector
    { vectorTxid :: ByteString
    , vectorIndex :: Integer
    , vectorAid :: ByteString
    , vectorOld :: Data
    , vectorNew :: Data
    , vectorFrozen :: Data
    , vectorEvidence :: Data
    , vectorFreezePayload :: Data
    , vectorFact :: Data
    }

field :: Text -> Value -> Either String Value
field k v = case v of
    Object o | Just x <- KM.lookup (K.fromText k) o -> Right x
    _ -> Left (T.unpack k <> " missing")

hexBytes :: Text -> Either String ByteString
hexBytes = convertFromBase Base16 . TE.encodeUtf8

{- | A Plutus Data tree of the vector file: @{"i": n}@, @{"b": hex}@, @{"l": [..]}@
and @{"c": n, "f": [..]}@.
-}
tree :: Value -> Either String Data
tree v = case v of
    Object o
        | Just (Number n) <- KM.lookup "i" o -> Right (I (truncate n))
        | Just (String h) <- KM.lookup "b" o -> B <$> hexBytes h
        | Just (Array xs) <- KM.lookup "l" o -> List <$> traverse tree (toList xs)
        | Just (Number c) <- KM.lookup "c" o
        , Just (Array fs) <- KM.lookup "f" o ->
            Constr (truncate c) <$> traverse tree (toList fs)
    _ -> Left "not a Plutus Data tree"

vectorOf :: Value -> Either String Vector
vectorOf v = do
    txid <- field "txid" v >>= text >>= hexBytes
    index <- field "index" v >>= number
    aid <- field "aid" v >>= text
    old <- field "oldDatum" v >>= tree
    new <- field "newDatum" v >>= tree
    frozen <- field "frozenOld" v >>= tree
    evidence <- field "evidence" v >>= tree
    freezePayload <- field "freezePayload" v >>= tree
    fact <- field "fact" v >>= tree
    pure (Vector txid index (TE.encodeUtf8 aid) old new frozen evidence freezePayload fact)
  where
    text (String t) = Right t
    text _ = Left "not a string"
    number (Number n) = Right (truncate n)
    number _ = Left "not a number"

loadVectorNamed :: Text -> IO Vector
loadVectorNamed name = do
    path <- getDataFileName "test/keri-fixtures/fixtures/advance-split-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure (field name top >>= vectorOf)

{- | A journey of #591 (@R01@ as @r01@, @R17@ as @r17@): the datums, the evidence and the fact of a rotation with its own
predecessor inception, written by @scripts/january-591-vectors.mjs@ from the signed bytes and keripy's attachments.
-}
loadJanuaryVector :: Text -> IO Vector
loadJanuaryVector name = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure (field name top >>= vectorOf)

-- | What the signed rotation declares for its successor, read from the signed event by the generator, not from the datums.
data JanuaryExpectation = JanuaryExpectation
    { expectedNextKeys :: [ByteString]
    , expectedNextThreshold :: Integer
    , expectedSpentNextKeys :: [ByteString]
    }

loadJanuaryExpectation :: Text -> IO JanuaryExpectation
loadJanuaryExpectation name = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        expect <- field name top >>= field "expect"
        keys <- field "nextKeys" expect >>= hexList
        spent <- field "spentNextKeys" expect >>= hexList
        threshold <- field "nextThreshold" expect >>= asNumber
        Right (JanuaryExpectation keys threshold spent)
  where
    hexList v = case v of
        Array xs -> traverse (asText >=> hexBytes) (toList xs)
        _ -> Left "not an array"
    asNumber v = case v of
        Number n -> Right (truncate n)
        _ -> Left "not a number"

-- | The rotation body of R01 whose seal spells the abandonment fields: the body, and the offsets of that spelling.
data NestedSeal = NestedSeal {sealBody :: ByteString, sealOffNt :: Integer, sealOffBt :: Integer}

loadNestedSeal :: IO NestedSeal
loadNestedSeal = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        seal <- field "nested_seal" top
        body <- field "body" seal >>= asText >>= hexBytes
        offNt <- field "offNt" seal >>= asNumber
        offBt <- field "offBt" seal >>= asNumber
        Right (NestedSeal body offNt offBt)
  where
    asNumber v = case v of
        Number n -> Right (truncate n)
        _ -> Left "not a number"

-- | The body of R01 followed, after its last member, by a repeated top-level declaration.
loadTrailingPair :: IO ByteString
loadTrailingPair = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure (field "trailing_pair" top >>= field "body" >>= asText >>= hexBytes)

-- | Two bodies of R01 that differ in the scalars of their last member: valid numbers, and a minus sign without digits.
loadScalarPair :: IO (ByteString, ByteString)
loadScalarPair = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        pair <- field "scalar_pair" top
        valid <- field "valid" pair >>= asText >>= hexBytes
        malformed <- field "malformed" pair >>= asText >>= hexBytes
        Right (valid, malformed)

{- | Two bodies of R01 that differ in the text of their last member: every length and boundary of well-formed UTF-8, and an
isolated continuation byte.
-}
loadTextPair :: IO (ByteString, ByteString)
loadTextPair = do
    path <- getDataFileName "test/keri-fixtures/fixtures/january-591-cases.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        pair <- field "text_pair" top
        valid <- field "valid" pair >>= asText >>= hexBytes
        malformed <- field "malformed" pair >>= asText >>= hexBytes
        Right (valid, malformed)

loadVector :: IO Vector
loadVector = loadVectorNamed "two_key"

-- | The signing seeds of the rotation's current keys and of the inception's, from the fixture bundle.
data Seeds = Seeds {rotationSeeds :: [ByteString], inceptionSeeds :: [ByteString]}

loadSeeds :: IO Seeds
loadSeeds = do
    path <- getDataFileName "test/keri-fixtures/fixtures/advance.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        seeds <- field "adv_wit_2key" top >>= field "signer_seeds"
        let seedsOf name = do
                entries <- field name seeds >>= asArray
                traverse (\e -> field "seed_hex" e >>= asText >>= hexBytes) entries
        Seeds <$> seedsOf "rotation_current" <*> seedsOf "inception_current"
  where
    asArray (Array xs) = Right (toList xs)
    asArray _ = Left "not an array"

-- | An Ed25519 signature of a message by the key of a seed.
signedBy :: ByteString -> ByteString -> ByteString
signedBy seed message =
    case Ed25519.secretKey seed of
        CryptoPassed secret -> BA.convert (Ed25519.sign secret (Ed25519.toPublic secret) message)
        CryptoFailed err -> error (show err)

asText :: Value -> Either String Text
asText (String t) = Right t
asText _ = Left "not a string"
