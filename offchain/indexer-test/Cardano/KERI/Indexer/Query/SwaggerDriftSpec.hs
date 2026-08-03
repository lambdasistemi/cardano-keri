{- |
Module      : Cardano.KERI.Indexer.Query.SwaggerDriftSpec
Description : #176 T176-S1-8/PROVE-LIST 8 — OpenAPI field-set drift check

Per the navigator's PLAN-APPROVED condition: the "expected" field set for
each response schema is derived by encoding a real, representative
production value with the real 'Data.Aeson.ToJSON' instances from
"Cardano.KERI.Indexer.Query.Types" and reading the resulting object's key
set — never a second hand-maintained string list living next to the
committed @docs\/assets\/swagger\/query-api.json@. A rename in either the
encoder or the committed schema (and nowhere else) must fail exactly one of
these comparisons; this is the executable half of T176-S1-10's field-drift
proof (see @evidence\/s1-contract-field-drift-red.txt@ for the captured red
run against the encoder side).
-}
module Cardano.KERI.Indexer.Query.SwaggerDriftSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.Indexer.Query.Types (
    BoardData (..),
    BoardListEntry (..),
    BoardListResponse (..),
    BoardResponse (..),
    CheckpointData (..),
    CheckpointResponse (..),
    Freshness (..),
    ReadyResponse (..),
    UnavailableResponse (..),
    WatchabilityData (..),
    WatchabilityResponse (..),
 )
