{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingCommand
Description : @ckeri registry register@ books a registration, @ckeri registry fold@ folds one

Both commands read chain state only through the one provider the settings choose (a node socket, or Koios) and the two files
@ckeri registry deploy@ wrote. They open no follower store and no manifest of
the first deployment, and keep no list of registered keys of their own: a fold
is given a snapshot of the registry's keys by a named party and checks it
against the registry state the chain holds before it pays anything.

Every refusal says where it was made: by the command before any transaction, by
the node's evaluation of a transaction, or by the ledger. Every transaction id
is printed, flushed, as it settles.
-}
module Cardano.KERI.Deployment.RegistryBookingCommand (
    RegistryRegisterSettings (..),
    registryRegisterSettingsParser,
    runRegistryRegister,
    runRegistryRegisterWith,
    RegistryFoldSettings (..),
    registryFoldSettingsParser,
    registryReturnSettingsParser,
    runRegistryFold,
    runRegistryFoldWith,
    runRegistryFoldReporting,
    runRegistryRegisterReporting,
    runRegistryRegisterOver,
    runRegistryFoldOver,
    runRegistryReturnOver,
    RegistryReturnSettings (..),
    runRegistryReturn,
    runRegistryReturnWith,
    runRegistryReturnReporting,
    printReturnEvent,
    renderReturnStopped,
    printFoldEvent,
    renderFoldStopped,
    renderRegisterFailure,
    openRegistryNode,
    openRegistryNodeBetween,
    openRegistryKoios,
    openRegistryKoiosFold,
    shippedOpeners,
    dieChoice,
    openKey,
    parseRequestReference,
    RegistryReadFlags (..),
    RegistryReadMode (..),
    registryReadFlagsParser,
    registryReadMode,
    KoiosReadOpener,
    openRegistryKoiosRead,
    runRegistryReadbackOver,
    renderReadback,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (ApplicationParameters (..))
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive, qb64Aid)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..), parseInceptionExport)
import Cardano.KERI.Deployment.KoiosRegistryRuntime (KoiosAccess (..), KoiosOpened (..), openKoios, openKoiosRuntime, renderKoiosStartFailure)
import Cardano.KERI.Deployment.LiveRuntime (decodePaymentAddress)
import Cardano.KERI.Deployment.NodeSocketRuntime (Connection (..), KeySource (..), NodeAccess (..), RegistryOpener, withNodeRuntime)
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Boundary (..),
    Refusal (..),
    SubmitError (..),
    deriveDeployment,
    feeOf,
    renderBoundary,
    submitBoundary,
 )
import Cardano.KERI.Deployment.RegistryFiles (FilesError (..), ReferenceRecord, StoredRecord (..), readStoredDeploymentFiles, writeFileNew)
import Cardano.KERI.Deployment.RegistryFold (
    FoldCause (..),
    FoldDone (..),
    FoldEvent (..),
    FoldInput (..),
    FoldStopped (..),
    foldBookedRequest,
 )
import Cardano.KERI.Deployment.RegistryFoldNamed (FoldedRequest (..), NamedFoldDone (..), NamedFoldInput (..), NamedFoldStop (..), foldNamed)
import Cardano.KERI.Deployment.RegistryKeySource (passphraseFdSetting, renderKeySourceRefusal, resolveKeySource, signingKeyFileSetting, vaultSetting)
import Cardano.KERI.Deployment.RegistryProvider (
    Counterpart (..),
    KoiosFoldOpener,
    KoiosOpener,
    Openers (..),
    Provider (..),
    ProviderChoice (..),
    ProviderRefusal,
    counterpartOf,
    evidence,
    forCounterpart,
    nodeOnly,
    printHandoffReport,
    providerChoiceParser,
    reasonText,
    renderProviderRefusal,
    resolveProvider,
    transliterateReports,
    withProvider,
 )
import Cardano.KERI.Deployment.RegistryReadback (Acquirer (..), Link (..), LinkFailure (..), Linked (..), Readback (..), readCheckpoint)
import Cardano.KERI.Deployment.RegistryRegister (
    RegisterEvent (..),
    RegisterFailure (..),
    RegisterRequest (..),
    registerRegistration,
 )
