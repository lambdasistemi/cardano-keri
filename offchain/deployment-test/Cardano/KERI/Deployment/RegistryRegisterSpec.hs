{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryRegisterSpec
Description : a registration is booked in the registry the files name, inside the booking width, and refused by name when the chain shows it cannot be

Booking runs over a registry that @ckeri registry deploy@ created, on a chain
that keeps its unspent outputs and runs no script. What it books, over what
interval, and what it refuses before it pays are observed from outside. Every
expected value is spelled out here or read from the export and the files, never
from the code that booked.
-}
module Cardano.KERI.Deployment.RegistryRegisterSpec (spec) where

import Cardano.KERI.AID.Application (
    Credential (..),
    PlutusAddress (..),
    RegistrationData (..),
    RegistryIdentity (..),
 )
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryChain
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (
    Chain (..),
    Faults (..),
    noFaults,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord (..), ScriptReference (..))
import Cardano.KERI.Deployment.RegistryRegister
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..))
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.N2C.Types (ConnectionLost (..))
import Cardano.Node.Client.Provider (SlotNo (..))
import Control.Exception (AsyncException (..), toException, try)
import Control.Monad (forM_, void)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import Test.Hspec

-- | What a booking reported, with how many submissions had been made when it did.
type Seen = [(Int, RegisterEvent)]

booked :: World -> RegisterRequest -> IO (Either RegisterFailure Registered, Seen)
booked world request = do
    seen <- newIORef []
    outcome <-
        registerRegistration
            (runtimeOf noFaults world)
            ( \event -> do
                n <- submissionsMade world
                modifyIORef' seen ((n, event) :)
            )
            request
    (,) outcome . reverse <$> readIORef seen

