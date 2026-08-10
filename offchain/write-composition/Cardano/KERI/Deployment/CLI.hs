{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.Deployment.CLI
Description : opt-env-conf command surface and execution for ckeri
-}
module Cardano.KERI.Deployment.CLI (
    DeploySettings (..),
    RegisterSettings (..),
    RegisterRuntime (..),
    AdvanceSettings (..),
    CloseSettings (..),
    BoardInstructions (..),
    BoardPostSettings (..),
    BoardUpdateSettings (..),
    BoardRetireSettings (..),
    registerPreflight,
    renderQuerySnapshotDiagnostic,

    -- * Reused by "Cardano.KERI.CLI" to compose the top-level and board

    -- command trees (#240: "Cardano.KERI.CLI" also composes
    -- "Cardano.KERI.Deployment.Verify"'s read-only leaves alongside these;
    -- this module has no edge to that provider-owning module, EDGE-240-04).
    deploySettingsParser,
    deploySettingsParserWithOut,
    registerSettingsParser,
    advanceSettingsParser,
    closeSettingsParser,
    boardPostSettingsParser,
    boardUpdateSettingsParser,
    boardRetireSettingsParser,
    runDeploy,
    runRegister,
    runRegisterWith,
    runAdvance,
    runClose,
    runBoard,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Close (CloseEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.ChainQuery (
    ActiveCheckpoint (..),
    BoardLocator (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySnapshot (..),
    SettlementObservation (..),
    SettlementObserver (..),
    SettlementTarget (..),
    SettlementTimeoutPolicy (..),
    observeSettlement,
 )
import Cardano.KERI.ChainQuery.LedgerOutput (
    chainAssetUtxoToLedgerOutput,
    chainReferenceToLedgerOutput,
 )
import Cardano.KERI.ChainQuery.Registration (
    RegistrationQueryRequest (..),
    RegistrationSnapshot (..),
    runRegistrationSnapshot,
 )
import Cardano.KERI.Deployment.Advance (
    AdvancePackage (..),
    AdvanceSigningFiles (..),
    attachControllerSignatures,
    mkAdvancePackage,
    writeAdvanceSigningPackage,
 )
import Cardano.KERI.Deployment.AdvanceTransaction qualified as AdvanceTx
import Cardano.KERI.Deployment.Close (
    ClosePackage (..),
    CloseSigningFiles (..),
    attachCloseControllerSignatures,
    mkClosePackage,
    writeCloseSigningPackage,
 )
import Cardano.KERI.Deployment.CloseTransaction qualified as CloseTx
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
    missingBoardWitnesses,
    parseEndpointRecord,
    parseWitnessKey,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    mkEndpointBoardManifest,
    readEndpointBoardManifest,
    writeEndpointBoardManifestAtomic,
 )
import Cardano.KERI.Deployment.EndpointBoardTransaction qualified as BoardTx
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    RotationExport (..),
    parseInceptionExport,
    parseIndexedSignatureLines,
    parseRotationExport,
 )
import Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    decodePaymentAddress,
    rewardAccountForScript,
    rewardAccountRegistered,
    withLiveContext,
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
    blueprintSha256,
    mkManifest,
    readManifest,
    writeManifestAtomic,
 )
import Cardano.KERI.Deployment.Publisher (
    PublishConfig (..),
    publishScripts,
 )
import Cardano.KERI.Deployment.Registration (
    RegistrationPlan (..),
    mkRegistrationPlan,
    premintOne,
    registerOne,
 )
import Cardano.KERI.Deployment.Registration qualified as Registration
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deriveBoardScript,
    deriveV1Scripts,
    loadBlueprint,
 )
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId)
import Cardano.KERI.Indexer.App (decodePolicyId)
import Cardano.KERI.Indexer.ChainQuery (
    LocalQueryScope (..),
    LocalSettings (..),
    localBoardCatalogWithOutputs,
    localCurrentCheckpoint,
    localInterpreter,
    localOutputAtTx,
    localPayerUtxos,
    localReferenceObservation,
    localReferenceScriptsTx,
    localSettlementObserver,
    localTransactionSettled,
    runLocalSnapshotTx,
    withLocalQueryScope,
 )
import Cardano.KERI.Indexer.Config (decodeAddress)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when, (>=>))
import Data.ByteString qualified as BS
import Data.Char (isHexDigit)
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Database.KV.Transaction (Transaction, runTransaction)
import OptEnvConf qualified as Opt
import System.Directory (doesDirectoryExist)

{- | #240: no 'ManifestVerify'\/'BoardList' constructor here (moved to
"Cardano.KERI.Deployment.Verify", the provider-owning module) -- every
constructor left is a write verb. "Cardano.KERI.CLI" composes this with
'Cardano.KERI.Deployment.Verify.runVerify' itself; this module never
imports that module (EDGE-240-04: no write-composition -> provider-owning
edge).
-}
data BoardInstructions
    = BoardDeploy DeploySettings
    | BoardPost BoardPostSettings
    | BoardUpdate BoardUpdateSettings
    | BoardRetire BoardRetireSettings
    deriving stock (Show, Eq)

data DeploySettings = DeploySettings
    { deployNetwork :: Text
    , deployNetworkMagic :: Int
    , deployBlueprint :: FilePath
    , deployNodeSocket :: FilePath
    , deployFundingAddress :: Text
    , deploySigningKeyFile :: FilePath
    , deploySourceRepo :: FilePath
    , deploySourceRepositoryUrl :: Text
    , deploySourceCommit :: Maybe Text
    , deployOut :: FilePath
    , deployReferenceLovelace :: Integer
    , deployStorePath :: FilePath
    , deployTimeoutSeconds :: Int
    }
    deriving stock (Show, Eq)

data RegisterSettings = RegisterSettings
    { registerNetwork :: Text
    , registerNetworkMagic :: Int
    , registerKel :: FilePath
    , registerPayer :: FilePath
    , registerNodeSocket :: FilePath
    , registerFundingAddress :: Text
    , registerManifest :: FilePath
    , registerBoardManifest :: FilePath
    , registerStorePath :: FilePath
    , registerTimeoutSeconds :: Int
    , registerAllowUnlistedWitnesses :: Bool
    , registerAllowExistingCheckpoint :: Bool
    , registerEscrowLovelace :: Integer
    }
    deriving stock (Show, Eq)

