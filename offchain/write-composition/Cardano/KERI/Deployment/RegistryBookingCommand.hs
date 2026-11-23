{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingCommand
Description : @ckeri registry register@ books a registration, @ckeri registry fold@ folds one

Both commands read chain state only through the node and the two files
@ckeri registry deploy@ wrote. They open no follower store and no manifest of
the first deployment, and keep no list of registered keys of their own: a fold
is given a snapshot of the registry's keys by a named party and checks it
against the registry state the chain holds before it pays anything.

Every refusal says where it was made: by the command before any transaction, by
the node's evaluation of a transaction, or by the ledger. Every transaction id
is printed, flushed, as it settles.
-}
module Cardano.KERI.Deployment.RegistryBookingCommand (
    NodeAccess (..),
    RegistryOpener,
    RegistryRegisterSettings (..),
    registryRegisterSettingsParser,
    runRegistryRegister,
    runRegistryRegisterWith,
    RegistryFoldSettings (..),
    registryFoldSettingsParser,
    runRegistryFold,
    runRegistryFoldWith,
    runRegistryFoldReporting,
    runRegistryRegisterReporting,
    printFoldEvent,
    renderFoldStopped,
    renderRegisterFailure,
    observeFrom,
    openRegistryNode,
    openRegistryNodeBetween,
    parseRequestReference,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (ApplicationParameters (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..), parseInceptionExport)
import Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    decodePaymentAddress,
    withUnlinkedLiveContext,
 )
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Boundary (..),
    Observation (..),
    Refusal (..),
    RegistryRuntime (..),
    SubmitError (..),
    feeOf,
    renderBoundary,
    submitBoundary,
    whileConnected,
 )
import Cardano.KERI.Deployment.RegistryCommand (awaitFirstOutput)
import Cardano.KERI.Deployment.RegistryFiles (FilesError (..), ReferenceRecord, readDeploymentFiles, writeFileNew)
import Cardano.KERI.Deployment.RegistryFold (
    FoldCause (..),
    FoldDone (..),
    FoldEvent (..),
    FoldInput (..),
    FoldStage (..),
    FoldStopped (..),
    foldBookedRequest,
 )
import Cardano.KERI.Deployment.RegistryRegister (
    RegisterEvent (..),
    RegisterFailure (..),
    RegisterRequest (..),
    registerRegistration,
 )
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), decodeSnapshot, encodeSnapshot)
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..))
import Cardano.KERI.Deployment.Script (loadBlueprint)
import Cardano.KERI.Deployment.SigningKeyCheck (checkSigningKey)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
    posixMsToSlotH,
    queryLedgerSnapshotH,
 )
import Control.Exception (ErrorCall (..), IOException, catchJust, try)
import Control.Monad (forM_, when)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (toUpper)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import OptEnvConf qualified as Opt
import System.Directory (doesPathExist)
import System.Exit (exitFailure)
import System.IO (Handle, hFlush, hPutStrLn, stderr, stdout)
import System.IO.Error (isDoesNotExistError)

