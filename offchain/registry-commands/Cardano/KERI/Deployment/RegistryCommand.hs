{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryCommand
Description : @ckeri registry deploy@: create a fresh registry

The command reads chain state only through the one provider the settings choose, a node socket or Koios: the wallet's outputs, the
protocol parameters, the outputs a transaction created. It opens no follower
store and reads no manifest of the first deployment. Every term of the registry
is an input; none is a constant of the command.

A deployment that completes leaves two files: the release identity and the
reference-output record ("Cardano.KERI.Deployment.RegistryFiles"). Neither is
overwritten, and the command asks that both can be written before it submits
anything.
-}
module Cardano.KERI.Deployment.RegistryCommand (
    RegistryDeploySettings (..),
    registryDeploySettingsParser,
    registryTermsOf,
    runRegistryDeploy,
    runRegistryDeployWith,
    runRegistryDeployOver,
    renderFailureFor,
    renderStep,
    renderFailure,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..))
import Cardano.KERI.Deployment.LiveRuntime (decodePaymentAddress)
import Cardano.KERI.Deployment.NodeSocketRuntime (Connection (..), NodeAccess (..), RegistryOpener, withNodeRuntime)
import Cardano.KERI.Deployment.Registry (RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryBookingCommand (openKey, openRegistryKoios, openRegistryKoiosFold)
import Cardano.KERI.Deployment.RegistryDeploy (
    DeployError (..),
    DeployFailure (..),
    DeployRequest (..),
    Deployed (..),
    Landed (..),
    Step (..),
    TermRefusal (..),
    deployRegistry,
 )
import Cardano.KERI.Deployment.RegistryFiles (FilesError (..), checkFilesWritable, writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryKeySource (passphraseFdSetting, signingKeyFileSetting, vaultSetting)
import Cardano.KERI.Deployment.RegistryProvider (Counterpart (..), Openers (..), ProviderChoice (..), counterpartOf, evidence, forCounterpart, nodeOnly, providerChoiceParser, reasonText, renderProviderRefusal, resolveProvider, transliterateReports, withProvider)
import Cardano.KERI.Deployment.RegistryWindow (installNodeWindow)
import Cardano.KERI.Deployment.Script (CheckpointTerms (..), loadBlueprint)
import Cardano.KERI.Deployment.SingularFunding (singularFundingRules)
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.TxIn (TxIn (..))
import Control.Monad (forM_, when)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString.Char8 qualified as B8
import Data.Text (Text)
import Data.Text qualified as T
import OptEnvConf qualified as Opt
import System.Exit (exitFailure)
import System.IO (hFlush, hPutStrLn, stderr, stdout)

-- | Everything @ckeri registry deploy@ is given.
data RegistryDeploySettings = RegistryDeploySettings
    { rdNetworkMagic :: !Int
    , rdBlueprint :: !FilePath
    , rdProvider :: !ProviderChoice
    , rdFundingAddress :: !Text
    , rdSigningKeyFile :: !(Maybe FilePath)
    , rdVault :: !(Maybe FilePath)
    , rdPassphraseFd :: !(Maybe Int)
    , rdTimeoutSeconds :: !Int
    , rdReferenceLovelace :: !(Maybe Integer)
    , rdReleaseIdentityOut :: !FilePath
    , rdReferenceRecordOut :: !FilePath
    , rdRegistrationCost :: !Integer
    , rdMinimumTip :: !Integer
    , rdProcessTime :: !Integer
    , rdBookingWidth :: !Integer
    , rdDeposit :: !Integer
    , rdFreezeBond :: !Integer
    , rdPremium :: !Integer
    , rdMinimumAda :: !Integer
    , rdTerminationCarrier :: !Integer
    }
    deriving stock (Show, Eq)

{- | The terms the settings name. The chain is a test network: the funding
address is an @addr_test@ one, so the network discriminator is 0.
-}
registryTermsOf :: RegistryDeploySettings -> RegistryTerms
registryTermsOf settings =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = 0
                , termsDeposit = rdDeposit settings
                , termsFreezeBond = rdFreezeBond settings
                , termsPremium = rdPremium settings
                }
        , registryParameters =
            ApplicationParameters
                { registrationCost = rdRegistrationCost settings
                , minimumTip = rdMinimumTip settings
                , processTime = rdProcessTime settings
                , bookingWidth = rdBookingWidth settings
                }
        , registryMinimumAda = rdMinimumAda settings
        , registryTerminationCarrier = rdTerminationCarrier settings
        }

