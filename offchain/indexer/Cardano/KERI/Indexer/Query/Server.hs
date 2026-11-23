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
    ReleaseQueryHandle (..),
    mkReleaseQueryApplication,
) where

import Cardano.KERI.AID.Application (OutputReference (..), RegistryIdentity (..))
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Datum (KeyMaterial (..), KeyStateView (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..), registryIdentityOf)
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    missingBoardWitnesses,
    watchabilityGrade,
 )
import Cardano.KERI.Indexer.Board (indexedBoardCatalog)
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..), Holding (..), HoldingKind (..))
import Cardano.KERI.Indexer.Identity (
    Consumer (..),
    IdentityAnswer (..),
    IdentityRead (..),
    LiveHolding (..),
    answerIdentity,
    consumerOf,
    identityTx,
    unavailableText,
 )
import Cardano.KERI.Indexer.Query.Tx (
    HoldingsRead (..),
    QueryHandle (..),
    boardTx,
    checkpointTx,
    holdingsTx,
    scanAddressTx,
    watchabilityTx,
    watermarkTx,
 )
import Cardano.KERI.Indexer.Query.Types (
    BoardData (..),
    BoardListEntry (..),
    BoardListResponse (..),
    BoardResponse (..),
    CheckpointData (..),
    CheckpointResponse (..),
    Freshness (..),
    IdentityConsumer (..),
    IdentityHolding (..),
    IdentityLiveResponse (..),
    IdentityNotReady (..),
    IdentityRegistry (..),
    IdentityRelease (..),
    IdentityUnavailableResponse (..),
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
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BSL
import Data.List (find)
import Data.Maybe (fromMaybe, isNothing, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
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
    queryString,
    requestMethod,
    responseLBS,
 )
import Paths_cardano_keri (getDataFileName)

-- | The complete #176 Slice 1 WAI application.
mkQueryApplication :: QueryHandle cf op -> Application
mkQueryApplication handle request respond =
    respond =<< route (sampleReadinessStatus handle) Nothing handle request

{- | How a service judges whether it is ready, given the watermark of the response it
has just composed: the manifest service by the fixed threshold, the registry service
by the ceiling it was started with.
-}
type Gate = Maybe SlotNo -> IO ReadinessStatus

{- | The routes shared by both modes, judged by this gate; /ready reports the ceiling
in force when there is one.
-}
route :: Gate -> Maybe Integer -> QueryHandle cf op -> Request -> IO Response
route gate limit handle request =
    case (requestMethod request, pathInfo request) of
        ("GET", ["ready"]) -> handleReady gate limit handle
        ("GET", ["checkpoint", aidText]) -> handleCheckpoint gate handle aidText
        ("GET", ["board"]) -> handleBoardList gate handle
        ("GET", ["board", witnessText]) -> handleBoard gate handle witnessText
        ("GET", ["watchability", aidText]) -> handleWatchability gate handle aidText
        ("GET", ["identity", _]) -> pure identityNotServedResponse
        ("GET", ["swagger.json"]) -> swaggerJsonResponse
        ("GET", ["swagger-ui"]) -> pure swaggerUiResponse
        _ -> pure notFoundResponse

-- ---------------------------------------------------------------------------
-- /ready

handleReady :: Gate -> Maybe Integer -> QueryHandle cf op -> IO Response
handleReady gate limit handle = do
    watermark <- runTransaction (qhRunner handle) watermarkTx
    status <- gate watermark
    pure $
        jsonResponse status200 $
            ReadyResponse
                { readyReady = rsReady status
                , readyFreshness = statusFreshness status
                , readyUpstream = rsUpstream status
                , readyReason = rsReason status
                , readyMaxTipLagSlots = limit
                }

-- ---------------------------------------------------------------------------
-- /checkpoint/{aid}

handleCheckpoint :: Gate -> QueryHandle cf op -> Text -> IO Response
handleCheckpoint gate handle aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            (mRecord, watermark) <- runTransaction (qhRunner handle) (checkpointTx handle aid)
            status <- gate watermark
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

handleBoard :: Gate -> QueryHandle cf op -> Text -> IO Response
handleBoard gate handle witnessText =
    case decodeWitnessKeyParam witnessText of
        Left _ -> pure badRequestResponse
        Right witnessKey -> do
            (catalogResult, watermark) <- runTransaction (qhRunner handle) (boardTx handle)
            case catalogResult of
                Left _ -> pure internalErrorResponse
                Right catalog -> do
                    status <- gate watermark
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
-- /board

handleBoardList :: Gate -> QueryHandle cf op -> IO Response
handleBoardList gate handle = do
    (catalogResult, watermark) <- runTransaction (qhRunner handle) (boardTx handle)
    case catalogResult of
        Left _ -> pure internalErrorResponse
        Right catalog -> do
            status <- gate watermark
            pure $
                if rsReady status
                    then
                        jsonResponse status200 $
                            BoardListResponse
                                { blrFreshness = statusFreshness status
                                , blrBoard = map boardListEntryOf catalog
                                }
                    else unavailableResponse status

boardListEntryOf :: BoardEntry -> BoardListEntry
boardListEntryOf entry =
    BoardListEntry
        { bleWitnessKey = boardWitnessKey entry
        , bleBoard = boardDataOf entry
        }

-- ---------------------------------------------------------------------------
-- /watchability/{aid}

handleWatchability :: Gate -> QueryHandle cf op -> Text -> IO Response
handleWatchability gate handle aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            (mRecord, catalogResult, watermark) <-
                runTransaction (qhRunner handle) (watchabilityTx handle aid)
            case catalogResult of
                Left _ -> pure internalErrorResponse
                Right catalog -> do
                    status <- gate watermark
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
watchabilityDataOf mRecord = watchabilityDataFrom (cdWitnesses . crDatum <$> mRecord)

-- | The watchability of a checkpoint with these declared witnesses ( 'Nothing' when there is no checkpoint) against a board catalog.
watchabilityDataFrom :: Maybe [ByteString] -> [BoardEntry] -> WatchabilityData
watchabilityDataFrom Nothing _ =
    WatchabilityData
        { wdCheckpointPresent = False
        , wdWitnessesDeclared = 0
        , wdWitnessesListed = 0
        , wdMissingWitnesses = []
        }
watchabilityDataFrom (Just declaredWitnesses) catalog =
    WatchabilityData
        { wdCheckpointPresent = True
        , wdWitnessesDeclared = length declaredWitnesses
        , wdWitnessesListed = fst (watchabilityGrade declaredWitnesses catalog)
        , wdMissingWitnesses = missingBoardWitnesses declaredWitnesses catalog
        }

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

-- | The same, against the ceiling of the registry mode.
sampleReadinessAgainst :: Integer -> QueryHandle cf op -> Maybe SlotNo -> IO ReadinessStatus
sampleReadinessAgainst limit handle watermark = do
    readiness <- atomically (qhReadiness handle)
    pure (computeReadinessStatusAgainst (Just limit) watermark readiness)

{- | The verdict of the version 1 routes: a lag of at most the fixed threshold of
sixty slots is ready.
-}
computeReadinessStatus :: Maybe SlotNo -> Readiness -> ReadinessStatus
computeReadinessStatus =
    readinessStatus
        (<= 60)
        (const "tip lag exceeds the 60-slot freshness threshold")

{- | The verdict of a read that answers within a ceiling given by its deployment
(none: the read applies no ceiling of its own, and only an unknown standing makes
it not ready). A lag above the ceiling says the lag and the ceiling.
-}
computeReadinessStatusAgainst :: Maybe Integer -> Maybe SlotNo -> Readiness -> ReadinessStatus
computeReadinessStatusAgainst limit =
    readinessStatus
        (\lag -> maybe True (toInteger lag <=) limit)
        ( \lag ->
            "tip lag "
                <> T.pack (show lag)
                <> " exceeds the ceiling "
                <> maybe "none" (T.pack . show) limit
        )

{- | The shared computation: whether the upstream is connected, the standing is
known, and the lag is within the limit, with the reason when it is not.
-}
readinessStatus :: (Word64 -> Bool) -> (Word64 -> Text) -> Maybe SlotNo -> Readiness -> ReadinessStatus
readinessStatus within beyond watermark readiness =
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
    ready = upstreamConnected && maybe False within tipLag
    reason
        | ready = Nothing
        | not upstreamConnected = Just "upstream disconnected"
        | isNothing watermark = Just "store has no watermark yet"
        | isNothing tip = Just "no tip observed yet"
        | otherwise = case tipLag of
            Nothing -> Just "store watermark is ahead of the observed tip"
            Just lag -> Just (beyond lag)

unavailableResponse :: ReadinessStatus -> Response
unavailableResponse = jsonResponse status503 . notReadyBody

notReadyBody :: ReadinessStatus -> UnavailableResponse
notReadyBody status =
    UnavailableResponse
        { unavailableFreshness = statusFreshness status
        , unavailableUpstream = rsUpstream status
        , unavailableReason = fromMaybe "unavailable" (rsReason status)
        }

-- | The 503 of the identity route: the body of the other data routes, saying besides that it is unavailable.
identityNotReadyResponse :: ReleaseIdentity -> Integer -> ReadinessStatus -> Response
identityNotReadyResponse release limit status =
    jsonResponse status503 $
        IdentityNotReady
            { inrBody = notReadyBody status
            , inrMaxTipLagSlots = limit
            , inrRegistry = identityRegistryOf release
            , inrRelease = identityReleaseOf release
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

-- | The identity route is the registry service's: the manifest mode says so.
identityNotServedResponse :: Response
identityNotServedResponse =
    errorResponse
        status404
        "the identity route is served in release mode only; this service runs in manifest mode"

internalErrorResponse :: Response
internalErrorResponse = errorResponse status500 "internal_error"

{- | The release-identity mode's handle: the release and the ordinary query
handle built from it (the checkpoint address of the release, the state policy,
the board address and the follower's readiness).
-}
data ReleaseQueryHandle cf op = ReleaseQueryHandle
    { rqhRelease :: !ReleaseIdentity
    , rqhQuery :: !(QueryHandle cf op)
    , rqhMaxTipLagSlots :: !Integer
    -- ^ The deployment's ceiling on the tip lag, in slots, of every route of the registry mode.
    }

{- | The query application of the release-identity mode. It has the paths and
response shapes of 'mkQueryApplication'; the checkpoint of an AID is the
classified checkpoint holding of the release, and a pending termination is
served as no checkpoint. The watchability of an AID is read from its classified checkpoint holding: the
witnesses a live checkpoint declares against the board, and no checkpoint when
the AID has none or its holding is a pending termination.
-}
mkReleaseQueryApplication :: ReleaseQueryHandle cf op -> Application
mkReleaseQueryApplication handle request respond =
    respond =<< routeRelease handle request

routeRelease :: ReleaseQueryHandle cf op -> Request -> IO Response
routeRelease handle request =
    case (requestMethod request, pathInfo request) of
        ("GET", ["checkpoint", aidText]) -> handleReleaseCheckpoint handle aidText
        ("GET", ["watchability", aidText]) -> handleReleaseWatchability handle aidText
        ("GET", ["identity", aidText]) -> handleReleaseIdentity handle aidText request
        _ -> route (sampleReadinessAgainst (rqhMaxTipLagSlots handle) (rqhQuery handle)) (Just (rqhMaxTipLagSlots handle)) (rqhQuery handle) request

handleReleaseCheckpoint :: ReleaseQueryHandle cf op -> Text -> IO Response
handleReleaseCheckpoint (ReleaseQueryHandle release query limit) aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            reading <- runTransaction (qhRunner query) (holdingsTx release)
            status <- sampleReadinessAgainst limit query (fst <$> hrPoint reading)
            pure $
                if rsReady status
                    then
                        jsonResponse status200 $
                            CheckpointResponse
                                { crAid = aid
                                , crFreshness = statusFreshness status
                                , crCheckpoint =
                                    listToMaybe
                                        [ checkpoint
                                        | (_, Right holding) <- hrOutputs reading
                                        , holdingAid holding == qb64Aid aid
                                        , Just checkpoint <- [checkpointDataOfHolding holding]
                                        ]
                                }
                    else unavailableResponse status

handleReleaseWatchability :: ReleaseQueryHandle cf op -> Text -> IO Response
handleReleaseWatchability (ReleaseQueryHandle release query limit) aidText =
    case decodeAidParam aidText of
        Left _ -> pure badRequestResponse
        Right aid -> do
            (reading, catalogResult) <- runTransaction (qhRunner query) $ do
                holdings <- holdingsTx release
                boardEntries <- scanAddressTx (qhBoardAddress query)
                pure (holdings, indexedBoardCatalog (qhBoardAddress query) boardEntries)
            case catalogResult of
                Left _ -> pure internalErrorResponse
                Right catalog -> do
                    status <- sampleReadinessAgainst limit query (fst <$> hrPoint reading)
                    pure $
                        if rsReady status
                            then
                                jsonResponse status200 $
                                    WatchabilityResponse
                                        { wrAid = aid
                                        , wrFreshness = statusFreshness status
                                        , wrWatchability =
                                            watchabilityDataFrom
                                                ( listToMaybe
                                                    [ kmWitnesses keys
                                                    | (_, Right holding) <- hrOutputs reading
                                                    , holdingAid holding == qb64Aid aid
                                                    , HeldCheckpoint{hcKeys = keys} <- [holdingKind holding]
                                                    ]
                                                )
                                                catalog
                                        }
                            else unavailableResponse status

-- | The checkpoint a holding is, if it is one: a pending termination is none.
checkpointDataOfHolding :: Holding -> Maybe CheckpointData
checkpointDataOfHolding Holding{holdingTxIn, holdingSn, holdingEpoch, holdingKind} =
    case holdingKind of
        HeldCheckpoint{hcKeys = KeyMaterial{..}} ->
            Just
                CheckpointData
                    { chkTxId = Indexer.txInId holdingTxIn
                    , chkOutputIndex = fromIntegral (Indexer.txInIx holdingTxIn)
                    , chkSequence = holdingEpoch
                    , chkNativeSequence = holdingSn
                    , chkCurrentKeys = kmCurKeys
                    , chkCurrentThreshold = kmCurThreshold
                    , chkNextKeyDigests = kmNextKeys
                    , chkNextThreshold = kmNextThreshold
                    , chkWitnesses = kmWitnesses
                    , chkWitnessThreshold = kmToad
                    }
        HeldPendingTermination -> Nothing

{- | @GET \/identity\/{aid}@ in the release-identity mode: the AID's checked live
holding at the store's chain point, with the consumer result beside it, or
@unavailable@ with its reason. One store transaction reads the holdings and the
chain point; readiness is sampled after it, and a service that is not ready
answers the same 503 as the other data routes. A malformed AID, or a
@window_ms@ or @now_ms@ that is not a non-negative integer, is a 400.
-}
handleReleaseIdentity :: ReleaseQueryHandle cf op -> Text -> Request -> IO Response
handleReleaseIdentity (ReleaseQueryHandle release query limit) aidText request =
    case (decodeAidParam aidText, consumerParameters request) of
        (Left _, _) -> pure badRequestResponse
        (_, Left ()) -> pure malformedParameterResponse
        (Right aid, Right parameters) -> do
            reading <- runTransaction (qhRunner query) (identityTx release aid)
            status <- sampleReadinessAgainst limit query (fst <$> irPoint reading)
            pure $ case (rsReady status, irPoint reading) of
                (True, Just (_, Indexer.BlockHash blockHash)) ->
                    case answerIdentity reading of
                        Live live ->
                            jsonResponse status200 $
                                identityLiveResponse release limit aid (statusFreshness status) blockHash parameters live
                        NotLive why ->
                            jsonResponse status200 $
                                IdentityUnavailableResponse
                                    { iuAid = TE.decodeUtf8 (qb64Aid aid)
                                    , iuFreshness = statusFreshness status
                                    , iuMaxTipLagSlots = limit
                                    , iuBlockHash = blockHash
                                    , iuRegistry = identityRegistryOf release
                                    , iuRelease = identityReleaseOf release
                                    , iuReason = unavailableText why
                                    }
                _ -> identityNotReadyResponse release limit status

{- | The two optional parameters of the consumer result: both, or neither, or a
refusal when one of them is present and no non-negative integer. A lone one
leaves the result not evaluated.
-}
consumerParameters :: Request -> Either () (Maybe (Integer, Integer))
consumerParameters request = do
    window <- parameter "window_ms"
    now <- parameter "now_ms"
    pure ((,) <$> window <*> now)
  where
    parameter name = case lookup name (queryString request) of
        Nothing -> Right Nothing
        Just Nothing -> Left ()
        Just (Just value) -> case BC.readInteger value of
            Just (n, rest) | BS.null rest, n >= 0 -> Right (Just n)
            _ -> Left ()

malformedParameterResponse :: Response
malformedParameterResponse = errorResponse status400 "malformed_parameter"

identityLiveResponse ::
    ReleaseIdentity ->
    Integer ->
    ByteString ->
    Freshness ->
    ByteString ->
    Maybe (Integer, Integer) ->
    LiveHolding ->
    IdentityLiveResponse
identityLiveResponse release limit aid freshness blockHash parameters live =
    IdentityLiveResponse
        { ilrAid = TE.decodeUtf8 (qb64Aid aid)
        , ilrFreshness = freshness
        , ilrMaxTipLagSlots = limit
        , ilrBlockHash = blockHash
        , ilrRegistry = identityRegistryOf release
        , ilrRelease = identityReleaseOf release
        , ilrHolding =
            IdentityHolding
                { ihTxId = Indexer.txInId (lhTxIn live)
                , ihOutputIndex = fromIntegral (Indexer.txInIx (lhTxIn live))
                , ihSn = lhSn live
                , ihEpoch = lhEpoch live
                , ihPoisoned = lhPoisoned live
                , ihFrozen = lhFrozen live
                , ihToppedUp = lhToppedUp live
                , ihBornAt = lhBornAt live
                , ihRefundAddress = lhRefund live
                , ihDeposit = lhDeposit live
                , ihFreezeBond = lhFreezeBond live
                , ihPool = lhPool live
                , ihLovelace = lhLovelace live
                , ihKeys = lhKeys live
                }
        , ilrConsumer = case consumerOf release aid parameters live of
            NotEvaluated reason -> ConsumerNotEvaluated reason
            Evaluated failed -> ConsumerEvaluated (null failed) (map (T.pack . show) failed)
        }

-- | The registry a release names, as the identity answers give it.
identityRegistryOf :: ReleaseIdentity -> IdentityRegistry
identityRegistryOf release =
    IdentityRegistry
        { irgStatePolicy = registryStatePolicy registry
        , irgStateTokenName = registryName registry
        , irgSeedTxId = seedTx
        , irgSeedOutputIndex = seedIndex
        }
  where
    registry = registryIdentityOf release
    OutputReference seedTx seedIndex = riSeed release

-- | The four identities of the release, as the identity answers give them.
identityReleaseOf :: ReleaseIdentity -> IdentityRelease
identityReleaseOf release =
    IdentityRelease
        { irlApplicationPolicy = rlApplicationPolicy application
        , irlApplicationCredential = rlApplicationCredential application
        , irlStateProgram = rlStateProgram application
        , irlStatePolicy = rlStatePolicy application
        }
  where
    application = riRelease release