{- | Effects used by the register preflight and live transaction boundary.
Keeping them explicit makes the required read-before-submit order observable
without requiring unit tests to open a node connection.

NOTE-012 repair: preflight's existing-checkpoint and board-catalog reads no
longer thread bare query callbacks (INV-257-BUILDER); 'registerQuerySnapshot'
is the one named registration snapshot, executed by the chosen real
interpreter, that supplies both.

#240 (RQ-240-03\/04): 'registerQuerySnapshot'\/'registerSubmit' both take an
already-open 'LocalQueryScope' rather than provider settings -- 'runRegisterWith'
brackets exactly one 'Cardano.KERI.Indexer.ChainQuery.withLocalQueryScope'
runner for the whole register flow (N-017: one bracket per write action,
never a fresh one per query\/poll) and both fields run against that SAME
runner. The 'forall' makes DATA-INV-240-03 ("a local query scope cannot
outlive its store bracket") a type, not a convention: no concrete @cf@\/@op@
can be named outside 'withLocalQueryScope''s own callback, so a
'RegisterRuntime' cannot smuggle a handle out of its bracket.
-}
data RegisterRuntime = RegisterRuntime
    { registerReadKel :: FilePath -> IO BS.ByteString
    , registerReadManifest :: FilePath -> IO (Either String Manifest)
    , registerReadBoardManifest ::
        FilePath ->
        IO (Either String EndpointBoardManifest)
    , registerQuerySnapshot ::
        forall cf op.
        LocalQueryScope cf op ->
        RegistrationQueryRequest ->
        IO (Either ChainQueryError (QuerySnapshot RegistrationSnapshot))
    , registerWriteLine :: String -> IO ()
    , registerSubmit ::
        forall cf op.
        LocalQueryScope cf op ->
        RegisterSettings ->
        Manifest ->
        RegistrationPlan ->
        IO ()
    }

data AdvanceSettings = AdvanceSettings
    { advanceNetwork :: Text
    , advanceNetworkMagic :: Int
    , advanceConfiguredAid :: Text
    , advanceKel :: FilePath
    , advanceSigningPackage :: Maybe FilePath
    , advanceControllerSignatures :: Maybe FilePath
    , advancePayer :: Maybe FilePath
    , advanceNodeSocket :: Maybe FilePath
    , advanceFundingAddress :: Maybe Text
    , advanceManifest :: FilePath
    , advanceStorePath :: FilePath
    , advanceTimeoutSeconds :: Int
    , advanceValidatorTestUnderSigned :: Bool
    , advanceValidatorTestUnderWitnessed :: Bool
    , advanceValidatorTestStale :: Bool
    }
    deriving stock (Show, Eq)

data CloseSettings = CloseSettings
    { closeNetwork :: Text
    , closeNetworkMagic :: Int
    , closeConfiguredAid :: Text
    , closeKel :: FilePath
    , closeTo :: Text
    , closeSigningPackage :: Maybe FilePath
    , closeControllerSignatures :: Maybe FilePath
    , closePayer :: Maybe FilePath
    , closeNodeSocket :: Maybe FilePath
    , closeFundingAddress :: Maybe Text
    , closeChangeAddress :: Maybe Text
    , closeManifest :: FilePath
    , closeStorePath :: FilePath
    , closeTimeoutSeconds :: Int
    , closeValidatorTestNonController :: Bool
    }
    deriving stock (Show, Eq)

data BoardTransactionSettings = BoardTransactionSettings
    { boardTransactionNetwork :: !Text
    , boardTransactionNetworkMagic :: !Int
    , boardTransactionPayer :: !FilePath
    , boardTransactionNodeSocket :: !FilePath
    , boardTransactionFundingAddress :: !Text
    , boardTransactionChangeAddress :: !(Maybe Text)
    , boardTransactionManifest :: !FilePath
    , boardTransactionStorePath :: !FilePath
    , boardTransactionTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

data BoardPostSettings = BoardPostSettings
    { boardPostEndpointRecord :: !FilePath
    , boardPostDepositLovelace :: !Integer
    , boardPostTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

data BoardUpdateSettings = BoardUpdateSettings
    { boardUpdateEndpointRecord :: !FilePath
    , boardUpdateOutReference :: !(Maybe Text)
    , boardUpdateTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

data BoardRetireSettings = BoardRetireSettings
    { boardRetireWitness :: !Text
    , boardRetireOutReference :: !(Maybe Text)
    , boardRetireTo :: !Text
    , boardRetireTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

deploySettingsParser :: Opt.Parser DeploySettings
deploySettingsParser =
    deploySettingsParserWithOut "deploy/preprod/m1-manifest.json"

deploySettingsParserWithOut :: FilePath -> Opt.Parser DeploySettings
deploySettingsParserWithOut defaultOut = do
    deployNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    deployNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    deployBlueprint <-
        stringSetting
            "blueprint"
            "CKERI_BLUEPRINT"
            "blueprint"
            "Immutable Aiken plutus.json"
            Nothing
    deployNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    deployFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding publication"
            Nothing
    deploySigningKeyFile <-
        stringSetting
            "signing-key-file"
            "CKERI_SIGNING_KEY_FILE"
            "signing-key-file"
            "Cardano payment signing-key envelope"
            Nothing
    deploySourceRepo <-
        stringSetting
            "source-repo"
            "CKERI_SOURCE_REPO"
            "source-repo"
            "Checkout used for source provenance"
            (Just ".")
    deploySourceRepositoryUrl <-
        textSetting
            "source-repository-url"
            "CKERI_SOURCE_REPOSITORY_URL"
            "source-repository-url"
            "Repository URL recorded in the manifest"
            (Just "https://github.com/lambdasistemi/cardano-keri")
    deploySourceCommit <-
        Opt.optional $
            textSetting
                "source-commit"
                "CKERI_SOURCE_COMMIT"
                "source-commit"
                "Source commit (defaults to the checkout HEAD)"
                Nothing
    deployOut <-
        stringSetting
            "out"
            "CKERI_OUT"
            "out"
            "Output manifest path"
            (Just defaultOut)
    deployReferenceLovelace <-
        integerSetting
            "reference-lovelace"
            "CKERI_REFERENCE_LOVELACE"
            "reference-lovelace"
            "Lovelace held in each reference-script output"
            (Just 100_000_000)
    deployStorePath <-
        stringSetting
            "store"
            "CKERI_STORE"
            "store"
            "Local follower RocksDB store path"
            Nothing
    deployTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout per script"
            (Just 600)
    pure DeploySettings{..}

registerSettingsParser :: Opt.Parser RegisterSettings
registerSettingsParser = do
    registerNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    registerNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    registerKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to a kli export stream"
            Nothing
    registerPayer <-
        stringSetting
            "payer"
            "CKERI_PAYER"
            "payer"
            "Cardano payment signing-key file"
            Nothing
    registerNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    registerFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding registration"
            Nothing
    registerManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    registerBoardManifest <-
        stringSetting
            "board-manifest"
            "CKERI_BOARD_MANIFEST"
            "board-manifest"
            "Endpoint-board preprod deployment manifest"
            (Just "deploy/preprod/board-manifest.json")
    registerStorePath <-
        stringSetting
            "store"
            "CKERI_STORE"
            "store"
            "Local follower RocksDB store path"
            Nothing
    registerTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout per transaction"
            (Just 600)
    registerAllowUnlistedWitnesses <-
        Opt.yesNoSwitch
            [ Opt.long "allow-unlisted-witnesses"
            , Opt.env "CKERI_ALLOW_UNLISTED_WITNESSES"
            , Opt.conf "allow-unlisted-witnesses"
            , Opt.help
                "Acknowledge that declared witnesses lack a board record check"
            , Opt.value False
            ]
    registerAllowExistingCheckpoint <-
        Opt.yesNoSwitch
            [ Opt.long "allow-existing-checkpoint"
            , Opt.env "CKERI_ALLOW_EXISTING_CHECKPOINT"
            , Opt.conf "allow-existing-checkpoint"
            , Opt.help
                "Acknowledge sovereign repeat registration of a live AID"
            , Opt.value False
            ]
    registerEscrowLovelace <-
        integerSetting
            "escrow-lovelace"
            "CKERI_ESCROW_LOVELACE"
            "escrow-lovelace"
            "ACTIVE output lovelace (acceptance-only underfunding override)"
            (Just 1_007_000_000)
    pure RegisterSettings{..}

advanceSettingsParser :: Opt.Parser AdvanceSettings
advanceSettingsParser = do
    advanceNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    advanceNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    advanceConfiguredAid <-
        textSetting
            "aid"
            "CKERI_AID"
            "aid"
            "44-character KERI E-code identifier"
            Nothing
    advanceKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to a witnessed kli rotation export"
            Nothing
    advanceSigningPackage <-
        Opt.optional $
            stringSetting
                "signing-package"
                "CKERI_SIGNING_PACKAGE"
                "signing-package"
                "Directory receiving the binary AdvanceMessage package"
                Nothing
    advanceControllerSignatures <-
        Opt.optional $
            stringSetting
                "controller-signatures"
                "CKERI_CONTROLLER_SIGNATURES"
                "controller-signatures"
                "Bare indexed CESR signatures over advance-message.cbor"
                Nothing
    advancePayer <-
        Opt.optional $
            stringSetting
                "payer"
                "CKERI_PAYER"
                "payer"
                "Cardano payment signing-key file"
                Nothing
    advanceNodeSocket <-
        Opt.optional $
            stringSetting
                "node-socket"
                "CKERI_NODE_SOCKET"
                "node-socket"
                "Cardano node socket"
                Nothing
    advanceFundingAddress <-
        Opt.optional $
            textSetting
                "funding-address"
                "CKERI_FUNDING_ADDRESS"
                "funding-address"
                "Bech32 payment address funding the advance"
                Nothing
    advanceManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    advanceStorePath <-
        stringSetting
            "store"
            "CKERI_STORE"
            "store"
            "Local follower RocksDB store path"
            Nothing
    advanceTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    advanceValidatorTestUnderSigned <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-under-signed"
            , Opt.env "CKERI_VALIDATOR_TEST_UNDER_SIGNED"
            , Opt.conf "validator-test-under-signed"
            , Opt.help
                "ACCEPTANCE ONLY: send one signature to real script evaluation"
            , Opt.value False
            ]
    advanceValidatorTestUnderWitnessed <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-under-witnessed"
            , Opt.env "CKERI_VALIDATOR_TEST_UNDER_WITNESSED"
            , Opt.conf "validator-test-under-witnessed"
            , Opt.help
                "ACCEPTANCE ONLY: send one witness receipt to real script evaluation"
            , Opt.value False
            ]
    advanceValidatorTestStale <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-stale"
            , Opt.env "CKERI_VALIDATOR_TEST_STALE"
            , Opt.conf "validator-test-stale"
            , Opt.help
                "ACCEPTANCE ONLY: replay the rotation against current live state"
            , Opt.value False
            ]
    pure AdvanceSettings{..}

closeSettingsParser :: Opt.Parser CloseSettings
closeSettingsParser = do
    closeNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    closeNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    closeConfiguredAid <-
        textSetting
            "aid"
            "CKERI_AID"
            "aid"
            "44-character KERI E-code identifier"
            Nothing
    closeKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to the controller's kli inception export"
            Nothing
    closeTo <-
        textSetting
            "to"
            "CKERI_TO"
            "to"
            "Preprod payment address receiving the complete escrow"
            Nothing
    closeSigningPackage <-
        Opt.optional $
            stringSetting
                "signing-package"
                "CKERI_SIGNING_PACKAGE"
                "signing-package"
                "Directory receiving the binary CloseMessage package"
                Nothing
    closeControllerSignatures <-
        Opt.optional $
            stringSetting
                "controller-signatures"
                "CKERI_CONTROLLER_SIGNATURES"
                "controller-signatures"
                "Bare indexed CESR signatures over close-message.cbor"
                Nothing
    closePayer <-
        Opt.optional $
            stringSetting
                "payer"
                "CKERI_PAYER"
                "payer"
                "Cardano payment signing-key file"
                Nothing
    closeNodeSocket <-
        Opt.optional $
            stringSetting
                "node-socket"
                "CKERI_NODE_SOCKET"
                "node-socket"
                "Cardano node socket"
                Nothing
    closeFundingAddress <-
        Opt.optional $
            textSetting
                "funding-address"
                "CKERI_FUNDING_ADDRESS"
                "funding-address"
                "Bech32 payment address funding the close fee"
                Nothing
    closeChangeAddress <-
        Opt.optional $
            textSetting
                "change-address"
                "CKERI_CHANGE_ADDRESS"
                "change-address"
                "Fee change address, distinct from the exact refund target"
                Nothing
    closeManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    closeStorePath <-
        stringSetting
            "store"
            "CKERI_STORE"
            "store"
            "Local follower RocksDB store path"
            Nothing
    closeTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    closeValidatorTestNonController <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-non-controller"
            , Opt.env "CKERI_VALIDATOR_TEST_NON_CONTROLLER"
            , Opt.conf "validator-test-non-controller"
            , Opt.help
                "ACCEPTANCE ONLY: bypass local signature proof and reach the validator"
            , Opt.value False
            ]
    pure CloseSettings{..}

{- | #240: this module builds no combined \"board\" command parser of its
own any more -- "Cardano.KERI.CLI" composes the four write leaves below
('deploySettingsParserWithOut', 'boardPostSettingsParser',
'boardUpdateSettingsParser', 'boardRetireSettingsParser') together with
"Cardano.KERI.Deployment.Verify"'s read-only \"list\" leaf under the one
installed @board@ command tree, so no provider edge is needed here
(EDGE-240-04).
-}
boardTransactionSettingsParser :: Opt.Parser BoardTransactionSettings
boardTransactionSettingsParser = do
    boardTransactionNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    boardTransactionNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    boardTransactionPayer <-
        stringSetting
            "payer"
            "CKERI_PAYER"
            "payer"
            "Cardano payment signing-key file for the board owner"
            Nothing
    boardTransactionNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    boardTransactionFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding and owning the board record"
            Nothing
    boardTransactionChangeAddress <-
        Opt.optional $
            textSetting
                "change-address"
                "CKERI_CHANGE_ADDRESS"
                "change-address"
                "Fee change address (must differ from an identical retire target)"
                Nothing
    boardTransactionManifest <-
        stringSetting
            "board-manifest"
            "CKERI_BOARD_MANIFEST"
            "board-manifest"
            "Endpoint-board preprod deployment manifest"
            (Just "deploy/preprod/board-manifest.json")
    boardTransactionStorePath <-
        stringSetting
            "store"
            "CKERI_STORE"
            "store"
            "Local follower RocksDB store path"
            Nothing
    boardTransactionTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    pure BoardTransactionSettings{..}

boardPostSettingsParser :: Opt.Parser BoardPostSettings
boardPostSettingsParser = do
    boardPostEndpointRecord <-
        stringSetting
            "endpoint-record"
            "CKERI_ENDPOINT_RECORD"
            "endpoint-record"
            "Binary-safe path to a witness-signed KERI OOBI stream"
            Nothing
    boardPostDepositLovelace <-
        integerSetting
            "deposit-lovelace"
            "CKERI_BOARD_DEPOSIT_LOVELACE"
            "deposit-lovelace"
            "Exact lovelace deposit carried by the record"
            (Just 4_000_000)
    boardPostTransaction <- boardTransactionSettingsParser
    pure BoardPostSettings{..}

boardUpdateSettingsParser :: Opt.Parser BoardUpdateSettings
boardUpdateSettingsParser = do
    boardUpdateEndpointRecord <-
        stringSetting
            "endpoint-record"
            "CKERI_ENDPOINT_RECORD"
            "endpoint-record"
            "Binary-safe path to the replacement witness-signed KERI OOBI stream"
            Nothing
    boardUpdateOutReference <-
        Opt.optional $
            textSetting
                "board-out-ref"
                "CKERI_BOARD_OUT_REF"
                "board-out-ref"
                "Exact TXID#INDEX to select when duplicate records exist"
                Nothing
    boardUpdateTransaction <- boardTransactionSettingsParser
    pure BoardUpdateSettings{..}

boardRetireSettingsParser :: Opt.Parser BoardRetireSettings
boardRetireSettingsParser = do
    boardRetireWitness <-
        textSetting
            "witness"
            "CKERI_WITNESS"
            "witness"
            "44-character KERI B-code witness identifier"
            Nothing
    boardRetireOutReference <-
        Opt.optional $
            textSetting
                "board-out-ref"
                "CKERI_BOARD_OUT_REF"
                "board-out-ref"
                "Exact TXID#INDEX to select when duplicate records exist"
                Nothing
    boardRetireTo <-
        textSetting
            "to"
            "CKERI_TO"
            "to"
            "Preprod payment address receiving the complete board deposit"
            Nothing
    boardRetireTransaction <- boardTransactionSettingsParser
    pure BoardRetireSettings{..}

stringSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe String ->
    Opt.Parser String
stringSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

textSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Text ->
    Opt.Parser Text
textSetting optionName environmentName configName description defaultValue =
    T.pack
        <$> stringSetting
            optionName
            environmentName
            configName
            description
            (T.unpack <$> defaultValue)

intSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Int ->
    Opt.Parser Int
intSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

integerSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Integer ->
    Opt.Parser Integer
integerSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

withMaybeDefault :: (Show a) => Maybe a -> Opt.Parser a -> Opt.Parser a
withMaybeDefault defaultValue parser =
    maybe parser (`Opt.withDefault` parser) defaultValue

{- | #240: no 'ManifestVerify'\/'BoardList' case -- both moved to
"Cardano.KERI.Deployment.Verify"; "Cardano.KERI.CLI" dispatches them
directly, never through this function.
-}
runBoard :: BoardInstructions -> IO ()
runBoard = \case
    BoardDeploy settings -> runBoardDeploy settings
    BoardPost settings -> runBoardPost settings
    BoardUpdate settings -> runBoardUpdate settings
    BoardRetire settings -> runBoardRetire settings

runBoardDeploy :: DeploySettings -> IO ()
runBoardDeploy settings = do
    unless
        (deployNetwork settings == "preprod" && deployNetworkMagic settings == 1)
        (fail "M1 endpoint-board deployment supports only preprod network magic 1")
    when (deployReferenceLovelace settings <= 0) $
        fail "reference-lovelace must be positive"
    when (deployTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    blueprint <-
        loadBlueprint (deployBlueprint settings) >>= either fail pure
    artifact <- either fail pure (deriveBoardScript blueprint)
    digest <- blueprintSha256 (deployBlueprint settings)
    commit <- resolveSourceCommit settings
    verifySourceTree (deploySourceRepo settings) commit
    let localSettings = deployLocalSettingsFor (deployStorePath settings)
    references <-
        withLocalQueryScope localSettings $ \scope ->
            withLiveContext
                (deployLiveConfig settings)
                (awaitLocalTransaction scope (deployTimeoutSeconds settings))
                $ \context ->
                    publishArtifactsLive scope settings context [artifact]
    reference <-
        case references of
            [("endpoint-board", settled)] -> pure settled
            _ ->
                fail
                    "publisher did not return exactly the endpoint-board reference"
    publishedAt <- publicationTimestamp
    manifest <-
        either fail pure $
            mkEndpointBoardManifest
                (deploySourceRepositoryUrl settings)
                commit
                digest
                publishedAt
                artifact
                reference
    writeEndpointBoardManifestAtomic (deployOut settings) manifest
    putStrLn ("board manifest: " <> deployOut settings)

runBoardPost :: BoardPostSettings -> IO ()
runBoardPost settings = do
    let transaction = boardPostTransaction settings
    validateBoardTransactionSettings transaction
    endpointBytes <- BS.readFile (boardPostEndpointRecord settings)
    record <- either fail pure (parseEndpointRecord endpointBytes)
    manifest <- readBoardTransactionManifest transaction
    plan <-
        either fail pure $
            BoardTx.mkBoardPostPlan
                manifest
                (boardTransactionFundingAddress transaction)
                (boardPostDepositLovelace settings)
                record
    let info = endpointBoardManifestInfo manifest
    localSettings <-
        either fail pure $
            boardLocalSettingsFor (boardTransactionStorePath transaction) info
    withLocalQueryScope localSettings $ \scope -> do
        envelope <-
            runLocalSnapshotTx
                scope
                (boardWriteBundleTx info (boardTransactionFundingAddress transaction))
                >>= either (fail . show) pure
        let (reference, funding) = snapshotValue envelope
        withBoardContext scope transaction [reference] $ \_context config -> do
            result <-
                BoardTx.runBoardPostTransaction config plan funding
                    >>= either (fail . show) pure
            putStrLn $
                "board txid: "
                    <> T.unpack
                        (renderTransactionId $ BoardTx.boardResultTxId result)
                    <> " deposit: "
                    <> show (boardPostDepositLovelace settings `div` 1_000_000)
                    <> " tADA"

runBoardUpdate :: BoardUpdateSettings -> IO ()
runBoardUpdate settings = do
    let transaction = boardUpdateTransaction settings
    validateBoardTransactionSettings transaction
    endpointBytes <- BS.readFile (boardUpdateEndpointRecord settings)
    record <- either fail pure (parseEndpointRecord endpointBytes)
    manifest <- readBoardTransactionManifest transaction
    let info = endpointBoardManifestInfo manifest
    localSettings <-
        either fail pure $
            boardLocalSettingsFor (boardTransactionStorePath transaction) info
    withLocalQueryScope localSettings $ \scope -> do
        envelope <-
            runLocalSnapshotTx
                scope
                (boardCatalogBundleTx scope info (boardTransactionFundingAddress transaction))
                >>= either (fail . show) pure
        let (reference, catalogWithOutputs, funding) = snapshotValue envelope
        entry <-
            either fail pure $
                BoardTx.selectBoardEntry
                    (boardUpdateOutReference settings)
                    (endpointWitnessKey record)
                    (map fst catalogWithOutputs)
        boardInput <- either fail pure (pairedBoardOutput entry catalogWithOutputs)
        plan <-
            either fail pure $
                BoardTx.mkBoardUpdatePlan
                    manifest
                    (boardTransactionFundingAddress transaction)
                    entry
                    record
        withBoardContext scope transaction [reference] $ \_context config -> do
            result <-
                BoardTx.runBoardUpdateTransaction config plan funding boardInput
                    >>= either (fail . show) pure
            putStrLn $
                "board update txid: "
                    <> T.unpack
                        (renderTransactionId $ BoardTx.boardResultTxId result)
            putStrLn $
                "replaced: "
                    <> T.unpack (BoardTx.boardUpdateSpentReference plan)

runBoardRetire :: BoardRetireSettings -> IO ()
runBoardRetire settings = do
    let transaction = boardRetireTransaction settings
    validateBoardTransactionSettings transaction
    witness <- either fail pure (parseWitnessKey $ boardRetireWitness settings)
    manifest <- readBoardTransactionManifest transaction
    let info = endpointBoardManifestInfo manifest
    localSettings <-
        either fail pure $
            boardLocalSettingsFor (boardTransactionStorePath transaction) info
    withLocalQueryScope localSettings $ \scope -> do
        envelope <-
            runLocalSnapshotTx
                scope
                (boardCatalogBundleTx scope info (boardTransactionFundingAddress transaction))
                >>= either (fail . show) pure
        let (reference, catalogWithOutputs, funding) = snapshotValue envelope
        entry <-
            either fail pure $
                BoardTx.selectBoardEntry
                    (boardRetireOutReference settings)
                    witness
                    (map fst catalogWithOutputs)
        boardInput <- either fail pure (pairedBoardOutput entry catalogWithOutputs)
        plan <-
            either fail pure $
                BoardTx.mkBoardRetirePlan
                    manifest
                    (boardTransactionFundingAddress transaction)
                    (boardRetireTo settings)
                    entry
        withBoardContext scope transaction [reference] $ \_context config -> do
            result <-
                BoardTx.runBoardRetireTransaction config plan funding boardInput
                    >>= either (fail . show) pure
            putStrLn $
                "board retire txid: "
                    <> T.unpack
                        (renderTransactionId $ BoardTx.boardResultTxId result)
            putStrLn $
                "refunded: "
                    <> show
                        (BoardTx.boardRetireRefundLovelace plan `div` 1_000_000)
                    <> " tADA to "
                    <> T.unpack (boardRetireTo settings)

validateBoardTransactionSettings :: BoardTransactionSettings -> IO ()
validateBoardTransactionSettings settings = do
    unless
        ( boardTransactionNetwork settings == "preprod"
            && boardTransactionNetworkMagic settings == 1
        )
        (fail "M1 endpoint-board transactions support only preprod network magic 1")
    when (boardTransactionTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"

readBoardTransactionManifest ::
    BoardTransactionSettings ->
    IO EndpointBoardManifest
readBoardTransactionManifest settings =
    readEndpointBoardManifest (boardTransactionManifest settings)
        >>= either fail pure

{- | #240 (N-022): the 'LiveContext' bracket and 'BoardTx.BoardConfig'
build only -- 'references' arrives already resolved by the phase's own
combined local snapshot (never N2C\/'resolveBoardReference' here).
-}
withBoardContext ::
    LocalQueryScope cf op ->
    BoardTransactionSettings ->
    [(TxIn, TxOut ConwayEra)] ->
    (LiveContext -> BoardTx.BoardConfig -> IO a) ->
    IO a
withBoardContext scope settings references action =
    withLiveContext
        (boardLiveConfig settings)
        (awaitLocalTransaction scope (boardTransactionTimeoutSeconds settings))
        $ \context -> do
            changeAddress <-
                either fail pure $
                    decodePaymentAddress $
                        fromMaybe
                            (boardTransactionFundingAddress settings)
                            (boardTransactionChangeAddress settings)
            action
                context
                BoardTx.BoardConfig
                    { BoardTx.boardRuntime = liveTransactionRuntime context
                    , BoardTx.boardReferenceUtxos = references
                    , BoardTx.boardFundingAddress = liveFundingAddress context
                    , BoardTx.boardChangeAddress = changeAddress
                    }

{- | #240 (RQ-240-08\/T240-S1-09): the exact-AID checkpoint lookup, run
against the local 'scope' instead of Koios -- relocated from the former
Koios @queryActiveCheckpoint@. Its own single-purpose 'runLocalSnapshotTx'
call: at the point this runs (before a write action even knows whether it
will submit), there is nothing else to compose it with.
-}
activeCheckpointLocal :: LocalQueryScope cf op -> Text -> IO ActiveCheckpoint
activeCheckpointLocal scope aid = do
    envelope <-
        runLocalSnapshotTx scope (localCurrentCheckpoint scope aid)
            >>= either (fail . show) pure
    maybe (fail "checkpoint is not registered") pure (snapshotValue envelope)

{- | #240 (N-022\/N-025): one script hash resolved through the local
reference-output algebra and converted straight to a ledger input,
preserving the real inline datum -- never N2C.
-}
referenceOutputsTx ::
    [Text] -> Transaction IO cf Cols op (Either ChainQueryError [(TxIn, TxOut ConwayEra)])
referenceOutputsTx hashes = do
    result <- localReferenceScriptsTx hashes
    pure (result >>= traverse chainReferenceToLedgerOutput)

{- | #240 (N-022): every M1 V1 manifest script, hash-resolved, in the
manifest's own stable order.
-}
manifestReferencesTx ::
    Manifest -> Transaction IO cf Cols op (Either ChainQueryError [(TxIn, TxOut ConwayEra)])
manifestReferencesTx manifest = referenceOutputsTx (map scriptHash (manifestScripts manifest))

{- | #240 (N-025): the endpoint-board's own reference script,
hash-resolved exactly like a manifest script ('endpointBoardPolicyId' IS
the board artifact's deployed script hash, set from @artifactScriptHash@
by 'mkEndpointBoardManifest' and cross-validated by
'endpointBoardManifestValidationErrors' -- not a distinct minting-policy
concept, despite the field name). The resolved output's own identity is
additionally checked against the manifest's recorded 'endpointBoardReference'
locator, defense in depth against a stale\/mismatched manifest.
-}
boardReferenceOutputTx ::
    EndpointBoardInfo -> Transaction IO cf Cols op (Either ChainQueryError (TxIn, TxOut ConwayEra))
boardReferenceOutputTx info = do
    result <- referenceOutputsTx [endpointBoardPolicyId info]
    pure $ do
        outputs <- result
        case outputs of
            [output@(TxIn txId (TxIx index), _)]
                | renderTransactionId txId == referenceTxId reference
                    && fromIntegral index == referenceIndex reference ->
                    Right output
                | otherwise ->
                    Left
                        ( DecodingFailure
                            "board reference output does not match the manifest's recorded locator"
                        )
            _ ->
                Left
                    ( AmbiguousCurrentState
                        "board reference script hash did not resolve to exactly one output"
                    )
  where
    reference = endpointBoardReference info

{- | #240 (RQ-240-03\/DATA-INV-240-01, N-021\/N-022): enumerate the funding
address through the local reference algebra and convert every returned row
directly with 'chainAssetUtxoToLedgerOutput' -- the local snapshot already
carries the complete follower-held output, so payer selection and values
both come from that SAME snapshot; N2C\/'LiveContext' never substitutes for
a stored row (relocated from the former Koios @indexedFundingUtxos@,
provider dependency dropped; #257 MOD-257-COMPOSITION's N2C half is gone
with it).
-}
fundingOutputsTx ::
    Text -> Transaction IO cf Cols op (Either ChainQueryError [(TxIn, TxOut ConwayEra)])
fundingOutputsTx address = do
    result <- localPayerUtxos [address]
    pure $ do
        indexed <- result
        unless (all ((== address) . chainAssetAddress) indexed) $
            Left (DecodingFailure "indexer returned a payer output at a different address")
        traverse chainAssetUtxoToLedgerOutput indexed

{- | #240 (N-022\/N-023): find the paired ledger output
'localBoardCatalogWithOutputs' already decoded for one PURE-selected
'BoardEntry' -- never a second store transaction just to spend the entry
'BoardTx.selectBoardEntry' picked.
-}
pairedBoardOutput ::
    BoardEntry -> [(BoardEntry, (TxIn, TxOut ConwayEra))] -> Either String (TxIn, TxOut ConwayEra)
pairedBoardOutput entry catalogWithOutputs =
    maybe
        (Left "board catalog entry has no matching decoded output")
        (Right . snd)
        (find ((== entry) . fst) catalogWithOutputs)

{- | #240 (N-022): board post's whole phase bundle -- the board's own
reference output plus funding, composed together (post never reads the
catalog: it creates a NEW entry, it does not select an existing one).
-}
boardWriteBundleTx ::
    EndpointBoardInfo ->
    Text ->
    Transaction IO cf Cols op (Either ChainQueryError ((TxIn, TxOut ConwayEra), [(TxIn, TxOut ConwayEra)]))
boardWriteBundleTx info fundingAddress = do
    refResult <- boardReferenceOutputTx info
    case refResult of
        Left err -> pure (Left err)
        Right ref -> do
            fundingResult <- fundingOutputsTx fundingAddress
            pure ((,) ref <$> fundingResult)

{- | #240 (N-022): board update\/retire's whole phase bundle -- the
board's own reference output, the complete catalog paired with each
entry's own decoded output ('localBoardCatalogWithOutputs', so selecting
one entry afterward never needs a second store transaction), and funding,
composed together.
-}
boardCatalogBundleTx ::
    LocalQueryScope cf op ->
    EndpointBoardInfo ->
    Text ->
    Transaction
        IO
        cf
        Cols
        op
        ( Either
            ChainQueryError
            ( (TxIn, TxOut ConwayEra)
            , [(BoardEntry, (TxIn, TxOut ConwayEra))]
            , [(TxIn, TxOut ConwayEra)]
            )
        )
boardCatalogBundleTx scope info fundingAddress = do
    refResult <- boardReferenceOutputTx info
    case refResult of
        Left err -> pure (Left err)
        Right ref -> do
            catalogResult <- localBoardCatalogWithOutputs scope
            case catalogResult of
                Left err -> pure (Left err)
                Right catalog -> do
                    fundingResult <- fundingOutputsTx fundingAddress
                    pure ((,,) ref catalog <$> fundingResult)

{- | #240 (N-022): advance\/close's shared submit-phase bundle -- every
manifest reference script, the exact active-checkpoint output being
spent (by the SAME @(txid,index)@ identity 'activeCheckpointLocal' already
found, re-read fresh so the real ledger 'TxOut'\/datum is used, never the
'ActiveCheckpoint' summary), and funding, composed together.
-}
manifestAndActiveBundleTx ::
    Manifest ->
    Text ->
    Int ->
    Text ->
    Transaction
        IO
        cf
        Cols
        op
        ( Either
            ChainQueryError
            ([(TxIn, TxOut ConwayEra)], (TxIn, TxOut ConwayEra), [(TxIn, TxOut ConwayEra)])
        )
manifestAndActiveBundleTx manifest activeTxId activeIndex fundingAddress = do
    refsResult <- manifestReferencesTx manifest
    case refsResult of
        Left err -> pure (Left err)
        Right refs -> do
            activeResult <- localOutputAtTx activeTxId activeIndex
            case activeResult of
                Left err -> pure (Left err)
                Right activeOut -> do
                    fundingResult <- fundingOutputsTx fundingAddress
                    pure ((,,) refs activeOut <$> fundingResult)

{- | #240 (N-026\/N-027\/DAT-240-LOCAL-SETTINGS): every board write verb
dispatches neither 'currentCheckpoint' nor 'liveCheckpoints' -- the
checkpoint identity is genuinely 'Nothing', never a fabricated value. The
board address is real and validated ('Just').
-}
boardLocalSettingsFor :: FilePath -> EndpointBoardInfo -> Either String LocalSettings
boardLocalSettingsFor storePath info = do
    boardAddr <- decodeAddress (endpointBoardAddress info)
    pure
        LocalSettings
            { localStorePath = storePath
            , localCheckpointIdentity = Nothing
            , localBoardIdentity = Just boardAddr
            }

{- | #240 (N-026\/N-027\/DAT-240-LOCAL-SETTINGS): 'deploy'\/'board deploy'
dispatch neither 'currentCheckpoint'\/'liveCheckpoints' nor 'boardCatalog'
(there is no manifest yet to source either identity from -- deploy
PRODUCES the manifest) -- both identities are genuinely 'Nothing', never a
fabricated value.
-}
deployLocalSettingsFor :: FilePath -> LocalSettings
deployLocalSettingsFor storePath =
    LocalSettings
        { localStorePath = storePath
        , localCheckpointIdentity = Nothing
        , localBoardIdentity = Nothing
        }

{- | #240 (N-026\/N-027\/DAT-240-LOCAL-SETTINGS): 'advance'\/'close' both
operate on an existing manifest's own real checkpoint identity ('Just',
validated); neither dispatches 'boardCatalog' or a board write, so the
board identity is genuinely 'Nothing', never a fabricated value.
-}
manifestLocalSettingsFor :: FilePath -> Manifest -> Either String LocalSettings
manifestLocalSettingsFor storePath manifest = do
    let checkpoint = manifestCheckpoint manifest
    checkpointAddr <- decodeAddress (checkpointAddressBech32 checkpoint)
    checkpointPolicy <- decodePolicyId (checkpointPolicyId checkpoint)
    pure
        LocalSettings
            { localStorePath = storePath
            , localCheckpointIdentity = Just (checkpointPolicy, checkpointAddr)
            , localBoardIdentity = Nothing
            }

{- | #240 (RQ-240-06): constructs 'withLiveContext''s observation
capability from the SAME already-open local 'scope'
('Cardano.KERI.Indexer.ChainQuery.localTransactionSettled', a fresh
temporal probe on the held-open runner, N-017), never a fresh store
bracket per poll.
-}
awaitLocalTransaction :: LocalQueryScope cf op -> Int -> TxId -> IO ()
awaitLocalTransaction scope timeoutSeconds txId = do
    started <- getCurrentTime
    let loop = do
            observed <- try (localTransactionSettled scope txId)
            case observed of
                Right True -> pure ()
                Right False -> retry started
                Left (_ :: SomeException) -> retry started
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral timeoutSeconds
                then fail $ "transaction settlement timed out: " <> T.unpack (renderTransactionId txId)
                else threadDelay 2_000_000 >> loop
    loop

deployLiveConfig :: DeploySettings -> LiveConfig
deployLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = deployNetworkMagic settings
        , liveNodeSocket = deployNodeSocket settings
        , liveSigningKeyFile = deploySigningKeyFile settings
        , liveFundingAddressText = deployFundingAddress settings
        , liveTimeoutSeconds = deployTimeoutSeconds settings
        }

