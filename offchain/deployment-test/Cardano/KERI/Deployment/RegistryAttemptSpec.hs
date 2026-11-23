{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryAttemptSpec
Description : how far a signed transaction got, at the real boundaries of a fold and a booking

A transaction that was signed is in one of four conditions when the command stops: it was
never handed to the node, the handoff began and its outcome is unknown, the node refused it,
or the node accepted it. Each is reached here where it is reachable: a refusal by the
node, a client that dies as the handoff begins or after the node took it, a client that dies in
the code between two checked calls (while an event is reported), and a cancellation, which
is never a stop.
-}
module Cardano.KERI.Deployment.RegistryAttemptSpec (spec) where

import Cardano.KERI.Deployment.KEL (InceptionExport)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand (renderFoldStopped, renderRegisterFailure)
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), SubmitError (..), feeOf, whileConnected)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistryRegister
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.TxIn (TxId, TxIn)
import Control.Exception (AsyncException (..), throwIO, try)
import Control.Monad (forM_, void, when)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (isJust)
import Data.Text qualified as T
import System.Timeout (timeout)
import Test.Hspec

-- | The nth handoff of the run: the node takes it or not, and the client ends as it goes.
endingHandoff :: Int -> Bool -> RegistryRuntime -> IO RegistryRuntime
endingHandoff nth reaches = withClient $ \client runtime -> do
    count <- newIORef (0 :: Int)
    let transactions = rtTransactions runtime
    pure
        runtime
            { rtTransactions =
                transactions
                    { trSubmit = \tx -> do
                        modifyIORef' count (+ 1)
                        n <- readIORef count
                        if n /= nth
                            then trSubmit transactions tx
                            else do
                                when reaches (void (trSubmit transactions tx))
                                connectionEnds client
                    }
            }

foldInputOf :: World -> InceptionExport -> TxIn -> FoldInput
foldInputOf world export request =
    FoldInput
        { foldBlueprint = worldBlueprint world
        , foldIdentity = deployedIdentity (worldDeployed world)
        , foldRecord = deployedRecord (worldDeployed world)
        , foldExport = export
        , foldRequestOutput = request
        , foldSnapshot = Snapshot "the deployer" [] []
        , foldPayerAddress = folderAddress
        }

stoppedBy :: Either FoldStopped FoldDone -> IO FoldStopped
stoppedBy = \case
    Left stopped -> pure stopped
    Right done -> expectationFailure ("not stopped: " <> show done) >> fail "not stopped"

