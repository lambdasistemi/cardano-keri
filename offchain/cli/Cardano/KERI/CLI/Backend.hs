{-# LANGUAGE ApplicativeDo #-}

{- |
Module      : Cardano.KERI.CLI.Backend
Description : #177 Slice 1 typed query backend seam

One typed interface (FR-1) for the checkpoint/watchability read @ckeri
status@ needs, plus board-by-witness for interface completeness. Every
successful answer is rendered through the one 'StatusView' shape (FR-2..FR-4:
honest 'Freshness', no adapter-specific label ever leaks through). Backend
selection ('selectBackend') is pure and total: exactly one backend is chosen
or a closed 'BackendError' is returned — never a silent fallback (FR-5).
-}
module Cardano.KERI.CLI.Backend (
    -- * Freshness / rendered envelope
    Freshness (..),
    CheckpointFields (..),
    CheckpointListItem (..),
    CheckpointListView (..),
    CheckpointView (..),
    PayerUtxoFields (..),
    PayerView (..),
    BoardFields (..),
    WatchabilityFields (..),
    StatusView (..),
    renderStatusView,
    renderCheckpointListView,
    renderCheckpointView,
    renderPayerView,

    -- * Errors
    BackendError (..),
    renderBackendError,

    -- * The interface
    QueryBackend (..),
    runBackendListCheckpoints,
    runBackendCheckpointByAid,
    runBackendPayerUtxos,
    runBackendStatus,

    -- * Selection / configuration
    Backend (..),
    BackendSettings (..),
    BackendCommonSettings (..),
    ListSettings (..),
    CheckpointSettings (..),
    PayerSettings (..),
    SelectedBackend (..),
    selectBackend,
    selectCommonBackend,
    backendSettingsParser,
    listSettingsParser,
    checkpointSettingsParser,
    payerSettingsParser,
    backendCommonSettings,

    -- * Dispatch
    resolveBackend,
) where

import Cardano.KERI.AID.CESR (Primitive (SelfAddressing), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.Deployment.ChainIndex (KoiosToken (..))
import Cardano.KERI.Indexer.Config (decodeAddress)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import OptEnvConf qualified as Opt

-- ---------------------------------------------------------------------------
-- Freshness / rendered envelope (FR-2..FR-4)

-- | Common freshness pair every successful answer carries.
data Freshness = Freshness
    { freshAsOfSlot :: !(Maybe Word64)
    , freshTipLagSlots :: !(Maybe Word64)
    }
    deriving stock (Show, Eq)

-- | The nullable checkpoint payload, backend-agnostic (already qb64/hex text).
data CheckpointFields = CheckpointFields
    { cfTxId :: !Text
    , cfOutputIndex :: !Int
    , cfSequence :: !Integer
    , cfNativeSequence :: !Integer
    , cfCurrentKeys :: ![Text]
    , cfCurrentThreshold :: !Threshold
    , cfWitnesses :: ![Text]
    , cfWitnessThreshold :: !Integer
    }
    deriving stock (Show, Eq)

-- | One live checkpoint in a catalog result.
data CheckpointListItem = CheckpointListItem
    { cliAid :: !Text
    , cliCheckpoint :: !CheckpointFields
    }
    deriving stock (Show, Eq)

-- | Production rendering envelope for one checkpoint-list observation.
data CheckpointListView = CheckpointListView
    { clvSource :: !Text
    , clvFreshness :: !Freshness
    , clvCheckpoints :: ![CheckpointListItem]
    }
    deriving stock (Show, Eq)

-- | Production rendering envelope for one checkpoint-by-AID observation.
data CheckpointView = CheckpointView
    { cvSource :: !Text
    , cvFreshness :: !Freshness
    , cvAid :: !Text
    , cvCheckpoint :: !(Maybe CheckpointFields)
    }
    deriving stock (Show, Eq)

-- | A payer UTxO's stable cross-backend identity.
data PayerUtxoFields = PayerUtxoFields
    { pufTxId :: !Text
    , pufOutputIndex :: !Int
    }
    deriving stock (Show, Eq)

-- | Production rendering envelope for one payer-address observation.
data PayerView = PayerView
    { pvSource :: !Text
    , pvFreshness :: !Freshness
    , pvAddress :: !Text
    , pvUtxos :: ![PayerUtxoFields]
    }
    deriving stock (Show, Eq)

-- | The nullable board-by-witness payload.
data BoardFields = BoardFields
    { bfAid :: !Text
    , bfScheme :: !Text
    , bfUrl :: !Text
    , bfTxId :: !Text
    , bfOutputIndex :: !Int
    , bfLovelace :: !Integer
    , bfOwnerKeyHash :: !Text
    }
    deriving stock (Show, Eq)

-- | The non-nullable watchability payload.
data WatchabilityFields = WatchabilityFields
    { wfCheckpointPresent :: !Bool
    , wfWitnessesDeclared :: !Int
    , wfWitnessesListed :: !Int
    , wfMissingWitnesses :: ![Text]
    }
    deriving stock (Show, Eq)

-- | The one stable rendered envelope every backend's status answer produces.
data StatusView = StatusView
    { svSource :: !Text
    , svFreshness :: !Freshness
    , svAid :: !Text
    , svCheckpoint :: !(Maybe CheckpointFields)
    , svWatchability :: !WatchabilityFields
    }
    deriving stock (Show, Eq)

-- | Human-readable rendering; every adapter's answer goes through this one.
renderStatusView :: StatusView -> Text
renderStatusView view =
    T.unwords $
        [ "source"
        , svSource view
        , "as_of_slot"
        , maybe "unknown" (T.pack . show) (freshAsOfSlot $ svFreshness view)
        , "tip_lag_slots"
        , maybe "unknown" (T.pack . show) (freshTipLagSlots $ svFreshness view)
        , "aid"
        , svAid view
        ]
            <> checkpointWords (svCheckpoint view)
            <> watchabilityWords (svWatchability view)
  where
    watchabilityWords wf =
        [ "watchable"
        , T.pack (show $ wfWitnessesListed wf)
            <> "/"
            <> T.pack (show $ wfWitnessesDeclared wf)
        ]

renderCheckpointListView :: CheckpointListView -> Text
renderCheckpointListView view =
    T.intercalate "\n" $
        operationHeader (clvSource view) (clvFreshness view)
            <> ["count " <> T.pack (show (length (clvCheckpoints view)))]
            <> map renderItem (clvCheckpoints view)
  where
    renderItem item =
        T.unwords (["aid", cliAid item] <> checkpointWords (Just (cliCheckpoint item)))

renderCheckpointView :: CheckpointView -> Text
renderCheckpointView view =
    T.intercalate "\n" $
        operationHeader (cvSource view) (cvFreshness view)
            <> [T.unwords (["aid", cvAid view] <> checkpointWords (cvCheckpoint view))]

renderPayerView :: PayerView -> Text
renderPayerView view =
    T.intercalate "\n" $
        operationHeader (pvSource view) (pvFreshness view)
            <> ["address " <> pvAddress view <> " count " <> T.pack (show (length (pvUtxos view)))]
            <> map renderUtxo (pvUtxos view)
  where
    renderUtxo utxo =
        "tx " <> pufTxId utxo <> "#" <> T.pack (show (pufOutputIndex utxo))

operationHeader :: Text -> Freshness -> [Text]
operationHeader source freshness =
    [ T.unwords
        [ "source"
        , source
        , "as_of_slot"
        , maybe "unknown" (T.pack . show) (freshAsOfSlot freshness)
        , "tip_lag_slots"
        , maybe "unknown" (T.pack . show) (freshTipLagSlots freshness)
        ]
    ]

checkpointWords :: Maybe CheckpointFields -> [Text]
checkpointWords Nothing = ["state", "NOT", "REGISTERED"]
checkpointWords (Just cf) =
    [ "state"
    , "ACTIVE"
    , "seq"
    , T.pack (show $ cfSequence cf)
    , "native"
    , T.pack (show $ cfNativeSequence cf)
    , "keys"
    , renderThreshold (cfCurrentThreshold cf) (length $ cfCurrentKeys cf)
    , "witnesses"
    , T.pack (show $ length $ cfWitnesses cf)
    , "(toad"
    , T.pack (show $ cfWitnessThreshold cf) <> ")"
    , "tx"
    , cfTxId cf <> "#" <> T.pack (show $ cfOutputIndex cf)
    ]

renderThreshold :: Threshold -> Int -> Text
renderThreshold (Unweighted required) keyCount =
    T.pack (show required <> "-of-" <> show keyCount)
renderThreshold (Weighted _) keyCount =
    "weighted-" <> T.pack (show keyCount)

-- ---------------------------------------------------------------------------
-- Errors (FR-3, FR-5)

{- | Every closed failure a backend can report. There is deliberately no
constructor that could carry a partial/successful-looking payload.
-}
data BackendError
    = ConfigError !Text
    | UpstreamUnavailable !Text
    | MalformedResponse !Text
    | UnsupportedCapability !Text
    deriving stock (Show, Eq)

renderBackendError :: BackendError -> Text
renderBackendError = \case
    ConfigError msg -> "config: " <> msg
    UpstreamUnavailable msg -> "unavailable: " <> msg
    MalformedResponse msg -> "malformed: " <> msg
    UnsupportedCapability msg -> "unsupported: " <> msg

-- ---------------------------------------------------------------------------
-- The interface (FR-1)

{- | One selected adapter's operations. 'qbStatus' is the one coherent
checkpoint+watchability observation 'runBackendStatus' renders; a fresh
'qbBoardByWitness' call exists for interface completeness (FR-1) even though
production @status@ never invokes it.
-}
data QueryBackend = QueryBackend
    { qbSourceLabel :: !Text
    , qbStatus :: !(Text -> IO (Either BackendError StatusView))
    , qbBoardByWitness ::
        !(Text -> IO (Either BackendError (Freshness, Maybe BoardFields)))
    , qbListCheckpoints ::
        !(IO (Either BackendError (Freshness, [CheckpointListItem])))
    , qbCheckpointByAid ::
        !(Text -> IO (Either BackendError (Freshness, Maybe CheckpointFields)))
    , qbPayerUtxos ::
        !(Text -> IO (Either BackendError (Freshness, [PayerUtxoFields])))
    }

-- | Dispatch exactly one operation on the selected backend. Never falls through.
runBackendStatus :: QueryBackend -> Text -> IO (Either BackendError StatusView)
runBackendStatus = qbStatus

runBackendListCheckpoints :: QueryBackend -> IO (Either BackendError (Freshness, [CheckpointListItem]))
runBackendListCheckpoints = qbListCheckpoints

runBackendCheckpointByAid :: QueryBackend -> Text -> IO (Either BackendError (Freshness, Maybe CheckpointFields))
runBackendCheckpointByAid backend aidText =
    case decodeAidText aidText of
        Left err -> pure (Left (MalformedResponse err))
        Right () -> qbCheckpointByAid backend aidText

runBackendPayerUtxos :: QueryBackend -> Text -> IO (Either BackendError (Freshness, [PayerUtxoFields]))
runBackendPayerUtxos backend addressText =
    case decodeAddress addressText of
        Left err -> pure (Left (MalformedResponse (T.pack err)))
        Right _ -> qbPayerUtxos backend addressText

decodeAidText :: Text -> Either Text ()
decodeAidText aidText =
    case parsePrimitive (TE.encodeUtf8 aidText) of
        Right (SelfAddressing _, rest)
            | BS.null rest -> Right ()
        _ -> Left "AID must be one 44-character KERI E-code identifier"

-- ---------------------------------------------------------------------------
-- Selection / configuration

data Backend = BackendLocal | BackendEndpoint | BackendKoios
    deriving stock (Show, Eq)

data BackendSettings = BackendSettings
    { backendAid :: !Text
    , backendExplicit :: !(Maybe Backend)
    , backendEndpointUrl :: !(Maybe Text)
    , backendStorePath :: !(Maybe FilePath)
    , backendManifest :: !FilePath
    , backendBoardManifest :: !FilePath
    , backendKoiosUrl :: !Text
    , backendKoiosToken :: !(Maybe KoiosToken)
    }
    deriving stock (Show, Eq)

-- | Backend selection and adapter construction shared by every query command.
data BackendCommonSettings = BackendCommonSettings
    { commonBackendExplicit :: !(Maybe Backend)
    , commonBackendEndpointUrl :: !(Maybe Text)
    , commonBackendStorePath :: !(Maybe FilePath)
    , commonBackendManifest :: !FilePath
    , commonBackendBoardManifest :: !FilePath
    , commonBackendKoiosUrl :: !Text
    , commonBackendKoiosToken :: !(Maybe KoiosToken)
    }
    deriving stock (Show, Eq)

newtype ListSettings = ListSettings
    { listBackendSettings :: BackendCommonSettings
    }
    deriving stock (Show, Eq)

data CheckpointSettings = CheckpointSettings
    { checkpointAid :: !Text
    , checkpointBackendSettings :: !BackendCommonSettings
    }
    deriving stock (Show, Eq)

data PayerSettings = PayerSettings
    { payerAddress :: !Text
    , payerBackendSettings :: !BackendCommonSettings
    }
    deriving stock (Show, Eq)

-- | The exactly-one-backend outcome of 'selectBackend'.
data SelectedBackend
    = SelectedLocal !FilePath
    | SelectedEndpoint !Text
    | SelectedKoios !Text !(Maybe KoiosToken)
    deriving stock (Show, Eq)

{- | Deterministic, total selection (spec.md "Selection rules"): explicit
@--backend@ wins; otherwise @--endpoint@ alone selects @endpoint@; otherwise
the default is @koios@. A flag for a backend other than the one selected is
rejected rather than silently ignored (FR-5's "no implicit fallback" starts
here, at configuration time).
-}
selectBackend :: BackendSettings -> Either BackendError SelectedBackend
selectBackend = selectCommonBackend . backendCommonSettings

selectCommonBackend :: BackendCommonSettings -> Either BackendError SelectedBackend
selectCommonBackend settings =
    case (commonBackendExplicit settings, commonBackendEndpointUrl settings, commonBackendStorePath settings) of
        (Just BackendLocal, Nothing, Just store) -> Right (SelectedLocal store)
        (Just BackendLocal, Just _, _) -> crossFlag "local" "--endpoint"
        (Just BackendLocal, Nothing, Nothing) -> missingFlag "local" "--store"
        (Just BackendEndpoint, Just url, Nothing) -> Right (SelectedEndpoint url)
        (Just BackendEndpoint, Nothing, _) -> missingFlag "endpoint" "--endpoint"
        (Just BackendEndpoint, Just _, Just _) -> crossFlag "endpoint" "--store"
        (Just BackendKoios, Nothing, Nothing) -> Right (koiosSelection settings)
        (Just BackendKoios, Just _, _) -> crossFlag "koios" "--endpoint"
        (Just BackendKoios, _, Just _) -> crossFlag "koios" "--store"
        (Nothing, Just url, Nothing) -> Right (SelectedEndpoint url)
        (Nothing, Just _, Just _) -> crossFlag "endpoint" "--store"
        (Nothing, Nothing, Nothing) -> Right (koiosSelection settings)
        (Nothing, Nothing, Just _) -> missingFlag "koios (the default)" "--backend local"
  where
    crossFlag backend flag =
        Left $
            ConfigError $
                "--backend " <> backend <> " rejects " <> flag <> "; it belongs to a different backend"
    missingFlag backend flag =
        Left $ ConfigError $ "--backend " <> backend <> " requires " <> flag

koiosSelection :: BackendCommonSettings -> SelectedBackend
koiosSelection settings =
    SelectedKoios (commonBackendKoiosUrl settings) (commonBackendKoiosToken settings)

backendSettingsParser :: Opt.Parser BackendSettings
backendSettingsParser = do
    backendAid <- aidSetting
    common <- commonBackendSettingsParser
    pure
        BackendSettings
            { backendAid
            , backendExplicit = commonBackendExplicit common
            , backendEndpointUrl = commonBackendEndpointUrl common
            , backendStorePath = commonBackendStorePath common
            , backendManifest = commonBackendManifest common
            , backendBoardManifest = commonBackendBoardManifest common
            , backendKoiosUrl = commonBackendKoiosUrl common
            , backendKoiosToken = commonBackendKoiosToken common
            }

listSettingsParser :: Opt.Parser ListSettings
listSettingsParser = ListSettings <$> commonBackendSettingsParser

checkpointSettingsParser :: Opt.Parser CheckpointSettings
checkpointSettingsParser = CheckpointSettings <$> aidSetting <*> commonBackendSettingsParser

payerSettingsParser :: Opt.Parser PayerSettings
payerSettingsParser = PayerSettings <$> addressSetting <*> commonBackendSettingsParser

aidSetting :: Opt.Parser Text
aidSetting =
    T.pack
        <$> Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long "aid"
            , Opt.env "CKERI_AID"
            , Opt.conf "aid"
            , Opt.metavar "AID"
            , Opt.help "44-character KERI E-code identifier"
            ]

addressSetting :: Opt.Parser Text
addressSetting =
    T.pack
        <$> Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long "address"
            , Opt.env "CKERI_ADDRESS"
            , Opt.conf "address"
            , Opt.metavar "ADDRESS"
            , Opt.help "Bech32 payer address"
            ]

