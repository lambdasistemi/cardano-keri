{- |
Module      : Cardano.KERI.AID.ReaderCorpus
Description : The frozen reader corpus, read once for every spec that drives it (#353)

The corpus is @lean\/reader-status-vectors.json@, of which the fixture under
@test\/keri-fixtures@ is a byte copy (checked against the Lean file by the
local gate and by the specs that read it). Every spec that drives a component
over its rows reads it through this one parser, so that no spec holds a second
reading of a row.

A row is read as the Lean writes it: the evidence (the asked chain point, the
resolved environment, the holding observation) and the answer (the status, the
custody the classifier read, whether the history admits the holder, the leaf
the history established). The answer cells are exposed as the expectation or as
the supplied intermediate values, as the spec using them says.
-}
module Cardano.KERI.AID.ReaderCorpus (
    Holding (..),
    Row (..),
    Corpus (..),
    fixtureName,
    loadCorpus,
    rowNamed,
) where

import Cardano.KERI.AID.Application (Credential (..), OutputReference (..))
import Cardano.KERI.AID.Consumer (
    Context (..),
    Environment (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
 )
import Cardano.KERI.AID.Reader (
    Custody (..),
    Determined (..),
    RegistryLeaf (..),
    Status (..),
 )
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)

-- | What a row observes of the holders of the asset.
data Holding = Holding
    { hoPoint :: Integer
    , hoAsset :: (ByteString, ByteString)
    , hoHolders :: [ObservedOutput]
    }

-- | The cells of a row the components read.
data Row = Row
    { rowId :: Text
    , rowPoint :: Integer
    , rowHolding :: Maybe Holding
    , rowCustody :: Text
    -- ^ the custody word of the answer
    , rowEnvironment :: Environment
    -- ^ the environment the evidence resolved
    , rowDetermined :: Determined
    -- ^ the intermediate values of the answer: custody, history agreement, leaf
    , rowStatus :: Status
    -- ^ the status of the answer, read only as an expectation
    }

data Corpus = Corpus
    { cpContext :: Context
    , cpDerivedApproval :: (ByteString, ByteString)
    , cpDerivedRegistry :: (ByteString, ByteString)
    , cpDerivedRepresentative :: (ByteString, ByteString)
    , cpDerivedKey :: ByteString
    , cpRows :: [Row]
    }

fixtureName :: FilePath
fixtureName = "test/keri-fixtures/fixtures/reader-status-vectors.json"

loadCorpus :: IO Corpus
loadCorpus = do
    path <- getDataFileName fixtureName
    value <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure (corpusOf value)

corpusOf :: Value -> Either String Corpus
corpusOf top = do
    context <- field "context" top
    releaseValue <- field "release" context
    networkValue <- field "network" context
    network <- integer networkValue
    seed <- field "seed" context
    seedTx <- field "transactionId" seed >>= hex
    seedIx <- field "outputIndex" seed >>= integer
    aid <- field "aid" context >>= text
    checkpoint <- field "checkpointCredential" context >>= hex
    release <- releaseOf releaseValue
    derived <- field "derived" top
    approval <- field "terminationApproval" derived >>= assetOf
    registry <- field "registryAsset" derived >>= assetOf
    representative <- field "representativeAsset" derived >>= assetOf
    key <- field "key" derived >>= hex
    rows <- field "rows" top >>= array >>= traverse rowOf
    pure
        Corpus
            { cpContext =
                Context
                    { cxNetwork = network
                    , cxRelease = release
                    , cxSeed = OutputReference seedTx seedIx
                    , cxAid = TE.encodeUtf8 aid
                    , cxCheckpointCredential = ScriptCredential checkpoint
                    }
            , cpDerivedApproval = approval
            , cpDerivedRegistry = registry
            , cpDerivedRepresentative = representative
            , cpDerivedKey = key
            , cpRows = rows
            }

rowOf :: Value -> Either String Row
rowOf value = do
    identifier <- field "id" value >>= text
    evidence <- field "evidence" value
    point <- field "point" evidence >>= integer
    holding <- case KM.lookup (K.fromText "holding") (object evidence) of
        Nothing -> Left "evidence.holding is missing"
        Just Null -> Right Nothing
        Just observed -> Just <$> holdingOf observed
    environment <- field "environment" evidence >>= environmentOf
    answer <- field "answer" value
    custody <- field "custody" answer >>= custodyWord
    typedCustody <- custodyOfWord custody
    admits <- field "admitsHolder" answer >>= bool
    leaf <- field "leaf" answer >>= leafOf
    status <- field "status" answer >>= text >>= statusOf
    pure
        Row
            { rowId = identifier
            , rowPoint = point
            , rowHolding = holding
            , rowCustody = custody
            , rowEnvironment = environment
            , rowDetermined =
                Determined
                    { dtCustody = typedCustody
                    , dtHistoryAdmitsHolder = admits
                    , dtEstablishedLeaf = leaf
                    }
            , rowStatus = status
            }
  where
    object (Object o) = o
    object _ = KM.empty

holdingOf :: Value -> Either String Holding
holdingOf observed = do
    point <- field "point" observed >>= integer
    asset <- field "asset" observed >>= assetOf
    holders <- field "holders" observed >>= array >>= traverse holderOf
    pure Holding{hoPoint = point, hoAsset = asset, hoHolders = holders}

holderOf :: Value -> Either String ObservedOutput
holderOf output = do
    credential <- field "credential" output >>= hex
    assets <- field "assets" output >>= array >>= traverse entryOf
    datum <- field "datum" output >>= datumOf
    pure
        ObservedOutput
            { ooCredential = ScriptCredential credential
            , ooAssets = assets
            , ooDatum = datum
            }
  where
    entryOf entry = do
        policy <- field "policy" entry >>= hex
        name <- field "name" entry >>= hex
        quantity <- field "quantity" entry >>= integer
        pure (policy, name, quantity)

-- | The custody word of an answer: a word, or an object keyed by the word that carries its facts.
custodyWord :: Value -> Either String Text
custodyWord = \case
    String t -> Right t
    Object o | [(key, _)] <- KM.toList o -> Right (K.toText key)
    _ -> Left "custody: neither a word nor a one-key object"

-- | The corpus writes @"empty"@ or @{"application": <inline datum bytes>}@.
datumOf :: Value -> Either String OutputDatum
datumOf = \case
    String "empty" -> Right DatumAbsent
    Object o -> case KM.lookup (K.fromText "application") o of
        Just bytes -> DatumInline <$> hex bytes
        Nothing -> Left "datum: the object names no application datum"
    _ -> Left "datum: neither empty nor an application datum"

assetOf :: Value -> Either String (ByteString, ByteString)
assetOf value = (,) <$> (field "policy" value >>= hex) <*> (field "name" value >>= hex)

field :: Text -> Value -> Either String Value
field name = \case
    Object o -> maybe (Left ("missing " <> T.unpack name)) Right (KM.lookup (K.fromText name) o)
    _ -> Left ("not an object at " <> T.unpack name)

array :: Value -> Either String [Value]
array = \case
    Array items -> Right (toList items)
    _ -> Left "not an array"

text :: Value -> Either String Text
text = \case
    String t -> Right t
    _ -> Left "not a string"

integer :: Value -> Either String Integer
integer = \case
    Number n -> Right (truncate n)
    _ -> Left "not a number"

hex :: Value -> Either String ByteString
hex value = do
    t <- text value
    convertFromBase Base16 (TE.encodeUtf8 t)

-- | The resolved environment of a row: the network, and the release and the checkpoint credential, each resolved or null.
environmentOf :: Value -> Either String Environment
environmentOf value = do
    network <- field "network" value >>= integer
    release <- field "release" value >>= nullable releaseOf
    checkpoint <- field "checkpointCredential" value >>= nullable (fmap ScriptCredential . hex)
    pure
        Environment
            { envNetwork = network
            , envRelease = release
            , envCheckpointCredential = checkpoint
            }

releaseOf :: Value -> Either String Release
releaseOf release = do
    stateProgram <- field "stateProgram" release >>= hex
    statePolicy <- field "statePolicy" release >>= hex
    applicationPolicy <- field "applicationPolicy" release >>= hex
    applicationCredential <- field "applicationCredential" release >>= hex
    pure
        Release
            { rlApplicationPolicy = applicationPolicy
            , rlApplicationCredential = applicationCredential
            , rlStateProgram = stateProgram
            , rlStatePolicy = statePolicy
            }

nullable :: (Value -> Either String a) -> Value -> Either String (Maybe a)
nullable _ Null = Right Nothing
nullable parse value = Just <$> parse value

bool :: Value -> Either String Bool
bool = \case
    Bool b -> Right b
    _ -> Left "not a boolean"

-- | The custody word of the answer, as the typed custody the status is decided from.
custodyOfWord :: Text -> Either String Custody
custodyOfWord = \case
    "not-established" -> Right CustodyNotEstablished
    "absent" -> Right CustodyAbsent
    "live" -> Right CustodyLive
    "convicted" -> Right CustodyConvicted
    "request" -> Right CustodyRequest
    "inconsistent" -> Right CustodyInconsistent
    other -> Left ("custody word " <> T.unpack other)

-- | The established leaf of the answer: null is no leaf established.
leafOf :: Value -> Either String (Maybe RegistryLeaf)
leafOf = nullable $ \v -> do
    word <- text v
    case word of
        "unknown" -> Right LeafUnknown
        "active" -> Right LeafActive
        "terminal" -> Right LeafTerminal
        other -> Left ("leaf word " <> T.unpack other)

statusOf :: Text -> Either String Status
statusOf = \case
    "active" -> Right Active
    "pending-termination" -> Right PendingTermination
    "terminal" -> Right Terminal
    "never-registered" -> Right NeverRegistered
    "unavailable" -> Right Unavailable
    other -> Left ("status word " <> T.unpack other)

-- | The one row of this name.
rowNamed :: Corpus -> Text -> Row
rowNamed corpus identifier =
    case [r | r <- cpRows corpus, rowId r == identifier] of
        [row] -> row
        found -> error ("the corpus holds " <> show (length found) <> " rows named " <> T.unpack identifier)