spec :: Spec
spec = describe "#351 how far a signed transaction got" $ around_ withinOneMinute $ do
    describe "a fold" $ do
        let setup = do
                world <- newWorld 1_000
                export <- loadExport "kli-export-single.cesr"
                (request, _) <- bookDirectly world export
                base <- length <$> accepted world
                sent0 <- submissionsMade world
                pure (world, export, request, base, sent0)
            runFold runtime report world export request =
                foldBookedRequest runtime report (foldInputOf world export request)
            quiet _ = pure ()
        it "says a premint the node refused is refused, with its id, and that it is not on chain" $ do
            (world, export, request, base, sent0) <- setup
            let runtime = runtimeOf noFaults{rejectSubmissionAt = Just sent0} world
            stopped <- runFold runtime quiet world export request >>= stoppedBy
            case stoppedPremintHandoff stopped of
                Just (Attempt txId (RefusedByNode _)) -> stoppedCause stopped `shouldSatisfy` isRefusalOf txId
                other -> expectationFailure ("not a refused premint: " <> show other)
            stoppedPremint stopped `shouldBe` Nothing
            accepted world >>= (`shouldBe` base) . length
        it "says a premint whose handoff the client did not survive may or may not have reached the node, whether or not the node took it" $
            mapM_
                ( \reaches -> do
                    (world, export, request, base, _) <- setup
                    runtime <- endingHandoff 1 reaches (runtimeOf noFaults world)
                    stopped <- runFold runtime quiet world export request >>= stoppedBy
                    case stoppedPremintHandoff stopped of
                        Just (Attempt txId HandoffUnknown) -> do
                            stoppedCause stopped `shouldSatisfy` isUnconfirmedOf txId
                            transactions <- accepted world
                            length transactions `shouldBe` base + (if reaches then 1 else 0)
                            when reaches $ transactionId (last transactions) `shouldBe` txId
                        other -> expectationFailure ("not an unknown handoff: " <> show other)
                    stoppedPremint stopped `shouldBe` Nothing
                )
                [False, True]
        it "says a premint whose client ended while its id was reported was not handed to the node" $ do
            (world, export, request, base, sent0) <- setup
            client <- newStandIn
            let report event = case event of
                    PremintHandingOff{} -> standInEnd client
                    _ -> pure ()
            stopped <- runFold (whileConnected (standInStatus client) (runtimeOf noFaults world)) report world export request >>= stoppedBy
            case stoppedPremintHandoff stopped of
                Just (Attempt _ NotHandedToNode) -> pure ()
                other -> expectationFailure ("not a premint that was never handed over: " <> show other)
            stoppedCause stopped `shouldSatisfy` \case
                FoldNodeFailed BeforePremint _ -> True
                _ -> False
            accepted world >>= (`shouldBe` base) . length
            submissionsMade world >>= (`shouldBe` sent0)
        it "says a fold the node refused is refused, with its id, after the premint that settled" $ do
            (world, export, request, base, sent0) <- setup
            let runtime = runtimeOf noFaults{rejectSubmissionAt = Just (sent0 + 1)} world
            stopped <- runFold runtime quiet world export request >>= stoppedBy
            case stoppedFoldAttempt stopped of
                Just (Attempt txId (RefusedByNode _)) -> stoppedCause stopped `shouldSatisfy` isRefusalOf txId
                other -> expectationFailure ("not a refused fold: " <> show other)
            stoppedPremint stopped `shouldSatisfy` isJust
            accepted world >>= (`shouldBe` (base + 1)) . length
        it "keeps the receipt of a fold seen to settle, and says so, when the report of it cannot be written: id, checkpoint, fee, the premint's receipt and the last confirmed state" $ do
            (world, export, request, base, _) <- setup
            let report event = case event of
                    FoldSettled{} -> ioError (userError "the report cannot be written")
                    _ -> pure ()
            stopped <- runFold (runtimeOf noFaults world) report world export request >>= stoppedBy
            transactions <- accepted world
            length transactions `shouldBe` base + 2
            let settledFold = last transactions
                settledPremint = last (init transactions)
            case stoppedFoldAttempt stopped of
                Just (Attempt txId (SettledOnChain settled)) -> do
                    txId `shouldBe` transactionId settledFold
                    feeOf settled `shouldBe` feeOf settledFold
                other -> expectationFailure ("not a fold seen to settle: " <> show other)
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId settledPremint)
            stoppedPremintFee stopped `shouldBe` Just (feeOf settledPremint)
            stoppedConfirmed stopped `shouldSatisfy` isJust
            -- what the command tells: the receipts of both, and never that the fold was not seen
            let said = renderFoldStopped stopped
                idText = T.unpack . renderTransactionId . transactionId
            said `shouldSatisfy` any ("ckeri: registry fold settled; the command was cut short after that" `isPrefixOf`)
            said `shouldSatisfy` elem ("fold-transaction: " <> idText settledFold)
            said `shouldSatisfy` elem ("checkpoint-output: " <> idText settledFold <> "#0")
            said `shouldSatisfy` elem ("fold-fee: " <> show (feeOf settledFold))
            said `shouldSatisfy` any (("premint-transaction: " <> idText settledPremint) `isPrefixOf`)
            said `shouldSatisfy` any ("node-confirmed-state: " `isPrefixOf`)
            said `shouldSatisfy` (not . any ("not seen on chain" `isInfixOf`))
            said `shouldSatisfy` notElem zeroLine
            stoppedCause stopped `shouldSatisfy` \case
                FoldNodeFailed AfterPremint _ -> True
                _ -> False
        it "lets a cancellation through at each of its own boundaries, as one, and sends nothing after it" $
            mapM_
                ( \(label, isHere) -> do
                    (world, export, request, _, _) <- setup
                    let report event = when (isHere event) throwUser
                    outcome <- try @AsyncException (runFold (runtimeOf noFaults world) report world export request)
                    (label :: String, either show (const "an outcome") outcome) `shouldBe` (label, show UserInterrupt)
                )
                [ ("while the premint is announced", \case PremintHandingOff{} -> True; _ -> False)
                , ("while the fold is announced", \case FoldHandingOff{} -> True; _ -> False)
                , ("after the fold settled", \case FoldSettled{} -> True; _ -> False)
                ]
        it "is a fold that settled, whatever happens to the node client after it settled: it ends while the settlement is reported" $ do
            (world, export, request, base, _) <- setup
            client <- newStandIn
            let report event = case event of
                    FoldSettled{} -> standInEnd client
                    _ -> pure ()
            outcome <- runFold (whileConnected (standInStatus client) (runtimeOf noFaults world)) report world export request
            outcome `shouldSatisfy` either (const False) (const True)
            accepted world >>= (`shouldBe` (base + 2)) . length
        it "answers within ten seconds wherever the node client ends, over calls that hold no acquired ledger state: every call before it is made, and every submission and settlement after the node did its part" $ do
            (world0, export0, request0, _, _) <- setup
            probe <- newStandIn
            (counting, callsMade) <- endingAt probe 0 False (runtimeOf noFaults world0)
            _ <- runFold counting quiet world0 export0 request0
            calls <- callsMade
            length calls `shouldSatisfy` (> 10)
            forM_ [(i, late) | i <- [1 .. length calls], late <- if calls !! (i - 1) == ReadCall then [False] else [False, True]] $ \(i, late) -> do
                (world, export, request, base, _) <- setup
                client <- newStandIn
                (ending, _) <- endingAt client i late (runtimeOf noFaults world)
                let earlier = take (i - 1) calls
                    -- what has already happened in the run: the premint is the first submission and the first settlement
                    stage = length (filter (== (if calls !! (i - 1) == SubmitCall then SubmitCall else ObserveCall)) earlier)
                    label = (i, calls !! (i - 1), late)
                outcome <- timeout 10_000_000 (runFold (whileConnected (standInStatus client) ending) quiet world export request)
                stopped <- maybe (expectationFailure (show label <> ": no answer within ten seconds") >> fail "no answer") stoppedBy outcome
                landed <- length <$> accepted world
                let said = renderFoldStopped stopped
                    premintSeen = fmap fst (stoppedPremint stopped)
                    premintSettled = case (calls !! (i - 1), stage) of
                        (ReadCall, 0) -> False
                        (_, 0) -> False
                        _ -> True
                case (calls !! (i - 1), stage) of
                    (ReadCall, 0) -> do
                        (label, stoppedPremintHandoff stopped, landed) `shouldBe` (label, Nothing, base)
                        (label, said) `shouldSatisfy` (\(_, text) -> zeroLine `elem` text)
                    (ReadCall, _) -> do
                        (label, isJust premintSeen, isJust (stoppedFoldAttempt stopped), landed) `shouldBe` (label, True, False, base + 1)
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                    (SubmitCall, 0) -> do
                        (label, fmap attemptStatus (stoppedPremintHandoff stopped), landed) `shouldBe` (label, Just HandoffUnknown, base + (if late then 1 else 0))
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                    (ObserveCall, 0) -> do
                        (label, fmap attemptStatus (stoppedPremintHandoff stopped), landed) `shouldBe` (label, Just AcceptedByNode, base + 1)
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                    (SubmitCall, _) -> do
                        (label, isJust premintSeen, fmap attemptStatus (stoppedFoldAttempt stopped), landed) `shouldBe` (label, True, Just HandoffUnknown, base + 1 + (if late then 1 else 0))
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                    (ObserveCall, _) -> do
                        (label, isJust premintSeen, fmap attemptStatus (stoppedFoldAttempt stopped), landed) `shouldBe` (label, True, Just AcceptedByNode, base + 2)
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                -- every stop after a premint settled carries its complete receipt: id, fee and proof output
                when premintSettled $ do
                    transactions <- accepted world
                    let premintTx = transactions !! base
                    (label, premintSeen, stoppedPremintFee stopped, fmap snd (stoppedPremint stopped))
                        `shouldBe` (label, Just (transactionId premintTx), Just (feeOf premintTx), proofOutputOf world premintTx)
                    forM_ (receiptLinesOf premintTx (proofOutputOf world premintTx)) $ \wanted ->
                        (label, concatMap lines said) `shouldSatisfy` (\(_, text) -> wanted `elem` text)
    describe "a booking" $ do
        let setup = do
                world <- newWorld 1_000
                export <- loadExport "kli-export-single.cesr"
                base <- length <$> accepted world
                sent0 <- submissionsMade world
                pure (world, export, base, sent0)
            book runtime report world export = registerRegistration runtime report (registerRequestOf world export)
            leaving event = case event of
                BookingSubmitting{eventTransaction = txId} -> Just txId
                _ -> Nothing
        it "says a booking whose client ended while its id was reported was not handed to the node" $ do
            (world, export, base, sent0) <- setup
            ids <- newIORef []
            client <- newStandIn
            let report event = do
                    mapM_ (\txId -> modifyIORef' ids (txId :)) (leaving event)
                    when (isJust (leaving event)) (standInEnd client)
            outcome <- book (whileConnected (standInStatus client) (runtimeOf noFaults world)) report world export
            reported <- readIORef ids
            case outcome of
                Left (RegisterTransaction (NotHandedOver txId _)) -> [txId] `shouldBe` reported
                other -> expectationFailure ("not a booking that was never handed over: " <> show other)
            accepted world >>= (`shouldBe` base) . length
            submissionsMade world >>= (`shouldBe` sent0)
        it "says a booking whose client died as the handoff went may or may not have reached the node, with the id it reported" $
            mapM_
                ( \reaches -> do
                    (world, export, base, _) <- setup
                    ids <- newIORef []
                    runtime <- endingHandoff 1 reaches (runtimeOf noFaults world)
                    outcome <- book runtime (mapM_ (\txId -> modifyIORef' ids (txId :)) . leaving) world export
                    reported <- readIORef ids
                    case outcome of
                        Left (RegisterTransaction (HandoffUnconfirmed txId _)) -> [txId] `shouldBe` reported
                        other -> expectationFailure ("not an unknown handoff: " <> show other)
                    accepted world >>= (`shouldBe` (base + (if reaches then 1 else 0))) . length
                )
                [False, True]
        it "keeps the receipt of a booking seen to settle, and says so, when the report of it cannot be written" $ do
            (world, export, base, _) <- setup
            outcome <- book (runtimeOf noFaults world) (\case BookingSettled{} -> ioError (userError "the report cannot be written"); _ -> pure ()) world export
            transactions <- accepted world
            length transactions `shouldBe` base + 1
            let settledBooking = last transactions
            case outcome of
                Left failure@(RegisterTransaction (SettledReportInterrupted settled _)) -> do
                    transactionId settled `shouldBe` transactionId settledBooking
                    let said = renderRegisterFailure failure
                        idText = T.unpack . renderTransactionId . transactionId
                    said `shouldSatisfy` any ("ckeri: registry register settled; the command was cut short after that" `isPrefixOf`)
                    said `shouldSatisfy` elem ("booking-transaction: " <> idText settledBooking)
                    said `shouldSatisfy` elem ("booking-output: " <> idText settledBooking <> "#0")
                    said `shouldSatisfy` elem ("booking-fee: " <> show (feeOf settledBooking))
                    said `shouldSatisfy` (not . any ("not seen on chain" `isInfixOf`))
                other -> expectationFailure ("not a booking seen to settle: " <> show other)
        it "says a booking the node refused is refused, with the id it reported" $ do
            (world, export, base, sent0) <- setup
            ids <- newIORef []
            outcome <- book (runtimeOf noFaults{rejectSubmissionAt = Just sent0} world) (mapM_ (\txId -> modifyIORef' ids (txId :)) . leaving) world export
            reported <- readIORef ids
            case outcome of
                Left (RegisterTransaction (SubmissionRefused txId _)) -> [txId] `shouldBe` reported
                other -> expectationFailure ("not a refused booking: " <> show other)
            accepted world >>= (`shouldBe` base) . length
        it "is a booking that settled, whatever happens to the node client after it settled: it ends while the settlement is reported" $ do
            (world, export, base, _) <- setup
            client <- newStandIn
            outcome <- book (whileConnected (standInStatus client) (runtimeOf noFaults world)) (\case BookingSettled{} -> standInEnd client; _ -> pure ()) world export
            outcome `shouldSatisfy` either (const False) (const True)
            accepted world >>= (`shouldBe` (base + 1)) . length
        it "answers within ten seconds wherever the node client ends, over calls that hold no acquired ledger state: every call before it is made, and the submission and the settlement after the node did its part" $ do
            (world0, export0, _, _) <- setup
            probe <- newStandIn
            (counting, callsMade) <- endingAt probe 0 False (runtimeOf noFaults world0)
            _ <- book counting (\_ -> pure ()) world0 export0
            calls <- callsMade
            length calls `shouldSatisfy` (> 5)
            forM_ [(i, late) | i <- [1 .. length calls], late <- if calls !! (i - 1) == ReadCall then [False] else [False, True]] $ \(i, late) -> do
                (world, export, base, _) <- setup
                client <- newStandIn
                (ending, _) <- endingAt client i late (runtimeOf noFaults world)
                let label = (i, calls !! (i - 1), late)
                outcome <- timeout 10_000_000 (book (whileConnected (standInStatus client) ending) (\_ -> pure ()) world export)
                failure <- case outcome of
                    Just (Left failed) -> pure failed
                    other -> expectationFailure (show label <> ": not a stop within ten seconds: " <> show other) >> fail "not a stop"
                landed <- length <$> accepted world
                let said = renderRegisterFailure failure
                case (calls !! (i - 1), failure) of
                    (ReadCall, RegisterTransaction (NodeFailed _)) -> (label, landed, zeroLine `elem` said) `shouldBe` (label, base, True)
                    (SubmitCall, RegisterTransaction (HandoffUnconfirmed _ _)) -> (label, landed) `shouldBe` (label, base + (if late then 1 else 0))
                    (ObserveCall, RegisterTransaction (NotObserved _ _)) -> (label, landed) `shouldBe` (label, base + 1)
                    other -> expectationFailure (show label <> ": " <> show other)
        it "lets a cancellation through while the booking is announced" $ do
            (world, export, _, _) <- setup
            outcome <- try @AsyncException (book (runtimeOf noFaults world) (\event -> when (isJust (leaving event)) throwUser) world export)
            either show (const "an outcome") outcome `shouldBe` show UserInterrupt
  where
    zeroLine = "nothing was submitted; nothing was spent"
    throwUser :: IO a
    throwUser = throwIO UserInterrupt
    isRefusalOf :: TxId -> FoldCause -> Bool
    isRefusalOf txId = \case
        FoldTransaction (SubmissionRefused refused _) -> refused == txId
        _ -> False
    isUnconfirmedOf :: TxId -> FoldCause -> Bool
    isUnconfirmedOf txId = \case
        FoldTransaction (HandoffUnconfirmed unconfirmed _) -> unconfirmed == txId
        _ -> False