import Data.Aeson (ToJSON, Value (..), decodeFileStrict', toJSON)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "docs/assets/swagger/query-api.json field-set drift (#176 PROVE-LIST 8)" $ do
    it "ReadyResponse matches components.schemas.ReadyResponse" $
        checkTopLevel "ReadyResponse" sampleReadyResponse

    it "UnavailableResponse matches components.schemas.UnavailableResponse" $
        checkTopLevel "UnavailableResponse" sampleUnavailableResponse

    it "CheckpointResponse (top level) matches components.schemas.CheckpointResponse" $
        checkTopLevel "CheckpointResponse" sampleCheckpointResponse

    it "CheckpointData (nested) matches components.schemas.CheckpointData" $
        checkTopLevel "CheckpointData" sampleCheckpointData

    it "BoardResponse (top level) matches components.schemas.BoardResponse" $
        checkTopLevel "BoardResponse" sampleBoardResponse

    it "BoardData (nested) matches components.schemas.BoardData" $
        checkTopLevel "BoardData" sampleBoardData

    it "BoardListResponse (top level) matches components.schemas.BoardListResponse" $
        checkTopLevel "BoardListResponse" sampleBoardListResponse

    it "BoardListEntry (nested) matches components.schemas.BoardListEntry" $
        checkTopLevel "BoardListEntry" sampleBoardListEntry

    it "WatchabilityResponse (top level) matches components.schemas.WatchabilityResponse" $
        checkTopLevel "WatchabilityResponse" sampleWatchabilityResponse

    it "WatchabilityData (nested) matches components.schemas.WatchabilityData" $
        checkTopLevel "WatchabilityData" sampleWatchabilityData

-- ---------------------------------------------------------------------------
-- The check

checkTopLevel :: (ToJSON a) => Text -> a -> IO ()
checkTopLevel schemaName sample = do
    swagger <- loadSwagger
    declared <- schemaPropertyKeys swagger schemaName
    actual <- encodedKeys sample
    actual `shouldBe` declared

encodedKeys :: (ToJSON a) => a -> IO (Set Text)
encodedKeys value = case toJSON value of
    Object obj -> pure (keySet obj)
    other -> expectationFailure ("not a JSON object: " <> show other) >> fail "not an object"

schemaPropertyKeys :: Value -> Text -> IO (Set Text)
schemaPropertyKeys swagger schemaName =
    case swagger of
        Object top -> case KeyMap.lookup "components" top of
            Just (Object components) -> case KeyMap.lookup "schemas" components of
                Just (Object schemas) -> case KeyMap.lookup (Key.fromText schemaName) schemas of
                    Just (Object schema) -> case KeyMap.lookup "properties" schema of
                        Just (Object props) -> pure (keySet props)
                        _ -> failMissing "properties"
                    _ -> failMissing ("components.schemas." <> schemaName)
                _ -> failMissing "components.schemas"
            _ -> failMissing "components"
        _ -> failMissing "top-level object"
  where
    failMissing :: Text -> IO a
    failMissing what = expectationFailure ("swagger missing " <> T.unpack what) >> fail "missing"

keySet :: KeyMap.KeyMap v -> Set Text
keySet = Set.fromList . map Key.toText . KeyMap.keys

loadSwagger :: IO Value
loadSwagger = do
    path <- getDataFileName "docs/assets/swagger/query-api.json"
    result <- decodeFileStrict' path
    case result of
        Just value -> pure value
        Nothing -> expectationFailure "swagger.json failed to parse" >> fail "parse"

-- ---------------------------------------------------------------------------
-- Representative production values

sampleFreshness :: Freshness
sampleFreshness = Freshness (Just 1) (Just 0)

sampleReadyResponse :: ReadyResponse
sampleReadyResponse =
    ReadyResponse
        { readyReady = True
        , readyFreshness = sampleFreshness
        , readyUpstream = "connected"
        , readyReason = Nothing
        }

sampleUnavailableResponse :: UnavailableResponse
sampleUnavailableResponse =
    UnavailableResponse
        { unavailableFreshness = sampleFreshness
        , unavailableUpstream = "disconnected"
        , unavailableReason = "upstream disconnected"
        }

sampleCheckpointData :: CheckpointData
sampleCheckpointData =
    CheckpointData
        { chkTxId = sampleBytes
        , chkOutputIndex = 0
        , chkSequence = 0
        , chkNativeSequence = 0
        , chkCurrentKeys = [sampleBytes]
        , chkCurrentThreshold = Unweighted 1
        , chkNextKeyDigests = [sampleBytes]
        , chkNextThreshold = Unweighted 1
        , chkWitnesses = [sampleBytes]
        , chkWitnessThreshold = 0
        }

sampleCheckpointResponse :: CheckpointResponse
sampleCheckpointResponse =
    CheckpointResponse
        { crAid = sampleBytes
        , crFreshness = sampleFreshness
        , crCheckpoint = Just sampleCheckpointData
        }

sampleBoardData :: BoardData
sampleBoardData =
    BoardData
        { bdAid = "sample"
        , bdScheme = "https"
        , bdUrl = "https://example.test/"
        , bdTxId = "00"
        , bdOutputIndex = 0
        , bdLovelace = 0
        , bdOwnerKeyHash = sampleBytes
        }

sampleBoardResponse :: BoardResponse
sampleBoardResponse =
    BoardResponse
        { brWitnessKey = sampleBytes
        , brFreshness = sampleFreshness
        , brBoard = Just sampleBoardData
        }

sampleBoardListEntry :: BoardListEntry
sampleBoardListEntry =
    BoardListEntry
        { bleWitnessKey = sampleBytes
        , bleBoard = sampleBoardData
        }

sampleBoardListResponse :: BoardListResponse
sampleBoardListResponse =
    BoardListResponse
        { blrFreshness = sampleFreshness
        , blrBoard = [sampleBoardListEntry]
        }

sampleWatchabilityData :: WatchabilityData
sampleWatchabilityData =
    WatchabilityData
        { wdCheckpointPresent = True
        , wdWitnessesDeclared = 1
        , wdWitnessesListed = 1
        , wdMissingWitnesses = []
        }

sampleWatchabilityResponse :: WatchabilityResponse
sampleWatchabilityResponse =
    WatchabilityResponse
        { wrAid = sampleBytes
        , wrFreshness = sampleFreshness
        , wrWatchability = sampleWatchabilityData
        }

sampleBytes :: ByteString
sampleBytes = "\NUL"
