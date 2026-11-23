{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFoldSpec
Description : a booked request is folded into the registry on a snapshot the chain confirms, and the fold stops and reports when the registry moves

Folding runs over a registry that @ckeri registry deploy@ created, on a chain that
keeps its unspent outputs and runs no script. The request is booked with the
library's own builder, so a fold is judged on what it does, not on the command
that books. Refusals and stops are observed from outside: which transactions
were submitted, what was reported and what the node last confirmed.
-}
module Cardano.KERI.Deployment.RegistryFoldSpec (spec) where

import Cardano.KERI.AID.Application (RegistrationData (..), stateDatumData)
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryChain
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults, walletAddress)
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord (..))
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), decodeSnapshot, encodeSnapshot, snapshotRoot)
import Cardano.KERI.Deployment.RegistryTransactions (emptyRoot, registryRootOf)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), transactionId)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, coinTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.N2C.Types (ConnectionLost (..), LocalStateQueryTimeout (..))
import Cardano.Node.Client.Provider (SlotNo (..))
import Control.Exception (AsyncException (..), toException, try)
import Control.Monad (forM_, void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Maybe (isJust, isNothing)
import Lens.Micro ((^.))
import Test.Hspec

type Seen = [(Int, FoldEvent)]

inputOf :: World -> InceptionExport -> TxIn -> Snapshot -> FoldInput
inputOf world export request snapshot =
    FoldInput
        { foldBlueprint = worldBlueprint world
        , foldIdentity = deployedIdentity (worldDeployed world)
        , foldRecord = deployedRecord (worldDeployed world)
        , foldExport = export
        , foldRequestOutput = request
        , foldSnapshot = snapshot
        , foldPayerAddress = folderAddress
        }

folded :: Faults -> World -> FoldInput -> IO (Either FoldStopped FoldDone, Seen)
folded faults world = foldedOver (runtimeOf faults world) world

foldedOver :: RegistryRuntime -> World -> FoldInput -> IO (Either FoldStopped FoldDone, Seen)
foldedOver runtime world input = do
    seen <- newIORef []
    outcome <-
        foldBookedRequest
            runtime
            ( \event -> do
                n <- submissionsMade world
                modifyIORef' seen ((n, event) :)
            )
            input
    (,) outcome . reverse <$> readIORef seen

snapshotOf :: [ByteString] -> [ByteString] -> Snapshot
snapshotOf = Snapshot "the follower of the first folder"

-- | A registry with a booked request for an export, and nothing folded.
booking :: Integer -> FilePath -> IO (World, InceptionExport, TxIn, RegistrationData)
booking slotMs name = do
    world <- newWorld slotMs
    export <- loadExport name
    (ref, record) <- bookDirectly world export
    pure (world, export, ref, record)

stoppedWith :: Either FoldStopped FoldDone -> IO FoldStopped
stoppedWith = \case
    Left stopped -> pure stopped
    Right done -> expectationFailure ("the fold was not stopped: " <> show done) >> fail "not stopped"

spec :: Spec
spec = describe "#351 folding a booked registration" $ around_ withinOneMinute $ do
    describe "a fold that settles" $ do
        it "delivers the checkpoint, moves the registry's root to the one key, spends the request, and reports each transaction as it settles" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            base <- length <$> accepted world
            sent0 <- submissionsMade world
            (outcome, seen) <-
                folded noFaults world (inputOf world export request (snapshotOf [] []))
            done <- either (fail . show) pure outcome
            transactions <- accepted world
            length transactions `shouldBe` base + 2
            [premint, foldTx] <- pure (drop base transactions)
            let key = requestKey record
            -- the holding: at the checkpoint validator, the committed deposit, the committed datum, the key's active token
            held <- checkpointHolding world key
            map fst held `shouldBe` [doneHolding done]
            doneHolding done `shouldBe` TxIn (transactionId foldTx) (TxIx 0)
            forM_ held $ \(_, out) -> do
                out ^. coinTxOutL `shouldBe` Coin (requestDeposit record)
                rawInlineData out `shouldBe` Just (requestInitialDatum record)
            -- the registry's root is the root of the one key, in the one state output, and the request is gone
            Just (_, stateOut) <- stateOutputOf world
            rawInlineData stateOut `shouldBe` Just (stateDatumData (registryRootOf [key] []))
            donePremint done `shouldBe` transactionId premint
            doneFold done `shouldBe` transactionId foldTx
            snapshotActive (doneSnapshot done) `shouldBe` [key]
            snapshotTerminal (doneSnapshot done) `shouldBe` []
            -- reported in order, each before the next was submitted
            map fst seen `shouldBe` [sent0, sent0, sent0 + 1, sent0 + 1, sent0 + 2]
            case map snd seen of
                [ SnapshotChecked{eventSupplier = supplier, eventRoot = root}
                    , PremintHandingOff{eventTransaction = premintSigned}
                    , PremintSettled{eventTransaction = premintId, eventProof = proof}
                    , FoldHandingOff{eventTransaction = foldSigned}
                    , FoldSettled{eventTransaction = foldId, eventHolding = holding}
                    ] -> do
                        premintSigned `shouldBe` transactionId premint
                        foldSigned `shouldBe` transactionId foldTx
                        supplier `shouldBe` "the follower of the first folder"
                        root `shouldBe` emptyRoot
                        premintId `shouldBe` transactionId premint
                        Just proof `shouldBe` proofOutputOf world premint
                        foldId `shouldBe` transactionId foldTx
                        holding `shouldBe` doneHolding done
                other -> expectationFailure ("unexpected events: " <> show other)
        it "folds a second identity into a registry that already holds the first: the root is the root of both" $ do
            world <- newWorld 1_000
            single <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            (firstRef, _) <- bookDirectly world single
            (secondRef, _) <- bookDirectly world multi
            (first', _) <- folded noFaults world (inputOf world single firstRef (snapshotOf [] []))
            firstDone <- either (fail . show) pure first'
            (second', _) <-
                folded noFaults world (inputOf world multi secondRef (doneSnapshot firstDone))
            secondDone <- either (fail . show) pure second'
            Just (_, stateOut) <- stateOutputOf world
            rawInlineData stateOut
                `shouldBe` Just (stateDatumData (registryRootOf [keyOf single, keyOf multi] []))
            snapshotActive (doneSnapshot secondDone) `shouldMatchList` [keyOf single, keyOf multi]

    describe "a snapshot that went through a file" $ do
        it "refuses the identity it was written after, booked again: one key in the registry, the snapshot and the booking" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (firstRef, firstRecord) <- bookDirectly world export
            (secondRef, _) <- bookDirectly world export
            (first', _) <- folded noFaults world (inputOf world export firstRef (snapshotOf [] []))
            done <- either (fail . show) pure first'
            -- the snapshot is written for the next folder and read back from its file
            snapshot <- either (fail . show) pure (decodeSnapshot (encodeSnapshot (doneSnapshot done)))
            -- the key is the identifier's text, as the registry's state holds it
            snapshotActive snapshot `shouldBe` [requestKey firstRecord]
            requestKey firstRecord `shouldBe` keyOf export
            Just (_, stateOut) <- stateOutputOf world
            rawInlineData stateOut `shouldBe` Just (stateDatumData (snapshotRoot snapshot))
            sent0 <- submissionsMade world
            (second', _) <- folded noFaults world (inputOf world export secondRef snapshot)
            stopped <- stoppedWith second'
            stoppedCause stopped `shouldBe` FoldRefused (RegistryHoldsKey (keyOf export))
            submissionsMade world >>= (`shouldBe` sent0)

    describe "the snapshot is checked against the registry the chain holds before anything is paid" $ do
        it "refuses a snapshot that is not the registry state as stale or unavailable, in each way it can differ, and never as a duplicate" $ do
            single <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            let chainHolds active terminal = (active, terminal)
                cases =
                    [ ("an extra active key", chainHolds [] [], snapshotOf [keyOf multi] [], emptyRoot)
                    , ("a missing active key", chainHolds [keyOf multi] [], snapshotOf [] [], registryRootOf [keyOf multi] [])
                    , ("a key active that the chain holds terminal", chainHolds [] [keyOf multi], snapshotOf [keyOf multi] [], registryRootOf [] [keyOf multi])
                    , ("a key terminal that the chain holds active", chainHolds [keyOf multi] [], snapshotOf [] [keyOf multi], registryRootOf [keyOf multi] [])
                    ]
            forM_ cases $ \(label :: String, (active, terminal), snapshot, chainRoot) -> do
                (world, _, request, _) <- booking 1_000 "kli-export-single.cesr"
                setRegistryRoot world active terminal
                sent0 <- submissionsMade world
                (outcome, seen) <- folded noFaults world (inputOf world single request snapshot)
                stopped <- stoppedWith outcome
                (label, stoppedCause stopped)
                    `shouldBe` (label, FoldRefused (StaleOrUnavailableRegistryState (Just chainRoot)))
                (label, stoppedPremint stopped, stoppedFold stopped) `shouldBe` (label, Nothing, Nothing)
                seen `shouldBe` []
                submissionsMade world >>= (\n -> (label, n) `shouldBe` (label, sent0))
        it "refuses it as unavailable when the node holds no output with the registry's state token" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            Just (stateRef, _) <- stateOutputOf world
            removeOutput world stateRef
            sent0 <- submissionsMade world
            (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` FoldRefused (StaleOrUnavailableRegistryState Nothing)
            submissionsMade world >>= (`shouldBe` sent0)
        it "refuses a fold with the snapshot from before another fold as stale, not as a held key" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            setRegistryRoot world [requestKey record] []
            (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            stoppedCause stopped
                `shouldBe` FoldRefused (StaleOrUnavailableRegistryState (Just (registryRootOf [requestKey record] [])))

    describe "a key the registry holds is refused by the command, before any transaction" $ do
        it "whether the checked snapshot holds it active or terminal" $
            forM_ [("active", True), ("terminal", False)] $ \(label, isActive) -> do
                (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
                let key = requestKey record
                    (active, terminal) = if isActive then ([key], []) else ([], [key])
                setRegistryRoot world active terminal
                sent0 <- submissionsMade world
                (outcome, seen) <- folded noFaults world (inputOf world export request (snapshotOf active terminal))
                stopped <- stoppedWith outcome
                (label :: String, stoppedCause stopped) `shouldBe` (label, FoldRefused (RegistryHoldsKey key))
                map snd seen `shouldBe` [SnapshotChecked "the follower of the first folder" (registryRootOf active terminal)]
                submissionsMade world >>= (\n -> (label, n) `shouldBe` (label, sent0))
        it "when other keys are held too, only this key is the refusal" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            setRegistryRoot world [keyOf multi] []
            (outcome, _) <-
                folded noFaults world (inputOf world export request (snapshotOf [keyOf multi] []))
            done <- either (fail . show) pure outcome
            snapshotActive (doneSnapshot done) `shouldMatchList` [keyOf multi, requestKey record]

    describe "the request" $ do
        it "must be an output the node holds unspent that is a registration of this registry, for the export's key" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            let configuration = txInOfReference (recordConfiguration (deployedRecord (worldDeployed world)))
                unknown = case request of TxIn txId _ -> TxIn txId (TxIx 9)
            sent0 <- submissionsMade world
            (a, _) <- folded noFaults world (inputOf world export unknown (snapshotOf [] []))
            fmap stoppedCause (either Just (const Nothing) a) `shouldBe` Just (FoldRefused (RequestUnavailable unknown))
            (b, _) <- folded noFaults world (inputOf world export configuration (snapshotOf [] []))
            fmap stoppedCause (either Just (const Nothing) b) `shouldBe` Just (FoldRefused (RequestIsNotARegistration configuration))
            (c, _) <- folded noFaults world (inputOf world multi request (snapshotOf [] []))
            fmap stoppedCause (either Just (const Nothing) c)
                `shouldBe` Just (FoldRefused (RequestIsForAnotherKey (keyOf export) (keyOf multi)))
            submissionsMade world >>= (`shouldBe` sent0)
        it "is refused when the files do not describe the scripts the blueprint derives" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            let input = inputOf world export request (snapshotOf [] [])
                identity = foldIdentity input
            sent0 <- submissionsMade world
            (outcome, _) <-
                folded noFaults world input{foldIdentity = identity{riCheckpointValidator = BS.replicate 28 0x99}}
            stopped <- stoppedWith outcome
            case stoppedCause stopped of
                FoldRefused (DeploymentDisagrees _) -> pure ()
                other -> expectationFailure ("not refused as a disagreeing deployment: " <> show other)
            submissionsMade world >>= (`shouldBe` sent0)

    describe "an output that only looks like the request" $ do
        it "is refused by name before any transaction when it holds the datum and not the approval the booking minted" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            forged <- stripApproval world request
            sent0 <- submissionsMade world
            (outcome, seen) <- folded noFaults world (inputOf world export forged (snapshotOf [] []))
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` FoldRefused (RequestHasNoApproval forged)
            seen `shouldBe` []
            submissionsMade world >>= (`shouldBe` sent0)
            -- the genuine request is folded
            (genuine, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            either (expectationFailure . show) (const (pure ())) genuine

    describe "a failed read of the node, at each stage" $ do
        let failures =
                [ ("a query timeout", toException (LocalStateQueryTimeout 1_000_000))
                , ("a lost connection", toException ConnectionLost)
                , ("an unrelated failure", toException (userError "the disk is full"))
                ]
        it "at the first stage ends the fold with nothing submitted, as a node failure and not as a window row" $
            forM_ failures $ \(label, failure) -> do
                (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
                sent0 <- submissionsMade world
                runtime <- failingObservation 1 failure (runtimeOf noFaults world)
                (outcome, _) <- foldedOver runtime world (inputOf world export request (snapshotOf [] []))
                stopped <- stoppedWith outcome
                (label :: String, stoppedCause stopped) `shouldBe` (label, FoldNodeFailed BeforePremint (show failure))
                (stoppedPremint stopped, stoppedPremintFee stopped, stoppedFold stopped) `shouldBe` (Nothing, Nothing, Nothing)
                submissionsMade world >>= (`shouldBe` sent0)
        it "at the second stage ends the fold with the one settled premint, its fee, its proof output and the last confirmed state, and the fold never submitted" $
            forM_ failures $ \(label, failure) -> do
                (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
                Just (stateRef, _) <- stateOutputOf world
                base <- length <$> accepted world
                sent0 <- submissionsMade world
                runtime <- failingObservation 2 failure (runtimeOf noFaults world)
                (outcome, _) <- foldedOver runtime world (inputOf world export request (snapshotOf [] []))
                stopped <- stoppedWith outcome
                [premint] <- drop base <$> accepted world
                (label :: String, stoppedCause stopped) `shouldBe` (label, FoldNodeFailed AfterPremint (show failure))
                fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
                fmap snd (stoppedPremint stopped) `shouldBe` proofOutputOf world premint
                stoppedPremintFee stopped `shouldBe` Just (feeOf premint)
                stoppedFold stopped `shouldBe` Nothing
                stoppedConfirmed stopped `shouldBe` Just (stateRef, Just emptyRoot)
                submissionsMade world >>= (`shouldBe` sent0 + 1)
        it "treats the node client ending as a failed read at each stage, with the same report" $ do
            -- first stage
            (world1, export1, request1, _) <- booking 1_000 "kli-export-single.cesr"
            sent1 <- submissionsMade world1
            first <- withClient (failingObservationBy 1 . connectionEnds) (runtimeOf noFaults world1)
            (outcome1, _) <- foldedOver first world1 (inputOf world1 export1 request1 (snapshotOf [] []))
            stopped1 <- stoppedWith outcome1
            case stoppedCause stopped1 of
                FoldNodeFailed BeforePremint failure -> failure `shouldSatisfy` ("ConnectionLost" `isInfixOf`)
                other -> expectationFailure ("not a first-stage node failure: " <> show other)
            stoppedPremint stopped1 `shouldBe` Nothing
            submissionsMade world1 >>= (`shouldBe` sent1)
            -- second stage: the one settled premint, what it paid, its proof, the state last confirmed
            (world2, export2, request2, _) <- booking 1_000 "kli-export-single.cesr"
            Just (stateRef, _) <- stateOutputOf world2
            base <- length <$> accepted world2
            sent2 <- submissionsMade world2
            second <- withClient (failingObservationBy 2 . connectionEnds) (runtimeOf noFaults world2)
            (outcome2, _) <- foldedOver second world2 (inputOf world2 export2 request2 (snapshotOf [] []))
            stopped2 <- stoppedWith outcome2
            [premint] <- drop base <$> accepted world2
            case stoppedCause stopped2 of
                FoldNodeFailed AfterPremint failure -> failure `shouldSatisfy` ("ConnectionLost" `isInfixOf`)
                other -> expectationFailure ("not a second-stage node failure: " <> show other)
            fmap fst (stoppedPremint stopped2) `shouldBe` Just (transactionId premint)
            stoppedPremintFee stopped2 `shouldBe` Just (feeOf premint)
            stoppedFold stopped2 `shouldBe` Nothing
            stoppedConfirmed stopped2 `shouldBe` Just (stateRef, Just emptyRoot)
            submissionsMade world2 >>= (`shouldBe` sent2 + 1)
        it "keeps the attempted fold and the uncertainty when its settlement is lost to the dying client, with the last confirmed state" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            base <- length <$> accepted world
            runtime <- withClient (failingSettlementBy 2 . void . connectionEnds) (runtimeOf noFaults world)
            (outcome, _) <- foldedOver runtime world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint, foldTx] <- drop base <$> accepted world
            case stoppedCause stopped of
                FoldTransaction (NotObserved txId _) -> txId `shouldBe` transactionId foldTx
                other -> expectationFailure ("not an uncertain fold: " <> show other)
            stoppedFold stopped `shouldBe` Just (transactionId foldTx)
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            stoppedPremintFee stopped `shouldBe` Just (feeOf premint)
            stoppedConfirmed stopped `shouldSatisfy` isJust
        it "is not caused by a cancellation, which passes through as itself at either stage" $
            forM_ [1, 2] $ \failingCall -> do
                (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
                runtime <- failingObservation failingCall (toException UserInterrupt) (runtimeOf noFaults world)
                outcome <- try @AsyncException (foldedOver runtime world (inputOf world export request (snapshotOf [] [])))
                either show (const "a stop record") outcome `shouldBe` show UserInterrupt

    describe "the fold window: one observation per decision, and the row that decided" $ do
        let attempt world export request record = do
                sent0 <- submissionsMade world
                observed0 <- observationsMade world
                (outcome, seen) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
                observed1 <- observationsMade world
                sent1 <- submissionsMade world
                pure (outcome, seen, sent1 - sent0, observed1 - observed0, requestProcessDeadline record)
            idle (_, seen, _, _, _) = all (\(_, event) -> case event of PremintSettled{} -> False; FoldSettled{} -> False; _ -> True) seen
        it "W1: the chain has reached the deadline: deadline reached, one tip read, nothing submitted" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            setTip world (deadlineSlot (requestProcessDeadline record))
            result@(outcome, _, spent, tipReads, deadline) <- attempt world export request record
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` FoldRefused (DeadlineReached deadline)
            (spent, tipReads, idle result) `shouldBe` (0, 1, True)
        it "W2: the tip is before the deadline and the clock is at or after it: the conflict, with the sampled clock, one tip read, nothing submitted" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            let tipSlot = deadlineSlot (requestProcessDeadline record) - 2
            setTip world tipSlot
            advanceClock world 3_000
            result@(outcome, _, spent, tipReads, deadline) <- attempt world export request record
            stopped <- stoppedWith outcome
            stoppedCause stopped
                `shouldBe` FoldRefused (TimeEvidenceConflicts (slotStart 1_000 tipSlot + 100 + 3_000) deadline (slotStart 1_000 tipSlot))
            (spent, tipReads, idle result) `shouldBe` (0, 1, True)
        it "W3: the deadline is ahead but inside the slot the clock is in: no fold slot remains, not a deadline passed, not retryable" $ do
            -- slots of 700 ms: the deadline falls 400 ms into a slot
            (world, export, request, record) <- booking 700 "kli-export-single.cesr"
            let deadline = requestProcessDeadline record
                tipSlot = (deadline - originMs) `div` 700
            setTip world tipSlot
            (slotStart 700 tipSlot < deadline) `shouldBe` True
            result@(outcome, _, spent, tipReads, _) <- attempt world export request record
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` FoldRefused (NoFoldSlotRemains deadline)
            (spent, tipReads, idle result) `shouldBe` (0, 1, True)
        it "W4: a whole slot would fit but the forecast ends before the slot the clock is in: no interval yet, with the sampled clock; retryable" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            -- tip 10000, forecast 10003, the clock reads slot 10004, the deadline is slot 10095
            setTip world 10_000
            setHorizon world 3
            advanceClock world 4_000
            result@(outcome, _, spent, tipReads, deadline) <- attempt world export request record
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` FoldRefused (NoIntervalYet deadline (slotStart 1_000 10_000 + 100 + 4_000))
            (spent, tipReads, idle result) `shouldBe` (0, 1, True)
        it "W5: otherwise a plan from the slot the clock is in, ending by the deadline and inside the horizon, from one observation per stage" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            setTip world 10_000
            advanceClock world 2_000
            base <- length <$> accepted world
            (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            _ <- either (fail . show) pure outcome
            [premint, foldTx] <- drop base <$> accepted world
            let interval tx = tx ^. bodyTxL . vldtTxBodyL
            -- the clock is in slot 10002: the interval starts there and is the booking width wide
            interval premint `shouldBe` ValidityInterval (SJust (SlotNo 10_002)) (SJust (SlotNo 10_007))
            interval foldTx `shouldBe` ValidityInterval (SJust (SlotNo 10_002)) (SJust (SlotNo 10_007))
            observationsMade world >>= (`shouldBe` 2)
        it "W6: a block lands after the observation: the decision stands on it, and the premint carries its interval" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            base <- length <$> accepted world
            let runtime = runtimeOf noFaults world
                racing = runtime{rtObserve = rtObserve runtime <* setTip world 10_003}
            (outcome, _) <- foldedOver racing world (inputOf world export request (snapshotOf [] []))
            _ <- either (fail . show) pure outcome
            [premint, _] <- drop base <$> accepted world
            -- the first observation was of tip 10000: its plan stands though the tip moved
            (premint ^. bodyTxL . vldtTxBodyL) `shouldBe` ValidityInterval (SJust (SlotNo 10_000)) (SJust (SlotNo 10_005))
        it "W6: a premint the node refuses is reported as the node's refusal: attempted, not included, no window row" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            sent0 <- submissionsMade world
            (outcome, _) <-
                folded noFaults{rejectSubmissionAt = Just sent0} world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            case stoppedCause stopped of
                FoldTransaction failure -> submitBoundary failure `shouldBe` Ledger
                other -> expectationFailure ("not the node's refusal: " <> show other)
            stoppedPremint stopped `shouldBe` Nothing
            stoppedPremintAttempt stopped `shouldSatisfy` isJust
            observationsMade world >>= (`shouldSatisfy` (>= 1))
        it "second stage W2: the clock runs past the deadline while the premint settles: the premint is named, the fold was not submitted, one fresh observation" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            let deadline = requestProcessDeadline record
                tipSlot = deadlineSlot deadline - 3
            setTip world tipSlot
            base <- length <$> accepted world
            let runtime = runtimeOf noFaults world
                slow =
                    runtime
                        { rtTransactions =
                            (rtTransactions runtime)
                                { trObserve = \txId -> trObserve (rtTransactions runtime) txId >> advanceClock world 4_000
                                }
                        }
            (outcome, _) <- foldedOver slow world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint] <- drop base <$> accepted world
            stoppedCause stopped
                `shouldBe` FoldWindowAfterPremint (TimeEvidenceConflicts (slotStart 1_000 tipSlot + 100 + 500 + 4_000) deadline (slotStart 1_000 tipSlot))
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            stoppedPremintFee stopped `shouldBe` Just (feeOf premint)
            fmap snd (stoppedPremint stopped) `shouldBe` proofOutputOf world premint
            stoppedFold stopped `shouldBe` Nothing
            observationsMade world >>= (`shouldBe` 2)
        it "second stage W4: the forecast ends before the clock's slot after the premint: no interval yet, the premint named, the fold not submitted" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            setHorizon world 3
            base <- length <$> accepted world
            sent0 <- submissionsMade world
            let runtime = runtimeOf noFaults world
                slow =
                    runtime
                        { rtTransactions =
                            (rtTransactions runtime)
                                { trObserve = \txId -> trObserve (rtTransactions runtime) txId >> advanceClock world 4_000
                                }
                        }
            (outcome, _) <- foldedOver slow world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint] <- drop base <$> accepted world
            stoppedCause stopped
                `shouldBe` FoldWindowAfterPremint (NoIntervalYet (requestProcessDeadline record) (slotStart 1_000 10_000 + 100 + 500 + 4_000))
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            stoppedFold stopped `shouldBe` Nothing
            submissionsMade world >>= (`shouldBe` sent0 + 1)
            observationsMade world >>= (`shouldBe` 2)

    describe "the deadline of the request" $ do
        it "caps the validity of the premint and of the fold at the deadline" $ do
            (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
            let deadline = requestProcessDeadline record
            -- 2 slots before the deadline: the interval is cut short
            setTip world (deadlineSlot deadline - 2)
            base <- length <$> accepted world
            (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            _ <- either (fail . show) pure outcome
            transactions <- accepted world
            [premint, foldTx] <- pure (drop base transactions)
            let upperOf tx = case tx ^. bodyTxL . vldtTxBodyL of
                    ValidityInterval _ (SJust slot) -> Just (slotStart 1_000 (toInteger (unSlotNo slot)))
                    _ -> Nothing
                lowerOf tx = case tx ^. bodyTxL . vldtTxBodyL of
                    ValidityInterval (SJust slot) _ -> Just slot
                    _ -> Nothing
            upperOf premint `shouldBe` Just deadline
            upperOf foldTx `shouldBe` Just deadline
            lowerOf foldTx `shouldBe` Just (SlotNo (fromInteger (deadlineSlot deadline - 2)))
        it "leaves the interval at the booking width when the deadline is far" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            setTip world 10_010
            base <- length <$> accepted world
            (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
            _ <- either (fail . show) pure outcome
            [premint, foldTx] <- drop base <$> accepted world
            forM_ [premint, foldTx] $ \tx ->
                case tx ^. bodyTxL . vldtTxBodyL of
                    ValidityInterval (SJust lower) (SJust upper) ->
                        (lower, upper) `shouldBe` (SlotNo 10_010, SlotNo 10_015)
                    other -> expectationFailure ("no whole interval: " <> show other)
        it "refuses by name before any transaction when no whole slot is left, naming when the request can be returned" $
            forM_ [10_095, 10_096, 10_200] $ \tip -> do
                (world, export, request, record) <- booking 1_000 "kli-export-single.cesr"
                setTip world tip
                sent0 <- submissionsMade world
                (outcome, _) <- folded noFaults world (inputOf world export request (snapshotOf [] []))
                stopped <- stoppedWith outcome
                (tip, stoppedCause stopped) `shouldBe` (tip, FoldRefused (DeadlineReached (requestProcessDeadline record)))
                submissionsMade world >>= (\n -> (tip, n) `shouldBe` (tip, sent0))

    describe "a fold the registry's movement or a refusal stops" $ do
        it "ends in the stop report when the registry state cannot be read after the premint: what landed and the last state the node confirmed" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            Just (stateRef, stateOut) <- stateOutputOf world
            base <- length <$> accepted world
            runtime <- failStateReadsFrom 2 (stateOut ^. addrTxOutL) (runtimeOf noFaults world)
            (outcome, _) <- foldedOver runtime world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint] <- drop base <$> accepted world
            case stoppedCause stopped of
                FoldNodeFailed AfterPremint _ -> pure ()
                other -> expectationFailure ("not a stop on an unreadable node: " <> show other)
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            fmap snd (stoppedPremint stopped) `shouldBe` proofOutputOf world premint
            stoppedFold stopped `shouldBe` Nothing
            stoppedConfirmed stopped `shouldBe` Just (stateRef, Just emptyRoot)
        it "keeps the moved state it saw when the node can no longer be read for the report" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            Just (_, stateOut) <- stateOutputOf world
            base <- length <$> accepted world
            let faults = noFaults{afterAccepted = \n chain -> if n == base then moveRegistryRoot world [keyOf multi] chain else chain}
            runtime <- failStateReadsFrom 3 (stateOut ^. addrTxOutL) (runtimeOf faults world)
            (outcome, _) <- foldedOver runtime world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            stoppedCause stopped `shouldBe` RegistryMoved
            Just (movedRef, _) <- stateOutputOf world
            stoppedConfirmed stopped `shouldBe` Just (movedRef, Just (registryRootOf [keyOf multi] []))
        it "stops after the premint when the registry state moved, and says what landed and what the node confirmed, without a retry" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            base <- length <$> accepted world
            submissionsBefore <- submissionsMade world
            let faults = noFaults{afterAccepted = \n chain -> if n == base then moveRegistryRoot world [keyOf multi] chain else chain}
            (outcome, _) <- folded faults world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint] <- drop base <$> accepted world
            stoppedCause stopped `shouldBe` RegistryMoved
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            fmap snd (stoppedPremint stopped) `shouldBe` proofOutputOf world premint
            stoppedFold stopped `shouldBe` Nothing
            Just (movedRef, _) <- stateOutputOf world
            stoppedConfirmed stopped `shouldBe` Just (movedRef, Just (registryRootOf [keyOf multi] []))
            -- one transaction, the premint: no remint, no fold, no resubmission
            submissionsMade world >>= (`shouldBe` submissionsBefore + 1)
        it "stops and reports the fold it submitted when the ledger refuses it, without a retry" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            base <- length <$> accepted world
            submissionsBefore <- submissionsMade world
            (outcome, _) <-
                folded noFaults{rejectSubmissionAt = Just (submissionsBefore + 1)} world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            [premint] <- drop base <$> accepted world
            case stoppedCause stopped of
                FoldTransaction failure -> submitBoundary failure `shouldBe` Ledger
                other -> expectationFailure ("not a ledger refusal: " <> show other)
            fmap fst (stoppedPremint stopped) `shouldBe` Just (transactionId premint)
            stoppedFold stopped `shouldSatisfy` isJust
            -- two submissions, the premint and the fold, and nothing after
            submissionsMade world >>= (`shouldBe` submissionsBefore + 2)
        it "stops at the premint, naming nothing landed, when the node refuses it" $ do
            (world, export, request, _) <- booking 1_000 "kli-export-single.cesr"
            submissionsBefore <- submissionsMade world
            (outcome, _) <-
                folded noFaults{rejectSubmissionAt = Just submissionsBefore} world (inputOf world export request (snapshotOf [] []))
            stopped <- stoppedWith outcome
            stoppedPremint stopped `shouldSatisfy` isNothing
            stoppedFold stopped `shouldSatisfy` isNothing
            submissionsMade world >>= (`shouldBe` submissionsBefore + 1)
        it "is refused by the ledger, not the command, when two folds are built against one state: the second consumed registry input is not unspent" $ do
            world <- newWorld 1_000
            single <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            (firstRef, _) <- bookDirectly world single
            (secondRef, _) <- bookDirectly world multi
            -- the second folder reads the registry state as it was before the first fold
            behind <- copyChain world
            (first', _) <- folded noFaults world (inputOf world single firstRef (snapshotOf [] []))
            _ <- either (fail . show) pure first'
            submissionsBefore <- submissionsMade world
            let secondInput = (inputOf world multi secondRef (snapshotOf [] [])){foldPayerAddress = walletAddress}
            Just (_, stateOut) <- stateOutputOf world
            let live = runtimeOf noFaults world
                stale = runtimeOfUnder noFaults world behind
                stateAddress = stateOut ^. addrTxOutL
                staleState = live{rtUtxosAt = \address -> if address == stateAddress then rtUtxosAt stale address else rtUtxosAt live address}
            (outcome, _) <- foldedOver staleState world secondInput
            stopped <- stoppedWith outcome
            case stoppedCause stopped of
                FoldTransaction failure -> do
                    submitBoundary failure `shouldBe` Ledger
                    case failure of
                        SubmissionRefused _ reason -> reason `shouldBe` "an input is not unspent"
                        _ -> expectationFailure ("not a refusal: " <> show failure)
                other -> expectationFailure ("not a ledger refusal: " <> show other)
            stoppedPremint stopped `shouldSatisfy` isJust
            stoppedFold stopped `shouldSatisfy` isJust
            submissionsMade world >>= (`shouldBe` submissionsBefore + 2)

-- | The slot that starts at a deadline of these specs, whose slots last a second.
deadlineSlot :: Integer -> Integer
deadlineSlot deadline = (deadline - originMs) `div` 1_000
