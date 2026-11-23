{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReturnSpec
Description : a booked request is returned after its deadline, the refund address its own datum names is paid everything but the tip, and the return stops and reports when it cannot

Returning runs over a registry that @ckeri registry deploy@ created, on a chain that
keeps its unspent outputs and runs no script. The request is booked with the library's own
builder, so a return is judged on what it does, not on the command that books. What it
pays, to whom, over which interval, and what it refuses before it pays are observed from
outside. Every expected value is spelled here or read from the request, never from the code
that returned it; the window is checked against the statement of the Lean model's
@returnWindow@: a non-empty interval whose lower bound is at or after the deadline.
-}
module Cardano.KERI.Deployment.RegistryReturnSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (HeldDatum (..), PlutusAddress (..), RegistrationData (..), heldDatumData)
import Cardano.KERI.AID.Application qualified as App
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand (renderReturnStopped)
import Cardano.KERI.Deployment.RegistryChain
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), Faults (..), noFaults, walletAddress)
import Cardano.KERI.Deployment.RegistryReturn
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..), ledgerAddressOf, plutusAddressOf)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL, outputsTxBodyL, vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, coinTxOutL, datumTxOutL)
import Cardano.Ledger.BaseTypes (Network (..), StrictMaybe (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefBase, StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Cardano.Ledger.Mary.Value (MultiAsset (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Node.Client.Provider (SlotNo (..))
import Control.Exception (AsyncException (..), SomeException, throwIO, toException, try)
import Control.Monad (forM_, unless, void, when)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((.~), (^.))
import System.Timeout (timeout)
import Test.Hspec

type Seen = [(Int, ReturnEvent)]

inputOf :: World -> TxIn -> ReturnInput
inputOf world request =
    ReturnInput
        { returnBlueprint = worldBlueprint world
        , returnIdentity = deployedIdentity (worldDeployed world)
        , returnRecord = deployedRecord (worldDeployed world)
        , returnRequestOutput = request
        , returnPayerAddress = folderAddress
        }

returned :: Faults -> World -> TxIn -> IO (Either ReturnStopped ReturnDone, Seen)
returned faults world = returnedOver (runtimeOf faults world) world

returnedOver :: RegistryRuntime -> World -> TxIn -> IO (Either ReturnStopped ReturnDone, Seen)
returnedOver runtime world request = do
    seen <- newIORef []
    outcome <-
        returnBookedRequest
            runtime
            ( \event -> do
                n <- submissionsMade world
                modifyIORef' seen ((n, event) :)
            )
            (inputOf world request)
    (,) outcome . reverse <$> readIORef seen

-- | A registry with a request booked for the single export, the tip where it was booked.
booking :: Integer -> IO (World, TxIn, RegistrationData)
booking slotMs = do
    world <- newWorld slotMs
    export <- loadExport "kli-export-single.cesr"
    (ref, record) <- bookDirectly world export
    pure (world, ref, record)

{- | The first slot that starts at or after the request's deadline: the first slot the chain
can show reaching it.
-}
eligibleSlot :: World -> RegistrationData -> Integer
eligibleSlot world record =
    (requestProcessDeadline record - originMs + slotMs - 1) `div` slotMs
  where
    slotMs = worldSlotMs world

stoppedWith :: Either ReturnStopped ReturnDone -> IO ReturnStopped
stoppedWith = \case
    Left stopped -> pure stopped
    Right done -> expectationFailure ("the return was not stopped: " <> show done) >> fail "not stopped"

lovelaceAt :: World -> Addr -> IO Integer
lovelaceAt world address = do
    held <- rtUtxosAt (runtimeOf noFaults world) address
    pure (sum [unCoin (out ^. coinTxOutL) | (_, out) <- held])

idText :: TxId -> String
idText = T.unpack . renderTransactionId

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

spec :: Spec
spec = describe "#351 returning a booked request" $ around_ withinOneMinute $ do
    describe "a return that settles" $ do
        it "pays the refund address the request's datum names the request's lovelace less the tip, burns the approval, and leaves the tip to the wallet that returns" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            base <- length <$> accepted world
            returnerBefore <- lovelaceAt world folderAddress
            refundBefore <- lovelaceAt world walletAddress
            (outcome, _) <- returned noFaults world request
            done <- either (fail . show) pure outcome
            transactions <- accepted world
            length transactions `shouldBe` base + 1
            let returnTx = last transactions
                outputs = toList (returnTx ^. bodyTxL . outputsTxBodyL)
            -- the request held 1_009_000_000 + 1_000_000 + 500_000; the refund is all but the 500_000 tip
            requestRecordLovelace record `shouldBe` 1_010_500_000
            case outputs of
                refund : _ -> do
                    refund ^. addrTxOutL `shouldBe` walletAddress
                    refund ^. coinTxOutL `shouldBe` Coin 1_010_000_000
                [] -> expectationFailure "the return has no output"
            doneReturn done `shouldBe` transactionId returnTx
            doneRefundOutput done `shouldBe` TxIn (transactionId returnTx) (TxIx 0)
            doneRefundLovelace done `shouldBe` 1_010_000_000
            doneFee done `shouldBe` feeOf returnTx
            -- the refund address received exactly the refund; the returner gained the tip less the fee
            refundAfter <- lovelaceAt world walletAddress
            refundAfter - refundBefore `shouldBe` 1_010_000_000
            returnerAfter <- lovelaceAt world folderAddress
            returnerAfter - returnerBefore `shouldBe` 500_000 - feeOf returnTx
            -- the request is spent, and its approval is burned: one asset, minus one
            rtOutputs (runtimeOf noFaults world) (singletonSet request) >>= (`shouldBe` Map.empty)
            let MultiAsset burned = returnTx ^. bodyTxL . mintTxBodyL
            [quantity | names <- Map.elems burned, quantity <- Map.elems names] `shouldBe` [-1]
        it "reports what it will pay before it hands anything to the node: the request, the refund address, the amounts and the interval, then the handoff, then the settlement" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            sent0 <- submissionsMade world
            (outcome, seen) <- returned noFaults world request
            done <- either (fail . show) pure outcome
            map fst seen `shouldBe` [sent0, sent0, sent0 + 1]
            case map snd seen of
                [ ReturnPlanned{plannedRequest = ref, plannedRefundAddress = refund, plannedRefundLovelace = paid, plannedTipLovelace = tip, plannedPlan = plan, plannedDeadline = deadline}
                    , ReturnHandingOff{handingOffTransaction = leaving}
                    , ReturnSettled{settledTransaction = settled, settledRefundOutput = refundOut, settledFee = fee}
                    ] -> do
                        ref `shouldBe` request
                        refund `shouldBe` walletAddress
                        paid `shouldBe` 1_010_000_000
                        tip `shouldBe` 500_000
                        deadline `shouldBe` requestProcessDeadline record
                        lowerSlot plan `shouldBe` SlotNo (fromInteger (eligibleSlot world record))
                        leaving `shouldBe` doneReturn done
                        settled `shouldBe` doneReturn done
                        refundOut `shouldBe` doneRefundOutput done
                        fee `shouldBe` doneFee done
                other -> expectationFailure ("unexpected events: " <> show other)
        it "takes the amounts from the request's own output, not from a sum of the terms: a request holding another lovelace is returned in full but the tip" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            reshape world request (coinTxOutL .~ Coin 1_234_567_890)
            (outcome, _) <- returned noFaults world request
            done <- either (fail . show) pure outcome
            doneRefundLovelace done `shouldBe` 1_234_067_890
            transactions <- accepted world
            case toList (last transactions ^. bodyTxL . outputsTxBodyL) of
                refund : _ -> refund ^. coinTxOutL `shouldBe` Coin 1_234_067_890
                [] -> expectationFailure "the return has no output"
        it "pays the address the datum names, whoever returns, whatever the address is: a script payment credential with a stake credential" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            let named = Addr Testnet (ScriptHashObj (ScriptHash (hashOf 0x44))) (StakeRefBase (KeyHashObj (KeyHash (hashOf 0x55))))
            reshape world request $
                datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record{requestRefundAddress = plutusAddressOf named}))
            (outcome, _) <- returned noFaults world request
            _ <- either (fail . show) pure outcome
            transactions <- accepted world
            case toList (last transactions ^. bodyTxL . outputsTxBodyL) of
                refund : _ -> refund ^. addrTxOutL `shouldBe` named
                [] -> expectationFailure "the return has no output"
            lovelaceAt world named >>= (`shouldBe` 1_010_000_000)
        it "is a return that settled whatever happens to the node client after it settled: it ends while the settlement is reported" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            base <- length <$> accepted world
            client <- newStandIn
            seen <- newIORef []
            outcome <-
                returnBookedRequest
                    (whileConnected (standInStatus client) (runtimeOf noFaults world))
                    (\event -> modifyIORef' seen (event :) >> case event of ReturnSettled{} -> standInEnd client; _ -> pure ())
                    (inputOf world request)
            outcome `shouldSatisfy` either (const False) (const True)
            accepted world >>= (`shouldBe` (base + 1)) . length
    describe "the refund address of a request" $ do
        it "is a ledger address of the network when its credentials are hashes of the length of a ledger credential, with or without a stake credential"
            $ forM_
                [ (Testnet, Addr Testnet (KeyHashObj (KeyHash (hashOf 0x11))) StakeRefNull)
                , (Testnet, Addr Testnet (ScriptHashObj (ScriptHash (hashOf 0x22))) StakeRefNull)
                , (Testnet, Addr Testnet (KeyHashObj (KeyHash (hashOf 0x33))) (StakeRefBase (ScriptHashObj (ScriptHash (hashOf 0x44)))))
                , (Mainnet, Addr Mainnet (ScriptHashObj (ScriptHash (hashOf 0x55))) (StakeRefBase (KeyHashObj (KeyHash (hashOf 0x66)))))
                ]
            $ \(network, address) ->
                ledgerAddressOf network (plutusAddressOf address) `shouldBe` Just address
        it "is not an address when a credential is not a hash of that length, and is on the network it is asked on" $ do
            ledgerAddressOf Testnet (PlutusAddress (App.KeyCredential (BS.replicate 27 0x11)) Nothing) `shouldBe` Nothing
            ledgerAddressOf Testnet (PlutusAddress (App.ScriptCredential (BS.replicate 29 0x11)) Nothing) `shouldBe` Nothing
            ledgerAddressOf Testnet (PlutusAddress (App.KeyCredential (BS.replicate 28 0x11)) (Just (App.KeyCredential BS.empty))) `shouldBe` Nothing
            ledgerAddressOf Mainnet (PlutusAddress (App.KeyCredential (BS.replicate 28 0x11)) Nothing)
                `shouldBe` Just (Addr Mainnet (KeyHashObj (KeyHash (hashOf 0x11))) StakeRefNull)
    describe "the return window: one observation per decision, and the row that decided" $ do
        it "is open from the first slot the chain shows at or after the deadline, whatever the length of a slot: the interval starts at the tip, in whole slots, no wider than the booking width" $
            forM_ [(slotMs, slots, later) | (slotMs, slots) <- [(1_000, 5), (700, 7), (250, 20), (5_000, 1)], later <- [0, 3]] $ \(slotMs, slots, later) -> do
                (world, request, record) <- booking slotMs
                let tip = eligibleSlot world record + later
                setTip world tip
                observed0 <- observationsMade world
                (outcome, seen) <- returned noFaults world request
                _ <- either (fail . show) pure outcome
                observed1 <- observationsMade world
                observed1 - observed0 `shouldBe` 1
                case map snd seen of
                    ReturnPlanned{plannedPlan = plan} : _ -> do
                        lowerSlot plan `shouldBe` SlotNo (fromInteger tip)
                        upperSlot plan `shouldBe` SlotNo (fromInteger (tip + slots))
                        lowerPosixMs plan `shouldBe` slotStart slotMs tip
                        (lowerPosixMs plan >= requestProcessDeadline record) `shouldBe` True
                        upperPosixMs plan - lowerPosixMs plan `shouldBe` slotMs * slots
                    other -> expectationFailure ("no plan was reported: " <> show other)
                -- the transaction the node was given declares exactly that interval
                transactions <- accepted world
                case last transactions ^. bodyTxL . vldtTxBodyL of
                    ValidityInterval (SJust lower) (SJust upper) -> do
                        lower `shouldBe` SlotNo (fromInteger tip)
                        upper `shouldBe` SlotNo (fromInteger (tip + slots))
                    other -> expectationFailure ("the return declares no bounded interval: " <> show other)
        it "refuses before the deadline by name, with the tip, the clock and the deadline, one observation, nothing submitted: the tip is before it and so is the clock" $
            forM_ [1_000, 250, 700, 5_000] $ \slotMs -> do
                (world, request, record) <- booking slotMs
                let tip = eligibleSlot world record - 1
                    deadline = requestProcessDeadline record
                setTip world tip
                sent0 <- submissionsMade world
                (outcome, seen) <- returned noFaults world request
                stopped <- stoppedWith outcome
                -- the clock of the world is a hundred milliseconds into the tip's slot
                returnCause stopped `shouldBe` ReturnRefused (DeadlineNotReached deadline (slotStart slotMs tip) (slotStart slotMs tip + 100))
                returnAttempt stopped `shouldBe` Nothing
                seen `shouldBe` []
                submissionsMade world >>= (`shouldBe` sent0)
                observationsMade world >>= (`shouldBe` 1)
        it "refuses when the clock reads the deadline as reached and the chain does not: the conflict is named with the three readings, not decided; at the deadline exactly, and past it" $
            forM_ [("at", 0), ("past", 7)] $ \(label :: String, past) -> do
                (world, request, record) <- booking 1_000
                let tip = eligibleSlot world record - 1
                    deadline = requestProcessDeadline record
                    tipStart = slotStart 1_000 tip
                setTip world tip
                -- the clock reads tipStart + 100 + elapsed
                advanceClock world (deadline - tipStart - 100 + past)
                sent0 <- submissionsMade world
                (outcome, seen) <- returned noFaults world request
                stopped <- stoppedWith outcome
                (label, returnCause stopped) `shouldBe` (label, ReturnRefused (TimeEvidenceConflicts (deadline + past) deadline tipStart))
                seen `shouldBe` []
                submissionsMade world >>= (`shouldBe` sent0)
                observationsMade world >>= (`shouldBe` 1)
        it "refuses a clock one millisecond short of the deadline as not reached, and not as a conflict" $ do
            (world, request, record) <- booking 1_000
            let tip = eligibleSlot world record - 1
                deadline = requestProcessDeadline record
                tipStart = slotStart 1_000 tip
            setTip world tip
            advanceClock world (deadline - tipStart - 100 - 1)
            (outcome, _) <- returned noFaults world request
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (DeadlineNotReached deadline tipStart (deadline - 1))
        it "returns when the chain has reached the deadline whatever the clock reads, and from the one observation" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            -- a clock far behind the chain does not hold a return back: only the chain says the deadline is reached
            observationsBefore <- observationsMade world
            (outcome, _) <- returned noFaults world request
            void (either (fail . show) pure outcome)
            observationsMade world >>= (`shouldBe` (observationsBefore + 1))
        it "refuses by name when the chain is at the deadline and the node can convert no slot after the tip" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            setHorizon world 0
            sent0 <- submissionsMade world
            (outcome, _) <- returned noFaults world request
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (NoReturnSlotYet (slotStart 1_000 (eligibleSlot world record)))
            submissionsMade world >>= (`shouldBe` sent0)
        it "ends the interval at what the node can convert: two slots of five" $ do
            (world, request, record) <- booking 1_000
            let tip = eligibleSlot world record
            setTip world tip
            setHorizon world 2
            (outcome, seen) <- returned noFaults world request
            void (either (fail . show) pure outcome)
            case map snd seen of
                ReturnPlanned{plannedPlan = plan} : _ -> upperSlot plan `shouldBe` SlotNo (fromInteger tip + 2)
                other -> expectationFailure ("no plan was reported: " <> show other)
        it "refuses a registry whose booking width is shorter than a slot, as the booking does, nothing submitted" $ do
            (world, request, record) <- booking 6_000
            setTip world (eligibleSlot world record)
            sent0 <- submissionsMade world
            (outcome, _) <- returned noFaults world request
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (BookingWidthBelowSlotLength 5_000 6_000)
            submissionsMade world >>= (`shouldBe` sent0)
        it "agrees with the model's return window on every observation of a grid: a plan is a non-empty interval starting at or after the deadline, and the chain at the deadline always has one when the node can convert a slot" $ do
            let deadline = 10_000_000
                width = 5_000
                grid =
                    [ (obs, slotMs)
                    | slotMs <- [250, 700, 1_000, 5_000, 6_000]
                    , tipStart <- [deadline - slotMs, deadline - 1, deadline, deadline + 1, deadline + slotMs]
                    , clock <- [tipStart + 100, deadline - 1, deadline, deadline + 500]
                    , ahead <- [0, 1, 3, 50]
                    , let obs =
                            Observation
                                { obsTipSlot = SlotNo 100
                                , obsTipStartMs = tipStart
                                , obsSlotLengthMs = slotMs
                                , obsClockMs = clock
                                , obsHorizonSlot = SlotNo (100 + ahead)
                                }
                    ]
                -- the model: a non-empty interval whose lower bound is at or after the deadline
                modelReturnWindow lower upper = lower < upper && deadline <= lower
                verdicts = [(obs, slotMs, returnWindow obs width deadline) | (obs, slotMs) <- grid]
            forM_ verdicts $ \(obs, slotMs, verdict) -> do
                let label = show (obs, verdict)
                    reached = obsTipStartMs obs >= deadline
                    ahead = toInteger (unSlotNo (obsHorizonSlot obs)) - 100
                case verdict of
                    Right plan -> do
                        (label, modelReturnWindow (lowerPosixMs plan) (upperPosixMs plan)) `shouldBe` (label, True)
                        (label, lowerSlot plan) `shouldBe` (label, obsTipSlot obs)
                        (label, upperPosixMs plan - lowerPosixMs plan) `shouldBe` (label, slotMs * toInteger (unSlotNo (upperSlot plan) - unSlotNo (lowerSlot plan)))
                        (label, upperPosixMs plan - lowerPosixMs plan <= width) `shouldBe` (label, True)
                        (label, upperSlot plan <= obsHorizonSlot obs) `shouldBe` (label, True)
                    Left refusal -> case refusal of
                        DeadlineNotReached d tipStart clock -> (label, (d, tipStart, clock, reached, clock < deadline)) `shouldBe` (label, (deadline, obsTipStartMs obs, obsClockMs obs, False, True))
                        TimeEvidenceConflicts clock d tipStart -> (label, (d, tipStart, clock, reached, clock >= deadline)) `shouldBe` (label, (deadline, obsTipStartMs obs, obsClockMs obs, False, True))
                        NoReturnSlotYet tipStart -> (label, (tipStart, reached, ahead)) `shouldBe` (label, (obsTipStartMs obs, True, 0))
                        BookingWidthBelowSlotLength w s -> (label, (w, s, slotMs > width)) `shouldBe` (label, (width, slotMs, True))
                        other -> expectationFailure (label <> ": a row the window does not have: " <> show other)
                -- the chain at the deadline has a plan whenever a slot fits the width and the node can convert one
                when (reached && slotMs <= width && ahead >= 1) $
                    (label, either (const False) (const True) verdict) `shouldBe` (label, True)
                -- before the deadline, the chain never has one, whatever the clock reads
                unless reached $
                    (label, either (const True) (const False) verdict) `shouldBe` (label, True)
            -- the grid is not vacuous: every kind of verdict is among the ones it checked
            let kinds =
                    [ case verdict of
                        Right _ -> "plan" :: String
                        Left DeadlineNotReached{} -> "not-reached"
                        Left TimeEvidenceConflicts{} -> "conflict"
                        Left NoReturnSlotYet{} -> "no-slot"
                        Left BookingWidthBelowSlotLength{} -> "width"
                        Left _ -> "other"
                    | (_, _, verdict) <- verdicts
                    ]
            forM_ ["plan", "not-reached", "conflict", "no-slot", "width"] $ \kind ->
                (kind, kind `elem` kinds) `shouldBe` (kind, True)
            length (filter (== "other") kinds) `shouldBe` 0
    describe "the request" $ do
        it "must be an output the node holds unspent: one that was spent is refused by name before any transaction" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            first <- returned noFaults world request
            void (either (fail . show) pure (fst first))
            sent1 <- submissionsMade world
            (outcome, seen) <- returned noFaults world request
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (RequestUnavailable request)
            seen `shouldBe` []
            submissionsMade world >>= (`shouldBe` sent1)
        it "must be a request: the registry's own state output is refused by name" $ do
            (world, _, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            Just (stateRef, _) <- stateOutputOf world
            sent0 <- submissionsMade world
            (outcome, _) <- returned noFaults world stateRef
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (RequestIsNotARegistration stateRef)
            submissionsMade world >>= (`shouldBe` sent0)
        it "must hold the approval the booking minted: an output that only looks like the request is refused by name" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            forged <- stripApproval world request
            sent0 <- submissionsMade world
            (outcome, _) <- returned noFaults world forged
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (RequestHasNoApproval forged)
            submissionsMade world >>= (`shouldBe` sent0)
        it "must name a refund address of this network: a hash of another length is refused by name, and nothing is paid to a guess" $ do
            (world, request, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            reshape world request $
                datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record{requestRefundAddress = PlutusAddress (App.KeyCredential (BS.replicate 5 0x11)) Nothing}))
            sent0 <- submissionsMade world
            (outcome, _) <- returned noFaults world request
            stopped <- stoppedWith outcome
            returnCause stopped `shouldBe` ReturnRefused (RequestRefundUnreadable request)
            submissionsMade world >>= (`shouldBe` sent0)
    describe "the handoff count" $
        it "tells one handoff from two, and counts a call the ended connection kept from the node: at the boundary the command calls" $ do
            (world, _, record) <- booking 1_000
            setTip world (eligibleSlot world record)
            sent0 <- submissionsMade world
            tx <- last <$> accepted world
            -- a caller that calls for the handoff once, and a caller that calls twice
            forM_ [1, 2 :: Int] $ \times -> do
                (runtime, handoffs) <- handoffsCounted (runtimeOf noFaults world)
                forM_ [1 .. times] $ \_ -> void (trSubmit (rtTransactions runtime) tx)
                handoffs >>= (`shouldBe` times)
            -- a call over a connection that ended never reaches the node, and is still a call
            client <- newStandIn
            (runtime, handoffs) <- handoffsCounted (whileConnected (standInStatus client) (runtimeOf noFaults world))
            standInEnd client
            _ <- try @SomeException (trSubmit (rtTransactions runtime) tx)
            handoffs >>= (`shouldBe` 1)
            submissionsMade world >>= (`shouldBe` (sent0 + 3))
    describe "how far a signed return got, at the real boundaries" $ do
        let setup = do
                (world, request, record) <- booking 1_000
                setTip world (eligibleSlot world record)
                base <- length <$> accepted world
                sent0 <- submissionsMade world
                pure (world, request, base, sent0)
            quiet _ = pure ()
            runIt runtime report world request =
                returnBookedRequest runtime report (inputOf world request)
        it "says a return the node refused is refused, with its id, and that it is not on chain" $ do
            (world, request, base, sent0) <- setup
            (runtime, handoffs) <- handoffsCounted (runtimeOf noFaults{rejectSubmissionAt = Just sent0} world)
            stopped <- runIt runtime quiet world request >>= stoppedWith
            case returnAttempt stopped of
                Just (Attempt txId (RefusedByNode _)) -> do
                    returnCause stopped `shouldSatisfy` \case
                        ReturnTransaction (SubmissionRefused refused _) -> refused == txId
                        _ -> False
                    let said = renderReturnStopped stopped
                    said `shouldSatisfy` elem ("return " <> idText txId <> " was refused by the node: the node refuses this transaction; it is not on chain")
                    said `shouldSatisfy` any ("not retried: " `isPrefixOf`)
                other -> expectationFailure ("not a refused return: " <> show other)
            accepted world >>= (`shouldBe` base) . length
            handoffs >>= (`shouldBe` 1)
        it "says a return whose handoff the client did not survive may or may not have reached the node, whether or not the node took it" $
            forM_ [False, True] $ \reaches -> do
                (world, request, base, _) <- setup
                (runtime, handoffs) <- handoffsCounted =<< endingHandoff reaches (runtimeOf noFaults world)
                stopped <- runIt runtime quiet world request >>= stoppedWith
                case returnAttempt stopped of
                    Just (Attempt txId HandoffUnknown) -> do
                        returnCause stopped `shouldSatisfy` \case
                            ReturnTransaction (HandoffUnconfirmed unconfirmed _) -> unconfirmed == txId
                            _ -> False
                        renderReturnStopped stopped `shouldSatisfy` elem ("return " <> idText txId <> " may or may not have reached the node; check it before spending again")
                        renderReturnStopped stopped `shouldSatisfy` notElem zeroLine
                        transactions <- accepted world
                        length transactions `shouldBe` base + (if reaches then 1 else 0)
                        handoffs >>= (`shouldBe` 1)
                    other -> expectationFailure ("not an unknown handoff: " <> show other)
        it "says a return whose client ended while its id was reported was not handed to the node, and that nothing was spent" $ do
            (world, request, base, sent0) <- setup
            client <- newStandIn
            let report = \case
                    ReturnHandingOff{} -> standInEnd client
                    _ -> pure ()
            (runtime, handoffs) <- handoffsCounted (whileConnected (standInStatus client) (runtimeOf noFaults world))
            stopped <- runIt runtime report world request >>= stoppedWith
            case returnAttempt stopped of
                Just (Attempt txId NotHandedToNode) -> do
                    renderReturnStopped stopped `shouldSatisfy` elem ("return " <> idText txId <> " was not handed to the node")
                    renderReturnStopped stopped `shouldSatisfy` elem zeroLine
                other -> expectationFailure ("not a return that was never handed over: " <> show other)
            accepted world >>= (`shouldBe` base) . length
            submissionsMade world >>= (`shouldBe` sent0)
            -- the command called for the handoff once; the ended connection kept it from the node
            handoffs >>= (`shouldBe` 1)
        it "says a return the node took and whose settlement was not seen is accepted by the node and not seen on chain" $ do
            (world, request, base, _) <- setup
            -- the fault index counts the observations made so far: the next one fails
            observed <- chainObservations <$> readIORef (worldChain world)
            (runtime, handoffs) <- handoffsCounted (runtimeOf noFaults{failObservationAt = Just observed} world)
            stopped <- runIt runtime quiet world request >>= stoppedWith
            case returnAttempt stopped of
                Just (Attempt txId AcceptedByNode) ->
                    renderReturnStopped stopped `shouldSatisfy` elem ("return " <> idText txId <> " was accepted by the node and is not seen on chain; check it before spending again")
                other -> expectationFailure ("not an accepted return: " <> show other)
            accepted world >>= (`shouldBe` (base + 1)) . length
            -- the settlement was not seen, and the return was not handed over again
            handoffs >>= (`shouldBe` 1)
        it "keeps the receipt of a return seen to settle, and says so, when the report of it cannot be written: id, refund output, fee" $ do
            (world, request, base, _) <- setup
            let report = \case
                    ReturnSettled{} -> ioError (userError "the report cannot be written")
                    _ -> pure ()
            (runtime, handoffs) <- handoffsCounted (runtimeOf noFaults world)
            stopped <- runIt runtime report world request >>= stoppedWith
            handoffs >>= (`shouldBe` 1)
            transactions <- accepted world
            length transactions `shouldBe` base + 1
            let settledReturn = last transactions
                said = renderReturnStopped stopped
            case returnAttempt stopped of
                Just (Attempt txId (SettledOnChain settled)) -> do
                    txId `shouldBe` transactionId settledReturn
                    feeOf settled `shouldBe` feeOf settledReturn
                other -> expectationFailure ("not a return seen to settle: " <> show other)
            said `shouldSatisfy` any ("ckeri: registry return settled; the command was cut short after that" `isPrefixOf`)
            said `shouldSatisfy` elem ("return-transaction: " <> idText (transactionId settledReturn))
            said `shouldSatisfy` elem ("refund-output: " <> idText (transactionId settledReturn) <> "#0")
            said `shouldSatisfy` elem ("return-fee: " <> show (feeOf settledReturn))
            said `shouldSatisfy` (not . any ("not seen on chain" `isInfixOf`))
            said `shouldSatisfy` notElem zeroLine
        it "ends as a stop that says nothing was spent when the node cannot be read before anything was signed" $ do
            (world, request, base, sent0) <- setup
            runtime <- failingObservation 1 (toException (userError "the node cannot be read")) (runtimeOf noFaults world)
            stopped <- runIt runtime quiet world request >>= stoppedWith
            returnCause stopped `shouldSatisfy` \case
                ReturnNodeFailed _ -> True
                _ -> False
            returnAttempt stopped `shouldBe` Nothing
            renderReturnStopped stopped `shouldSatisfy` elem zeroLine
            accepted world >>= (`shouldBe` base) . length
            submissionsMade world >>= (`shouldBe` sent0)
        it "labels a failure to report an event as the report's, with nothing submitted: at the plan and at the handoff announcement"
            $ forM_
                [ ("the plan", \case ReturnPlanned{} -> True; _ -> False, Nothing)
                , ("the handoff", \case ReturnHandingOff{} -> True; _ -> False, Just NotHandedToNode)
                ]
            $ \(label, isHere, attemptStatusWanted) -> do
                (world, request, base, sent0) <- setup
                (runtime, handoffs) <- handoffsCounted (runtimeOf noFaults world)
                stopped <- runIt runtime (\event -> when (isHere event) (ioError (userError "the report cannot be written"))) world request >>= stoppedWith
                let said = renderReturnStopped stopped
                (label :: String, returnCause stopped) `shouldSatisfy` \case (_, ReturnReportFailed message) -> "the report cannot be written" `isInfixOf` message; _ -> False
                (label, fmap attemptStatus (returnAttempt stopped)) `shouldBe` (label, attemptStatusWanted)
                (label, any ("the report could not be written" `isInfixOf`) said) `shouldBe` (label, True)
                (label, any ("the node could not be read" `isInfixOf`) said) `shouldBe` (label, False)
                (label, zeroLine `elem` said) `shouldBe` (label, True)
                handoffs >>= (`shouldBe` 0)
                submissionsMade world >>= (`shouldBe` sent0)
                accepted world >>= (`shouldBe` base) . length
        it "lets a cancellation through at each of its own boundaries, as one, and sends nothing after it"
            $ forM_
                [ ("while the plan is announced", \case ReturnPlanned{} -> True; _ -> False)
                , ("while the handoff is announced", \case ReturnHandingOff{} -> True; _ -> False)
                , ("after the return settled", \case ReturnSettled{} -> True; _ -> False)
                ]
            $ \(label, isHere) -> do
                (world, request, _, _) <- setup
                outcome <- try @AsyncException (runIt (runtimeOf noFaults world) (\event -> when (isHere event) (throwIO UserInterrupt)) world request)
                (label :: String, either show (const "an outcome") outcome) `shouldBe` (label, show UserInterrupt)
        it "answers within ten seconds wherever the node client ends, over calls that hold no acquired ledger state: every call before it is made, and the submission and the settlement after the node did its part" $ do
            (world0, request0, _, _) <- setup
            probe <- newStandIn
            (counting, callsMade) <- endingAt probe 0 False (runtimeOf noFaults world0)
            _ <- runIt counting quiet world0 request0
            calls <- callsMade
            length calls `shouldSatisfy` (> 5)
            forM_ [(i, late) | i <- [1 .. length calls], late <- if calls !! (i - 1) == ReadCall then [False] else [False, True]] $ \(i, late) -> do
                (world, request, base, _) <- setup
                client <- newStandIn
                (ending, _) <- endingAt client i late (runtimeOf noFaults world)
                let label = (i, calls !! (i - 1), late)
                (runtime, handoffs) <- handoffsCounted (whileConnected (standInStatus client) ending)
                outcome <- timeout 10_000_000 (runIt runtime quiet world request)
                stopped <- maybe (expectationFailure (show label <> ": no answer within ten seconds") >> fail "no answer") stoppedWith outcome
                landed <- length <$> accepted world
                let said = renderReturnStopped stopped
                -- the handoffs the command called for: none before the node client ends at a read, one after, and a
                -- second one fails here, however the first ended
                handoffs >>= (`shouldBe` (if calls !! (i - 1) == ReadCall then 0 else 1))
                case calls !! (i - 1) of
                    ReadCall -> do
                        (label, returnAttempt stopped, landed, zeroLine `elem` said) `shouldBe` (label, Nothing, base, True)
                    SubmitCall -> do
                        (label, fmap attemptStatus (returnAttempt stopped), landed) `shouldBe` (label, Just HandoffUnknown, base + (if late then 1 else 0))
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
                    ObserveCall -> do
                        (label, fmap attemptStatus (returnAttempt stopped), landed) `shouldBe` (label, Just AcceptedByNode, base + 1)
                        (label, last said) `shouldSatisfy` (\(_, text) -> "not retried" `isPrefixOf` text)
  where
    requestRecordLovelace record = requestDeposit record + 1_000_000 + 500_000
    singletonSet = Set.singleton
    hashOf n = fromJust (hashFromBytes (BS.replicate 28 n))

-- | The one handoff of the run: the node takes it or not, and the client ends as it goes.
endingHandoff :: Bool -> RegistryRuntime -> IO RegistryRuntime
endingHandoff reaches = withClient $ \client runtime -> do
    let transactions = rtTransactions runtime
    pure
        runtime
            { rtTransactions =
                transactions
                    { trSubmit = \tx -> do
                        when reaches (void (trSubmit transactions tx))
                        connectionEnds client
                    }
            }