import Cardano.KERI.Deployment.RegistryReturn (
    ReturnCause (..),
    ReturnEvent (..),
    ReturnInput (..),
    ReturnStopped (..),
    returnBookedRequest,
 )
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), decodeSnapshot, encodeSnapshot)
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..))
import Cardano.KERI.Deployment.Script (loadBlueprint)
import Cardano.KERI.Deployment.SigningKeyCheck (checkSigningEnvelope, checkSigningKey)
import Cardano.KERI.Deployment.SingularFunding (singularFundingRules)
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr, getNetwork, serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (..), TxIx (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Provider (SlotNo (..))
import Codec.Binary.Bech32 qualified as Bech32
import Control.Exception (IOException, try)
import Control.Monad (forM_, unless, when)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (toUpper)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import OptEnvConf qualified as Opt
import System.Directory (doesPathExist)
import System.Exit (exitFailure)
import System.IO (Handle, hFlush, hPutStrLn, stderr, stdout)
import System.IO.Error (isDoesNotExistError)

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------

-- | Everything @ckeri registry register@ is given.
data RegistryRegisterSettings = RegistryRegisterSettings
    { rgNetworkMagic :: !Int
    , rgBlueprint :: !FilePath
    , rgProvider :: !ProviderChoice
    , rgFundingAddress :: !Text
    , rgSigningKeyFile :: !(Maybe FilePath)
    , rgVault :: !(Maybe FilePath)
    , rgPassphraseFd :: !(Maybe Int)
    , rgTimeoutSeconds :: !Int
    , rgReleaseIdentity :: !FilePath
    , rgReferenceRecord :: !FilePath
    , rgKliExport :: !FilePath
    , rgDeposit :: !(Maybe Integer)
    }
    deriving stock (Show, Eq)

-- | Everything @ckeri registry fold@ is given.
data RegistryFoldSettings = RegistryFoldSettings
    { rfNetworkMagic :: !Int
    , rfBlueprint :: !FilePath
    , rfProvider :: !ProviderChoice
    , rfFundingAddress :: !Text
    , rfSigningKeyFile :: !(Maybe FilePath)
    , rfVault :: !(Maybe FilePath)
    , rfPassphraseFd :: !(Maybe Int)
    , rfTimeoutSeconds :: !Int
    , rfReleaseIdentity :: !FilePath
    , rfReferenceRecord :: !FilePath
    , rfRequest :: !Text
    , rfSnapshot :: !FilePath
    , rfSnapshotOut :: !(Maybe FilePath)
    , rfPending :: ![Text]
    }
    deriving stock (Show, Eq)

registryRegisterSettingsParser :: Opt.Parser RegistryRegisterSettings
registryRegisterSettingsParser = do
    rgNetworkMagic <- intSetting "network-magic" (Just 1) "Cardano testnet network magic"
    rgBlueprint <- stringSetting "blueprint" "Immutable Aiken plutus.json"
    rgProvider <- providerChoiceParser
    rgFundingAddress <- T.pack <$> stringSetting "funding-address" "Bech32 payment address that pays the booking and is the refund address"
    rgSigningKeyFile <- signingKeyFileSetting
    rgVault <- vaultSetting
    rgPassphraseFd <- passphraseFdSetting
    rgTimeoutSeconds <- intSetting "timeout-seconds" (Just 600) "Settlement timeout per transaction on the node (on Koios a transaction is waited for until two minutes after its validity end)"
    rgReleaseIdentity <- stringSetting "release-identity" "The release identity file registry deploy wrote"
    rgReferenceRecord <- stringSetting "reference-record" "The reference-output record registry deploy wrote"
    rgKliExport <- stringSetting "kli-export" "The controller's kli export stream"
    rgDeposit <-
        Opt.optional $
            integerSetting "request-deposit" "Lovelace the request commits as the checkpoint's deposit (default: the registry's initial floor)"
    pure RegistryRegisterSettings{..}

registryFoldSettingsParser :: Opt.Parser RegistryFoldSettings
registryFoldSettingsParser = do
    rfNetworkMagic <- intSetting "network-magic" (Just 1) "Cardano testnet network magic"
    rfBlueprint <- stringSetting "blueprint" "Immutable Aiken plutus.json"
    rfProvider <- providerChoiceParser
    rfFundingAddress <- T.pack <$> stringSetting "funding-address" "Bech32 payment address that pays the fold: not the controller's"
    rfSigningKeyFile <- signingKeyFileSetting
    rfVault <- vaultSetting
    rfPassphraseFd <- passphraseFdSetting
    rfTimeoutSeconds <- intSetting "timeout-seconds" (Just 600) "Settlement timeout per transaction on the node (on Koios a transaction is waited for until two minutes after its validity end)"
    rfReleaseIdentity <- stringSetting "release-identity" "The release identity file registry deploy wrote"
    rfReferenceRecord <- stringSetting "reference-record" "The reference-output record registry deploy wrote"
    rfRequest <- T.pack <$> Opt.withDefault "" (stringSetting "request" "On a node socket: the booking output to fold, as <transaction id>#<index>")
    rfSnapshot <- Opt.withDefault "" (stringSetting "snapshot" "On a node socket: the registry's active and terminal keys, as a named party supplies them")
    rfSnapshotOut <-
        Opt.optional $
            stringSetting "snapshot-out" "On a node socket: where the registry as it stands after the fold is written for the next folder (must not exist)"
    rfPending <- map T.pack <$> Opt.many pendingSetting
    pure RegistryFoldSettings{..}

stringSetting :: String -> String -> Opt.Parser String
stringSetting name description =
    Opt.setting
        [ Opt.reader Opt.str
        , Opt.option
        , Opt.long name
        , Opt.env (environmentOf name)
        , Opt.conf name
        , Opt.metavar "VALUE"
        , Opt.help description
        ]

{- | A setting given on the command line only. The packaged @ckeri@ exports @CKERI_BLUEPRINT@, so the
environment must not choose the registry a read command reads: only these flags do.
-}
flagSetting :: String -> String -> Opt.Parser String
flagSetting name description =
    Opt.setting
        [ Opt.reader Opt.str
        , Opt.option
        , Opt.long name
        , Opt.metavar "VALUE"
        , Opt.help description
        ]

intSetting :: String -> Maybe Int -> String -> Opt.Parser Int
intSetting name defaultValue description =
    maybe id Opt.withDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long name
            , Opt.env (environmentOf name)
            , Opt.conf name
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

integerSetting :: String -> String -> Opt.Parser Integer
integerSetting name description =
    Opt.setting
        [ Opt.reader Opt.auto
        , Opt.option
        , Opt.long name
        , Opt.env (environmentOf name)
        , Opt.conf name
        , Opt.metavar "VALUE"
        , Opt.help description
        ]

environmentOf :: String -> String
environmentOf name = "CKERI_" <> map (\c -> if c == '-' then '_' else toUpper c) name

-- ---------------------------------------------------------------------
-- register
-- ---------------------------------------------------------------------

runRegistryRegister :: RegistryRegisterSettings -> IO ()
runRegistryRegister = runRegistryRegisterOver (hPutStrLn stderr) shippedOpeners

{- | Book a registration through the node the opener reaches: what the files and the
export name, over a window the registry's booking width allows.
-}
runRegistryRegisterWith :: RegistryOpener -> RegistryRegisterSettings -> IO ()
runRegistryRegisterWith = runRegistryRegisterReporting (hPutStrLn stderr)

{- | The same, with the writer of the final failure report given: each line of it goes through
the writer, which is how a test reaches the instants inside that report.
-}
runRegistryRegisterReporting :: (String -> IO ()) -> RegistryOpener -> RegistryRegisterSettings -> IO ()
runRegistryRegisterReporting errLine = runRegistryRegisterOver errLine . nodeOnly

{- | The same over the openers of both providers: the one the settings choose is the one used,
and its reports name it.
-}
runRegistryRegisterOver :: (String -> IO ()) -> Openers -> RegistryRegisterSettings -> IO ()
runRegistryRegisterOver errLine openers settings = do
    transliterateReports
    hPutStrLn stderr "ckeri: not for mainnet"
    provider <- either dieChoice pure (resolveProvider (rgProvider settings))
    let counterpart = counterpartOf provider
    key <- openKey "register" (rgNetworkMagic settings) (rgSigningKeyFile settings) (rgVault settings) (rgPassphraseFd settings)
    when (rgTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rgBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles "register" (rgReleaseIdentity settings) (rgReferenceRecord settings)
    export <- readExport (rgKliExport settings)
    putStrLn
        "ckeri: this checks the registry's checkpoint address only: it cannot see a terminal key or another pending booking of this identity; the fold is where a duplicate is stopped"
    hFlush stdout
    withProvider openers provider (chosenNetworkTime (rgProvider settings)) (rgNetworkMagic settings) (rgFundingAddress settings) key (rgTimeoutSeconds settings) $ \(runtime, payer) -> do
        outcome <-
            registerRegistration
                runtime
                (printRegisterEvent counterpart (bookingWidth (riApplicationParameters identity)))
                RegisterRequest
                    { registerBlueprint = blueprint
                    , registerIdentity = identity
                    , registerRecord = record
                    , registerExport = export
                    , registerPayer = payer
                    , registerDeposit = rgDeposit settings
                    }
        case outcome of
            Right _ -> pure ()
            Left failure -> do
                mapM_ errLine (renderRegisterFailureFor counterpart failure)
                exitFailure

printRegisterEvent :: Counterpart -> Integer -> RegisterEvent -> IO ()
printRegisterEvent counterpart intended = \case
    PremintSettledForBooking{eventTransaction = txId, eventProof = proof, eventFee = fee} -> do
        putStrLn ("premint-transaction: " <> T.unpack (renderTransactionId txId))
        putStrLn ("proof-output: " <> renderTxIn proof)
        putStrLn ("premint-fee: " <> show fee)
        hFlush stdout
    BookingWindow{eventPlan = plan, eventDeadline = deadline} -> do
        let slots (SlotNo n) = show n
        putStrLn ("validity-interval-slots: " <> slots (lowerSlot plan) <> ".." <> slots (upperSlot plan))
        putStrLn ("validity-interval-ms: " <> show (lowerPosixMs plan) <> ".." <> show (upperPosixMs plan))
        putStrLn ("intended-width-ms: " <> show intended)
        putStrLn ("actual-width-ms: " <> show (upperPosixMs plan - lowerPosixMs plan))
        putStrLn ("deadline-ms: " <> show deadline)
        hFlush stdout
    BookingSubmitting{eventTransaction = txId, eventTimeLeftMs = left} -> do
        putStrLn (forCounterpart counterpart ("handing booking " <> T.unpack (renderTransactionId txId) <> " to the node"))
        putStrLn ("time-left-ms: " <> show left)
        hFlush stdout
    BookingSettled{eventTransaction = txId, eventOutput = output, eventFee = fee} -> do
        putStrLn ("booking-transaction: " <> T.unpack (renderTransactionId txId))
        putStrLn ("booking-output: " <> renderTxIn output)
        putStrLn ("booking-fee: " <> show fee)
        hFlush stdout

renderRegisterFailure :: RegisterFailure -> [String]
renderRegisterFailure = renderRegisterFailureFor TheNode

-- | The report of a failed booking, as it reads for the other end of the chain.
renderRegisterFailureFor :: Counterpart -> RegisterFailure -> [String]
renderRegisterFailureFor counterpart =
    map (forCounterpart counterpart) . \case
        RegisterRefused refusal ->
            ["ckeri: registry register " <> phrase Command <> ": " <> renderRefusal refusal, zeroSpend]
        -- the evaluation of a transaction refused it, at the redeemer purpose the evaluator named: the command did not pre-empt it
        RegisterTransaction (EvaluationFailed message) ->
            [ "ckeri: registry register stopped, " <> phrase NodeEvaluation <> ": the node's evaluation refused the booking: " <> evidence message
            , zeroSpend
            ]
        RegisterTransaction failure@(SettledReportInterrupted _ message) ->
            ["ckeri: registry register settled; the command was cut short after that: " <> evidence message]
                <> failureRow "booking" failure
        RegisterTransaction failure ->
            renderSubmitFailure "registry register" "premint" False failure
                <> [zeroSpend | knownNothingSpent failure]
        -- a refusal of the command after the premint settled: the premint landed, the booking was not built
        RegisterRefusedAfterPremint premintId proofIn refusal ->
            premintLanded premintId proofIn StaysWithController
                <> ["ckeri: registry register stopped, refused by the command before building the booking: " <> renderRefusal refusal, "the booking was not built"]
        -- the run stopped between the premint and the booking: the report failed, no booking exists
        RegisterStoppedAfterPremint premintId proofIn message ->
            ["ckeri: registry register stopped after the premint settled, before the booking was built: " <> evidence message]
                <> premintLanded premintId proofIn StaysWithController
                <> ["the booking was not built"]
        -- the premint of the hash proof settled and the booking stopped: what landed, and what did not
        RegisterAfterPremint _ _ failure@(SettledReportInterrupted _ message) ->
            ["ckeri: registry register settled; the command was cut short after that: " <> evidence message]
                <> failureRow "booking" failure
        RegisterAfterPremint premintId proofIn failure ->
            bookingStopped failure
                <> premintLanded premintId proofIn (maybe StaysWithController MayBeSpent (bookingMayHaveLanded failure))
                <> ["the booking was not submitted" | knownNothingSpent failure]
  where
    bookingStopped = \case
        EvaluationFailed message ->
            ["ckeri: registry register stopped, " <> phrase NodeEvaluation <> ": the node's evaluation refused the booking: " <> evidence message]
        failure -> renderSubmitFailure "registry register" "booking" True failure
    -- the booking was handed over and not seen to settle: the proof output is spent if it landed, which is not known
    bookingMayHaveLanded = \case
        HandoffUnconfirmed txId _ -> Just txId
        NotObserved txId _ -> Just txId
        _ -> Nothing
    premintLanded premintId proofIn custody =
        [ "the premint of the hash proof settled: "
            <> T.unpack (renderTransactionId premintId)
            <> "; the proof output "
            <> renderTxIn proofIn
            <> case custody of
                StaysWithController -> " stays with the controller"
                MayBeSpent bookingId ->
                    " is spent if the booking " <> T.unpack (renderTransactionId bookingId) <> " landed; whether it landed is not known: reconcile it by that transaction's identifier before using the proof output again"
        ]
    -- nothing of this command reached the node: it was refused, failed before signing or was signed and never handed over
    knownNothingSpent = \case
        BuildRefused _ -> True
        EvaluationFailed _ -> True
        PurposesDiffer _ -> True
        BudgetExceeded _ -> True
        SigningRefused _ -> True
        NodeFailed _ -> True
        NotHandedOver _ _ -> True
        _ -> False

-- ---------------------------------------------------------------------
-- fold
-- ---------------------------------------------------------------------

runRegistryFold :: RegistryFoldSettings -> IO ()
runRegistryFold = runRegistryFoldOver (hPutStrLn stderr) shippedOpeners

{- | Fold a booked request through the node the opener reaches, on a snapshot of the
registry's keys a named party supplied and the registry state the chain holds.
-}
runRegistryFoldWith :: RegistryOpener -> RegistryFoldSettings -> IO ()
runRegistryFoldWith = runRegistryFoldReporting (hPutStrLn stderr)

-- | The same, with the writer of the final stop report given.
runRegistryFoldReporting :: (String -> IO ()) -> RegistryOpener -> RegistryFoldSettings -> IO ()
runRegistryFoldReporting errLine = runRegistryFoldOver errLine . nodeOnly

-- | The fold runs on the node socket only: a Koios option is refused by name before anything is read.
runRegistryFoldOver :: (String -> IO ()) -> Openers -> RegistryFoldSettings -> IO ()
runRegistryFoldOver errLine openers settings = do
    hPutStrLn stderr "ckeri: not for mainnet"
    provider <- either dieChoice pure (resolveProvider (rfProvider settings))
    case provider of
        OnKoios url token -> runFoldFromHistory errLine openers settings url token
        OnNode socket -> runFoldOnSuppliedState errLine openers settings socket

{- | The fold on a node socket, on the registry's keys a named party supplied: the registry state is checked
against the chain and the request is the one named.
-}
runFoldOnSuppliedState :: (String -> IO ()) -> Openers -> RegistryFoldSettings -> FilePath -> IO ()
runFoldOnSuppliedState errLine openers settings socket = do
    unless (null (rfPending settings)) $
        dieZero "pending-needs-a-provider: --pending names requests for a provider that serves public history (--koios-url); on a node socket give --request and --snapshot"
    key <- openKey "fold" (rfNetworkMagic settings) (rfSigningKeyFile settings) (rfVault settings) (rfPassphraseFd settings)
    when (rfTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rfBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles "fold" (rfReleaseIdentity settings) (rfReferenceRecord settings)
    request <- either dieZero pure (parseRequestReference (T.unpack (rfRequest settings)))
    snapshotBytes <-
        try @IOException (BS.readFile (rfSnapshot settings))
            >>= either (\failure -> dieZero ("snapshot-invalid: " <> rfSnapshot settings <> ": " <> show failure)) pure
    snapshot <-
        either (dieZero . (("snapshot-invalid: " <> rfSnapshot settings <> ": ") <>) . show) pure (decodeSnapshot snapshotBytes)
    forM_ (rfSnapshotOut settings) $ \path -> do
        taken <- doesPathExist path
        when taken $ dieZero ("file-exists: " <> path <> " is already there; it is not overwritten")
    putStrLn ("snapshot-supplied-by: " <> T.unpack (snapshotSuppliedBy snapshot))
    hFlush stdout
    withProvider openers (OnNode socket) Nothing (rfNetworkMagic settings) (rfFundingAddress settings) key (rfTimeoutSeconds settings) $ \(runtime, payer) -> do
        outcome <-
            foldBookedRequest
                runtime
                (printFoldEvent stdout)
                FoldInput
                    { foldBlueprint = blueprint
                    , foldIdentity = identity
                    , foldRecord = record
                    , foldRequestOutput = request
                    , foldSnapshot = snapshot
                    , foldPayerAddress = payer
                    }
        case outcome of
            Left stopped -> do
                mapM_ errLine (renderFoldStopped stopped)
                exitFailure
            Right done ->
                forM_ (rfSnapshotOut settings) $ \path -> do
                    written <- writeFileNew path (encodeSnapshot (doneSnapshot done) <> "\n")
                    either (die' . renderFilesFailure) pure written
                    putStrLn ("snapshot-written: " <> path <> " (an input the next fold checks again against the chain)")
                    hFlush stdout

-- | Print what a fold reports as it happens, to a handle, each line flushed when written.
printFoldEvent :: Handle -> FoldEvent -> IO ()
printFoldEvent out = \case
    SnapshotChecked{eventRoot = root} -> do
        hPutStrLn out ("snapshot-root: " <> hex root)
        hFlush out
    FoldHandingOff{eventTransaction = txId} -> do
        hPutStrLn out ("handing fold " <> T.unpack (renderTransactionId txId) <> " to the node")
        hFlush out
    FoldSettled{eventTransaction = txId, eventHolding = holding, eventFee = fee} -> do
        hPutStrLn out ("fold-transaction: " <> T.unpack (renderTransactionId txId))
        hPutStrLn out ("checkpoint-output: " <> renderTxIn holding)
        hPutStrLn out ("fold-fee: " <> show fee)
        hFlush out

{- | What a fold that stopped tells the person running it: why, how far the transaction it signed
got, the registry state the node last confirmed, and that nothing is retried.
-}
renderFoldStopped :: FoldStopped -> [String]
renderFoldStopped stopped = map (forCounterpart TheNode) (renderFoldBody stopped <> [zeroSpend | null (stoppedFoldAttempt stopped)])

renderFoldBody :: FoldStopped -> [String]
renderFoldBody stopped
    | Just (Attempt _ (SettledOnChain _)) <- stoppedFoldAttempt stopped =
        [ "ckeri: registry fold settled; the command was cut short after that: " <> causeText
        ]
            <> details
    | otherwise =
        case stoppedCause stopped of
            FoldRefused refusal
                | landedNothing
                , isWindowRow refusal ->
                    ["ckeri: registry fold " <> phrase Command <> " at the window check: " <> renderRefusal refusal] <> waitHint refusal
                | landedNothing ->
                    ["ckeri: registry fold " <> phrase Command <> ", before any window check: " <> renderRefusal refusal]
            FoldRefused refusal -> ["ckeri: registry fold stopped, " <> phrase Command <> ": " <> renderRefusal refusal] <> details
            FoldNodeFailed message
                | Just _ <- stoppedFoldAttempt stopped -> [foldHandoffStage message] <> details
                | otherwise ->
                    ["ckeri: registry fold stopped, the node could not be read: " <> message]
            FoldTransaction failure
                | HandoffUnconfirmed _ message <- failure
                , Just _ <- stoppedFoldAttempt stopped ->
                    [foldHandoffStage message] <> details
                | otherwise ->
                    renderSubmitFailure "registry fold" "fold" False failure <> details
  where
    landedNothing = null (stoppedFoldAttempt stopped)
    isWindowRow = \case
        DeadlineReached{} -> True
        TimeEvidenceConflicts{} -> True
        NoFoldSlotRemains{} -> True
        NoIntervalYet{} -> True
        _ -> False
    -- nothing was spent: running the command again after the next block is possible
    waitHint = \case
        NoIntervalYet{} -> ["the command can be run again after the next block"]
        _ -> []
    causeText = case stoppedCause stopped of
        FoldNodeFailed message -> message
        other -> show other
    foldHandoffStage message =
        "ckeri: registry fold stopped at the handoff of the fold to the node: " <> message
    details =
        concat [attemptRows "fold" attempt | Just attempt <- [stoppedFoldAttempt stopped]]
            <> [ "node-confirmed-state: " <> renderTxIn ref <> maybe "" ((" root " <>) . hex) root
               | Just (ref, root) <- [stoppedConfirmed stopped]
               ]
            <> ["not retried: no transaction is sent again by this command"]

-- ---------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------

phrase :: Boundary -> String
phrase = \case
    Unsettled -> "not seen to settle"
    boundary -> "refused by " <> renderBoundary boundary

-- | What a command that sent nothing says: the check it can make, and that it cost nothing.
zeroSpend :: String
zeroSpend = "nothing was submitted; nothing was spent"

{- | What is known of a transaction that was signed, by how far it got. The wording is the
whole of what the evidence supports: a handoff that began and whose outcome is unknown is
never called a submission and never called not submitted.
-}
attemptRow :: String -> Attempt -> String
attemptRow kind (Attempt txId status) = case status of
    NotHandedToNode -> label <> " was not handed to the node"
    HandoffUnknown -> label <> " may or may not have reached the node; check it before spending again"
    RefusedByNode reason -> label <> " was refused by the node: " <> evidence (reasonText reason) <> "; it is not on chain"
    AcceptedByNode -> label <> " was accepted by the node and is not seen on chain; check it before spending again"
    SettledOnChain _ -> label <> " was seen to settle"
  where
    label = kind <> " " <> T.unpack (renderTransactionId txId)

-- | The lines that say how far a transaction got: one row, and for one seen to settle its receipt.
attemptRows :: String -> Attempt -> [String]
attemptRows kind attempt@(Attempt txId status) = case status of
    SettledOnChain settled ->
        [ kind <> "-transaction: " <> T.unpack (renderTransactionId txId)
        , receiptOutput kind <> ": " <> renderTxIn (TxIn txId (TxIx 0))
        , kind <> "-fee: " <> show (feeOf settled)
        ]
    _ -> [attemptRow kind attempt]
  where
    receiptOutput = \case
        "fold" -> "checkpoint-output"
        "return" -> "refund-output"
        "booking" -> "booking-output"
        other -> other <> "-output"

-- | The row of a failure that carries the transaction it is about.
failureRow :: String -> SubmitError -> [String]
failureRow kind = \case
    NotHandedOver txId _ -> [attemptRow kind (Attempt txId NotHandedToNode)]
    HandoffUnconfirmed txId _ -> [attemptRow kind (Attempt txId HandoffUnknown)]
    SubmissionRefused txId reason -> [attemptRow kind (Attempt txId (RefusedByNode reason))]
    NotObserved txId _ -> [attemptRow kind (Attempt txId AcceptedByNode)]
    SettledReportInterrupted settled _ -> attemptRows kind (Attempt (transactionId settled) (SettledOnChain settled))
    _ -> []

renderSubmitFailure :: String -> String -> Bool -> SubmitError -> [String]
renderSubmitFailure command kind premintSettled failure =
    ["ckeri: " <> command <> " stopped, " <> how <> ": " <> cause]
        <> failureRow kind failure
  where
    notSubmitted = "the " <> kind
    -- what is said of where it stopped: after a settled premint nothing is "before any transaction",
    -- and a node that could not be read refused nothing
    how = case (failure, submitBoundary failure) of
        (NodeFailed _, _) -> "the node could not be read"
        (_, Command) | premintSettled -> "refused by the command after the premint settled: " <> notSubmitted <> " was not submitted"
        (_, boundary) -> phrase boundary
    cause = case failure of
        BuildRefused refusal -> "build-refused: " <> evidence (show refusal)
        EvaluationFailed message -> "evaluation-failed: " <> evidence message
        PurposesDiffer message -> "purposes-differ: " <> evidence message
        BudgetExceeded message -> "budget-exceeded: " <> evidence message
        SigningRefused message -> "signing-refused: " <> evidence message
        SubmissionRefused _ reason -> "submission-refused: " <> evidence (reasonText reason)
        NotHandedOver _ message -> "not-handed-over: " <> evidence message
        HandoffUnconfirmed _ message -> "handoff-unconfirmed: " <> evidence message
        NotObserved _ message -> "not-observed: " <> evidence message
        SettledReportInterrupted _ message -> "settled-report-interrupted: " <> evidence message
        NodeFailed message -> "node-failed: " <> evidence message

renderRefusal :: Refusal -> String
renderRefusal = \case
    DeploymentDisagrees message -> "deployment-disagrees: " <> message
    ReferenceOutputsMissing refs -> "reference-outputs-missing: " <> unwords (map renderTxIn refs)
    AlreadyRegistered key -> "already registered in this registry: the active token of " <> hex key <> " stands at the checkpoint validator's address"
    BookingWidthBelowSlotLength width slot ->
        "booking-width-below-slot-length: the registry's booking width " <> show width <> " ms is shorter than a slot of " <> show slot <> " ms"
    StaleOrUnavailableRegistryState (Just root) ->
        "stale or unavailable registry state: the snapshot is not the registry state the node holds (the node holds root " <> hex root <> ")"
    StaleOrUnavailableRegistryState Nothing ->
        "stale or unavailable registry state: the node holds no output with the registry's state token"
    RegistryHoldsKey key -> "the registry already holds this key: " <> hex key
    DeadlineReached deadline ->
        "deadline-reached: the timing condition for a return can be met from " <> show deadline <> " ms [W1]"
    TimeEvidenceConflicts now deadline tipStart ->
        "time-evidence-conflicts [W2]: the chain's tip slot starts at " <> show tipStart <> " ms, the machine reads " <> show now <> " ms and the request's deadline is " <> show deadline <> " ms; these readings leave current return eligibility undetermined"
    NoFoldSlotRemains deadline ->
        "no-fold-slot-remains [W3]: no whole slot is left before the request's deadline, " <> show deadline <> " ms; a return is possible from " <> show deadline <> " ms"
    NoIntervalYet deadline now ->
        "no-interval-yet [W4]: no validity interval can be formed now: the node's forecast ends at or before the slot the machine's clock (" <> show now <> " ms) is in; the deadline is " <> show deadline <> " ms"
    NoBookingIntervalYet now ->
        "no-interval-yet: the node's forecast shows no slot to book in at the machine's clock (" <> show now <> " ms)"
    DeadlineNotReached deadline tipStart now ->
        "deadline-not-reached: the request's deadline is " <> show deadline <> " ms, the chain's tip slot starts at " <> show tipStart <> " ms and the machine reads " <> show now <> " ms; the request can be returned from " <> show deadline <> " ms"
    NoReturnSlotYet tipStart ->
        "no-return-slot-yet: the chain's tip slot starts at " <> show tipStart <> " ms, at or after the deadline, and the node's forecast shows no slot after it to return in"
    RequestRefundUnreadable ref ->
        "request-refund-unreadable: the refund address of " <> renderTxIn ref <> " is not an address of this network; nothing is paid to a guess"
    RequestUnavailable ref -> "request-unavailable: " <> renderTxIn ref <> " is not an output the node holds unspent"
    RequestIsNotARegistration ref -> "request-is-not-a-registration: " <> renderTxIn ref
    RequestHasNoApproval ref -> "request-has-no-approval: " <> renderTxIn ref <> " holds the datum of a request and not the approval the booking minted"
    RequestIsForAnotherRegistry ref -> "request-is-for-another-registry: " <> renderTxIn ref

renderFilesFailure :: FilesError -> String
renderFilesFailure = \case
    FileExists path -> "file-exists: " <> path <> " is already there; it is not overwritten"
    FileIo path message -> "file-error: " <> path <> ": " <> message
    other -> "files: " <> show other

renderTxIn :: TxIn -> String
renderTxIn (TxIn txId (TxIx index)) = T.unpack (renderTransactionId txId) <> "#" <> show index

hex :: ByteString -> String
hex = B8.unpack . convertToBase Base16

-- | Stop with a named reason before anything was submitted: nothing was spent.
dieZero :: String -> IO a
dieZero message = hPutStrLn stderr ("ckeri: " <> message) >> hPutStrLn stderr zeroSpend >> exitFailure

-- | Stop with a named reason after a transaction may have left: no claim about what was spent.
die' :: String -> IO a
die' message = hPutStrLn stderr ("ckeri: " <> message) >> exitFailure

-- ---------------------------------------------------------------------
-- Inputs
-- ---------------------------------------------------------------------

{- | Read the two files of a registry, of either version, at the entry point of a command. A record of the
earlier development form is read and refused here, by name and in plain words, before a provider is opened:
this version builds no transaction for it.
-}
readFiles :: String -> FilePath -> FilePath -> IO (ReleaseIdentity, ReferenceRecord)
readFiles operation identityPath recordPath =
    readStoredDeploymentFiles identityPath recordPath >>= \case
        Left failure -> dieZero ("deployment-files-invalid: " <> show failure)
        Right (identity, CurrentRecord record) -> pure (identity, record)
        Right (_, LegacyRecord _) ->
            dieZero
                ( "registry-predates-attestation: the record describes a registry of an earlier development form, whose application depends on a program this version does not use; this version cannot build transactions for it, so registry "
                    <> operation
                    <> " stops here. The registry must be deployed again with this version."
                )

readExport :: FilePath -> IO InceptionExport
readExport path = do
    bytes <- try @IOException (BS.readFile path)
    case bytes of
        Left failure -> dieZero ("kli-export-invalid: " <> path <> ": " <> show failure)
        Right stream -> either (dieZero . (("kli-export-invalid: " <> path <> ": ") <>)) pure (parseInceptionExport stream)

-- | A booking output as @<transaction id>#<index>@.
parseRequestReference :: String -> Either String TxIn
parseRequestReference text = case break (== '#') text of
    (transaction, '#' : index)
        | [(n, "")] <- reads index
        , n >= 0 && n <= (65_535 :: Integer)
        , Right bytes <- convertFromBase Base16 (B8.pack transaction)
        , Just hash <- hashFromBytes bytes ->
            Right (TxIn (TxId (unsafeMakeSafeHash hash)) (TxIx (fromInteger n)))
    _ -> Left ("request-reference-invalid: " <> text <> " is not <transaction id>#<index>, an index from 0 to 65535")

-- ---------------------------------------------------------------------
-- The node
-- ---------------------------------------------------------------------

openRegistryNode :: RegistryOpener
openRegistryNode = openRegistryNodeBetween (pure ())

{- | The opener the commands ship, with an action run between the named check of the signing key
and the live context's own read of it: the place a file can change under the command.

Anything that fails before the operation is handed the runtime ends in the named outcome
with nothing submitted and nothing spent, the live context's own refusals included; nothing
that fails once the operation has begun is ever reported that way.

The node client is not linked to the command's thread: when the connection ends, each call of
the node that needs it fails, and the library turns that into the report of how far the run got.
-}
openRegistryNodeBetween :: IO () -> RegistryOpener
openRegistryNodeBetween between access use = do
    payer <- either dieZero pure (decodePaymentAddress (naFundingAddress access))
    -- the signing key is checked by name before the node is opened: nothing can have been submitted
    checkKey (naSigningKey access) payer >>= either dieZero pure
    between
    begun <- newIORef False
    opened <- try @IOException $ withNodeRuntime singularFundingRules Unlinked access $ \(runtime, _) -> do
        -- from here the operation has begun: whatever follows is never a startup refusal
        writeIORef begun True
        use (runtime, payer)
    case opened of
        Right result -> pure result
        Left failure -> do
            started <- readIORef begun
            if started
                then ioError failure
                else dieZero (startupRefusal failure)
  where
    startupRefusal failure
        | isDoesNotExistError failure = "signing-key-file-missing: " <> show failure
        | otherwise = "signing-key-startup-failed: " <> show failure

{- | The opener the commands ship for Koios: the signing key is checked by name against the paying
address, then the instance is built over the live transport, which reads the token from its file.
Every handoff it makes is reported as it ends. Anything that fails before the operation is handed
the runtime ends in a named outcome with nothing submitted and nothing spent.
-}
openRegistryKoios :: KoiosOpener
openRegistryKoios access use = do
    payer <- either dieZero pure (decodePaymentAddress (koiosFundingAddress access))
    checkKey (koiosSigningKey access) payer >>= either dieZero pure
    opened <- openKoiosRuntime printHandoffReport access
    runtime <- either (dieZero . renderKoiosStartFailure) pure opened
    use (runtime, payer)

-- | The openers of the commands that run on the node unlinked: the node's and Koios's.
shippedOpeners :: Openers
shippedOpeners = Openers{openersNode = openRegistryNode, openersKoios = openRegistryKoios, openersKoiosFold = openRegistryKoiosFold}

-- | Stop with the refusal of a provider choice: nothing was read, so nothing was submitted.
dieChoice :: ProviderRefusal -> IO a
dieChoice = dieZero . renderProviderRefusal

-- ---------------------------------------------------------------------
-- return
-- ---------------------------------------------------------------------

-- | Everything @ckeri registry return@ is given: the files, the node, the request and who pays.
data RegistryReturnSettings = RegistryReturnSettings
    { rnNetworkMagic :: !Int
    , rnBlueprint :: !FilePath
    , rnProvider :: !ProviderChoice
    , rnFundingAddress :: !Text
    , rnSigningKeyFile :: !(Maybe FilePath)
    , rnVault :: !(Maybe FilePath)
    , rnPassphraseFd :: !(Maybe Int)
    , rnTimeoutSeconds :: !Int
    , rnReleaseIdentity :: !FilePath
    , rnReferenceRecord :: !FilePath
    , rnRequest :: !Text
    }
    deriving stock (Show, Eq)

registryReturnSettingsParser :: Opt.Parser RegistryReturnSettings
registryReturnSettingsParser = do
    rnNetworkMagic <- intSetting "network-magic" (Just 1) "Cardano testnet network magic"
    rnBlueprint <- stringSetting "blueprint" "Immutable Aiken plutus.json"
    rnProvider <- providerChoiceParser
    rnFundingAddress <- T.pack <$> stringSetting "funding-address" "Bech32 payment address that pays the return and keeps the tip"
    rnSigningKeyFile <- signingKeyFileSetting
    rnVault <- vaultSetting
    rnPassphraseFd <- passphraseFdSetting
    rnTimeoutSeconds <- intSetting "timeout-seconds" (Just 600) "Settlement timeout per transaction on the node (on Koios a transaction is waited for until two minutes after its validity end)"
    rnReleaseIdentity <- stringSetting "release-identity" "The release identity file registry deploy wrote"
    rnReferenceRecord <- stringSetting "reference-record" "The reference-output record registry deploy wrote"
    rnRequest <- T.pack <$> stringSetting "request" "The booking output to return, as <transaction id>#<index>"
    pure RegistryReturnSettings{..}

runRegistryReturn :: RegistryReturnSettings -> IO ()
runRegistryReturn = runRegistryReturnOver (hPutStrLn stderr) shippedOpeners

{- | Return a booked request through the node the opener reaches: what the request's own
datum and output say is paid to the refund address it names, whoever runs the command.
-}
runRegistryReturnWith :: RegistryOpener -> RegistryReturnSettings -> IO ()
runRegistryReturnWith = runRegistryReturnReporting (hPutStrLn stderr)

-- | The same, with the writer of the final stop report given.
runRegistryReturnReporting :: (String -> IO ()) -> RegistryOpener -> RegistryReturnSettings -> IO ()
runRegistryReturnReporting errLine = runRegistryReturnOver errLine . nodeOnly

-- | The same over the openers of both providers: the one the settings choose is the one used.
runRegistryReturnOver :: (String -> IO ()) -> Openers -> RegistryReturnSettings -> IO ()
runRegistryReturnOver errLine openers settings = do
    transliterateReports
    hPutStrLn stderr "ckeri: not for mainnet"
    provider <- either dieChoice pure (resolveProvider (rnProvider settings))
    let counterpart = counterpartOf provider
    key <- openKey "return" (rnNetworkMagic settings) (rnSigningKeyFile settings) (rnVault settings) (rnPassphraseFd settings)
    when (rnTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rnBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles "return" (rnReleaseIdentity settings) (rnReferenceRecord settings)
    request <- either dieZero pure (parseRequestReference (T.unpack (rnRequest settings)))
    withProvider openers provider (chosenNetworkTime (rnProvider settings)) (rnNetworkMagic settings) (rnFundingAddress settings) key (rnTimeoutSeconds settings) $ \(runtime, payer) -> do
        outcome <-
            returnBookedRequest
                runtime
                (printReturnEventFor counterpart stdout)
                ReturnInput
                    { returnBlueprint = blueprint
                    , returnIdentity = identity
                    , returnRecord = record
                    , returnRequestOutput = request
                    , returnPayerAddress = payer
                    }
        case outcome of
            Left stopped -> do
                mapM_ errLine (renderReturnStoppedFor counterpart stopped)
                exitFailure
            Right _ -> pure ()

-- | Print what a return reports as it happens, to a handle, each line flushed when written.
printReturnEvent :: Handle -> ReturnEvent -> IO ()
printReturnEvent = printReturnEventFor TheNode

-- | The same, as it reads for the other end of the chain.
printReturnEventFor :: Counterpart -> Handle -> ReturnEvent -> IO ()
printReturnEventFor counterpart out = \case
    ReturnPlanned{plannedRequest = request, plannedRefundAddress = refundTo, plannedRefundLovelace = refund, plannedTipLovelace = tip, plannedPlan = plan, plannedDeadline = deadline} -> do
        let slots (SlotNo n) = show n
        hPutStrLn out ("return-request: " <> renderTxIn request)
        hPutStrLn out ("refund-address: " <> renderAddress refundTo)
        hPutStrLn out ("refund-lovelace: " <> show refund)
        hPutStrLn out ("tip-lovelace: " <> show tip)
        hPutStrLn out ("validity-interval-slots: " <> slots (lowerSlot plan) <> ".." <> slots (upperSlot plan))
        hPutStrLn out ("validity-interval-ms: " <> show (lowerPosixMs plan) <> ".." <> show (upperPosixMs plan))
        hPutStrLn out ("deadline-ms: " <> show deadline)
        hFlush out
    ReturnHandingOff{handingOffTransaction = txId} -> do
        hPutStrLn out (forCounterpart counterpart ("handing return " <> T.unpack (renderTransactionId txId) <> " to the node"))
        hFlush out
    ReturnSettled{settledTransaction = txId, settledRefundOutput = refundOutput, settledFee = fee} -> do
        hPutStrLn out ("return-transaction: " <> T.unpack (renderTransactionId txId))
        hPutStrLn out ("refund-output: " <> renderTxIn refundOutput)
        hPutStrLn out ("return-fee: " <> show fee)
        hFlush out

-- | An address as the bech32 text of its bytes, with the human-readable part of its network.
renderAddress :: Addr -> String
renderAddress address = case Bech32.humanReadablePartFromText prefix of
    -- the strict encoder stops at 90 characters, and an address with a stake part is longer: the
    -- lenient one has no such limit, and 'decodePaymentAddress' reads it back
    Right hrp -> T.unpack (Bech32.encodeLenient hrp (Bech32.dataPartFromBytes (serialiseAddr address)))
    Left failure -> error (show failure)
  where
    prefix = case getNetwork address of
        Mainnet -> "addr"
        Testnet -> "addr_test"

{- | What a return that stopped tells the person running it: why, how far its transaction got,
and that nothing is retried.
-}
renderReturnStopped :: ReturnStopped -> [String]
renderReturnStopped = renderReturnStoppedFor TheNode

-- | The same, as it reads for the other end of the chain: on Koios the handoff may have sent the same signed bytes again, so nothing is said of sending nothing again.
renderReturnStoppedFor :: Counterpart -> ReturnStopped -> [String]
renderReturnStoppedFor counterpart stopped = map (forCounterpart counterpart) (body <> [zeroSpend | nothingSpent])
  where
    attempt = returnAttempt stopped
    -- nothing left the command: no transaction was signed, or it was signed and never handed over
    nothingSpent = all (\(Attempt _ status) -> status == NotHandedToNode) attempt
    notRetried = [retried | Just _ <- [attempt]]
    retried = case counterpart of
        TheNode -> "not retried: no transaction is sent again by this command"
        TheProvider -> "not retried: no other transaction is built, signed or sent by this command; the handoff report counts the attempts that sent the same signed bytes again"
    body
        | Just settled@(Attempt _ (SettledOnChain _)) <- attempt =
            ["ckeri: registry return settled; the command was cut short after that: " <> evidence causeText]
                <> attemptRows "return" settled
                <> notRetried
        | otherwise = case returnCause stopped of
            ReturnRefused refusal ->
                ["ckeri: registry return " <> phrase Command <> ": " <> renderRefusal refusal] <> waitHint refusal
            ReturnNodeFailed message ->
                ["ckeri: registry return stopped, the node could not be read: " <> evidence message]
                    <> maybe [] (\held -> [attemptRow "return" held]) attempt
                    <> notRetried
            ReturnReportFailed message ->
                ["ckeri: registry return stopped, the report could not be written: " <> evidence message]
                    <> maybe [] (\held -> [attemptRow "return" held]) attempt
                    <> notRetried
            ReturnTransaction failure ->
                renderSubmitFailure "registry return" "return" False failure <> notRetried
    causeText = case returnCause stopped of
        ReturnNodeFailed message -> message
        ReturnReportFailed message -> message
        ReturnTransaction (SettledReportInterrupted _ message) -> message
        other -> show other
    -- nothing was spent: running the command again after the next block is possible
    waitHint = \case
        NoReturnSlotYet{} -> ["the command can be run again after the next block"]
        _ -> []

{- | The key the settings name, or the stop before any transaction: the refusal is made by
the command, and nothing was submitted.
-}
openKey :: String -> Int -> Maybe FilePath -> Maybe FilePath -> Maybe Int -> IO KeySource
openKey verb magic file vault descriptor =
    resolveKeySource magic file vault descriptor
        >>= either (\refusal -> dieZero ("registry " <> verb <> " " <> phrase Command <> ": " <> renderKeySourceRefusal refusal)) pure

-- | The check of the signing key, by name, before the node is opened.
checkKey :: KeySource -> Addr -> IO (Either String ())
checkKey = \case
    KeyFile path -> checkSigningKey path
    KeyEnvelope envelope -> pure . checkSigningEnvelope envelope

-- | What the report may say of the proof output the premint left, once the booking stopped.
data ProofCustody
    = -- | the booking never reached the node, or was refused: the output is unspent
      StaysWithController
    | -- | the booking was handed over and not seen to settle: it spends the proof output if it landed
      MayBeSpent !TxId

-- | @--pending@, repeatable: a booked request to fold, as <transaction id>#<index>.
pendingSetting :: Opt.Parser String
pendingSetting =
    Opt.setting
        [ Opt.reader Opt.str
        , Opt.option
        , Opt.long "pending"
        , Opt.metavar "REF"
        , Opt.help "On a provider (--koios-url): a booked request to fold, as <transaction id>#<index>; repeat it to fold several in one transaction. The registry's state is rebuilt from public history"
        ]

-- ---------------------------------------------------------------------
-- fold from public history
-- ---------------------------------------------------------------------

-- | The opener the fold ships for Koios: the key is checked against the paying address, then the runtime and the session.
openRegistryKoiosFold :: KoiosFoldOpener
openRegistryKoiosFold access use = do
    payer <- either dieZero pure (decodePaymentAddress (koiosFundingAddress access))
    checkKey (koiosSigningKey access) payer >>= either dieZero pure
    opened <- openKoios printHandoffReport access
    session <- either (dieZero . renderKoiosStartFailure) pure opened
    use session payer

{- | The fold on a provider that serves public history: the registry's state is rebuilt from that
history, never supplied; the booked requests named with @--pending@ are read and authenticated from their
public outputs; the batch, its validity window and its balance are public Singular's. A provider
that cannot give the whole history stops the command before anything is signed.
-}
runFoldFromHistory :: (String -> IO ()) -> Openers -> RegistryFoldSettings -> Text -> Maybe FilePath -> IO ()
runFoldFromHistory errLine openers settings url token = do
    when (not (T.null (rfRequest settings)) || not (null (rfSnapshot settings)) || isJust (rfSnapshotOut settings)) $
        dieZero "supplied-state-not-used: on a provider the registry's state is rebuilt from public history; --request, --snapshot and --snapshot-out are for a node socket"
    when (null (rfPending settings)) $
        dieZero "pending-missing: name at least one booked request with --pending <transaction id>#<index>"
    pendings <- either dieZero pure (traverse (parseRequestReference . T.unpack) (rfPending settings))
    key <- openKey "fold" (rfNetworkMagic settings) (rfSigningKeyFile settings) (rfVault settings) (rfPassphraseFd settings)
    when (rfTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rfBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles "fold" (rfReleaseIdentity settings) (rfReferenceRecord settings)
    let access =
            KoiosAccess
                { koiosUrl = url
                , koiosTokenFile = token
                , koiosNetworkMagic = rfNetworkMagic settings
                , koiosFundingAddress = rfFundingAddress settings
                , koiosSigningKey = key
                , koiosNetworkTime = chosenNetworkTime (rfProvider settings)
                }
    putStrLn ("registry-state: rebuilt from the public history of its state token; requests named: " <> show (length pendings))
    hFlush stdout
    announced <- newIORef Nothing
    openersKoiosFold openers access $ \opened payer -> do
        outcome <-
            foldNamed
                opened
                (announceAttempt announced)
                NamedFoldInput
                    { namedBlueprint = blueprint
                    , namedIdentity = identity
                    , namedRecord = record
                    , namedPending = pendings
                    , namedPayer = payer
                    }
        case outcome of
            Left stop -> do
                mapM_ errLine (renderNamedStop stop)
                exitFailure
            Right done -> printNamedDone done
  where
    -- a signed transaction is announced to the person running the command once, before it is handed over
    announceAttempt announced = \case
        Attempt txId NotHandedToNode -> do
            before <- readIORef announced
            when (before /= Just txId) $ do
                writeIORef announced (Just txId)
                putStrLn ("handing fold " <> T.unpack (renderTransactionId txId) <> " to the provider")
                hFlush stdout
        _ -> pure ()

-- | What a settled fold says: the transaction, what it paid, what it folded, and what it left.
printNamedDone :: NamedFoldDone -> IO ()
printNamedDone done = do
    let tx = doneTransaction done
    putStrLn ("fold-transaction: " <> T.unpack (renderTransactionId (transactionId tx)))
    putStrLn ("fold-fee: " <> show (feeOf tx))
    forM_ (doneFolded done) $ \folded ->
        putStrLn ("folded: " <> renderTxIn (foldedRef folded) <> " " <> foldedKind folded <> " key " <> hex (foldedKeyBytes folded))
    forM_ (doneSkipped done) $ \(ref, reason) ->
        putStrLn ("skipped: " <> renderTxIn ref <> " " <> reason)
    putStrLn ("left: " <> show (doneLeft done))
    hFlush stdout

{- | What a fold that stopped tells the person running it: why, how far the transaction it signed
got, and that nothing is retried.
-}
renderNamedStop :: NamedFoldStop -> [String]
renderNamedStop =
    map (forCounterpart TheProvider) . \case
        NamedFilesRefused refusal ->
            ["ckeri: registry fold " <> phrase Command <> ", before anything was read of the registry: " <> renderRefusal refusal, zeroSpend]
        NamedReadFailed message ->
            ["ckeri: registry fold stopped, the node could not be read: " <> message, zeroSpend]
        NamedNotAcquired message ->
            ["ckeri: registry fold stopped, the chain could not be read as one session: " <> message, zeroSpend]
        NamedFoldRefused reason observed ->
            ["ckeri: registry fold refused before anything was submitted: " <> reason]
                <> [ "skipped: " <> renderTxIn ref <> " " <> why
                   | (ref, why) <- maybe [] fst observed
                   ]
                <> ["left: " <> show left | Just (_, left) <- [observed]]
                <> [zeroSpend]
        NamedTransaction failure attempt ->
            renderSubmitFailure "registry fold" "fold" False failure
                <> concat [attemptRows "fold" a | Just a <- [attempt]]
                <> ["not retried: no transaction is sent again by this command"]
                <> [zeroSpend | null attempt]

-- ---------------------------------------------------------------------
-- the readback of a checkpoint by its identifier
-- ---------------------------------------------------------------------

{- | What @ckeri status@ and @ckeri checkpoint@ are given beside their backend settings to read the rebuilt
registry: the files @registry deploy@ wrote, the blueprint, and the provider settings @registry fold@ takes. With
none of the three file settings the command reads the first deployment, as it always did.
-}
data RegistryReadFlags = RegistryReadFlags
    { rrReleaseIdentity :: !(Maybe FilePath)
    , rrReferenceRecord :: !(Maybe FilePath)
    , rrBlueprint :: !(Maybe FilePath)
    , rrNetworkMagic :: !Int
    , rrKoiosTokenFile :: !(Maybe FilePath)
    , rrNetworkTime :: !(Maybe FilePath)
    }
    deriving stock (Show, Eq)

-- | Which design a command reads.
data RegistryReadMode
    = -- | the first deployment, through its manifest, as before
      ReadFirstDeployment
    | -- | the rebuilt registry, through the ledger provider
      ReadRegistry !FilePath !FilePath !FilePath
    deriving stock (Show, Eq)

registryReadFlagsParser :: Opt.Parser RegistryReadFlags
registryReadFlagsParser = do
    rrReleaseIdentity <- Opt.optional (flagSetting "release-identity" "Read the rebuilt registry: the release identity file registry deploy wrote")
    rrReferenceRecord <- Opt.optional (flagSetting "reference-record" "Read the rebuilt registry: the reference-output record registry deploy wrote")
    rrBlueprint <- Opt.optional (flagSetting "blueprint" "Read the rebuilt registry: the immutable Aiken plutus.json")
    rrNetworkMagic <- intSetting "network-magic" (Just 1) "Cardano network magic of the rebuilt registry's provider"
    rrKoiosTokenFile <-
        Opt.optional $
            stringSetting "koios-token-file" "File holding the Koios bearer token, read by the transport (rebuilt registry)"
    rrNetworkTime <-
        Opt.optional $
            stringSetting "network-time" "Directory of the network time, as public Singular reads it (rebuilt registry)"
    pure RegistryReadFlags{..}

-- | The design the flags choose: all three files, or none and no other registry flag.
registryReadMode :: RegistryReadFlags -> Either String RegistryReadMode
registryReadMode flags = case (rrReleaseIdentity flags, rrReferenceRecord flags, rrBlueprint flags) of
    (Just identity, Just record, Just blueprint) -> Right (ReadRegistry identity record blueprint)
    (Nothing, Nothing, Nothing)
        | isJust (rrKoiosTokenFile flags) || isJust (rrNetworkTime flags) ->
            Left "registry-flags-without-files: --koios-token-file and --network-time are for the rebuilt registry, which is chosen with --release-identity, --reference-record and --blueprint"
        | otherwise -> Right ReadFirstDeployment
    _ -> Left "registry-files-incomplete: reading the rebuilt registry needs --release-identity, --reference-record and --blueprint together"

-- | How the readback opens the provider: no key and no payer, since nothing is signed.
type KoiosReadOpener = KoiosAccess -> (Acquirer -> IO ()) -> IO ()

-- | The opener the readback ships: the live Koios transport of the fold, without its key.
openRegistryKoiosRead :: KoiosReadOpener
openRegistryKoiosRead access use = do
    opened <- openKoios printHandoffReport access
    either (dieZero . renderKoiosStartFailure) (use . acquirerOf) opened
  where
    acquirerOf opened = Acquirer (openedAcquire opened)

{- | Read the checkpoint of an identifier, exactly as signed and booked, through the ledger provider, and print
what the registry stores for it with the references that tie it to the booking.
-}
runRegistryReadbackOver :: KoiosReadOpener -> RegistryReadFlags -> FilePath -> FilePath -> FilePath -> Text -> Text -> IO ()
runRegistryReadbackOver open flags identityPath recordPath blueprintPath url aid = do
    identifier <- case parsePrimitive (TE.encodeUtf8 aid) of
        Right (Ed25519PublicKey _, rest) | B8.null rest -> pure (TE.encodeUtf8 aid)
        Right (SelfAddressing _, rest) | B8.null rest -> pure (TE.encodeUtf8 aid)
        _ -> dieZero "aid-invalid: the identifier must be one complete qualified B, D or E identifier, as it was signed"
    blueprint <-
        try @IOException (loadBlueprint blueprintPath)
            >>= either (\failure -> dieZero ("blueprint-invalid: " <> blueprintPath <> ": " <> show failure)) (either (dieZero . ("blueprint-invalid: " <>)) pure)
    (identity, _) <- readFiles "status" identityPath recordPath
    deployment <- either (dieZero . ("deployment-refused: " <>) . renderRefusal) pure (deriveDeployment blueprint identity)
    let access =
            KoiosAccess
                { koiosUrl = url
                , koiosTokenFile = rrKoiosTokenFile flags
                , koiosNetworkMagic = rrNetworkMagic flags
                , koiosFundingAddress = ""
                , koiosSigningKey = KeyFile ""
                , koiosNetworkTime = rrNetworkTime flags
                }
    open access $ \(Acquirer acquire) ->
        acquire (\session -> readCheckpoint deployment session identifier) >>= \case
            Left failure -> dieZero ("provider-not-acquired: " <> show failure)
            Right (Left failure) -> dieZero ("provider-read-failed: " <> show failure)
            Right (Right readback) -> mapM_ putStrLn (renderReadback url aid readback) >> hFlush stdout

-- | What the readback prints: the stored state, then the links, or the link that could not be followed.
renderReadback :: Text -> Text -> Maybe Readback -> [String]
renderReadback url aid = \case
    Nothing ->
        [ "source: " <> T.unpack url
        , "identifier: " <> T.unpack aid
        , "checkpoint: none (no output holds the active token of this identifier)"
        ]
    Just readback ->
        ["source: " <> T.unpack url, "identifier: " <> B8.unpack (readbackIdentifier readback)]
            <> ["current-key: " <> B8.unpack key | key <- readbackKeys readback]
            <> ["checkpoint-output: " <> renderTxIn (readbackCheckpoint readback)]
            <> case readbackLinks readback of
                Right linked ->
                    [ "fold-transaction: " <> T.unpack (renderTransactionId (linkedFold linked))
                    , "pending-output: " <> renderTxIn (linkedPending linked)
                    , "booking-transaction: " <> T.unpack (renderTransactionId (linkedBooking linked))
                    , "booking-output-index: " <> show (linkedIndex linked)
                    , "inception-digest: " <> B8.unpack (qb64Aid (linkedDigest linked))
                    , "links: complete"
                    ]
                Left (link, failure) ->
                    [ "links: not linked"
                    , "failed-link: " <> renderLink link
                    , "reason: " <> renderLinkFailure failure
                    , "inception-digest: not established"
                    ]

renderLink :: Link -> String
renderLink = \case
    AtFoldTransaction -> "fold-transaction"
    AtPendingOutput -> "pending-output"
    AtBookingTransaction -> "booking-transaction"
    AtBookingEvidence -> "booking-evidence"
    AtSignedIdentifier -> "signed-identifier"

renderLinkFailure :: LinkFailure -> String
renderLinkFailure = \case
    NotShown link -> "the provider does not show the " <> renderLink link
    ProviderRefused link message -> "the provider refused the read of the " <> renderLink link <> ": " <> message
    EvidenceUndecodable -> "the evidence of the booking at this output is not one complete inception"
    IdentifierDiffers -> "the identifier in the signed bytes is not the stored one"
    DigestDoesNotBind -> "the signed bytes do not bind the digest they carry"