commonBackendSettingsParser :: Opt.Parser BackendCommonSettings
commonBackendSettingsParser = do
    commonBackendExplicit <-
        Opt.mapIO (traverse parseBackendOrDie) $
            Opt.optional $
                T.pack
                    <$> Opt.setting
                        [ Opt.reader Opt.str
                        , Opt.option
                        , Opt.long "backend"
                        , Opt.env "CKERI_BACKEND"
                        , Opt.conf "backend"
                        , Opt.metavar "local|endpoint|koios"
                        , Opt.help "Explicit backend selection"
                        ]
    commonBackendEndpointUrl <-
        Opt.optional $
            T.pack
                <$> Opt.setting
                    [ Opt.reader Opt.str
                    , Opt.option
                    , Opt.long "endpoint"
                    , Opt.env "CKERI_ENDPOINT"
                    , Opt.conf "endpoint"
                    , Opt.metavar "URL"
                    , Opt.help "Hosted #176 query endpoint base URL"
                    ]
    commonBackendStorePath <-
        Opt.optional $
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "store"
                , Opt.env "CKERI_STORE"
                , Opt.conf "store"
                , Opt.metavar "PATH"
                , Opt.help "Local follower RocksDB store path"
                ]
    commonBackendManifest <-
        Opt.withDefault "deploy/preprod/m1-manifest.json" $
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "manifest"
                , Opt.env "CKERI_MANIFEST"
                , Opt.conf "manifest"
                , Opt.metavar "VALUE"
                , Opt.help "V1 preprod deployment manifest"
                ]
    commonBackendBoardManifest <-
        Opt.withDefault "deploy/preprod/board-manifest.json" $
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "board-manifest"
                , Opt.env "CKERI_BOARD_MANIFEST"
                , Opt.conf "board-manifest"
                , Opt.metavar "VALUE"
                , Opt.help "Endpoint-board preprod deployment manifest"
                ]
    commonBackendKoiosUrl <-
        Opt.withDefault "https://preprod.koios.rest/api/v1" $
            T.pack
                <$> Opt.setting
                    [ Opt.reader Opt.str
                    , Opt.option
                    , Opt.long "koios-url"
                    , Opt.env "CKERI_KOIOS_URL"
                    , Opt.conf "koios-url"
                    , Opt.metavar "VALUE"
                    , Opt.help "Koios API base URL"
                    ]
    commonBackendKoiosToken <-
        Opt.optional $
            KoiosToken . T.pack
                <$> Opt.setting
                    [ Opt.reader Opt.str
                    , Opt.option
                    , Opt.long "koios-token"
                    , Opt.env "KOIOS_TOKEN"
                    , Opt.conf "koios-token"
                    , Opt.metavar "VALUE"
                    , Opt.help "Optional Koios bearer token"
                    ]
    pure BackendCommonSettings{..}