registerLiveConfig :: RegisterSettings -> LiveConfig
registerLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = registerNetworkMagic settings
        , liveNodeSocket = registerNodeSocket settings
        , liveSigningKeyFile = registerPayer settings
        , liveFundingAddressText = registerFundingAddress settings
        , liveTimeoutSeconds = registerTimeoutSeconds settings
        }

advanceLiveConfig ::
    AdvanceSettings ->
    FilePath ->
    FilePath ->
    Text ->
    LiveConfig
advanceLiveConfig settings payer nodeSocket fundingAddress =
    LiveConfig
        { liveNetworkMagic = advanceNetworkMagic settings
        , liveNodeSocket = nodeSocket
        , liveSigningKeyFile = payer
        , liveFundingAddressText = fundingAddress
        , liveTimeoutSeconds = advanceTimeoutSeconds settings
        }

closeLiveConfig ::
    CloseSettings ->
    FilePath ->
    FilePath ->
    Text ->
    LiveConfig
closeLiveConfig settings payer nodeSocket fundingAddress =
    LiveConfig
        { liveNetworkMagic = closeNetworkMagic settings
        , liveNodeSocket = nodeSocket
        , liveSigningKeyFile = payer
        , liveFundingAddressText = fundingAddress
        , liveTimeoutSeconds = closeTimeoutSeconds settings
        }