-- | How a command reaches the node and who pays.
data NodeAccess = NodeAccess
    { naNetworkMagic :: !Int
    , naNodeSocket :: !FilePath
    , naFundingAddress :: !Text
    , naSigningKeyFile :: !FilePath
    , naTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

-- | How the commands reach the node: the runtime and the paying address.
type RegistryOpener = NodeAccess -> ((RegistryRuntime, Addr) -> IO ()) -> IO ()

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------

-- | Everything @ckeri registry register@ is given.
data RegistryRegisterSettings = RegistryRegisterSettings
    { rgNetworkMagic :: !Int
    , rgBlueprint :: !FilePath
    , rgNodeSocket :: !FilePath
    , rgFundingAddress :: !Text
    , rgSigningKeyFile :: !FilePath
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
    , rfNodeSocket :: !FilePath
    , rfFundingAddress :: !Text
    , rfSigningKeyFile :: !FilePath
    , rfTimeoutSeconds :: !Int
    , rfReleaseIdentity :: !FilePath
    , rfReferenceRecord :: !FilePath
    , rfKliExport :: !FilePath
    , rfRequest :: !Text
    , rfSnapshot :: !FilePath
    , rfSnapshotOut :: !(Maybe FilePath)
    }
    deriving stock (Show, Eq)

registryRegisterSettingsParser :: Opt.Parser RegistryRegisterSettings
registryRegisterSettingsParser = do
    rgNetworkMagic <- intSetting "network-magic" (Just 1) "Cardano testnet network magic"
    rgBlueprint <- stringSetting "blueprint" "Immutable Aiken plutus.json"
    rgNodeSocket <- stringSetting "node-socket" "Cardano node socket"
    rgFundingAddress <- T.pack <$> stringSetting "funding-address" "Bech32 payment address that pays the booking and is the refund address"
    rgSigningKeyFile <- stringSetting "signing-key-file" "Cardano payment signing-key envelope"
    rgTimeoutSeconds <- intSetting "timeout-seconds" (Just 600) "Settlement timeout per transaction"
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
    rfNodeSocket <- stringSetting "node-socket" "Cardano node socket"
    rfFundingAddress <- T.pack <$> stringSetting "funding-address" "Bech32 payment address that pays the fold: not the controller's"
    rfSigningKeyFile <- stringSetting "signing-key-file" "Cardano payment signing-key envelope"
    rfTimeoutSeconds <- intSetting "timeout-seconds" (Just 600) "Settlement timeout per transaction"
    rfReleaseIdentity <- stringSetting "release-identity" "The release identity file registry deploy wrote"
    rfReferenceRecord <- stringSetting "reference-record" "The reference-output record registry deploy wrote"
    rfKliExport <- stringSetting "kli-export" "The controller's kli export stream"
    rfRequest <- T.pack <$> stringSetting "request" "The booking output to fold, as <transaction id>#<index>"
    rfSnapshot <- stringSetting "snapshot" "The registry's active and terminal keys, as a named party supplies them"
    rfSnapshotOut <-
        Opt.optional $
            stringSetting "snapshot-out" "Where the registry as it stands after the fold is written for the next folder (must not exist)"
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
runRegistryRegister = runRegistryRegisterWith openRegistryNode

{- | Book a registration through the node the opener reaches: what the files and the
export name, over a window the registry's booking width allows.
-}
runRegistryRegisterWith :: RegistryOpener -> RegistryRegisterSettings -> IO ()
runRegistryRegisterWith = runRegistryRegisterReporting (hPutStrLn stderr)

{- | The same, with the writer of the final failure report given: each line of it goes through
the writer, which is how a test reaches the instants inside that report.
-}
runRegistryRegisterReporting :: (String -> IO ()) -> RegistryOpener -> RegistryRegisterSettings -> IO ()
runRegistryRegisterReporting errLine open settings = do
    hPutStrLn stderr "ckeri: not for mainnet"
    when (rgTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rgBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles (rgReleaseIdentity settings) (rgReferenceRecord settings)
    export <- readExport (rgKliExport settings)
    putStrLn
        "ckeri: this checks the registry's checkpoint address only: it cannot see a terminal key or another pending booking of this identity; the fold is where a duplicate is stopped"
    hFlush stdout
    open (NodeAccess (rgNetworkMagic settings) (rgNodeSocket settings) (rgFundingAddress settings) (rgSigningKeyFile settings) (rgTimeoutSeconds settings)) $ \(runtime, payer) -> do
        outcome <-
            registerRegistration
                runtime
                (printRegisterEvent (bookingWidth (riApplicationParameters identity)))
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
                mapM_ errLine (renderRegisterFailure failure)
                exitFailure

printRegisterEvent :: Integer -> RegisterEvent -> IO ()
printRegisterEvent intended = \case
    BookingWindow{eventPlan = plan, eventDeadline = deadline} -> do
        let slots (SlotNo n) = show n
        putStrLn ("validity-interval-slots: " <> slots (lowerSlot plan) <> ".." <> slots (upperSlot plan))
        putStrLn ("validity-interval-ms: " <> show (lowerPosixMs plan) <> ".." <> show (upperPosixMs plan))
        putStrLn ("intended-width-ms: " <> show intended)
        putStrLn ("actual-width-ms: " <> show (upperPosixMs plan - lowerPosixMs plan))
        putStrLn ("deadline-ms: " <> show deadline)
        hFlush stdout
    BookingSubmitting{eventTransaction = txId, eventTimeLeftMs = left} -> do
        putStrLn ("handing booking " <> T.unpack (renderTransactionId txId) <> " to the node")
        putStrLn ("time-left-ms: " <> show left)
        hFlush stdout
    BookingSettled{eventTransaction = txId, eventOutput = output, eventFee = fee} -> do
        putStrLn ("booking-transaction: " <> T.unpack (renderTransactionId txId))
        putStrLn ("booking-output: " <> renderTxIn output)
        putStrLn ("booking-fee: " <> show fee)
        hFlush stdout

renderRegisterFailure :: RegisterFailure -> [String]
renderRegisterFailure = \case
    RegisterRefused refusal ->
        ["ckeri: registry register " <> phrase Command <> ": " <> renderRefusal refusal, zeroSpend]
    RegisterTransaction failure@(SettledReportInterrupted _ message) ->
        ["ckeri: registry register settled; the command was cut short after that: " <> message]
            <> failureRow "booking" failure
    RegisterTransaction failure ->
        renderSubmitFailure "registry register" False failure
            <> [zeroSpend | knownNothingSpent failure]
  where
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
runRegistryFold = runRegistryFoldWith openRegistryNode

{- | Fold a booked request through the node the opener reaches, on a snapshot of the
registry's keys a named party supplied and the registry state the chain holds.
-}
runRegistryFoldWith :: RegistryOpener -> RegistryFoldSettings -> IO ()
runRegistryFoldWith = runRegistryFoldReporting (hPutStrLn stderr)

-- | The same, with the writer of the final stop report given.
runRegistryFoldReporting :: (String -> IO ()) -> RegistryOpener -> RegistryFoldSettings -> IO ()
runRegistryFoldReporting errLine open settings = do
    hPutStrLn stderr "ckeri: not for mainnet"
    when (rfTimeoutSeconds settings <= 0) $ dieZero "timeout-seconds must be positive"
    blueprint <- loadBlueprint (rfBlueprint settings) >>= either (dieZero . ("blueprint-invalid: " <>)) pure
    (identity, record) <- readFiles (rfReleaseIdentity settings) (rfReferenceRecord settings)
    export <- readExport (rfKliExport settings)
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
    open (NodeAccess (rfNetworkMagic settings) (rfNodeSocket settings) (rfFundingAddress settings) (rfSigningKeyFile settings) (rfTimeoutSeconds settings)) $ \(runtime, payer) -> do
        outcome <-
            foldBookedRequest
                runtime
                (printFoldEvent stdout)
                FoldInput
                    { foldBlueprint = blueprint
                    , foldIdentity = identity
                    , foldRecord = record
                    , foldExport = export
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
    PremintHandingOff{eventTransaction = txId} -> do
        hPutStrLn out ("handing premint " <> T.unpack (renderTransactionId txId) <> " to the node")
        hFlush out
    PremintSettled{eventTransaction = txId, eventProof = proof, eventFee = fee} -> do
        hPutStrLn out ("premint-transaction: " <> T.unpack (renderTransactionId txId))
        hPutStrLn out ("proof-output: " <> renderTxIn proof)
        hPutStrLn out ("premint-fee: " <> show fee)
        hFlush out
    FoldSettled{eventTransaction = txId, eventHolding = holding, eventFee = fee} -> do
        hPutStrLn out ("fold-transaction: " <> T.unpack (renderTransactionId txId))
        hPutStrLn out ("checkpoint-output: " <> renderTxIn holding)
        hPutStrLn out ("fold-fee: " <> show fee)
        hFlush out

{- | What a fold that stopped tells the person running it: why, what landed, how far each
transaction it signed got, the registry state the node last confirmed, and that nothing is
retried.
-}
renderFoldStopped :: FoldStopped -> [String]
renderFoldStopped stopped = body <> [zeroSpend | nothingSpent]
  where
    -- no transaction of this command left it: none was handed to the node, and no premint settled
    nothingSpent =
        null (stoppedPremint stopped)
            && all notHanded (stoppedPremintHandoff stopped)
            && null (stoppedFoldAttempt stopped)
    notHanded (Attempt _ status) = status == NotHandedToNode
    body = renderFoldBody stopped

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
                    ["ckeri: registry fold " <> phrase Command <> " at the first window check, before the premint: " <> renderRefusal refusal] <> waitHint refusal
                | landedNothing ->
                    ["ckeri: registry fold " <> phrase Command <> ", before any window check: " <> renderRefusal refusal]
            FoldWindowAfterPremint refusal ->
                [ "ckeri: registry fold stopped after the premint settled: the fold was not submitted"
                , "check: second window check, after the premint: " <> renderRefusal refusal
                ]
                    <> details
            FoldRefused refusal -> ["ckeri: registry fold stopped, " <> phrase Command <> ": " <> renderRefusal refusal] <> details
            RegistryMoved ->
                ["ckeri: registry fold stopped: registry-moved: the registry state changed after the snapshot was checked, so the fold was not built"] <> details
            FoldNodeFailed BeforePremint message
                | Just _ <- stoppedPremintHandoff stopped ->
                    ["ckeri: registry fold stopped at the handoff of the premint to the node: " <> message] <> details
                | otherwise ->
                    ["ckeri: registry fold stopped at the first stage, the node could not be read: " <> message]
            FoldNodeFailed AfterPremint message
                | Just _ <- stoppedFoldAttempt stopped -> [foldHandoffStage message] <> details
                | otherwise ->
                    ["ckeri: registry fold stopped after the premint settled, the node could not be read: " <> message] <> details
            FoldTransaction failure
                | HandoffUnconfirmed _ message <- failure
                , Just _ <- stoppedFoldAttempt stopped ->
                    [foldHandoffStage message] <> details
                | otherwise ->
                    renderSubmitFailure "registry fold" (not (null (stoppedPremint stopped))) failure <> details
  where
    landedNothing = null (stoppedPremint stopped) && null (stoppedFoldAttempt stopped)
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
        FoldNodeFailed _ message -> message
        other -> show other
    foldHandoffStage message =
        "ckeri: registry fold stopped after the premint settled, at the handoff of the fold to the node: " <> message
    details =
        [ "premint-transaction: " <> T.unpack (renderTransactionId txId) <> "\nproof-output: " <> renderTxIn proof <> maybe "" (\fee -> "\npremint-fee: " <> show fee) (stoppedPremintFee stopped)
        | Just (txId, proof) <- [stoppedPremint stopped]
        ]
            -- a premint that did not settle says how far it got
            <> [attemptRow "premint" attempt | null (stoppedPremint stopped), Just attempt <- [stoppedPremintHandoff stopped]]
            <> concat [attemptRows "fold" attempt | Just attempt <- [stoppedFoldAttempt stopped]]
            -- no fold was signed: there is none to have reached the node
            <> ["the fold was not submitted" | not (null (stoppedPremint stopped)), null (stoppedFoldAttempt stopped)]
            <> [ "node-confirmed-state: " <> renderTxIn ref <> maybe "" ((" root " <>) . hex) root
               | Just (ref, root) <- [stoppedConfirmed stopped]
               ]
            <> ["not retried: the premint is not minted again and no transaction is sent again by this command"]

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
    RefusedByNode reason -> label <> " was refused by the node: " <> B8.unpack reason <> "; it is not on chain"
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

renderSubmitFailure :: String -> Bool -> SubmitError -> [String]
renderSubmitFailure command premintSettled failure =
    ["ckeri: " <> command <> " stopped, " <> how <> ": " <> cause]
        <> failureRow (if premintSettled then "fold" else kindOf command) failure
  where
    kindOf = \case
        "registry register" -> "booking"
        _ -> "premint"
    -- what is said of where it stopped: after a settled premint nothing is "before any transaction",
    -- and a node that could not be read refused nothing
    how = case (failure, submitBoundary failure) of
        (NodeFailed _, _) -> "the node could not be read"
        (_, Command) | premintSettled -> "refused by the command after the premint settled: the fold was not submitted"
        (_, boundary) -> phrase boundary
    cause = case failure of
        BuildRefused refusal -> "build-refused: " <> show refusal
        EvaluationFailed message -> "evaluation-failed: " <> message
        PurposesDiffer message -> "purposes-differ: " <> message
        BudgetExceeded message -> "budget-exceeded: " <> message
        SigningRefused message -> "signing-refused: " <> message
        SubmissionRefused _ reason -> "submission-refused: " <> B8.unpack reason
        NotHandedOver _ message -> "not-handed-over: " <> message
        HandoffUnconfirmed _ message -> "handoff-unconfirmed: " <> message
        NotObserved _ message -> "not-observed: " <> message
        SettledReportInterrupted _ message -> "settled-report-interrupted: " <> message
        NodeFailed message -> "node-failed: " <> message

renderRefusal :: Refusal -> String
renderRefusal = \case
    DeploymentDisagrees message -> "deployment-disagrees: " <> message
    ReferenceOutputsMissing refs -> "reference-outputs-missing: " <> unwords (map renderTxIn refs)
    AlreadyRegistered key -> "already registered in this registry: the active token of " <> hex key <> " stands at the checkpoint validator's address"
    DepositBelowFloor given floor' -> "deposit-below-floor: the request deposit " <> show given <> " is below the registry's floor " <> show floor'
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
    RequestUnavailable ref -> "request-unavailable: " <> renderTxIn ref <> " is not an output the node holds unspent"
    RequestIsNotARegistration ref -> "request-is-not-a-registration: " <> renderTxIn ref
    RequestHasNoApproval ref -> "request-has-no-approval: " <> renderTxIn ref <> " holds the datum of a request and not the approval the booking minted"
    RequestIsForAnotherRegistry ref -> "request-is-for-another-registry: " <> renderTxIn ref
    RequestIsForAnotherKey requestKey exportKey ->
        "request-is-for-another-key: the request is for " <> hex requestKey <> " and the export is of " <> hex exportKey

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

readFiles :: FilePath -> FilePath -> IO (ReleaseIdentity, ReferenceRecord)
readFiles identityPath recordPath =
    readDeploymentFiles identityPath recordPath >>= either (dieZero . ("deployment-files-invalid: " <>) . show) pure

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
    checkSigningKey (naSigningKeyFile access) payer >>= either dieZero pure
    between
    begun <- newIORef False
    opened <- try @IOException
        $ withUnlinkedLiveContext
            LiveConfig
                { liveNetworkMagic = naNetworkMagic access
                , liveNodeSocket = naNodeSocket access
                , liveSigningKeyFile = naSigningKeyFile access
                , liveFundingAddressText = naFundingAddress access
                , liveTimeoutSeconds = naTimeoutSeconds access
                }
            (\_ -> pure ())
        $ \context status -> do
            -- from here the operation has begun: whatever follows is never a startup refusal
            writeIORef begun True
            let provider = liveProvider context
                transactions = liveTransactionRuntime context
            use
                ( whileConnected
                    status
                    RegistryRuntime
                        { rtNetwork = Testnet
                        , rtUtxosAt = queryUTxOs provider
                        , rtOutputs = queryUTxOByTxIn provider
                        , rtTransactions = transactions{trObserve = awaitFirstOutput provider (naTimeoutSeconds access)}
                        , rtObserve = observeNode provider
                        , rtNowMs = clockMs
                        }
                , payer
                )
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

{- | One observation of the node, taken from one acquisition of its state: the tip, the
forecast horizon and every slot start come from the same chain point, and the machine's
clock is read once, before. The horizon is the slot of the latest instant the node's
interpreter converts, found by conversions in the same acquisition; the clock is compared
with it by arithmetic, so a clock beyond the forecast is an observation like another.
-}
observeNode :: Provider IO -> IO Observation
observeNode provider = do
    clock <- clockMs
    withAcquired provider $ \acquired ->
        observeFrom (ledgerTipSlot <$> queryLedgerSnapshotH acquired) (posixMsToSlotH acquired) clock

clockMs :: IO Integer
clockMs = (\t -> floor (t * 1_000)) <$> getPOSIXTime

{- | An observation from the three things one acquisition gives: the tip, the node's
conversion of an instant to a slot (it raises for an instant past its forecast), and one
reading of the clock. The tip is read once. An instant the node cannot convert is
treated as past its forecast.
-}
observeFrom :: IO SlotNo -> (Integer -> IO SlotNo) -> Integer -> IO Observation
observeFrom readTip toSlot clock = do
    tip <- readTip
    latest <- latestConvertible
    horizon <- toSlot latest
    when (horizon < tip) $
        fail ("the node's forecast ends at slot " <> show horizon <> ", before its tip, slot " <> show tip)
    when (tip < 2) $
        fail ("the node's tip is slot " <> show tip <> ": a slot length cannot be measured before slot 2")
    tipStart <- startOf latest tip
    before <- startOf tipStart (tip - 1)
    pure
        Observation
            { obsTipSlot = tip
            , obsTipStartMs = tipStart
            , obsSlotLengthMs = tipStart - before
            , obsClockMs = clock
            , obsHorizonSlot = horizon
            }
  where
    -- only the pin's own refusal of an instant past its forecast is a forecast: it is a plain
    -- error call "posixMsToSlot: <PastHorizon ...>" (N2C/Provider.hs). A timeout, a lost
    -- connection, a cancellation or any other failure is a failed read and leaves the observation.
    convertible instant =
        catchJust
            (\(ErrorCall message) -> if "posixMsToSlot: " `isPrefixOf` message then Just () else Nothing)
            (Just <$> toSlot instant)
            (\() -> pure Nothing)
    limit = 40_000_000_000
    -- the latest instant that converts: found from the clock, upwards or downwards
    latestConvertible =
        convertible clock >>= \case
            Just _ -> gallopUp clock 1_000
            Nothing -> gallopDown clock 1_000
    gallopUp good step
        | step > limit = pure good
        | otherwise =
            convertible (good + step) >>= \case
                Just _ -> gallopUp (good + step) (step * 2)
                Nothing -> boundary good (good + step)
    gallopDown bad step
        | step > limit = fail "the node converts no instant to a slot"
        | otherwise =
            convertible (bad - step) >>= \case
                Just _ -> boundary (bad - step) bad
                Nothing -> gallopDown (bad - step) (step * 2)
    -- the last convertible instant between one that converts and one that does not
    boundary good bad
        | bad - good <= 1 = pure good
        | otherwise = do
            let middle = (good + bad) `div` 2
            convertible middle >>= \case
                Just _ -> boundary middle bad
                Nothing -> boundary good middle
    -- the instant a slot starts: the first instant that is in it, below an instant known to be in or after it
    startOf upper slot = do
        slotAtUpper <- toSlot upper
        when (slotAtUpper < slot) $ fail ("slot " <> show slot <> " is after the instant asked from")
        lower <- searchDown upper slot 1_000
        search lower upper slot
    -- an instant the node cannot convert, before its system start, is before every slot
    below slot instant = maybe True (< slot) <$> convertible instant
    searchDown from slot step
        | step >= from = pure 0
        | otherwise = do
            isBelow <- below slot (from - step)
            if isBelow then pure (from - step) else searchDown from slot (step * 2)
    search lo hi slot
        | lo + 1 >= hi = pure hi
        | otherwise = do
            let middle = (lo + hi) `div` 2
            isBelow <- below slot middle
            if isBelow then search middle hi slot else search lo middle slot