backendCommonSettings :: BackendSettings -> BackendCommonSettings
backendCommonSettings settings =
    BackendCommonSettings
        { commonBackendExplicit = backendExplicit settings
        , commonBackendEndpointUrl = backendEndpointUrl settings
        , commonBackendStorePath = backendStorePath settings
        , commonBackendManifest = backendManifest settings
        , commonBackendBoardManifest = backendBoardManifest settings
        , commonBackendKoiosUrl = backendKoiosUrl settings
        , commonBackendKoiosToken = backendKoiosToken settings
        }

{- | 'Opt.conf' requires an 'autodocodec' @HasCodec@ instance to decode a
YAML enum, and adding that dependency edge forces cabal to re-solve (and
locally rebuild from source) most of the project's Cardano ledger/network
closure — far too costly for one enum. Reading the raw string uniformly
across option\/env\/YAML (all three already have 'HasCodec'\/'Opt.reader'
support for 'String') and validating afterwards via 'Opt.mapIO' keeps
CLI\/env\/YAML precedence intact and still rejects an unknown value loudly
(never silently), without that dependency.
-}
parseBackendOrDie :: Text -> IO Backend
parseBackendOrDie = \case
    "local" -> pure BackendLocal
    "endpoint" -> pure BackendEndpoint
    "koios" -> pure BackendKoios
    other -> fail ("unknown backend " <> show other <> "; expected local, endpoint, or koios")

{- | Resolve one already-selected backend into a live 'QueryBackend', given
injectable per-backend constructors. Production dispatch and tests call the
exact same function — tests substitute fakes for the constructors, never for
this dispatch table itself, so a mutation here is what T177-S1-9's wiring
guard proves able to fail.
-}
resolveBackend ::
    (FilePath -> IO QueryBackend) ->
    (Text -> IO QueryBackend) ->
    (Text -> Maybe KoiosToken -> IO QueryBackend) ->
    SelectedBackend ->
    IO QueryBackend
resolveBackend openLocal openEndpoint openKoios = \case
    SelectedLocal store -> openLocal store
    SelectedEndpoint url -> openEndpoint url
    SelectedKoios url token -> openKoios url token