boardLiveConfig :: BoardTransactionSettings -> LiveConfig
boardLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = boardTransactionNetworkMagic settings
        , liveNodeSocket = boardTransactionNodeSocket settings
        , liveSigningKeyFile = boardTransactionPayer settings
        , liveFundingAddressText = boardTransactionFundingAddress settings
        , liveTimeoutSeconds = boardTransactionTimeoutSeconds settings
        }

{- | #240 (N-022\/N-023): each artifact's funding is its own phase snapshot
-- publishing artifact N changes the payer's live UTxOs before artifact
N+1's funding can be read, a genuine causal separation (like
'runRegisterWith''s premint\/register split), never a needless sequence of
otherwise-simultaneous reads. 'publishQueryReferences' stays a fresh
per-poll local settlement probe ('localReferenceObservation'), exactly
like every other post-submit temporal observation in this module.
-}
publishArtifactsLive ::
    LocalQueryScope cf op ->
    DeploySettings ->
    LiveContext ->
    [ScriptArtifact] ->
    IO [(Text, Reference)]
publishArtifactsLive scope settings context = traverse publishArtifact
  where
    publishArtifact artifact = do
        envelope <-
            runLocalSnapshotTx scope (fundingOutputsTx (liveFundingAddressText (liveConfig context)))
                >>= either (fail . show) pure
        let funding = snapshotValue envelope
        published <-
            publishScripts
                PublishConfig
                    { publishRuntime = liveTransactionRuntime context
                    , publishInputUtxos = funding
                    , publishFundingAddress = liveFundingAddress context
                    , publishReferenceLovelace =
                        deployReferenceLovelace settings
                    , publishQueryReferences =
                        localReferenceObservation scope
                            >=> either (fail . show) pure
                    , publishTimeoutSeconds =
                        deployTimeoutSeconds settings
                    }
                [artifact]
        case published of
            [reference] -> pure reference
            _ -> fail "single-artifact publisher returned an impossible cardinality"

