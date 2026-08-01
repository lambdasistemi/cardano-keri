{- |
Module      : Cardano.KERI.Indexer.Query.Server
Description : #176 Slice 1 WAI application — the public query endpoint

Implements the frozen contract from @specs\/176-query-endpoint\/spec.md@
(base @0c11bf2@): the six public routes, the common freshness gate, and the
400\/503\/500 mapping. Every data route runs exactly one composed
'Cardano.KERI.Indexer.Query.Tx' transaction, then samples readiness /after/
that transaction commits — FR-3's provenance boundary. @as_of_slot@ always
comes from the transactional rollback-log watermark
('Cardano.KERI.Indexer.Query.Tx.watermarkTx'), never from
'Cardano.Node.Client.UTxOIndexer.Follower.Readiness.rProcessedSlot': a
rollback changes the store before the follower's readiness TVar catches up,
so sourcing the watermark from readiness would publish a false, too-high
@as_of_slot@ and let a rolled-back record survive in the response. Readiness
supplies only the tip (for lag) and the upstream/veto decision.

This module owns no mutable state — no 'Data.IORef.IORef',
'Control.Concurrent.MVar.MVar', or extra 'Control.Concurrent.STM.TVar'
besides the ones threaded in from outside via 'Cardano.KERI.Indexer.Query.Tx.QueryHandle'
and the readiness sample — so a rollback invalidates the next answer by
construction (FR-4).
-}
module Cardano.KERI.Indexer.Query.Server (
    mkQueryApplication,
) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    missingBoardWitnesses,
    watchabilityGrade,
 )
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..))
import Cardano.KERI.Indexer.Query.Tx (
    QueryHandle (..),
    boardTx,
    checkpointTx,
    watchabilityTx,
    watermarkTx,
 )