spec :: Spec
spec = describe "#351 booking a registration" $ around_ withinOneMinute $ do
    describe "a booking that settles" $ do
        it "books one request at the application's address: the export's key, the payer as refund and controller, the registry's floor as deposit" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            submissionsBefore <- submissionsMade world
            (outcome, seen) <- booked world (registerRequestOf world export)
            result <- either (fail . show) pure outcome
            submitted <- submissionsMade world
            submitted - submissionsBefore `shouldBe` 1
            transactions <- accepted world
            let booking = last transactions
                identity = deployedIdentity (worldDeployed world)
                outputs = toList (booking ^. bodyTxL . outputsTxBodyL)
                request = case outputs of
                    first : _ -> first
                    [] -> error "the booking has no output"
                record = registeredRecord result
            registeredTransaction result `shouldBe` transactionId booking
            registeredOutput result `shouldBe` TxIn (transactionId booking) (TxIx 0)
            -- the output the booking names is the request, at the application's address
            request ^. coinTxOutL `shouldBe` Coin 1_010_500_000
            registrationOfOutput request `shouldBe` Just record
            -- the record is what the export and the payer commit, spelled here
            requestKey record `shouldBe` keyOf export
            requestRefundAddress record `shouldBe` PlutusAddress (KeyCredential (BS.replicate 28 0x11)) Nothing
            requestController record `shouldBe` BS.replicate 28 0x11
            requestHoldingAddress record
                `shouldBe` PlutusAddress (ScriptCredential (riCheckpointValidator identity)) Nothing
            requestDeposit record `shouldBe` 1_009_000_000
            registryStatePolicy (requestRegistry record) `shouldBe` rlStatePolicy (riRelease identity)
            -- the clock: booked at the interval's upper bound, due the processing time later
            let plan = registeredPlan result
            requestBookedAt record `shouldBe` upperPosixMs plan
            requestProcessDeadline record `shouldBe` upperPosixMs plan + 90_000
            requestReclaimEnd record `shouldBe` requestProcessDeadline record
            -- it reported the window, the time left as the transaction leaves, then the settled booking
            map fst seen `shouldBe` [submissionsBefore, submissionsBefore, submissionsBefore + 1]
            case map snd seen of
                [ BookingWindow{eventPlan = reported, eventDeadline = deadline}
                    , BookingSubmitting{eventTransaction = leaving, eventTimeLeftMs = left}
                    , BookingSettled{eventTransaction = txId, eventOutput = out}
                    ] -> do
                        reported `shouldBe` plan
                        deadline `shouldBe` requestProcessDeadline record
                        -- the clock of the chain moves half a second at each signature, and the
                        -- booking is signed twice before it leaves: the controller has a second less
                        left `shouldBe` deadline - (slotStart 1_000 10_000 + 100 + 1_000)
                        leaving `shouldBe` transactionId booking
                        txId `shouldBe` transactionId booking
                        out `shouldBe` registeredOutput result
                other -> expectationFailure ("unexpected events: " <> show other)
        it "starts the interval at the node's tip and spans whole slots no wider than the registry's booking width" $
            forM_ [(1_000, 5), (700, 7), (250, 20), (5_000, 1), (1_300, 3)] $ \(slotMs, slots) -> do
                world <- newWorld slotMs
                export <- loadExport "kli-export-single.cesr"
                (outcome, _) <- booked world (registerRequestOf world export)
                result <- either (fail . show) pure outcome
                let plan = registeredPlan result
                lowerSlot plan `shouldBe` SlotNo 10_000
                upperSlot plan `shouldBe` SlotNo (10_000 + slots)
                lowerPosixMs plan `shouldBe` slotStart slotMs 10_000
                upperPosixMs plan - lowerPosixMs plan `shouldBe` slotMs * toInteger slots
                (upperPosixMs plan - lowerPosixMs plan <= 5_000) `shouldBe` True
        it "books two different identities, each under its own key" $ do
            world <- newWorld 1_000
            single <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            keyOf single `shouldSatisfy` (/= keyOf multi)
            (first', _) <- booked world (registerRequestOf world single)
            (second', _) <- booked world (registerRequestOf world multi)
            fmap (requestKey . registeredRecord) first' `shouldBe` Right (keyOf single)
            fmap (requestKey . registeredRecord) second' `shouldBe` Right (keyOf multi)
        it "commits the deposit it is given when it is at or above the registry's floor" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (outcome, _) <-
                booked world (registerRequestOf world export){registerDeposit = Just 1_013_000_000}
            fmap (requestDeposit . registeredRecord) outcome `shouldBe` Right 1_013_000_000

    describe "the window" $ do
        it "never spans more than the width, starts at the tip, and is the widest whole-slot interval that fits" $
            forM_ [(slotMs, width) | slotMs <- [250, 500, 700, 1_000, 1_300, 4_999], width <- [1, 249, 250, 999, 1_000, 5_000, 12_345]] $ \(slotMs, width) -> do
                world <- newWorld slotMs
                observed <- rtObserve (runtimeOf noFaults world)
                case bookingWindow observed width of
                    Nothing -> (width < slotMs) `shouldBe` True
                    Just p -> do
                        lowerSlot p `shouldBe` SlotNo 10_000
                        let span' = upperPosixMs p - lowerPosixMs p
                        (span' <= width) `shouldBe` True
                        (span' + slotMs > width) `shouldBe` True
                        (span' `mod` slotMs) `shouldBe` 0
        it "stops at the node's horizon: a width the node cannot convert is cut to the slots it can" $ do
            world <- newWorld 1_000
            setHorizon world 3
            observed <- rtObserve (runtimeOf noFaults world)
            plan <- maybe (fail "no window") pure (bookingWindow observed 5_000)
            upperSlot plan `shouldBe` SlotNo 10_003
            upperPosixMs plan `shouldBe` slotStart 1_000 10_003
            setHorizon world 0
            observed' <- rtObserve (runtimeOf noFaults world)
            bookingWindow observed' 5_000 `shouldBe` Nothing

    describe "a failed read of the node" $ do
        it "ends the booking with nothing submitted, as a node failure; a cancellation passes through" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            sent0 <- submissionsMade world
            runtime <- failingObservation 1 (toException ConnectionLost) (runtimeOf noFaults world)
            outcome <- registerRegistration runtime (\_ -> pure ()) (registerRequestOf world export)
            outcome `shouldBe` Left (RegisterTransaction (NodeFailed (show ConnectionLost)))
            submissionsMade world >>= (`shouldBe` sent0)
            linked <- withClient (failingObservationBy 1 . connectionEnds) (runtimeOf noFaults world)
            linkedOutcome <- registerRegistration linked (\_ -> pure ()) (registerRequestOf world export)
            case linkedOutcome of
                Left (RegisterTransaction (NodeFailed failure)) -> failure `shouldSatisfy` ("ConnectionLost" `isInfixOf`)
                other -> expectationFailure ("not a node failure: " <> show other)
            submissionsMade world >>= (`shouldBe` sent0)
            -- the booking handed to the node whose settlement is lost: uncertain, with its id
            lost <- withClient (failingSettlementBy 1 . void . connectionEnds) (runtimeOf noFaults world)
            lostOutcome <- registerRegistration lost (\_ -> pure ()) (registerRequestOf world export)
            transactions <- accepted world
            case lostOutcome of
                Left (RegisterTransaction (NotObserved txId _)) -> txId `shouldBe` transactionId (last transactions)
                other -> expectationFailure ("not an uncertain booking: " <> show other)
            interrupted <- failingObservation 1 (toException UserInterrupt) (runtimeOf noFaults world)
            result <- try @AsyncException (registerRegistration interrupted (\_ -> pure ()) (registerRequestOf world export))
            either show (const "an outcome") result `shouldBe` show UserInterrupt

    describe "what it refuses before it pays, by name" $ do
        it "an identity whose active token stands at the checkpoint validator's address in this registry" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            plantCheckpoint world (keyOf export)
            sent0 <- submissionsMade world
            (outcome, seen) <- booked world (registerRequestOf world export)
            outcome `shouldBe` Left (RegisterRefused (AlreadyRegistered (keyOf export)))
            seen `shouldBe` []
            submissionsMade world >>= (`shouldBe` sent0)
        it "but books an identity when only another identity's token stands there" $ do
            world <- newWorld 1_000
            single <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            plantCheckpoint world (keyOf single)
            (outcome, _) <- booked world (registerRequestOf world multi)
            fmap (requestKey . registeredRecord) outcome `shouldBe` Right (keyOf multi)
        it "a booking width the slot is wider than: no whole slot fits" $ do
            world <- newWorld 5_001
            export <- loadExport "kli-export-single.cesr"
            sent0 <- submissionsMade world
            (outcome, seen) <- booked world (registerRequestOf world export)
            outcome `shouldBe` Left (RegisterRefused (BookingWidthBelowSlotLength 5_000 5_001))
            seen `shouldBe` []
            submissionsMade world >>= (`shouldBe` sent0)
        it "a deposit below the registry's floor" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            sent0 <- submissionsMade world
            (outcome, _) <- booked world (registerRequestOf world export){registerDeposit = Just 1_008_999_999}
            outcome `shouldBe` Left (RegisterRefused (DepositBelowFloor 1_008_999_999 1_009_000_000))
            submissionsMade world >>= (`shouldBe` sent0)
        it "files that do not describe the scripts the blueprint derives" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            let identity = deployedIdentity (worldDeployed world)
                tampered = identity{riCheckpointValidator = BS.replicate 28 0x99}
            sent0 <- submissionsMade world
            (outcome, _) <- booked world (registerRequestOf world export){registerIdentity = tampered}
            case outcome of
                Left (RegisterRefused (DeploymentDisagrees _)) -> pure ()
                other -> expectationFailure ("not refused as a disagreeing deployment: " <> show other)
            submissionsMade world >>= (`shouldBe` sent0)
        it "a record whose published outputs are not on the chain" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            let ref = scriptOutput (recordApplication (deployedRecord (worldDeployed world)))
            let gone = txInOfReference ref
            removeOutput world gone
            sent0 <- submissionsMade world
            (outcome, _) <- booked world (registerRequestOf world export)
            outcome `shouldBe` Left (RegisterRefused (ReferenceOutputsMissing [gone]))
            submissionsMade world >>= (`shouldBe` sent0)

    describe "where a transaction that does not land was refused" $ do
        it "the node's evaluation refuses before submission; the ledger refuses a submission; a transaction not seen settle is unsettled" $ do
            export <- loadExport "kli-export-single.cesr"
            -- evaluation: the node names a failing purpose
            world1 <- newWorld 1_000
            base1 <- submissionsMade world1
            outcome1 <-
                registerRegistration
                    (runtimeOf noFaults{distortEvaluation = \_ _ -> Map.empty} world1)
                    (\_ -> pure ())
                    (registerRequestOf world1 export)
            case outcome1 of
                Left (RegisterTransaction failure) -> submitBoundary failure `shouldBe` NodeEvaluation
                other -> expectationFailure ("evaluation: " <> show other)
            submissionsMade world1 >>= (`shouldBe` base1)
            -- the ledger: the node refuses the submission
            world2 <- newWorld 1_000
            base2 <- submissionsMade world2
            outcome2 <-
                registerRegistration
                    (runtimeOf noFaults{rejectSubmissionAt = Just base2} world2)
                    (\_ -> pure ())
                    (registerRequestOf world2 export)
            case outcome2 of
                Left (RegisterTransaction failure) -> submitBoundary failure `shouldBe` Ledger
                other -> expectationFailure ("submission: " <> show other)
            -- not seen to settle: neither refused nor landed as far as the command knows
            world3 <- newWorld 1_000
            observed <- chainObservations <$> readIORef (worldChain world3)
            outcome3 <-
                registerRegistration
                    (runtimeOf noFaults{failObservationAt = Just observed} world3)
                    (\_ -> pure ())
                    (registerRequestOf world3 export)
            case outcome3 of
                Left (RegisterTransaction failure) -> submitBoundary failure `shouldBe` Unsettled
                other -> expectationFailure ("observation: " <> show other)
        it "every refusal the command makes is the command's" $ do
            map renderBoundary [Command, NodeEvaluation, Ledger]
                `shouldBe` [ "the command, before any transaction"
                           , "the node's evaluation of the transaction"
                           , "the ledger"
                           ]