resolveSourceCommit :: DeploySettings -> IO Text
resolveSourceCommit settings =
    case deploySourceCommit settings of
        Nothing ->
            fail
                "--source-commit is required; production composition does not inspect Git through a subprocess"
        Just commit -> pure (T.toLower commit)

publicationTimestamp :: IO Text
publicationTimestamp =
    T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
        <$> getCurrentTime

registerPreflight ::
    Text ->
    Int ->
    Bool ->
    Bool ->
    Int ->
    [BoardEntry] ->
    InceptionExport ->
    Either String ()
registerPreflight network networkMagic allowUnlisted allowExisting existingCount catalog inception = do
    unless (network == "preprod" && networkMagic == 1) $
        Left "M1 V1 registration supports only preprod network magic 1"
    when (existingCount < 0) $
        Left "checkpoint discovery count cannot be negative"
    when (not allowExisting && existingCount == 1) $
        Left "checkpoint already registered; refusing before premint"
    when (not allowExisting && existingCount > 1) $
        Left "checkpoint discovery is ambiguous; refusing before premint"
    let witnesses = cdWitnesses (inceptionDatum inception)
        missing = missingBoardWitnesses witnesses catalog
    when (not allowUnlisted && not (null missing)) $
        Left $
            show (length missing)
                <> "/"
                <> show (length witnesses)
                <> " declared witnesses are absent from the verified board; pass \
                   \--allow-unlisted-witnesses to acknowledge reduced watchability"