import Cardano.KERI.Indexer.Query.Types (
    BoardData (..),
    BoardResponse (..),
    CheckpointData (..),
    CheckpointResponse (..),
    Freshness (..),
    ReadyResponse (..),
    UnavailableResponse (..),
    WatchabilityData (..),
    WatchabilityResponse (..),
 )
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Types (SlotNo (..))
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (atomically)
import Data.Aeson (ToJSON, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.List (find)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Database.KV.Transaction (RunTransaction (..))
import Network.HTTP.Types (
    Status,
    hContentType,
    status200,
    status400,
    status404,
    status500,
    status503,
 )
import Network.Wai (
    Application,
    Request,
    Response,
    pathInfo,
    requestMethod,
    responseLBS,
 )
import Paths_cardano_keri (getDataFileName)

-- | The complete #176 Slice 1 WAI application.
mkQueryApplication :: QueryHandle cf op -> Application
mkQueryApplication handle request respond =
    respond =<< route handle request

route :: QueryHandle cf op -> Request -> IO Response
route handle request =
    case (requestMethod request, pathInfo request) of
        ("GET", ["ready"]) -> handleReady handle
        ("GET", ["checkpoint", aidText]) -> handleCheckpoint handle aidText
        ("GET", ["board", witnessText]) -> handleBoard handle witnessText
        ("GET", ["watchability", aidText]) -> handleWatchability handle aidText
        ("GET", ["swagger.json"]) -> swaggerJsonResponse
        ("GET", ["swagger-ui"]) -> pure swaggerUiResponse
        _ -> pure notFoundResponse

-- ---------------------------------------------------------------------------
-- /ready

handleReady :: QueryHandle cf op -> IO Response
handleReady handle = do
    watermark <- runTransaction (qhRunner handle) watermarkTx
    status <- sampleReadinessStatus handle watermark
    pure $
        jsonResponse status200 $
            ReadyResponse
                { readyReady = rsReady status
                , readyFreshness = statusFreshness status
                , readyUpstream = rsUpstream status
                , readyReason = rsReason status
                }

-- ---------------------------------------------------------------------------
-- /checkpoint/{aid}

handleCheckpoint :: QueryHandle cf op -> Text -> IO Response
handleCheckpoint handle aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            (mRecord, watermark) <- runTransaction (qhRunner handle) (checkpointTx handle aid)
            status <- sampleReadinessStatus handle watermark
            pure $
                if rsReady status
                    then
                        jsonResponse status200 $
                            CheckpointResponse
                                { crAid = aid
                                , crFreshness = statusFreshness status
                                , crCheckpoint = checkpointDataOf <$> mRecord
                                }
                    else unavailableResponse status

checkpointDataOf :: CheckpointRecord -> CheckpointData
checkpointDataOf record =
    CheckpointData
        { chkTxId = Indexer.txInId txIn
        , chkOutputIndex = fromIntegral (Indexer.txInIx txIn)
        , chkSequence = cdSeq datum
        , chkNativeSequence = cdNativeSn datum
        , chkCurrentKeys = cdCurKeys datum
        , chkCurrentThreshold = cdCurThreshold datum
        , chkNextKeyDigests = cdNextKeys datum
        , chkNextThreshold = cdNextThreshold datum
        , chkWitnesses = cdWitnesses datum
        , chkWitnessThreshold = cdToad datum
        }
  where
    txIn = crTxIn record
    datum = crDatum record

-- ---------------------------------------------------------------------------
-- /board/{witness_key}

handleBoard :: QueryHandle cf op -> Text -> IO Response
handleBoard handle witnessText =
    case decodeWitnessKeyParam witnessText of
        Left _ -> pure badRequestResponse
        Right witnessKey -> do
            (catalogResult, watermark) <- runTransaction (qhRunner handle) (boardTx handle)
            case catalogResult of
                Left _ -> pure internalErrorResponse
                Right catalog -> do
                    status <- sampleReadinessStatus handle watermark
                    pure $
                        if rsReady status
                            then
                                jsonResponse status200 $
                                    BoardResponse
                                        { brWitnessKey = witnessKey
                                        , brFreshness = statusFreshness status
                                        , brBoard =
                                            boardDataOf
                                                <$> find
                                                    ((== witnessKey) . boardWitnessKey)
                                                    catalog
                                        }
                            else unavailableResponse status

boardDataOf :: BoardEntry -> BoardData
boardDataOf entry =
    BoardData
        { bdAid = boardAid entry
        , bdScheme = boardScheme entry
        , bdUrl = boardUrl entry
        , bdTxId = boardTxId entry
        , bdOutputIndex = boardIndex entry
        , bdLovelace = boardLovelace entry
        , bdOwnerKeyHash = boardOwnerKeyHash entry
        }

-- ---------------------------------------------------------------------------
-- /watchability/{aid}

handleWatchability :: QueryHandle cf op -> Text -> IO Response
handleWatchability handle aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            (mRecord, catalogResult, watermark) <-
                runTransaction (qhRunner handle) (watchabilityTx handle aid)
            case catalogResult of
                Left _ -> pure internalErrorResponse
                Right catalog -> do
                    status <- sampleReadinessStatus handle watermark
                    pure $
                        if rsReady status
                            then
                                jsonResponse status200 $
                                    WatchabilityResponse
                                        { wrAid = aid
                                        , wrFreshness = statusFreshness status
                                        , wrWatchability = watchabilityDataOf mRecord catalog
                                        }
                            else unavailableResponse status

watchabilityDataOf :: Maybe CheckpointRecord -> [BoardEntry] -> WatchabilityData
watchabilityDataOf Nothing _ =
    WatchabilityData
        { wdCheckpointPresent = False
        , wdWitnessesDeclared = 0
        , wdWitnessesListed = 0
        , wdMissingWitnesses = []
        }
watchabilityDataOf (Just record) catalog =
    WatchabilityData
        { wdCheckpointPresent = True
        , wdWitnessesDeclared = length declaredWitnesses
        , wdWitnessesListed = fst (watchabilityGrade declaredWitnesses catalog)
        , wdMissingWitnesses = missingBoardWitnesses declaredWitnesses catalog
        }
  where
    declaredWitnesses = cdWitnesses (crDatum record)

-- ---------------------------------------------------------------------------
-- Swagger

-- | Serve the committed @docs\/assets\/swagger\/query-api.json@ verbatim.
swaggerJsonResponse :: IO Response
swaggerJsonResponse = do
    path <- getDataFileName "docs/assets/swagger/query-api.json"
    bytes <- BSL.readFile path
    pure (responseLBS status200 [(hContentType, "application/json")] bytes)

swaggerUiResponse :: Response
swaggerUiResponse =
    responseLBS status200 [(hContentType, "text/html; charset=utf-8")] swaggerUiHtml

{- | A minimal, self-contained Swagger UI shell loading the CDN-distributed
@swagger-ui-dist@ bundle against this service's own @\/swagger.json@. No
route/JSON generation logic lives here — the UI is purely a static viewer.
-}
swaggerUiHtml :: BSL.ByteString
swaggerUiHtml =
    "<!DOCTYPE html>\
    \<html><head><title>ckeri-query API</title>\
    \<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist/swagger-ui.css\" />\
    \</head><body><div id=\"swagger-ui\"></div>\
    \<script src=\"https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js\"></script>\
    \<script>window.onload = function() { window.ui = SwaggerUIBundle({ url: \"/swagger.json\", dom_id: \"#swagger-ui\" }); };</script>\
    \</body></html>"

-- ---------------------------------------------------------------------------
-- Readiness gate (FR-3)

-- | The decoded freshness/veto verdict for one composed response.
data ReadinessStatus = ReadinessStatus
    { rsReady :: !Bool
    , rsAsOfSlot :: !(Maybe Word64)
    , rsTipLag :: !(Maybe Word64)
    , rsUpstream :: !Text
    , rsReason :: !(Maybe Text)
    }

statusFreshness :: ReadinessStatus -> Freshness
statusFreshness status = Freshness (rsAsOfSlot status) (rsTipLag status)

{- | Sample readiness /after/ the caller's composed transaction has already
committed and produced @watermark@, and combine them into one gate verdict.
-}
sampleReadinessStatus :: QueryHandle cf op -> Maybe SlotNo -> IO ReadinessStatus
sampleReadinessStatus handle watermark = do
    readiness <- atomically (qhReadiness handle)
    pure (computeReadinessStatus watermark readiness)

computeReadinessStatus :: Maybe SlotNo -> Readiness -> ReadinessStatus
computeReadinessStatus watermark readiness =
    ReadinessStatus
        { rsReady = ready
        , rsAsOfSlot = slotWord <$> watermark
        , rsTipLag = tipLag
        , rsUpstream = upstreamText
        , rsReason = reason
        }
  where
    tip = rTipSlot readiness
    upstreamConnected = case rUpstream readiness of
        UpstreamConnected -> True
        UpstreamDisconnected _ -> False
    upstreamText = if upstreamConnected then "connected" else "disconnected"
    slotWord (SlotNo w) = w
    tipLag = do
        watermarkWord <- slotWord <$> watermark
        tipWord <- slotWord <$> tip
        if tipWord >= watermarkWord then Just (tipWord - watermarkWord) else Nothing
    ready = upstreamConnected && maybe False (<= 60) tipLag
    reason
        | ready = Nothing
        | not upstreamConnected = Just "upstream disconnected"
        | isNothing watermark = Just "store has no watermark yet"
        | isNothing tip = Just "no tip observed yet"
        | isNothing tipLag = Just "store watermark is ahead of the observed tip"
        | otherwise = Just "tip lag exceeds the 60-slot freshness threshold"

unavailableResponse :: ReadinessStatus -> Response
unavailableResponse status =
    jsonResponse status503 $
        UnavailableResponse
            { unavailableFreshness = statusFreshness status
            , unavailableUpstream = rsUpstream status
            , unavailableReason = fromMaybe "unavailable" (rsReason status)
            }

-- ---------------------------------------------------------------------------
-- CESR path-parameter decoding

decodeAidParam :: Text -> Either String ByteString
decodeAidParam txt =
    case parsePrimitive (TE.encodeUtf8 txt) of
        Right (SelfAddressing digest, trailing) | BS.null trailing -> Right digest
        _ -> Left "malformed AID"

decodeWitnessKeyParam :: Text -> Either String ByteString
decodeWitnessKeyParam txt
    | BS.take 1 bytes /= "B" = Left "malformed witness key"
    | otherwise = case parsePrimitive bytes of
        Right (Ed25519PublicKey key, trailing) | BS.null trailing -> Right key
        _ -> Left "malformed witness key"
  where
    bytes = TE.encodeUtf8 txt

-- ---------------------------------------------------------------------------
-- Generic response helpers

jsonResponse :: (ToJSON a) => Status -> a -> Response
jsonResponse status value =
    responseLBS status [(hContentType, "application/json")] (encode value)

errorResponse :: Status -> Text -> Response
errorResponse status msg =
    responseLBS status [(hContentType, "application/json")] (encode (object ["error" .= msg]))

badRequestResponse :: Response
badRequestResponse = errorResponse status400 "malformed_identifier"

notFoundResponse :: Response
notFoundResponse = errorResponse status404 "not_found"

internalErrorResponse :: Response
internalErrorResponse = errorResponse status500 "internal_error"