registryDeploySettingsParser :: Opt.Parser RegistryDeploySettings
registryDeploySettingsParser = do
    rdNetworkMagic <-
        intSetting "network-magic" "CKERI_NETWORK_MAGIC" "network-magic" "Cardano testnet network magic" (Just 1)
    rdBlueprint <-
        stringSetting "blueprint" "CKERI_BLUEPRINT" "blueprint" "Immutable Aiken plutus.json" Nothing
    rdProvider <- providerChoiceParser
    rdFundingAddress <-
        T.pack
            <$> stringSetting
                "funding-address"
                "CKERI_FUNDING_ADDRESS"
                "funding-address"
                "Bech32 payment address that pays the deployment"
                Nothing
    rdSigningKeyFile <- signingKeyFileSetting
    rdVault <- vaultSetting
    rdPassphraseFd <- passphraseFdSetting
    rdTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout per transaction on the node (on Koios a transaction is waited for until two minutes after its validity end)"
            (Just 600)
    rdReferenceLovelace <-
        Opt.optional $
            integerSetting
                "reference-lovelace"
                "CKERI_REFERENCE_LOVELACE"
                "reference-lovelace"
                "Lovelace held in each published output (default: the ledger's minimum for it)"
                Nothing
    rdReleaseIdentityOut <-
        stringSetting
            "release-identity-out"
            "CKERI_RELEASE_IDENTITY_OUT"
            "release-identity-out"
            "Where the release identity is written (must not exist)"
            (Just "release-identity.json")
    rdReferenceRecordOut <-
        stringSetting
            "reference-record-out"
            "CKERI_REFERENCE_RECORD_OUT"
            "reference-record-out"
            "Where the reference-output record is written (must not exist)"
            (Just "reference-outputs.json")
    rdRegistrationCost <-
        termSetting "registration-cost" "REGISTRATION_COST" "Lovelace a registration pays the treasury"
    rdMinimumTip <-
        termSetting "minimum-tip" "MINIMUM_TIP" "Least lovelace a booking holds for whoever folds or returns it"
    rdProcessTime <-
        termSetting "process-time" "PROCESS_TIME" "Milliseconds a booked request may wait for its fold"
    rdBookingWidth <-
        termSetting "booking-width" "BOOKING_WIDTH" "Widest validity interval of a booking, in milliseconds"
    rdDeposit <-
        termSetting "deposit" "DEPOSIT" "The checkpoint deposit, in lovelace"
    rdFreezeBond <-
        termSetting "freeze-bond" "FREEZE_BOND" "The freeze bond, in lovelace"
    rdPremium <-
        termSetting "premium" "PREMIUM" "The premium paid out of a pool at each rotation, in lovelace"
    rdMinimumAda <-
        termSetting "minimum-ada" "MINIMUM_ADA" "The minimum ADA of a checkpoint output, in lovelace"
    rdTerminationCarrier <-
        termSetting
            "termination-carrier"
            "TERMINATION_CARRIER"
            "What a termination request holds besides the tip, in lovelace"
    pure RegistryDeploySettings{..}

-- | A registry term: given by option, environment variable or configuration, never defaulted.
termSetting :: String -> String -> String -> Opt.Parser Integer
termSetting name suffix description =
    integerSetting name ("CKERI_" <> suffix) name description Nothing

stringSetting :: String -> String -> String -> String -> Maybe String -> Opt.Parser String
stringSetting optionName environmentName configName description defaultValue =
    maybe id Opt.withDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

intSetting :: String -> String -> String -> String -> Maybe Int -> Opt.Parser Int
intSetting optionName environmentName configName description defaultValue =
    maybe id Opt.withDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

integerSetting :: String -> String -> String -> String -> Maybe Integer -> Opt.Parser Integer
integerSetting optionName environmentName configName description defaultValue =
    maybe id Opt.withDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

-- ---------------------------------------------------------------------
-- Running
-- ---------------------------------------------------------------------

runRegistryDeploy :: RegistryDeploySettings -> IO ()
runRegistryDeploy = runRegistryDeployOver Openers{openersNode = openNode, openersKoios = openRegistryKoios, openersKoiosFold = openRegistryKoiosFold}