runRegister :: RegisterSettings -> IO ()
runRegister = runRegisterWith productionRegisterRuntime

{- | Render a snapshot envelope's provenance (INV-257-CONSISTENCY,
DATA-INV-257-03): every registration read prints its real, non-degenerate
source, consistency, and watermark rather than discarding them.
-}
renderQuerySnapshotDiagnostic :: QuerySnapshot a -> String
renderQuerySnapshotDiagnostic envelope =
    "registration snapshot: source="
        <> show (snapshotSource envelope)
        <> " consistency="
        <> show (snapshotConsistency envelope)
        <> " watermark="
        <> case snapshotWatermark envelope of
            Cold -> "cold"
            Populated watermark ->
                "slot="
                    <> show (watermarkSlot watermark)
                    <> " hash="
                    <> T.unpack (watermarkBlockHash watermark)

{- | Execute every read-only preflight effect, then submit live -- all
inside ONE 'Cardano.KERI.Indexer.ChainQuery.withLocalQueryScope' bracket
(N-017: one bracket per write action). Manifest/board-manifest identity is
decoded once, before the bracket opens, into the fixed
'Cardano.KERI.Indexer.ChainQuery.LocalSettings' the whole flow shares;
the board identity (N-026) is genuinely 'Nothing', never a fabricated
value, when no witness requires a real board read.
-}
runRegisterWith :: RegisterRuntime -> RegisterSettings -> IO ()
runRegisterWith runtime settings = do
    when (registerTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    kel <- registerReadKel runtime (registerKel settings)
    inception <- either fail pure (parseInceptionExport kel)
    manifest <-
        registerReadManifest runtime (registerManifest settings)
            >>= either fail pure
    plan <-
        either
            fail
            pure
            (mkRegistrationPlan manifest (registerEscrowLovelace settings) inception)
    let witnesses = cdWitnesses (inceptionDatum inception)
    boardLocator <-
        if null witnesses
            then pure Nothing
            else do
                boardManifest <-
                    registerReadBoardManifest
                        runtime
                        (registerBoardManifest settings)
                        >>= either fail pure
                let boardInfo = endpointBoardManifestInfo boardManifest
                pure $
                    Just
                        BoardLocator
                            { boardLocatorPolicyId = endpointBoardPolicyId boardInfo
                            , boardLocatorAddress = endpointBoardAddress boardInfo
                            }
    checkpointAddr <- either fail pure (decodeAddress (planCheckpointAddress plan))
    checkpointPolicy <- either fail pure (decodePolicyId (planCheckpointPolicy plan))
    boardIdentity <-
        case boardLocator of
            Nothing -> pure Nothing
            Just locator -> Just <$> either fail pure (decodeAddress (boardLocatorAddress locator))
    let localSettings =
            LocalSettings
                { localStorePath = registerStorePath settings
                , localCheckpointIdentity = Just (checkpointPolicy, checkpointAddr)
                , localBoardIdentity = boardIdentity
                }
    withLocalQueryScope localSettings $ \scope -> do
        envelope <-
            registerQuerySnapshot
                runtime
                scope
                RegistrationQueryRequest
                    { registrationQueryCheckpointLocator =
                        CheckpointLocator (planCheckpointPolicy plan) (planCheckpointAddress plan)
                    , registrationQueryAid = planAid plan
                    , registrationQueryBoardLocator = boardLocator
                    , registrationQueryReferenceHashes = []
                    , registrationQueryPayerAddresses = []
                    }
                >>= either (fail . show) pure
        registerWriteLine runtime (renderQuerySnapshotDiagnostic envelope)
        let snapshot = snapshotValue envelope
            existing = maybe (0 :: Int) (const 1) (snapshotCurrentCheckpoint snapshot)
            catalog = snapshotBoardCatalog snapshot
        either
            fail
            pure
            ( registerPreflight
                (registerNetwork settings)
                (registerNetworkMagic settings)
                (registerAllowUnlistedWitnesses settings)
                (registerAllowExistingCheckpoint settings)
                existing
                catalog
                inception
            )
        let missing = missingBoardWitnesses witnesses catalog
        when
            ( registerAllowUnlistedWitnesses settings
                && not (null missing)
            )
            ( registerWriteLine runtime $
                "warning: "
                    <> show (length missing)
                    <> "/"
                    <> show (length witnesses)
                    <> " declared witnesses are absent from the verified board; \
                       \accepting reduced public watchability"
            )
        when
            (registerAllowExistingCheckpoint settings && existing > 0)
            ( registerWriteLine
                runtime
                "warning: sovereign repeat registration creates another fully \
                \funded checkpoint copy; the benign residual is intentional"
            )
        registerSubmit runtime scope settings manifest plan

productionRegisterRuntime :: RegisterRuntime
productionRegisterRuntime =
    RegisterRuntime
        { registerReadKel = BS.readFile
        , registerReadManifest = readManifest
        , registerReadBoardManifest = readEndpointBoardManifest
        , registerQuerySnapshot = \scope req ->
            runTransaction
                (localScopeRunner scope)
                (runRegistrationSnapshot (localInterpreter scope) req)
        , registerWriteLine = putStrLn
        , registerSubmit = submitRegistration
        }

{- | #240 (RQ-240-03\/04\/06): each build phase's current-state inputs flow
through the SAME already-open local 'scope' (via
'Cardano.KERI.ChainQuery.Registration.runRegistrationSnapshot'
\@'localInterpreter' scope\@, unchanged from #257 otherwise) rather than a
fresh Koios interpreter per call, and settlement is
'Cardano.KERI.Indexer.ChainQuery.localSettlementObserver' \@scope\@ -- a
fresh 'runTransaction' per poll on that SAME runner, never a fresh RocksDB
bracket (N-017). The premint proof's settled output is converted directly
from the settlement observation's own already-decoded 'ChainAssetUtxo'
('chainAssetUtxoToLedgerOutput', pure) instead of a second store\/N2C
lookup -- the local settlement probe already decoded everything the
builder needs.
-}
submitRegistration ::
    LocalQueryScope cf op ->
    RegisterSettings ->
    Manifest ->
    RegistrationPlan ->
    IO ()
submitRegistration scope settings manifest plan =
    withLiveContext
        (registerLiveConfig settings)
        (awaitLocalTransaction scope (registerTimeoutSeconds settings))
        $ \context -> do
            lifecycleHash <-
                either fail pure $
                    maybe (Left "manifest script is absent: observer-lifecycle") (Right . scriptHash) $
                        find ((== "observer-lifecycle") . scriptName) (manifestScripts manifest)
            lifecycleAccount <-
                either fail pure $
                    rewardAccountForScript "observer-lifecycle" manifest
            lifecycleRegistered <-
                rewardAccountRegistered context lifecycleAccount
            let config =
                    Registration.RegisterConfig
                        { Registration.registerRuntime =
                            liveTransactionRuntime context
                        , Registration.registerFundingAddress =
                            liveFundingAddress context
                        , Registration.registerLifecycleRewardAccount =
                            lifecycleAccount
                        , Registration.registerSettlementObserver =
                            localSettlementObserver scope
                        , Registration.registerTimeoutSeconds =
                            registerTimeoutSeconds settings
                        , Registration.registerPollDelayMicros = 2_000_000
                        }
                interpreter = localInterpreter scope
                snapshotRequest referenceHashes =
                    RegistrationQueryRequest
                        { registrationQueryCheckpointLocator =
                            CheckpointLocator (planCheckpointPolicy plan) (planCheckpointAddress plan)
                        , registrationQueryAid = planAid plan
                        , registrationQueryBoardLocator = Nothing
                        , registrationQueryReferenceHashes = referenceHashes
                        , registrationQueryPayerAddresses = [registerFundingAddress settings]
                        }
                fetchSnapshot referenceHashes = do
                    envelope <-
                        runTransaction
                            (localScopeRunner scope)
                            (runRegistrationSnapshot interpreter (snapshotRequest referenceHashes))
                            >>= either (fail . show) pure
                    putStrLn (renderQuerySnapshotDiagnostic envelope)
                    pure (snapshotValue envelope)
                settlementTimeoutPolicy =
                    SettlementTimeoutPolicy
                        { settlementTimeoutSeconds = Registration.registerTimeoutSeconds config
                        , settlementPollDelayMicros = Registration.registerPollDelayMicros config
                        }
                observeOrFail target =
                    observeSettlement (Registration.registerSettlementObserver config) target settlementTimeoutPolicy
                        >>= either (fail . show) pure
            premintSnapshot <-
                fetchSnapshot ([planProofPolicy plan] <> [lifecycleHash | not lifecycleRegistered])
            premintTxId <-
                premintOne config plan premintSnapshot (not lifecycleRegistered)
                    >>= either (fail . show) pure
            proof <-
                observeOrFail
                    SettlementTarget
                        { settlementPolicy = planProofPolicy plan
                        , settlementAssetName = planProofName plan
                        , settlementTxId = renderTransactionId premintTxId
                        , settlementAddress = registerFundingAddress settings
                        }
            proofInput <-
                either (fail . show) pure $
                    chainAssetUtxoToLedgerOutput (settlementObservedUtxo proof)
            registerSnapshot <-
                fetchSnapshot [planProofPolicy plan, planCheckpointPolicy plan, lifecycleHash]
            registerTxId <-
                registerOne config plan registerSnapshot proofInput
                    >>= either (fail . show) pure
            _ <-
                observeOrFail
                    SettlementTarget
                        { settlementPolicy = planCheckpointPolicy plan
                        , settlementAssetName = planCheckpointName plan
                        , settlementTxId = renderTransactionId registerTxId
                        , settlementAddress = planCheckpointAddress plan
                        }
            putStrLn $
                "premint txid: "
                    <> T.unpack (renderTransactionId premintTxId)
            putStrLn $
                "register txid: "
                    <> T.unpack (renderTransactionId registerTxId)
            putStrLn $
                "escrow: "
                    <> show (registerEscrowLovelace settings `div` 1_000_000)
                    <> " tADA (min 2 + D 1000 + B 5)"

runAdvance :: AdvanceSettings -> IO ()
runAdvance settings = do
    unless
        (advanceNetwork settings == "preprod" && advanceNetworkMagic settings == 1)
        (fail "M1 V1 advance supports only preprod network magic 1")
    unless
        ( T.length (advanceConfiguredAid settings) == 44
            && "E" `T.isPrefixOf` advanceConfiguredAid settings
        )
        (fail "AID must be one 44-character KERI E-code identifier")
    when (advanceTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    let negativeCount =
            length $
                filter
                    id
                    [ advanceValidatorTestUnderSigned settings
                    , advanceValidatorTestUnderWitnessed settings
                    , advanceValidatorTestStale settings
                    ]
    when (negativeCount > 1) $
        fail "choose at most one validator-test mode"
    kel <- BS.readFile (advanceKel settings)
    rotation <- either fail pure (parseRotationExport kel)
    unless (advanceConfiguredAid settings == rotationAid rotation) $
        fail "configured AID does not match the kli rotation export"
    manifest <-
        readManifest (advanceManifest settings) >>= either fail pure
    localSettings <-
        either fail pure (manifestLocalSettingsFor (advanceStorePath settings) manifest)
    withLocalQueryScope localSettings $ \scope -> do
        active <- activeCheckpointLocal scope (advanceConfiguredAid settings)
        package <-
            either fail pure (mkAdvancePackage manifest active rotation)
        case ( advanceSigningPackage settings
             , advanceControllerSignatures settings
             ) of
            (Just directory, Nothing) -> do
                when (negativeCount /= 0) $
                    fail "validator-test modes apply only when submitting"
                files <- writeAdvanceSigningPackage directory package
                putStrLn $
                    "signing package: "
                        <> advancePreimageFile files
                putStrLn $
                    "preimage sha256: "
                        <> T.unpack (advancePackageSha256 package)
                putStrLn $
                    "spent checkpoint: "
                        <> T.unpack (advanceSpentReference package)
            (Nothing, Just signatureFile) ->
                submitAdvance scope settings manifest active package signatureFile
            _ ->
                fail
                    "choose exactly one of --signing-package DIR or \
                    \--controller-signatures FILE"

submitAdvance ::
    LocalQueryScope cf op ->
    AdvanceSettings ->
    Manifest ->
    ActiveCheckpoint ->
    AdvancePackage ->
    FilePath ->
    IO ()
submitAdvance scope settings manifest active package signatureFile = do
    payer <-
        requireAdvanceSetting "--payer" (advancePayer settings)
    nodeSocket <-
        requireAdvanceSetting "--node-socket" (advanceNodeSocket settings)
    fundingAddress <-
        requireAdvanceSetting "--funding-address" (advanceFundingAddress settings)
    signatureBytes <- BS.readFile signatureFile
    signatures <-
        either fail pure (parseIndexedSignatureLines signatureBytes)
    submittedPackage <-
        prepareSubmittedPackage settings active signatures package
    plan <- either fail pure (AdvanceTx.mkAdvancePlan manifest submittedPackage)
    envelope <-
        runLocalSnapshotTx
            scope
            ( manifestAndActiveBundleTx
                manifest
                (activeCheckpointTxId active)
                (activeCheckpointIndex active)
                fundingAddress
            )
            >>= either (fail . show) pure
    let (references, activeInput, funding) = snapshotValue envelope
    withLiveContext
        ( advanceLiveConfig
            settings
            payer
            nodeSocket
            fundingAddress
        )
        (awaitLocalTransaction scope (advanceTimeoutSeconds settings))
        $ \context -> do
            observerAccount <-
                either fail pure $
                    rewardAccountForScript "observer-advance" manifest
            observerRegistered <-
                rewardAccountRegistered context observerAccount
            result <-
                AdvanceTx.runAdvanceTransaction
                    AdvanceTx.AdvanceConfig
                        { AdvanceTx.advanceRuntime =
                            liveTransactionRuntime context
                        , AdvanceTx.advanceReferenceUtxos = references
                        , AdvanceTx.advanceFundingAddress =
                            liveFundingAddress context
                        , AdvanceTx.advanceObserverRewardAccount =
                            observerAccount
                        }
                    plan
                    funding
                    activeInput
                    (not observerRegistered)
                    >>= either (fail . show) pure
            let txId = AdvanceTx.resultAdvanceTxId result
            _ <-
                AdvanceTx.awaitAdvance
                    (probeSettlement (localSettlementObserver scope))
                    2_000_000
                    (advanceTimeoutSeconds settings)
                    (AdvanceTx.planCheckpointPolicy plan)
                    (AdvanceTx.planCheckpointAssetName plan)
                    (renderTransactionId txId)
                    (AdvanceTx.planCheckpointAddress plan)
                    >>= either (fail . show) pure
            putStrLn $
                "advance txid: "
                    <> T.unpack (renderTransactionId txId)

prepareSubmittedPackage ::
    AdvanceSettings ->
    ActiveCheckpoint ->
    [(Int, BS.ByteString)] ->
    AdvancePackage ->
    IO AdvancePackage
prepareSubmittedPackage settings active signatures package
    | advanceValidatorTestUnderSigned settings = do
        when (null signatures) $
            fail "under-signed validator test needs at least one valid signature"
        warnValidatorTest "under-signed"
        pure $
            package
                { advanceEvidence =
                    (advanceEvidence package)
                        { aeCtrlSigs = take 1 signatures
                        }
                }
    | advanceValidatorTestUnderWitnessed settings = do
        validated <-
            either fail pure (attachControllerSignatures signatures package)
        when (length (aeWitReceipts $ advanceEvidence validated) < 2) $
            fail "under-witnessed validator test needs at least two receipts"
        warnValidatorTest "under-witnessed"
        pure $
            validated
                { advanceEvidence =
                    (advanceEvidence validated)
                        { aeWitReceipts =
                            take 1 (aeWitReceipts $ advanceEvidence validated)
                        }
                }
    | advanceValidatorTestStale settings = do
        unless
            ( cdNativeSn (activeCheckpointDatum active)
                >= cdNativeSn (advanceSuccessor package)
            )
            (fail "stale validator test requires an already-applied rotation")
        warnValidatorTest "stale replay"
        pure $
            package
                { advanceEvidence =
                    (advanceEvidence package)
                        { aeCtrlSigs = signatures
                        }
                }
    | otherwise =
        either fail pure (attachControllerSignatures signatures package)

warnValidatorTest :: String -> IO ()
warnValidatorTest label =
    putStrLn $
        "warning: ACCEPTANCE-ONLY "
            <> label
            <> " package will be sent to real validator evaluation"

requireAdvanceSetting :: String -> Maybe a -> IO a
requireAdvanceSetting name =
    maybe (fail $ name <> " is required when submitting an advance") pure

runClose :: CloseSettings -> IO ()
runClose settings = do
    unless
        (closeNetwork settings == "preprod" && closeNetworkMagic settings == 1)
        (fail "M1 V1 close supports only preprod network magic 1")
    unless
        ( T.length (closeConfiguredAid settings) == 44
            && "E" `T.isPrefixOf` closeConfiguredAid settings
        )
        (fail "AID must be one 44-character KERI E-code identifier")
    when (closeTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    kel <- BS.readFile (closeKel settings)
    inception <- either fail pure (parseInceptionExport kel)
    unless (closeConfiguredAid settings == inceptionAid inception) $
        fail "configured AID does not match the kli inception export"
    manifest <-
        readManifest (closeManifest settings) >>= either fail pure
    localSettings <-
        either fail pure (manifestLocalSettingsFor (closeStorePath settings) manifest)
    withLocalQueryScope localSettings $ \scope -> do
        active <- activeCheckpointLocal scope (closeConfiguredAid settings)
        package <-
            either fail pure (mkClosePackage manifest active $ closeTo settings)
        case (closeSigningPackage settings, closeControllerSignatures settings) of
            (Just directory, Nothing) -> do
                when (closeValidatorTestNonController settings) $
                    fail "validator-test mode applies only when submitting"
                files <- writeCloseSigningPackage directory package
                putStrLn $
                    "signing package: "
                        <> closePreimageFile files
                putStrLn $
                    "preimage sha256: "
                        <> T.unpack (closePackageSha256 package)
                putStrLn $
                    "spent checkpoint: "
                        <> T.unpack (closeSpentReference package)
                putStrLn $
                    "refund: "
                        <> show (closeRefundLovelace package `div` 1_000_000)
                        <> " tADA to "
                        <> T.unpack (closeRefundAddress package)
            (Nothing, Just signatureFile) ->
                submitClose scope settings manifest package signatureFile
            _ ->
                fail
                    "choose exactly one of --signing-package DIR or \
                    \--controller-signatures FILE"

submitClose ::
    LocalQueryScope cf op ->
    CloseSettings ->
    Manifest ->
    ClosePackage ->
    FilePath ->
    IO ()
submitClose scope settings manifest package signatureFile = do
    payer <- requireCloseSetting "--payer" (closePayer settings)
    nodeSocket <-
        requireCloseSetting "--node-socket" (closeNodeSocket settings)
    fundingAddress <-
        requireCloseSetting
            "--funding-address"
            (closeFundingAddress settings)
    changeAddress <-
        requireCloseSetting "--change-address" (closeChangeAddress settings)
    signatureBytes <- BS.readFile signatureFile
    signatures <-
        either fail pure (parseIndexedSignatureLines signatureBytes)
    submittedPackage <-
        if closeValidatorTestNonController settings
            then do
                when (null signatures) $
                    fail
                        "non-controller validator test needs at least one signature"
                warnValidatorTest "non-controller close"
                pure
                    package
                        { closeEvidence =
                            (closeEvidence package)
                                { ceCtrlSigs = signatures
                                }
                        }
            else
                either
                    fail
                    pure
                    (attachCloseControllerSignatures signatures package)
    plan <- either fail pure (CloseTx.mkClosePlan manifest submittedPackage)
    change <- either fail pure (decodePaymentAddress changeAddress)
    envelope <-
        runLocalSnapshotTx
            scope
            ( manifestAndActiveBundleTx
                manifest
                (activeCheckpointTxId $ closeActiveCheckpoint submittedPackage)
                (activeCheckpointIndex $ closeActiveCheckpoint submittedPackage)
                fundingAddress
            )
            >>= either (fail . show) pure
    let (references, active, funding) = snapshotValue envelope
        liveConfig =
            closeLiveConfig
                settings
                payer
                nodeSocket
                fundingAddress
    withLiveContext
        liveConfig
        (awaitLocalTransaction scope (closeTimeoutSeconds settings))
        $ \context -> do
            result <-
                CloseTx.runCloseTransaction
                    CloseTx.CloseConfig
                        { CloseTx.closeRuntime =
                            liveTransactionRuntime context
                        , CloseTx.closeReferenceUtxos = references
                        , CloseTx.closeFundingAddress =
                            liveFundingAddress context
                        , CloseTx.closeChangeAddress = change
                        }
                    plan
                    funding
                    active
                    >>= either (fail . show) pure
            let txId = CloseTx.closeResultTxId result
            _ <-
                CloseTx.awaitClose
                    (localTransactionSettled scope)
                    2_000_000
                    (closeTimeoutSeconds settings)
                    txId
                    >>= either (fail . show) pure
            putStrLn $
                "close txid: "
                    <> T.unpack (renderTransactionId txId)
            putStrLn $
                "refunded: "
                    <> show (closeRefundLovelace submittedPackage `div` 1_000_000)
                    <> " tADA to "
                    <> T.unpack (closeRefundAddress submittedPackage)

requireCloseSetting :: String -> Maybe a -> IO a
requireCloseSetting name =
    maybe (fail $ name <> " is required when submitting a close") pure

runDeploy :: DeploySettings -> IO ()
runDeploy settings = do
    unless
        (deployNetwork settings == "preprod" && deployNetworkMagic settings == 1)
        (fail "M1 V1 deployment supports only preprod network magic 1")
    when (deployReferenceLovelace settings <= 0) $
        fail "reference-lovelace must be positive"
    when (deployTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    artifacts <- loadArtifacts (deployBlueprint settings)
    digest <- blueprintSha256 (deployBlueprint settings)
    commit <- resolveSourceCommit settings
    verifySourceTree (deploySourceRepo settings) commit
    let localSettings = deployLocalSettingsFor (deployStorePath settings)
    references <-
        withLocalQueryScope localSettings $ \scope ->
            withLiveContext
                (deployLiveConfig settings)
                (awaitLocalTransaction scope (deployTimeoutSeconds settings))
                $ \context ->
                    publishArtifactsLive scope settings context artifacts
    publishedAt <- publicationTimestamp
    manifest <-
        either fail pure $
            mkManifest
                (deploySourceRepositoryUrl settings)
                commit
                digest
                publishedAt
                artifacts
                references
    writeManifestAtomic (deployOut settings) manifest
    putStrLn ("manifest: " <> deployOut settings)

loadArtifacts :: FilePath -> IO [ScriptArtifact]
loadArtifacts path = do
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveV1Scripts blueprint)

verifySourceTree :: FilePath -> Text -> IO ()
verifySourceTree repository commit = do
    unless
        (T.length commit == 40 && T.all isHexDigit commit)
        (fail "source commit must be exactly 40 hexadecimal characters")
    sourcePresent <- doesDirectoryExist (repository <> "/onchain")
    unless sourcePresent $
        fail "source repository has no onchain/ directory"
