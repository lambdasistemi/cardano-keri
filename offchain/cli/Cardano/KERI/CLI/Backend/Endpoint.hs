{- |
Module      : Cardano.KERI.CLI.Backend.Endpoint
Description : #177 Slice 1 hosted #176 endpoint client adapter

A strict client for the frozen @specs\/176-query-endpoint\/spec.md@ routes.
Decodes the wire shape independently of the producer's
"Cardano.KERI.Indexer.Query.Types" (deliberately not shared, per plan.md, so
the two sides can't silently drift together) and validates HTTP status, the
echoed identifier, and non-negative freshness (FR-3): a 503, malformed body,
mismatched AID, or impossible freshness is a closed error with no partial
output. @status@ composes @\/checkpoint@ and @\/watchability@ — two
independent HTTP calls, since #176 has no combined route — and rejects the
answer if their freshness disagrees (a "false cross-call coherence" per
plan.md's risk section: the store could have mutated between the two calls).
-}
module Cardano.KERI.CLI.Backend.Endpoint (mkEndpointBackend) where

import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    BoardFields (..),
    CheckpointFields (..),
    Freshness (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
 )
import Control.Exception (SomeException, try)
import Data.Aeson (Value, eitherDecode)
import Data.Aeson.Types (Object, Parser, parseEither)
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Simple (
    getResponseBody,
    getResponseStatusCode,
    httpLBS,
    parseRequest,
 )

mkEndpointBackend :: Text -> QueryBackend
mkEndpointBackend baseUrl =
    QueryBackend
        { qbSourceLabel = baseUrl
        , qbStatus = endpointStatus baseUrl
        , qbBoardByWitness = endpointBoardByWitness baseUrl
        }

endpointStatus :: Text -> Text -> IO (Either BackendError StatusView)
endpointStatus baseUrl aidText = do
    checkpointResult <- fetchCheckpoint baseUrl aidText
    case checkpointResult of
        Left err -> pure (Left err)
        Right (checkpointFreshness, checkpoint) -> do
            watchabilityResult <- fetchWatchability baseUrl aidText
            pure $ case watchabilityResult of
                Left err -> Left err
                Right (watchabilityFreshness, watchability)
                    | watchabilityFreshness /= checkpointFreshness ->
                        Left (MalformedResponse "checkpoint and watchability freshness disagree between calls")
                    | otherwise ->
                        Right
                            StatusView
                                { svSource = baseUrl
                                , svFreshness = checkpointFreshness
                                , svAid = aidText
                                , svCheckpoint = checkpoint
                                , svWatchability = watchability
                                }

endpointBoardByWitness :: Text -> Text -> IO (Either BackendError (Freshness, Maybe BoardFields))
endpointBoardByWitness baseUrl witnessText = do
    result <- httpGet baseUrl ("/board/" <> T.unpack witnessText)
    pure $ result >>= decodeWith parseBoardResponse

-- ---------------------------------------------------------------------------
-- HTTP transport

httpGet :: Text -> String -> IO (Either BackendError (Int, BSL.ByteString))
httpGet baseUrl path = do
    outcome <- try performRequest
    pure $ case outcome of
        Left (exc :: SomeException) -> Left (UpstreamUnavailable (T.pack (show exc)))
        Right ok -> ok
  where
    performRequest = do
        initial <- parseRequest (T.unpack (T.dropWhileEnd (== '/') baseUrl) <> path)
        response <- httpLBS initial
        pure (Right (getResponseStatusCode response, getResponseBody response))

fetchCheckpoint :: Text -> Text -> IO (Either BackendError (Freshness, Maybe CheckpointFields))
fetchCheckpoint baseUrl aidText = do
    result <- httpGet baseUrl ("/checkpoint/" <> T.unpack aidText)
    pure $ result >>= decodeWith (parseCheckpointResponse aidText)

fetchWatchability :: Text -> Text -> IO (Either BackendError (Freshness, WatchabilityFields))
fetchWatchability baseUrl aidText = do
    result <- httpGet baseUrl ("/watchability/" <> T.unpack aidText)
    pure $ result >>= decodeWith (parseWatchabilityResponse aidText)

decodeWith :: (Value -> Parser a) -> (Int, BSL.ByteString) -> Either BackendError a
decodeWith _ (503, _) = Left (UpstreamUnavailable "endpoint reported not ready (HTTP 503)")
decodeWith parser (200, body) =
    case eitherDecode body of
        Left err -> Left (MalformedResponse ("undecodable JSON body: " <> T.pack err))
        Right value -> either (Left . MalformedResponse . T.pack) Right (parseEither parser value)
decodeWith _ (code, _) = Left (MalformedResponse ("unexpected HTTP status " <> T.pack (show code)))

-- ---------------------------------------------------------------------------
-- Independent wire decode (deliberately not Query.Types' FromJSON)

parseCheckpointResponse :: Text -> Value -> Parser (Freshness, Maybe CheckpointFields)
parseCheckpointResponse expectedAid = Aeson.withObject "CheckpointResponse" $ \obj -> do
    echoedAid <- obj Aeson..: "aid"
    freshness <- parseFreshness obj
    checkpointValue <- obj Aeson..: "checkpoint"
    checkPointMismatch expectedAid echoedAid
    checkpoint <- traverse parseCheckpointData checkpointValue
    checkFreshnessCoherence (freshness, checkpoint)
    pure (freshness, checkpoint)

parseWatchabilityResponse :: Text -> Value -> Parser (Freshness, WatchabilityFields)
parseWatchabilityResponse expectedAid = Aeson.withObject "WatchabilityResponse" $ \obj -> do
    echoedAid <- obj Aeson..: "aid"
    freshness <- parseFreshness obj
    checkPointMismatch expectedAid echoedAid
    watchabilityValue <- obj Aeson..: "watchability"
    watchability <- parseWatchabilityData watchabilityValue
    pure (freshness, watchability)

parseBoardResponse :: Value -> Parser (Freshness, Maybe BoardFields)
parseBoardResponse = Aeson.withObject "BoardResponse" $ \obj -> do
    freshness <- parseFreshness obj
    boardValue <- obj Aeson..: "board"
    board <- traverse parseBoardData boardValue
    pure (freshness, board)

parseFreshness :: Object -> Parser Freshness
parseFreshness obj =
    Freshness
        <$> obj Aeson..: "as_of_slot"
        <*> obj Aeson..: "tip_lag_slots"

checkPointMismatch :: Text -> Text -> Parser ()
checkPointMismatch expected echoed
    | expected == echoed = pure ()
    | otherwise = fail "echoed identifier does not match the requested identifier"

-- | A found checkpoint with no established @as_of_slot@ is an impossible pairing.
checkFreshnessCoherence :: (Freshness, Maybe CheckpointFields) -> Parser ()
checkFreshnessCoherence (Freshness Nothing _, Just _) =
    fail "a checkpoint was returned with no as_of_slot — impossible freshness"
checkFreshnessCoherence _ = pure ()

parseCheckpointData :: Value -> Parser CheckpointFields
parseCheckpointData = Aeson.withObject "CheckpointData" $ \obj ->
    CheckpointFields
        <$> obj Aeson..: "tx_id"
        <*> obj Aeson..: "output_index"
        <*> obj Aeson..: "sequence"
        <*> obj Aeson..: "native_sequence"
        <*> obj Aeson..: "current_keys"
        <*> (obj Aeson..: "current_threshold" >>= parseThresholdJson)
        <*> obj Aeson..: "witnesses"
        <*> obj Aeson..: "witness_threshold"

parseThresholdJson :: Value -> Parser Threshold
parseThresholdJson = Aeson.withObject "ThresholdJson" $ \obj -> do
    kind <- obj Aeson..: "type" :: Parser Text
    case kind of
        "unweighted" -> Unweighted <$> obj Aeson..: "value"
        "weighted" -> do
            clauses <- obj Aeson..: "clauses"
            Weighted <$> traverse (traverse parseWeight) clauses
        other -> fail ("unknown threshold type " <> T.unpack other)

parseWeight :: Value -> Parser Weight
parseWeight = Aeson.withObject "Weight" $ \obj ->
    Weight
        <$> obj Aeson..: "numerator"
        <*> obj Aeson..: "denominator"

parseWatchabilityData :: Value -> Parser WatchabilityFields
parseWatchabilityData = Aeson.withObject "WatchabilityData" $ \obj ->
    WatchabilityFields
        <$> obj Aeson..: "checkpoint_present"
        <*> obj Aeson..: "witnesses_declared"
        <*> obj Aeson..: "witnesses_listed"
        <*> obj Aeson..: "missing_witnesses"

parseBoardData :: Value -> Parser BoardFields
parseBoardData = Aeson.withObject "BoardData" $ \obj ->
    BoardFields
        <$> obj Aeson..: "aid"
        <*> obj Aeson..: "scheme"
        <*> obj Aeson..: "url"
        <*> obj Aeson..: "tx_id"
        <*> obj Aeson..: "output_index"
        <*> obj Aeson..: "lovelace"
        <*> obj Aeson..: "owner_key_hash"