{- | Deploy a registry through the node the opener reaches, write the two files
and print what landed.
-}
runRegistryDeployWith :: RegistryOpener -> RegistryDeploySettings -> IO ()
runRegistryDeployWith = runRegistryDeployOver . nodeOnly

-- | The same over the openers of both providers: the one the settings choose is the one used.
runRegistryDeployOver :: Openers -> RegistryDeploySettings -> IO ()
runRegistryDeployOver openers settings = do
    transliterateReports
    hPutStrLn stderr "ckeri: not for mainnet"
    provider <- either (die' . renderProviderRefusal) pure (resolveProvider (rdProvider settings))
    let counterpart = counterpartOf provider
    key <- openKey "deploy" (rdNetworkMagic settings) (rdSigningKeyFile settings) (rdVault settings) (rdPassphraseFd settings)
    when (rdTimeoutSeconds settings <= 0) $
        die' "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rdBlueprint settings) >>= either die' pure
    writable <-
        checkFilesWritable
            (rdReleaseIdentityOut settings)
            (rdReferenceRecordOut settings)
    either (die' . renderFilesError) pure writable
    withProvider openers provider (chosenNetworkTime (rdProvider settings)) (rdNetworkMagic settings) (rdFundingAddress settings) key (rdTimeoutSeconds settings) $ \(runtime, payer) -> do
        let request =
                DeployRequest
                    { requestTerms = registryTermsOf settings
                    , requestBlueprint = blueprint
                    , requestPayer = payer
                    , requestReferenceLovelace = rdReferenceLovelace settings
                    }
        outcome <- deployRegistry runtime printLanded request
        case outcome of
            Left failure -> do
                forM_ (renderFailureFor counterpart failure) (hPutStrLn stderr)
                exitFailure
            Right deployed -> do
                written <-
                    writeDeploymentFiles
                        (rdReleaseIdentityOut settings)
                        (rdReferenceRecordOut settings)
                        (deployedIdentity deployed)
                        (deployedRecord deployed)
                either (die' . renderFilesError) pure written
                putStrLn ("release identity: " <> rdReleaseIdentityOut settings)
                putStrLn ("reference outputs: " <> rdReferenceRecordOut settings)
                putStrLn "the advance, enforcement and entitlement observers and the bounty commitment program are not deployed by this command"
  where
    -- flushed at once: whoever collects the ids through a pipe has each as it settles
    printLanded landed = do
        putStrLn
            ( renderStep (landedStep landed)
                <> ": "
                <> T.unpack (renderTransactionId (landedTransaction landed))
                <> " fee="
                <> show (landedFee landed)
                <> " locked="
                <> show (landedLocked landed)
                <> " collateral="
                <> show (landedCollateral landed)
                <> " valid-until-slot="
                <> maybe "none" show (landedValidUntil landed)
            )
        hFlush stdout

die' :: String -> IO a
die' message = hPutStrLn stderr ("ckeri: " <> message) >> exitFailure

-- | The name of a step in what the command prints.
renderStep :: Step -> String
renderStep = \case
    PublishTemplate -> "publish-state-template"
    PublishAttestation -> "publish-booking-attestation"
    PublishApplication -> "publish-application"
    PublishState -> "publish-state-script"
    PublishHashProof -> "publish-hash-proof"
    PublishCheckpoint -> "publish-checkpoint-validator"
    CreateRegistry -> "create-registry"

{- | What a failed deployment tells the person running the command: what landed, where it stopped
and why, and what did not land. Nothing is retried and a transaction that may
still land is said to be uncertain.
-}
renderFailure :: DeployFailure -> [String]
renderFailure = renderFailureFor TheNode

-- | The same, as it reads for the other end of the chain: on Koios the handoff may have sent the same signed bytes again, so only a new transaction is said not to have been made.
renderFailureFor :: Counterpart -> DeployFailure -> [String]
renderFailureFor counterpart failure =
    map (forCounterpart counterpart) $
        ["ckeri: registry deployment stopped: " <> renderCause (failureCause failure)]
            <> [ "landed: " <> renderStep step <> " " <> T.unpack (renderTransactionId txId)
               | Landed{landedStep = step, landedTransaction = txId} <- failureLanded failure
               ]
            <> maybe [] (\step -> ["stopped at: " <> renderStep step]) (failureStoppedAt failure)
            <> [ "not landed: " <> renderStep step
               | step <- failureNotLanded failure
               ]
            <> [ renderStep step <> " " <> T.unpack (renderTransactionId txId) <> " was refused by the node: " <> evidence (reasonText reason) <> "; it is not on chain"
               | SubmissionRefused txId reason <- [failureCause failure]
               , Just step <- [failureStoppedAt failure]
               ]
            <> [ "uncertain: " <> T.unpack (renderTransactionId txId) <> " may still land; " <> unsent
               | NotObserved txId _ <- [failureCause failure]
               ]
            <> [ "unconfirmed: " <> T.unpack (renderTransactionId txId) <> " was not seen before its deadline and may still be included; look it up by its identifier before anything is built again; " <> unsent
               | Unconfirmed txId _ <- [failureCause failure]
               ]
  where
    unsent = case counterpart of
        TheNode -> "it was not resubmitted"
        TheProvider -> "no other transaction was built or signed"

renderCause :: DeployError -> String
renderCause = \case
    TermsRefused refusals -> "terms-refused: " <> unwords (map renderRefusal refusals)
    NetworkDisagrees discriminator -> "network-disagrees: the terms name network " <> show discriminator
    ScriptsRefused message -> "scripts-refused: " <> evidence message
    NoSeedOutput -> "no-seed-output: the wallet holds no output of lovelace alone to create the registry from"
    SeedSpent (OutputReference transaction index) ->
        "seed-spent: the registry's seed "
            <> B8.unpack (convertToBase Base16 transaction)
            <> "#"
            <> show index
            <> " was spent before the genesis"
    FundsBelowRequirement needed held ->
        "funds-below-requirement: the publications need at least " <> show needed <> " lovelace of outputs that carry no script or datum, the wallet holds " <> show held
    ReferenceVanished (TxIn txId (TxIx index)) ->
        "reference-vanished: " <> T.unpack (renderTransactionId txId) <> "#" <> show index
    BuildRefused refusal -> "build-refused: " <> evidence (show refusal)
    EvaluationFailed message -> "evaluation-failed: " <> evidence message
    PurposesDiffer message -> "purposes-differ: " <> evidence message
    BudgetExceeded message -> "budget-exceeded: " <> evidence message
    SigningRefused message -> "signing-refused: " <> evidence message
    SubmissionRefused _ reason -> "submission-refused: " <> evidence (reasonText reason)
    NotObserved txId message ->
        "not-observed: " <> T.unpack (renderTransactionId txId) <> " " <> evidence message
    Unconfirmed txId message ->
        "unconfirmed: " <> T.unpack (renderTransactionId txId) <> " " <> evidence message
    NodeFailed message -> "node-failed: " <> evidence message
    NoWindow -> "no-usable-window: no validity interval at the tip is usable; the transaction was not built or handed over"

renderRefusal :: TermRefusal -> String
renderRefusal = \case
    NegativeTerm name -> "negative-" <> T.unpack name
    DepositBelowFloor -> "deposit-below-floor"
    FreezeBondBelowFloor -> "freeze-bond-below-floor"
    NetworkDiscriminatorNotZeroOrOne -> "network-discriminator-not-zero-or-one"
    MinimumAdaNotTheCheckpoints -> "minimum-ada-not-the-checkpoints"
    TerminationCarrierExceedsMinimumAda -> "termination-carrier-exceeds-minimum-ada"

renderFilesError :: FilesError -> String
renderFilesError = \case
    FileExists path -> "file-exists: " <> path <> " is already there; it is not overwritten"
    DirectoryMissing path -> "directory-missing: " <> path
    DirectoryNotWritable path -> "directory-not-writable: " <> path
    FileIo path message -> "file-error: " <> path <> ": " <> message
    other -> "files: " <> show other

-- ---------------------------------------------------------------------
-- The node
-- ---------------------------------------------------------------------

openNode :: RegistryOpener
openNode access use = do
    payer <- either die' pure (decodePaymentAddress (naFundingAddress access))
    withNodeRuntime singularFundingRules Linked access (\(runtime, _) -> use (installNodeWindow (naNetworkMagic access) (naNetworkTime access) runtime, payer))
