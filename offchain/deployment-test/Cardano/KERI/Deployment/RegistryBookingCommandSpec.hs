{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingCommandSpec
Description : @ckeri registry register@ and @ckeri registry fold@ over a chain that keeps its outputs

Each command is run whole, over the chain of "Cardano.KERI.Deployment.RegistryBookingChain",
in a directory of its own: what it prints as it goes, what it refuses and at which
boundary, what it leaves alone. The words a refusal is made of are spelled here.
-}
module Cardano.KERI.Deployment.RegistryBookingCommandSpec (spec, Setup (..), withSetup, openerOver, runCaptured, requestText) where

import Cardano.Crypto.DSIGN.Class (deriveVerKeyDSIGN, rawDeserialiseSignKeyDSIGN)
import Cardano.KERI.AID.Application (RegistrationData (..))
import Cardano.KERI.Deployment.LiveRuntime (decodePaymentAddress)
import Cardano.KERI.Deployment.NodeSocketRuntime
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryChain (Observation (..), Refusal (..), RegistryRuntime (..), foldWindow, whileConnected)
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing, capturingLive)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults, walletAddress)
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryProvider (ProviderChoice (..))
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), decodeSnapshot, encodeSnapshot)
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..))
import Cardano.KERI.Deployment.SigningKeyCheck (checkSigningKey)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Credential (Credential (..), StakeReference (StakeRefNull))
import Cardano.Ledger.Keys (DSIGN, KeyRole (Payment), VKey (..), hashKey)
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.N2C.Types (ConnectionLost (..), LocalStateQueryTimeout (..))
import Cardano.Node.Client.Provider (Provider (..), SlotNo (..))
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (forkFinally, forkIO, killThread, threadDelay, throwTo)
import Control.Concurrent.Async (async, wait)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar, takeMVar, tryTakeMVar)
import Control.Exception (AsyncException (..), ErrorCall (..), SomeException, bracket, bracket_, throwIO, toException, try, uninterruptibleMask_)
import Control.Monad (forM_, join, unless, void, when)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor qualified as Bi
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromLeft, isLeft, isRight)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf, isPrefixOf)
import Data.Set qualified as Set
import Data.Text qualified as T
import GHC.Clock (getMonotonicTime)
import Network.Socket qualified as Net
import Paths_cardano_keri (getDataFileName)
import System.Directory (createDirectory, listDirectory, removeFile, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Hspec

-- | A directory with the two files of the deployment, the export, and the settings that name them.
data Setup = Setup
    { setupDirectory :: FilePath
    , setupRegister :: RegistryRegisterSettings
    , setupFold :: RegistryFoldSettings
    }

withSetup :: World -> (Setup -> IO a) -> IO a
withSetup world action = withSystemTempDirectory "registry-booking-command" $ \scratch -> do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    export <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
    let work = scratch </> "work"
        identityFile = scratch </> "release-identity.json"
        recordFile = scratch </> "reference-outputs.json"
    createDirectory work
    written <-
        writeDeploymentFiles
            identityFile
            recordFile
            (deployedIdentity (worldDeployed world))
            (deployedRecord (worldDeployed world))
    either (fail . show) pure written
    action
        Setup
            { setupDirectory = work
            , setupRegister =
                RegistryRegisterSettings
                    { rgNetworkMagic = 42
                    , rgBlueprint = blueprint
                    , rgProvider = ProviderChoice (Just "no-node.socket") Nothing Nothing Nothing
                    , rgFundingAddress = "addr_test1unused"
                    , rgSigningKeyFile = Just "no-key.skey"
                    , rgVault = Nothing
                    , rgPassphraseFd = Nothing
                    , rgTimeoutSeconds = 5
                    , rgReleaseIdentity = identityFile
                    , rgReferenceRecord = recordFile
                    , rgKliExport = export
                    , rgDeposit = Nothing
                    }
            , setupFold =
                RegistryFoldSettings
                    { rfNetworkMagic = 42
                    , rfBlueprint = blueprint
                    , rfProvider = ProviderChoice (Just "no-node.socket") Nothing Nothing Nothing
                    , rfFundingAddress = "addr_test1unused"
                    , rfSigningKeyFile = Just "no-key.skey"
                    , rfVault = Nothing
                    , rfPassphraseFd = Nothing
                    , rfTimeoutSeconds = 5
                    , rfReleaseIdentity = identityFile
                    , rfReferenceRecord = recordFile
                    , rfRequest = ""
                    , rfSnapshot = scratch </> "snapshot.json"
                    , rfSnapshotOut = Nothing
                    , rfPending = []
                    }
            }

-- | The opener over a world, with the payer the command is given and a note of how it was reached.
openerOver :: Faults -> World -> Addr -> IO (RegistryOpener, IO [NodeAccess])
openerOver faults world payer = do
    reached <- newIORef []
    pure
        ( \access use -> do
            modifyIORef' reached (access :)
            use (runtimeOf faults world, payer)
        , reverse <$> readIORef reached
        )

-- | Run an action, and give its exit, what it printed and what it printed as an error.
runCaptured :: IO () -> IO (ExitCode, String, String)
runCaptured action = do
    ((outcome, out), err) <- capturing stderr (capturing stdout (try @ExitCode action))
    pure (fromLeft ExitSuccess outcome, out, err)

requestText :: TxIn -> String
requestText (TxIn txId (TxIx ix)) = T.unpack (renderTransactionId txId) <> "#" <> show ix

spec :: Spec
spec = describe "#351 ckeri registry register and ckeri registry fold" $ around_ withinOneMinute $ do
    describe "register" $ do
        it "prints the window, the deadline and the time left before it submits, then the booking and its output as it settles" $ do
            world <- newWorld 1_000
            withSetup world $ \setup -> do
                (opener, reachedBy) <- openerOver noFaults world walletAddress
                (code, out, _err) <- withCurrentDirectory (setupDirectory setup) (runCaptured (runRegistryRegisterWith opener (setupRegister setup)))
                code `shouldBe` ExitSuccess
                transactions <- accepted world
                let booking = last transactions
                    premint = last (init transactions)
                    txText = T.unpack (renderTransactionId (transactionId booking))
                    premintText = T.unpack (renderTransactionId (transactionId premint))
                    linesOut = lines out
                    position needle = length (takeWhile (not . (needle `isInfixOf`)) linesOut)
                -- spelled values: tip slot 10000 of one-second slots from the origin; five slots wide; 90 s to process
                out `shouldSatisfy` ("validity-interval-slots: 10000..10005" `isInfixOf`)
                out `shouldSatisfy` ("validity-interval-ms: 1800010000000..1800010005000" `isInfixOf`)
                out `shouldSatisfy` ("deadline-ms: 1800010095000" `isInfixOf`)
                -- the premint is signed first: half a second of the chain's clock less is left than for a booking alone
                out `shouldSatisfy` ("time-left-ms: 93400" `isInfixOf`)
                out `shouldSatisfy` (("premint-transaction: " <> premintText) `isInfixOf`)
                out `shouldSatisfy` (("proof-output: " <> premintText <> "#0") `isInfixOf`)
                out `shouldSatisfy` (("booking-transaction: " <> txText) `isInfixOf`)
                out `shouldSatisfy` (("booking-output: " <> txText <> "#0") `isInfixOf`)
                -- in the order the transactions happen
                (position "premint-transaction" < position "validity-interval-ms") `shouldBe` True
                (position "validity-interval-ms" < position "booking-transaction") `shouldBe` True
                (position "deadline-ms" < position "booking-transaction") `shouldBe` True
                (position "booking-transaction" < position "booking-output") `shouldBe` True
                -- it says what it cannot see
                out `shouldSatisfy` ("cannot see a terminal key or another pending booking" `isInfixOf`)
                out `shouldSatisfy` ("the fold is where a duplicate is stopped" `isInfixOf`)
                -- it reached the node as it was told, and left nothing in its directory
                reachedBy >>= (`shouldBe` [NodeAccess 42 "no-node.socket" "addr_test1unused" (KeyFile "no-key.skey") 5 Nothing])
                listDirectory (setupDirectory setup) >>= (`shouldBe` [])
        it "flushes the window before the booking is submitted, so whoever pipes it has it first" $ do
            world <- newWorld 1_000
            withSetup world $ \setup -> do
                (opener, _) <- openerOver noFaults world walletAddress
                (liveAtSubmission, _) <-
                    capturingLive stdout $ \readLive -> do
                        seen <- newIORef ""
                        let probed access use =
                                opener access $ \(runtime, payer) ->
                                    use
                                        ( runtime
                                            { rtTransactions =
                                                (rtTransactions runtime)
                                                    { trSubmit = \tx -> do
                                                        readLive >>= writeSeen seen
                                                        trSubmit (rtTransactions runtime) tx
                                                    }
                                            }
                                        , payer
                                        )
                        _ <- try @ExitCode (runRegistryRegisterWith probed (setupRegister setup))
                        readIORef seen
                liveAtSubmission `shouldSatisfy` ("deadline-ms: " `isInfixOf`)
                liveAtSubmission `shouldSatisfy` ("time-left-ms: " `isInfixOf`)
                liveAtSubmission `shouldSatisfy` (not . ("booking-transaction" `isInfixOf`))
        it "refuses an identity already registered here by name, before any transaction, as the command's refusal" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            plantCheckpoint world (keyOf export)
            withSetup world $ \setup -> do
                (opener, _) <- openerOver noFaults world walletAddress
                sent0 <- submissionsMade world
                (code, _out, err) <- runCaptured (runRegistryRegisterWith opener (setupRegister setup))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("already registered in this registry" `isInfixOf`)
                err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                err `shouldSatisfy` ("refused by the command, before any transaction" `isInfixOf`)
                submissionsMade world >>= (`shouldBe` sent0)
        it "says which boundary refused a transaction: the node's evaluation, or the ledger" $ do
            world1 <- newWorld 1_000
            withSetup world1 $ \setup -> do
                (opener, _) <- openerOver noFaults{distortEvaluation = \_ _ -> mempty} world1 walletAddress
                (code, _, err) <- runCaptured (runRegistryRegisterWith opener (setupRegister setup))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("refused by the node's evaluation of the transaction" `isInfixOf`)
            world2 <- newWorld 1_000
            withSetup world2 $ \setup -> do
                base <- submissionsMade world2
                (opener, _) <- openerOver noFaults{rejectSubmissionAt = Just base} world2 walletAddress
                (code, _, err) <- runCaptured (runRegistryRegisterWith opener (setupRegister setup))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("refused by the ledger" `isInfixOf`)
        it "refuses an export it cannot read, by name, before the node is reached" $ do
            world <- newWorld 1_000
            withSetup world $ \setup -> do
                (opener, reachedBy) <- openerOver noFaults world walletAddress
                (code, _, err) <-
                    runCaptured (runRegistryRegisterWith opener (setupRegister setup){rgKliExport = setupDirectory setup </> "missing.cesr"})
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("kli-export-invalid" `isInfixOf`)
                reachedBy >>= (`shouldBe` [])

    describe "the node's time" $ do
        it "recognises the pin's own forecast refusal and nothing else: a timeout, a lost connection and an unrelated failure end the observation at the failed read, whatever the stage; a cancellation is not a failure" $ do
            let origin = 1_800_000_000_000 :: Integer
                failures =
                    [ ("a query timeout", toException (LocalStateQueryTimeout 1_000_000))
                    , ("a lost connection", toException ConnectionLost)
                    , ("an unrelated failure", toException (userError "the disk is full"))
                    , ("another error call", toException (ErrorCall "queryUTxOByTxIn: era mismatch"))
                    ]
            forM_ failures $ \(label :: String, failure) ->
                forM_ [1, 2, 5, 13 :: Int] $ \failingCall -> do
                    calls <- newIORef (0 :: Int)
                    let toSlot ms = do
                            modifyIORef' calls (+ 1)
                            n <- readIORef calls
                            when (n == failingCall) $ throwIO failure
                            when (ms > origin + 10_003_999) pinRefusal
                            pure (SlotNo (fromInteger ((ms - origin) `div` 1_000)))
                    outcome <- try @SomeException (observeFrom (pure (SlotNo 10_000)) toSlot (origin + 10_004_100))
                    -- the failed read ends the observation: it is the failure, and no read follows it
                    (label, failingCall, either show (const "an observation") outcome) `shouldBe` (label, failingCall, show failure)
                    readIORef calls >>= (\n -> (label, failingCall, n) `shouldBe` (label, failingCall, failingCall))
            -- a cancellation passes through as itself
            forM_ [1, 4 :: Int] $ \failingCall -> do
                calls <- newIORef (0 :: Int)
                let toSlot ms = do
                        modifyIORef' calls (+ 1)
                        n <- readIORef calls
                        when (n == failingCall) $ throwIO UserInterrupt
                        when (ms > origin + 10_003_999) pinRefusal
                        pure (SlotNo (fromInteger ((ms - origin) `div` 1_000)))
                outcome <- try @AsyncException (observeFrom (pure (SlotNo 10_000)) toSlot (origin + 10_004_100))
                either show (const "an observation") outcome `shouldBe` show UserInterrupt
                readIORef calls >>= (`shouldBe` failingCall)
        it "observes a clock beyond the node's forecast without asking for it to be converted: the forecast, the tip start and the slot length are exact" $ do
            let origin = 1_800_000_000_000 :: Integer
                forecastEnd = origin + 10_003_999
                toSlot ms = do
                    when (ms > forecastEnd) pinRefusal
                    pure (SlotNo (fromInteger ((ms - origin) `div` 1_000)))
            reads' <- newIORef (0 :: Int)
            observed <-
                observeFrom (modifyIORef' reads' (+ 1) >> pure (SlotNo 10_000)) toSlot (origin + 10_004_100)
            observed
                `shouldBe` Observation
                    { obsTipSlot = SlotNo 10_000
                    , obsTipStartMs = origin + 10_000_000
                    , obsSlotLengthMs = 1_000
                    , obsClockMs = origin + 10_004_100
                    , obsHorizonSlot = SlotNo 10_003
                    }
            readIORef reads' >>= (`shouldBe` 1)
            -- the decision on it is W4, with the clock as sampled
            foldWindow observed 5_000 (origin + 10_095_000)
                `shouldBe` Left (NoIntervalYet (origin + 10_095_000) (origin + 10_004_100))
        it "keeps a clock conflict and an established expiry under a short forecast: W2 and W1, not W4" $ do
            let origin = 1_800_000_000_000 :: Integer
                toSlot forecastEnd ms = do
                    when (ms > forecastEnd) pinRefusal
                    pure (SlotNo (fromInteger ((ms - origin) `div` 1_000)))
                forecast = origin + 10_003_999
            -- tip 10000, the clock far beyond the forecast, the deadline just after the tip's start
            conflict <- observeFrom (pure (SlotNo 10_000)) (toSlot forecast) (origin + 10_600_100)
            foldWindow conflict 5_000 (origin + 10_000_050)
                `shouldBe` Left (TimeEvidenceConflicts (origin + 10_600_100) (origin + 10_000_050) (origin + 10_000_000))
            -- the chain has reached the deadline: the tip's slot starts at it
            reached <- observeFrom (pure (SlotNo 10_000)) (toSlot forecast) (origin + 10_600_100)
            foldWindow reached 5_000 (origin + 10_000_000) `shouldBe` Left (DeadlineReached (origin + 10_000_000))
        it "keeps exact slot boundaries for a clock far ahead of an old tip that the node converts" $
            forM_ [1_000, 700, 250] $ \slotMs -> do
                let origin = 1_800_000_000_000 :: Integer
                    toSlot ms = do
                        when (ms < origin) pinRefusal
                        pure (SlotNo (fromInteger ((ms - origin) `div` slotMs)))
                    clock = origin + 10_601 * slotMs + 100
                observed <- observeFrom (pure (SlotNo 10_000)) toSlot clock
                obsTipStartMs observed `shouldBe` origin + 10_000 * slotMs
                obsSlotLengthMs observed `shouldBe` slotMs
                -- a tip so old and a clock so far ahead: the plan starts in the clock's slot
                case foldWindow observed (5 * slotMs) (origin + 10_695 * slotMs) of
                    Right plan -> lowerSlot plan `shouldBe` SlotNo 10_601
                    Left refusal -> expectationFailure ("not a plan: " <> show refusal)
        it "takes a request reference only with an index a transaction can have" $ do
            let transaction = concat (replicate 32 "ab")
            parseRequestReference (transaction <> "#0") `shouldSatisfy` isRight
            parseRequestReference (transaction <> "#65535") `shouldSatisfy` isRight
            parseRequestReference (transaction <> "#65536") `shouldSatisfy` isLeft
            parseRequestReference (transaction <> "#-1") `shouldSatisfy` isLeft
            parseRequestReference (transaction <> "#4294967296") `shouldSatisfy` isLeft

    describe "fold" $ do
        it "names the supplier of the snapshot, prints each transaction as it settles, and writes the registry as it stands for the next folder" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, record) <- bookDirectly world export
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "the deployer" [] []))
                (opener, reachedBy) <- openerOver noFaults world folderAddress
                let settings =
                        (setupFold setup)
                            { rfRequest = T.pack (requestText request)
                            , rfSnapshotOut = Just (setupDirectory setup </> "after.json")
                            }
                (code, out, _) <- runCaptured (runRegistryFoldWith opener settings)
                code `shouldBe` ExitSuccess
                [foldTx] <- reverse . take 1 . reverse <$> accepted world
                let text txId = T.unpack (renderTransactionId (transactionId txId))
                    linesOut = lines out
                    position needle = length (takeWhile (not . (needle `isInfixOf`)) linesOut)
                out `shouldSatisfy` ("snapshot-supplied-by: the deployer" `isInfixOf`)
                out `shouldSatisfy` (("fold-transaction: " <> text foldTx) `isInfixOf`)
                out `shouldSatisfy` (("checkpoint-output: " <> text foldTx <> "#0") `isInfixOf`)
                (position "snapshot-supplied-by" < position "fold-transaction") `shouldBe` True
                -- the booking attested the inception: no premint is made, none is reported
                out `shouldSatisfy` (not . ("premint" `isInfixOf`))
                out `shouldSatisfy` ("snapshot-written: " `isInfixOf`)
                out `shouldSatisfy` ("an input the next fold checks again" `isInfixOf`)
                written <- BS.readFile (setupDirectory setup </> "after.json")
                fmap snapshotActive (decodeSnapshot written) `shouldBe` Right [requestKey record]
                reachedBy >>= (`shouldBe` [NodeAccess 42 "no-node.socket" "addr_test1unused" (KeyFile "no-key.skey") 5 Nothing])
        it "refuses a snapshot that is not the registry, as stale or unavailable, and a key it holds, as held: each by name, as the command's refusal, with no transaction" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            multi <- loadExport "kli-export-2-of-5.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                sent0 <- submissionsMade world
                (opener, _) <- openerOver noFaults world folderAddress
                let settings = (setupFold setup){rfRequest = T.pack (requestText request)}
                BS.writeFile (rfSnapshot settings) (encodeSnapshot (Snapshot "an out of date list" [keyOf multi] []))
                (code, _, err) <- runCaptured (runRegistryFoldWith opener settings)
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("stale or unavailable registry state" `isInfixOf`)
                err `shouldSatisfy` ("before any window check" `isInfixOf`)
                err `shouldSatisfy` (not . ("first window check" `isInfixOf`))
                err `shouldSatisfy` ("refused by the command, before any transaction" `isInfixOf`)
                err `shouldSatisfy` (not . ("already holds" `isInfixOf`))
                err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                setRegistryRoot world [keyOf export] []
                BS.writeFile (rfSnapshot settings) (encodeSnapshot (Snapshot "the follower" [keyOf export] []))
                (code', _, err') <- runCaptured (runRegistryFoldWith opener settings)
                code' `shouldBe` ExitFailure 1
                err' `shouldSatisfy` ("the registry already holds this key" `isInfixOf`)
                err' `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                err' `shouldSatisfy` ("refused by the command, before any transaction" `isInfixOf`)
                submissionsMade world >>= (`shouldBe` sent0)
        it "refuses a fold that can no longer be built inside the deadline, naming when the request can be returned" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            setTip world 10_200
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (opener, _) <- openerOver noFaults world folderAddress
                sent0 <- submissionsMade world
                (code, _, err) <-
                    runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request)})
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("deadline-reached: the timing condition for a return can be met from 1800010095000" `isInfixOf`)
                submissionsMade world >>= (`shouldBe` sent0)
        it "says each fold-window row in its own words: the deadline reached, the clock in conflict, no slot remains, and never a deadline passed where only a slot is missing" $ do
            let run slotMs tipOf elapsed = do
                    world <- newWorld slotMs
                    export <- loadExport "kli-export-single.cesr"
                    (request, record) <- bookDirectly world export
                    setTip world (tipOf (requestProcessDeadline record))
                    advanceClock world elapsed
                    withSetup world $ \setup -> do
                        BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                        (opener, _) <- openerOver noFaults world folderAddress
                        (code, _, err) <- runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request)})
                        code `shouldBe` ExitFailure 1
                        pure err
            w1 <- run 1_000 (\d -> (d - originMs) `div` 1_000) 0
            w1 `shouldSatisfy` ("deadline-reached: the timing condition for a return can be met from 1800010095000 ms [W1]" `isInfixOf`)
            w1 `shouldSatisfy` ("at the window check" `isInfixOf`)
            w1 `shouldSatisfy` (not . ("passed" `isInfixOf`))
            w2 <- run 1_000 (\d -> (d - originMs) `div` 1_000 - 2) 3_000
            w2 `shouldSatisfy` ("time-evidence-conflicts [W2]" `isInfixOf`)
            w2 `shouldSatisfy` ("these readings leave current return eligibility undetermined" `isInfixOf`)
            w3 <- run 700 (\d -> (d - originMs) `div` 700) 0
            w3 `shouldSatisfy` ("no-fold-slot-remains [W3]" `isInfixOf`)
            w3 `shouldSatisfy` ("a return is possible from" `isInfixOf`)
            w3 `shouldSatisfy` (not . ("passed" `isInfixOf`))
            w3 `shouldSatisfy` (not . ("run again" `isInfixOf`))
        it "says an interval cannot be formed yet, and that running again after the next block is possible, when nothing was spent" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            setTip world 10_000
            setHorizon world 3
            advanceClock world 4_000
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (opener, _) <- openerOver noFaults world folderAddress
                sent0 <- submissionsMade world
                (code, _, err) <- runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request)})
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("no-interval-yet" `isInfixOf`)
                err `shouldSatisfy` ("the command can be run again after the next block" `isInfixOf`)
                err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                err `shouldSatisfy` (not . ("deadline has passed" `isInfixOf`))
                submissionsMade world >>= (`shouldBe` sent0)
        it "says a node that could not be read is not a retryable window: nothing submitted, no run-again hint" $ do
            let failing = toException (LocalStateQueryTimeout 1_000_000)
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                let settings = (setupFold setup){rfRequest = T.pack (requestText request)}
                sent0 <- submissionsMade world
                (code1, _, first) <- runCaptured (runRegistryFoldWith (openerChanged (failingObservation 1 failing) world folderAddress) settings)
                code1 `shouldBe` ExitFailure 1
                first `shouldSatisfy` ("registry fold stopped, the node could not be read" `isInfixOf`)
                first `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                first `shouldSatisfy` (not . ("run again" `isInfixOf`))
                first `shouldSatisfy` (not . ("[W4]" `isInfixOf`))
                submissionsMade world >>= (`shouldBe` sent0)
        it "keeps the flushed handoff line: what a reader of the pipe has before the node is first read and, when the settlement of the fold is awaited, after it was handed over" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                pipeEarly <- newIORef ""
                pipeLate <- newIORef ""
                ((), _) <-
                    capturingLive stdout $ \readLive -> do
                        let watching runtime = do
                                calls <- newIORef (0 :: Int)
                                pure
                                    runtime
                                        { rtObserve = do
                                            modifyIORef' calls (+ 1)
                                            n <- readIORef calls
                                            seen <- readLive
                                            when (n == 1) (modifyIORef' pipeEarly (const seen))
                                            rtObserve runtime
                                        , rtTransactions =
                                            (rtTransactions runtime)
                                                { trObserve = \txId -> do
                                                    seen <- readLive
                                                    modifyIORef' pipeLate (const seen)
                                                    trObserve (rtTransactions runtime) txId
                                                }
                                        }
                        _ <- try @ExitCode (runRegistryFoldWith (openerChanged watching world folderAddress) (setupFold setup){rfRequest = T.pack (requestText request)})
                        pure ()
                [foldTx] <- reverse . take 1 . reverse <$> accepted world
                pipeBefore <- readIORef pipeEarly
                pipeAfter <- readIORef pipeLate
                -- before the node is read: the supplier, no transaction; once the fold awaits settlement: its id, already flushed
                pipeBefore `shouldSatisfy` ("snapshot-supplied-by:" `isInfixOf`)
                pipeBefore `shouldSatisfy` (not . ("handing fold" `isInfixOf`))
                pipeAfter `shouldSatisfy` (("handing fold " <> T.unpack (renderTransactionId (transactionId foldTx)) <> " to the node") `isInfixOf`)
        it "tells a fold that may have reached the node from one that did not: the attempted id, the uncertainty and the last confirmed state; and a node client that ends before and after the fold is signed" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                let settings = (setupFold setup){rfRequest = T.pack (requestText request)}
                sent0 <- submissionsMade world
                -- (a) before any submission
                (_, _, a) <- runCaptured (runRegistryFoldWith (openerChanged (withClient (failingObservationBy 1 . connectionEnds)) world folderAddress) settings)
                a `shouldSatisfy` ("registry fold stopped, the node could not be read" `isInfixOf`)
                a `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                submissionsMade world >>= (`shouldBe` sent0)
            -- (b) a fold that may already have reached the node
            world2 <- newWorld 1_000
            (request2, _) <- bookDirectly world2 export
            withSetup world2 $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (_, _, b) <-
                    runCaptured (runRegistryFoldWith (openerChanged (withClient (failingSettlementBy 1 . void . connectionEnds)) world2 folderAddress) (setupFold setup){rfRequest = T.pack (requestText request2)})
                [foldTx] <- reverse . take 1 . reverse <$> accepted world2
                b `shouldSatisfy` (("fold " <> T.unpack (renderTransactionId (transactionId foldTx)) <> " was accepted by the node and is not seen on chain; check it before spending again") `isInfixOf`)
                b `shouldSatisfy` ("node-confirmed-state: " `isInfixOf`)
                b `shouldSatisfy` (not . ("premint" `isInfixOf`))
        it "says the same of a booking whose node cannot be read: nothing submitted, a node failure" $ do
            world <- newWorld 1_000
            withSetup world $ \setup -> do
                sent0 <- submissionsMade world
                (code, _, err) <-
                    runCaptured (runRegistryRegisterWith (openerChanged (failingObservation 1 (toException ConnectionLost)) world walletAddress) (setupRegister setup))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("the node could not be read" `isInfixOf`)
                err `shouldSatisfy` (not . ("settle" `isInfixOf`))
                err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                submissionsMade world >>= (`shouldBe` sent0)
        it "names the fold it submitted when the ledger refused it" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            submissionsBefore <- submissionsMade world
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (opener, _) <- openerOver noFaults{rejectSubmissionAt = Just submissionsBefore} world folderAddress
                (code, _, err) <-
                    runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request)})
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("refused by the ledger" `isInfixOf`)
                err `shouldSatisfy` ("fold " `isInfixOf`)
                err `shouldSatisfy` (" was refused by the node: the node refuses this transaction; it is not on chain" `isInfixOf`)
                err `shouldSatisfy` ("not retried" `isInfixOf`)
        it "gives the whole report of a fold that stopped to a working reader wherever the node client ends: before each call and after each submission and settlement" $ do
            world0 <- newWorld 1_000
            export0 <- loadExport "kli-export-single.cesr"
            (request0, _) <- bookDirectly world0 export0
            calls <- withSetup world0 $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (opener, callsMade) <- openerEnding 0 False world0 folderAddress
                _ <- runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request0)})
                callsMade
            length calls `shouldSatisfy` (> 5)
            forM_ [(i, late) | i <- [1 .. length calls], late <- if calls !! (i - 1) == ReadCall then [False] else [False, True]] $ \(i, late) -> do
                world <- newWorld 1_000
                export <- loadExport "kli-export-single.cesr"
                (request, _) <- bookDirectly world export
                withSetup world $ \setup -> do
                    BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                    (opener, _) <- openerEnding i late world folderAddress
                    let label = (i, calls !! (i - 1), late)
                    ran <- timeout 20_000_000 (runCaptured (runRegistryFoldWith opener (setupFold setup){rfRequest = T.pack (requestText request)}))
                    (code, _, err) <- maybe (expectationFailure (show label <> ": the command did not end within twenty seconds") >> fail "no end") pure ran
                    (label, code) `shouldBe` (label, ExitFailure 1)
                    let said = lines err
                        wanted = case calls !! (i - 1) of
                            ReadCall -> ["the node could not be read", zeroLine]
                            SubmitCall -> ["fold ", " may or may not have reached the node; check it before spending again", "not retried"]
                            ObserveCall -> ["fold ", " was accepted by the node and is not seen on chain; check it before spending again", "not retried"]
                    forM_ wanted $ \needle -> (label, err) `shouldSatisfy` (\(_, text) -> needle `isInfixOf` text)
                    -- a report that was whole ends where a report ends
                    (label, last said) `shouldSatisfy` (\(_, final) -> final == zeroLine || "not retried" `isPrefixOf` final)
                    -- no premint exists in a fold to be named
                    (label, err) `shouldSatisfy` (\(_, text) -> not ("premint" `isInfixOf` text))
        it "gives the whole stop report of a fold to a working reader when the node client ends after the library has returned and between the lines of the report" $ do
            let run endAt = do
                    world <- newWorld 1_000
                    export <- loadExport "kli-export-single.cesr"
                    (request, _) <- bookDirectly world export
                    sent0 <- submissionsMade world
                    client <- newStandIn
                    written <- newIORef (0 :: Int)
                    withSetup world $ \setup -> do
                        BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                        let writer line = do
                                n <- readIORef written
                                modifyIORef' written (+ 1)
                                when (Just n == endAt) (standInEnd client)
                                hPutStrLn stderr line
                        (_, _, err) <-
                            runCaptured $
                                runRegistryFoldReporting
                                    writer
                                    (openerClient client noFaults{rejectSubmissionAt = Just sent0} world folderAddress)
                                    (setupFold setup){rfRequest = T.pack (requestText request)}
                        pure (lines err)
            baseline <- run Nothing
            length baseline `shouldSatisfy` (> 3)
            -- the report the others are compared with is itself whole: the fold's refusal, the state last confirmed and that nothing is retried
            baseline `shouldSatisfy` any ("node-confirmed-state: " `isPrefixOf`)
            baseline `shouldSatisfy` any (" was refused by the node" `isInfixOf`)
            baseline `shouldSatisfy` (("not retried" `isPrefixOf`) . last)
            forM_ [0 .. length baseline - 1] $ \at -> do
                reported <- timeout 20_000_000 (run (Just at))
                reported `shouldBe` Just baseline
        it "gives the whole failure report of a booking to a working reader when the node client ends after the library has returned and between the lines of the report" $ do
            let run endAt = do
                    world <- newWorld 1_000
                    sent0 <- submissionsMade world
                    client <- newStandIn
                    written <- newIORef (0 :: Int)
                    withSetup world $ \setup -> do
                        let writer line = do
                                n <- readIORef written
                                modifyIORef' written (+ 1)
                                when (Just n == endAt) (standInEnd client)
                                hPutStrLn stderr line
                        (_, _, err) <-
                            runCaptured $
                                runRegistryRegisterReporting
                                    writer
                                    (openerClient client noFaults{rejectSubmissionAt = Just (sent0 + 1)} world walletAddress)
                                    (setupRegister setup)
                        pure (lines err)
            baseline <- run Nothing
            length baseline `shouldSatisfy` (> 1)
            baseline `shouldSatisfy` any (" was refused by the node" `isInfixOf`)
            baseline `shouldSatisfy` any ("booking " `isPrefixOf`)
            forM_ [0 .. length baseline - 1] $ \at -> do
                reported <- timeout 20_000_000 (run (Just at))
                reported `shouldBe` Just baseline
        it "gives the whole failure report of a booking to a working reader wherever the node client ends before the library returns" $ do
            world0 <- newWorld 1_000
            calls <- withSetup world0 $ \setup -> do
                (opener, callsMade) <- openerEnding 0 False world0 walletAddress
                _ <- runCaptured (runRegistryRegisterWith opener (setupRegister setup))
                callsMade
            length calls `shouldSatisfy` (> 5)
            forM_ [(i, late) | i <- [1 .. length calls], late <- if calls !! (i - 1) == ReadCall then [False] else [False, True]] $ \(i, late) -> do
                world <- newWorld 1_000
                withSetup world $ \setup -> do
                    (opener, _) <- openerEnding i late world walletAddress
                    let label = (i, calls !! (i - 1), late)
                    ran <- timeout 20_000_000 (runCaptured (runRegistryRegisterWith opener (setupRegister setup)))
                    (code, _, err) <- maybe (expectationFailure (show label <> ": the command did not end within twenty seconds") >> fail "no end") pure ran
                    (label, code) `shouldBe` (label, ExitFailure 1)
                    -- the call is the premint's or the booking's: a stop before the premint settled has spent nothing, and one
                    -- after it says what landed
                    let premintLanded = "the premint of the hash proof settled" `isInfixOf` err
                        said needle = (label, err) `shouldSatisfy` (\(_, text) -> needle `isInfixOf` text)
                    case calls !! (i - 1) of
                        ReadCall -> do
                            said "the node could not be read"
                            (label, premintLanded, zeroLine `isInfixOf` err) `shouldBe` (label, premintLanded, not premintLanded)
                        SubmitCall -> do
                            said " may or may not have reached the node; check it before spending again"
                            (label, "booking " `isInfixOf` err || "premint " `isInfixOf` err) `shouldBe` (label, True)
                        ObserveCall -> do
                            said " was accepted by the node and is not seen on chain; check it before spending again"
                            (label, "booking " `isInfixOf` err || "premint " `isInfixOf` err) `shouldBe` (label, True)
        it "ends a fold as a cancellation when the person running it interrupts while its report cannot be written" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            sent0 <- submissionsMade world
            withSetup world $ \setup -> do
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                (opener, _) <- openerOver noFaults{rejectSubmissionAt = Just sent0} world folderAddress
                outcome <-
                    interruptedWhileReporting $ \writer ->
                        runRegistryFoldReporting writer opener (setupFold setup){rfRequest = T.pack (requestText request)}
                fmap (either show (const "returned")) outcome `shouldBe` Just (show UserInterrupt)
        it "ends a booking as a cancellation when the person running it interrupts while its report cannot be written" $ do
            world <- newWorld 1_000
            sent0 <- submissionsMade world
            withSetup world $ \setup -> do
                (opener, _) <- openerOver noFaults{rejectSubmissionAt = Just sent0} world walletAddress
                outcome <-
                    interruptedWhileReporting $ \writer ->
                        runRegistryRegisterReporting writer opener (setupRegister setup)
                fmap (either show (const "returned")) outcome `shouldBe` Just (show UserInterrupt)
        it "refuses inputs it cannot read by name, before the node is reached" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                (opener, reachedBy) <- openerOver noFaults world folderAddress
                BS.writeFile (rfSnapshot (setupFold setup)) "not a snapshot"
                let settings = (setupFold setup){rfRequest = T.pack (requestText request)}
                (_, _, err1) <- runCaptured (runRegistryFoldWith opener settings)
                err1 `shouldSatisfy` ("snapshot-invalid" `isInfixOf`)
                err1 `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                (_, _, err2) <- runCaptured (runRegistryFoldWith opener settings{rfRequest = "nonsense"})
                err2 `shouldSatisfy` ("request-reference-invalid" `isInfixOf`)
                err2 `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                (_, _, err2b) <- runCaptured (runRegistryFoldWith opener settings{rfRequest = T.pack (concat (replicate 32 "ab") <> "#65536")})
                err2b `shouldSatisfy` ("request-reference-invalid" `isInfixOf`)
                BS.writeFile (rfSnapshot settings) (encodeSnapshot (Snapshot "x" [] []))
                BS.writeFile (setupDirectory setup </> "after.json") "taken"
                (_, _, err3) <- runCaptured (runRegistryFoldWith opener settings{rfSnapshotOut = Just (setupDirectory setup </> "after.json")})
                err3 `shouldSatisfy` ("file-exists" `isInfixOf`)
                err3 `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                reachedBy >>= (`shouldBe` [])
    describe "a node whose connection is gone, reached for real" $ do
        let scenarios =
                [ ("there is no socket", Nothing)
                , ("the node hung up before the command ran", Just False)
                , ("the node hangs up while the command runs", Just True)
                ]
            -- the second argument of the action is what is done when the operation begins: the node
            -- that is to hang up has taken the client's connection first, so what ends is a connection that was up
            withNode short (scenario :: Maybe Bool) action = case scenario of
                Nothing -> action (short <> "/none.socket") (pure ())
                Just later -> do
                    let socketPath = short <> "/n.socket"
                    withNodeThatHangsUp socketPath $ \node -> do
                        unless later (nodeHangUp node)
                        action socketPath (when later (nodeConnected node >> nodeHangUp node))
        it "ends a fold with the node unreadable and nothing spent, within five seconds of its start, however the connection is gone, with no query that has acquired ledger state" $
            forM_ scenarios $ \(label, scenario) -> do
                world <- newWorld 1_000
                withSetup world $ \setup -> withSystemTempDirectory "ckn" $ \short -> do
                    let keyFile = setupDirectory setup </> "payment.skey"
                    BL.writeFile keyFile (encode keyEnvelope)
                    BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                    withNode short scenario $ \socketPath whenBegun -> do
                        let settings =
                                (setupFold setup)
                                    { rfSigningKeyFile = Just keyFile
                                    , rfFundingAddress = keyAddressText
                                    , rfProvider = ProviderChoice (Just socketPath) Nothing Nothing Nothing
                                    , rfRequest = T.pack (replicate 64 'a' <> "#0")
                                    }
                            open access use = openRegistryNode access (\runtime -> whenBegun >> use runtime)
                        started <- getMonotonicTime
                        ran <- timeout 20_000_000 (runCaptured (runRegistryFoldWith open settings))
                        ended <- getMonotonicTime
                        (code, _, err) <- maybe (expectationFailure (label <> ": the command did not end within twenty seconds") >> fail "no end") pure ran
                        hPutStrLn stderr (label <> ": fold ended " <> show (ended - started) <> " s after it started")
                        (label, code) `shouldBe` (label, ExitFailure 1)
                        (label, err) `shouldSatisfy` (\(_, text) -> "the node could not be read" `isInfixOf` text)
                        (label, err) `shouldSatisfy` (\(_, text) -> zeroLine `isInfixOf` text)
                        (label, err) `shouldSatisfy` (\(_, text) -> not ("signing-key-" `isInfixOf` text))
                        (label, ended - started < 5) `shouldBe` (label, True)
        it "ends a booking with the node unreadable and nothing spent, within five seconds of its start, however the connection is gone, with no query that has acquired ledger state" $
            forM_ scenarios $ \(label, scenario) -> do
                world <- newWorld 1_000
                withSetup world $ \setup -> withSystemTempDirectory "ckn" $ \short -> do
                    let keyFile = setupDirectory setup </> "payment.skey"
                    BL.writeFile keyFile (encode keyEnvelope)
                    withNode short scenario $ \socketPath whenBegun -> do
                        let settings =
                                (setupRegister setup)
                                    { rgSigningKeyFile = Just keyFile
                                    , rgFundingAddress = keyAddressText
                                    , rgProvider = ProviderChoice (Just socketPath) Nothing Nothing Nothing
                                    }
                            open access use = openRegistryNode access (\runtime -> whenBegun >> use runtime)
                        started <- getMonotonicTime
                        ran <- timeout 20_000_000 (runCaptured (runRegistryRegisterWith open settings))
                        ended <- getMonotonicTime
                        (code, _, err) <- maybe (expectationFailure (label <> ": the command did not end within twenty seconds") >> fail "no end") pure ran
                        hPutStrLn stderr (label <> ": booking ended " <> show (ended - started) <> " s after it started")
                        (label, code) `shouldBe` (label, ExitFailure 1)
                        (label, err) `shouldSatisfy` (\(_, text) -> "the node could not be read" `isInfixOf` text)
                        (label, err) `shouldSatisfy` (\(_, text) -> zeroLine `isInfixOf` text)
                        (label, err) `shouldSatisfy` (\(_, text) -> not ("signing-key-" `isInfixOf` text))
                        (label, ended - started < 5) `shouldBe` (label, True)
        it "returns from a query that has not acquired ledger state and from a submission within a second of the connection ending, over the node's own client" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            signed <- last <$> accepted world
            withSetup world $ \setup -> withSystemTempDirectory "ckn" $ \short -> do
                let keyFile = setupDirectory setup </> "payment.skey"
                    access = NodeAccess 42 (short <> "/n.socket") keyAddressText (KeyFile keyFile) 5 Nothing
                BL.writeFile keyFile (encode keyEnvelope)
                withNodeThatHangsUp (short <> "/n.socket") $ \node -> do
                    measured <- newIORef Nothing
                    openRegistryNode access $ \(runtime, _) -> do
                        -- the client's connection was taken by the node, and then the node hangs up
                        nodeConnected node
                        nodeHangUp node
                        q <- timed (try @SomeException (rtOutputs runtime (Set.singleton request)))
                        s <- timed (try @SomeException (trSubmit (rtTransactions runtime) signed))
                        writeIORef measured (Just (q, s))
                    Just (query, submission) <- readIORef measured
                    hPutStrLn stderr ("a query after the connection ended: " <> show (fst query) <> " s")
                    hPutStrLn stderr ("a submission after the connection ended: " <> show (fst submission) <> " s")
                    (fst query < 1, isLeft (snd query)) `shouldBe` (True, True)
                    (fst submission < 1, isLeft (snd submission)) `shouldBe` (True, True)
        it "returns from a query that has not acquired ledger state and from a submission that are under way when the node hangs up, within a second of it" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            signed <- last <$> accepted world
            forM_ [("query", Left request), ("submission", Right signed)] $ \(label, call) ->
                withSetup world $ \setup -> withSystemTempDirectory "ckn" $ \short -> do
                    let keyFile = setupDirectory setup </> "payment.skey"
                        access = NodeAccess 42 (short <> "/n.socket") keyAddressText (KeyFile keyFile) 5 Nothing
                    BL.writeFile keyFile (encode keyEnvelope)
                    withNodeThatHangsUp (short <> "/n.socket") $ \node -> do
                        measured <- newIORef Nothing
                        openRegistryNode access $ \(runtime, _) -> do
                            nodeConnected node
                            running <-
                                async . try @SomeException $
                                    either (void . rtOutputs runtime . Set.singleton) (void . trSubmit (rtTransactions runtime)) call
                            -- the call is waiting for the node when it hangs up
                            threadDelay 300_000
                            nodeHangUp node
                            hungUp <- getMonotonicTime
                            outcome <- timeout 10_000_000 (wait running)
                            returned <- getMonotonicTime
                            writeIORef measured (Just (returned - hungUp, outcome))
                        Just (seconds, outcome) <- readIORef measured
                        hPutStrLn stderr ("a " <> label <> " under way when the node hung up returned after " <> show seconds <> " s")
                        (label :: String, seconds < 1, maybe False isLeft outcome) `shouldBe` (label, True, True)
    describe "a query that has acquired ledger state when the connection ends, over the node's own client and a scripted node" $ do
        -- The bound of this path: the node client's release timeout (one second in the pinned
        -- client: 'releaseAcquiredLSQBestEffort') plus a scheduling margin. The margin is half a
        -- second: the release timer is the protocol's, so the wait is never shorter than one second,
        -- and what is added to it is only the wake-up of a timer and of a few threads, which takes
        -- milliseconds on this machine and not a half second except under a load no gate row has.
        let releaseTimeoutSeconds = 1 :: Double
            schedulingMarginSeconds = 0.5 :: Double
            acquiredBound = releaseTimeoutSeconds + schedulingMarginSeconds
        it "returns from it within the release timeout of the node client plus half a second of scheduling, in each order in which the end becomes known" $ do
            world <- newWorld 1_000
            forM_ [ClientStatusFirst, LivenessFirst] $ \ending -> do
                acquired <- runAcquiredCase (runtimeOf noFaults world) ending folderAddress (\provider address -> void (queryUTxOs provider address))
                hPutStrLn stderr (show ending <> ": an acquired query returned " <> show (caseSeconds acquired) <> " s after the connection ended")
                (ending, caseWitness acquired) `shouldBe` (ending, (True, True))
                (ending, caseSeconds acquired <= acquiredBound) `shouldBe` (ending, True)
                (ending, isLeft (caseOutcome acquired)) `shouldBe` (ending, True)
        it "waits out the whole release timeout when the client is reported ended before the library's liveness signal is raised" $ do
            world <- newWorld 1_000
            acquired <- runAcquiredCase (runtimeOf noFaults world) ClientStatusFirst folderAddress (\provider address -> void (queryUTxOs provider address))
            -- the case is on the acquired path: the call did not return before the library's release gave up
            (caseSeconds acquired >= releaseTimeoutSeconds - 0.1) `shouldBe` True
        it "shows the case can fail: a release that never times out exceeds the bound" $ do
            world <- newWorld 1_000
            held <-
                runAcquiredCase (runtimeOf noFaults world) ClientStatusFirst folderAddress $ \provider address ->
                    bracket_ (pure ()) (uninterruptibleMask_ (threadDelay 3_000_000)) (void (queryUTxOs provider address))
            hPutStrLn stderr ("a call whose release never times out returned " <> show (caseSeconds held) <> " s after the connection ended")
            caseWitness held `shouldBe` (True, True)
            (caseSeconds held <= acquiredBound) `shouldBe` False
        it "ends a fold and a booking with their whole report within the same bound, in each order in which the end becomes known" $
            forM_ [(command, ending) | command <- ["fold", "booking"], ending <- [ClientStatusFirst, LivenessFirst]] $ \(command :: String, ending) -> do
                world <- newWorld 1_000
                export <- loadExport "kli-export-single.cesr"
                (request, _) <- bookDirectly world export
                withSetup world $ \setup -> withScriptedClient ending $ \client -> do
                    BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                    let payer = if command == "fold" then folderAddress else walletAddress
                        open _ use =
                            use (whileConnected (scriptedStatus client) (acquiringReads (scriptedProvider client) payer (runtimeOf noFaults world)), payer)
                        run
                            | command == "fold" = runRegistryFoldWith open (setupFold setup){rfRequest = T.pack (requestText request)}
                            | otherwise = runRegistryRegisterWith open (setupRegister setup)
                    running <- async (runCaptured run)
                    witness <- awaitWitness client
                    scriptedEnd client
                    ended <- getMonotonicTime
                    ran <- timeout 20_000_000 (wait running)
                    returned <- getMonotonicTime
                    let label = (command, ending)
                    (code, _, err) <- maybe (expectationFailure (show label <> ": the command did not end within twenty seconds") >> fail "no end") pure ran
                    (label, witness) `shouldBe` (label, (True, True))
                    (label, returned - ended <= acquiredBound) `shouldBe` (label, True)
                    (label, code) `shouldBe` (label, ExitFailure 1)
                    forM_ ["the node could not be read", zeroLine] $ \needle -> (label, err) `shouldSatisfy` (\(_, text) -> needle `isInfixOf` text)
                    (label, last (lines err)) `shouldBe` (label, zeroLine)
    describe "the signing key, checked by name before the node is opened" $ do
        it "passes the key of the funding address, and refuses by name a missing file, an invalid one, another address and a script address" $
            withSystemTempDirectory "ckeri-key-check" $ \dir -> do
                let keyFile = dir </> "payment.skey"
                    absent = dir </> "absent.skey"
                    broken = dir </> "broken.skey"
                BL.writeFile keyFile (encode keyEnvelope)
                BS.writeFile broken "not a key"
                otherAddress <- either (fail . ("test address: " <>)) pure (decodeTestAddress otherAddressText)
                checkSigningKey keyFile keyAddress >>= (`shouldBe` Right ())
                checkSigningKey keyFile otherAddress >>= (`shouldSatisfy` leftStarting "signing-key-does-not-match-address")
                checkSigningKey absent keyAddress >>= (`shouldSatisfy` leftStarting "signing-key-file-missing")
                checkSigningKey broken keyAddress >>= (`shouldSatisfy` leftStarting "signing-key-file-invalid")
        it "ends each startup failure of the key, in register and in fold, in its named outcome and says nothing was submitted and nothing was spent, through the opener the commands ship" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                let keyFile = setupDirectory setup </> "payment.skey"
                    broken = setupDirectory setup </> "broken.skey"
                BL.writeFile keyFile (encode keyEnvelope)
                BS.writeFile broken "not a key"
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                let register file address = (setupRegister setup){rgSigningKeyFile = Just file, rgFundingAddress = address}
                    fold' file address = (setupFold setup){rfSigningKeyFile = Just file, rfFundingAddress = address, rfRequest = T.pack (requestText request)}
                    cases =
                        [ ("signing-key-file-missing", setupDirectory setup </> "absent.skey", otherAddressText)
                        , ("signing-key-file-invalid", broken, otherAddressText)
                        , ("signing-key-does-not-match-address", keyFile, otherAddressText)
                        ]
                forM_ cases $ \(named, file, address) -> do
                    (codeR, _, errR) <- runCaptured (runRegistryRegisterWith openRegistryNode (register file address))
                    (codeF, _, errF) <- runCaptured (runRegistryFoldWith openRegistryNode (fold' file address))
                    forM_ [("register", codeR, errR), ("fold", codeF, errF)] $ \(command, code, err) -> do
                        (command :: String, named :: String, code) `shouldBe` (command, named, ExitFailure 1)
                        (command, named, err) `shouldSatisfy` (\(_, _, text) -> named `isInfixOf` text)
                        (command, named, err) `shouldSatisfy` (\(_, _, text) -> "nothing was submitted; nothing was spent" `isInfixOf` text)
        it "ends a key that changes between the named check and the live context's own read in the same outcome, in register and in fold" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (request, _) <- bookDirectly world export
            withSetup world $ \setup -> do
                let keyFile = setupDirectory setup </> "payment.skey"
                    anotherKey = object ["type" .= ("PaymentSigningKeyShelley_ed25519" :: String), "description" .= ("" :: String), "cborHex" .= ("5820" <> concat (replicate 32 "11") :: String)]
                BS.writeFile (rfSnapshot (setupFold setup)) (encodeSnapshot (Snapshot "x" [] []))
                let register = (setupRegister setup){rgSigningKeyFile = Just keyFile, rgFundingAddress = keyAddressText}
                    fold' = (setupFold setup){rfSigningKeyFile = Just keyFile, rfFundingAddress = keyAddressText, rfRequest = T.pack (requestText request)}
                    scenarios =
                        [ ("removed", removeFile keyFile)
                        , ("replaced by what is not a key", BS.writeFile keyFile "not a key")
                        , ("replaced by the key of another address", BL.writeFile keyFile (encode anotherKey))
                        ]
                forM_ scenarios $ \(label, change) -> do
                    BL.writeFile keyFile (encode keyEnvelope)
                    (codeR, _, errR) <- runCaptured (runRegistryRegisterWith (openRegistryNodeBetween change) register)
                    BL.writeFile keyFile (encode keyEnvelope)
                    (codeF, _, errF) <- runCaptured (runRegistryFoldWith (openRegistryNodeBetween change) fold')
                    forM_ [("register", codeR, errR), ("fold", codeF, errF)] $ \(command, code, err) -> do
                        (label :: String, command :: String, code) `shouldBe` (label, command, ExitFailure 1)
                        (label, command, err) `shouldSatisfy` (\(_, _, text) -> "signing-key-" `isInfixOf` text)
                        (label, command, err) `shouldSatisfy` (\(_, _, text) -> "nothing was submitted; nothing was spent" `isInfixOf` text)
        it "never reports what fails once the operation has begun as a startup refusal" $ do
            world <- newWorld 1_000
            withSetup world $ \setup -> do
                let keyFile = setupDirectory setup </> "payment.skey"
                BL.writeFile keyFile (encode keyEnvelope)
                -- the live context is opened for real, against a socket that is listening and says nothing, so
                -- the node client neither fails nor ends: the operation fails as soon as it is handed the runtime
                withSystemTempDirectory "ckn" $ \short -> do
                    let socketPath = short <> "/n.socket"
                        access = NodeAccess 42 socketPath keyAddressText (KeyFile keyFile) 5 Nothing
                    withListeningSocket socketPath $ do
                        reached <- newIORef False
                        ((outcome, _), err) <-
                            capturing stderr . capturing stdout $
                                onOwnThread (openRegistryNodeBetween (pure ()) access (\_ -> writeIORef reached True >> ioError (userError "after the start")))
                        began <- readIORef reached
                        began `shouldBe` True
                        either show (const "an outcome") outcome `shouldBe` show (userError "after the start")
                        err `shouldSatisfy` (not . ("nothing was spent" `isInfixOf`))
                        err `shouldSatisfy` (not . ("signing-key-" `isInfixOf`))
  where
    writeSeen ref text = modifyIORef' ref (const text)

{- | What the pinned client raises for an instant past the node's forecast: a plain error
call from the interpreter's refusal (N2C/Provider.hs, queryWallclockToSlot).
-}
pinRefusal :: IO a
pinRefusal =
    throwIO
        ( ErrorCall
            "posixMsToSlot: PastHorizon {pastHorizonCallStack = [], pastHorizonExpression = Some (EDict []), pastHorizonSummary = []}"
        )

-- | An opener over a world whose runtime is changed first (a node that fails to be read, say).
openerChanged :: (RegistryRuntime -> IO RegistryRuntime) -> World -> Addr -> RegistryOpener
openerChanged change world payer access use = do
    (opener, _) <- openerOver noFaults world payer
    opener access $ \(runtime, paying) -> do
        changed <- change runtime
        use (changed, paying)

-- | A payment signing key in the shape the key files have: a throwaway used only by tests.
keyEnvelope :: Value
keyEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex" .= ("582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" :: String)
        ]

-- | The testnet address of that key.
keyAddress :: Addr
keyAddress =
    case convertFromBase Base16 (B8.pack "83c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde") :: Either String BS.ByteString of
        Left failure -> error ("test key: " <> failure)
        Right bytes -> case rawDeserialiseSignKeyDSIGN @DSIGN bytes of
            Nothing -> error "test key: not an Ed25519 signing key"
            Just signingKey ->
                Addr Testnet (KeyHashObj (hashKey (VKey (deriveVerKeyDSIGN signingKey) :: VKey Payment))) StakeRefNull

-- | A testnet address of some other key.
otherAddressText :: T.Text
otherAddressText = "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"

decodeTestAddress :: T.Text -> Either String Addr
decodeTestAddress = decodePaymentAddress

leftStarting :: String -> Either String () -> Bool
leftStarting prefix = either (prefix `isPrefixOf`) (const False)

-- | The testnet address of that key, as the commands take it.
keyAddressText :: T.Text
keyAddressText =
    either (error . ("test address: " <>)) id $ do
        hrp <- Bi.first show (Bech32.humanReadablePartFromText "addr_test")
        Bi.first show (Bech32.encode hrp (Bech32.dataPartFromBytes (serialiseAddr keyAddress)))

{- | Run an action on a thread of its own and give its outcome: what the node client's failure
leaves pending is delivered to that thread, never to the example that is waiting.
-}
onOwnThread :: IO a -> IO (Either SomeException a)
onOwnThread action = do
    done <- newEmptyMVar
    _ <- forkFinally action (putMVar done)
    takeMVar done

-- | A unix socket that is listening and never answers: a node client that connects to it waits.
withListeningSocket :: FilePath -> IO a -> IO a
withListeningSocket path =
    bracket
        ( do
            listener <- Net.socket Net.AF_UNIX Net.Stream Net.defaultProtocol
            Net.bind listener (Net.SockAddrUnix path)
            Net.listen listener 1
            pure listener
        )
        Net.close
        . const

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

-- | An opener over a world whose node client is the given thread: every call returns once it has ended.
openerClient :: StandIn -> Faults -> World -> Addr -> RegistryOpener
openerClient client faults world payer access use = do
    (opener, _) <- openerOver faults world payer
    opener access $ \(runtime, paying) -> use (whileConnected (standInStatus client) runtime, paying)

{- | An opener over a world whose node client ends at the nth call of the run, before the call
or after the node did what it asked, with the kinds of the calls made. Zero is no end at all.
-}
openerEnding :: Int -> Bool -> World -> Addr -> IO (RegistryOpener, IO [Call])
openerEnding nth late world payer = do
    made <- newIORef (pure [])
    pure
        ( \access use -> do
            client <- newStandIn
            (opener, _) <- openerOver noFaults world payer
            opener access $ \(runtime, paying) -> do
                (ending, callsMade) <- endingAt client nth late runtime
                writeIORef made callsMade
                use (whileConnected (standInStatus client) ending, paying)
        , join (readIORef made)
        )

{- | Run a command whose final report cannot be written, and interrupt it as the report starts:
what became of it, or nothing if it was not over within five seconds.
-}
interruptedWhileReporting :: ((String -> IO ()) -> IO ()) -> IO (Maybe (Either SomeException ()))
interruptedWhileReporting command = do
    ((outcome, _), _) <- capturing stderr . capturing stdout $ do
        entered <- newEmptyMVar
        done <- newEmptyMVar
        let stalled _ = putMVar entered () >> (newEmptyMVar :: IO (MVar ())) >>= takeMVar
        helper <- forkFinally (command stalled) (putMVar done)
        takeMVar entered
        -- delivered from a thread of its own: a thread that cannot be interrupted would hold this one too
        _ <- forkIO (throwTo helper UserInterrupt)
        timeout 5_000_000 (takeMVar done)
    pure outcome

timed :: IO a -> IO (Double, a)
timed action = do
    started <- getMonotonicTime
    result <- timeout 10_000_000 action
    ended <- getMonotonicTime
    maybe (expectationFailure "no return within ten seconds" >> fail "no return") (\r -> pure (ended - started, r)) result

-- | A node behind a unix socket.
data Node = Node
    { nodeConnected :: IO ()
    -- ^ wait until a client's connection has been taken, and fail the example if none is within five seconds
    , nodeHangUp :: IO ()
    -- ^ close the connection that was taken, and the socket
    }

{- | A node that takes the connection of one client and keeps it, saying nothing, until it is
told to hang up.
-}
withNodeThatHangsUp :: FilePath -> (Node -> IO a) -> IO a
withNodeThatHangsUp path action =
    bracket
        ( do
            listener <- Net.socket Net.AF_UNIX Net.Stream Net.defaultProtocol
            Net.bind listener (Net.SockAddrUnix path)
            Net.listen listener 1
            taken <- newEmptyMVar
            acceptor <- forkIO (try @SomeException (Net.accept listener) >>= either (const (pure ())) (putMVar taken . fst))
            pure (listener, taken, acceptor)
        )
        (\(listener, _, acceptor) -> killThread acceptor >> Net.close listener)
        ( \(listener, taken, _) ->
            action
                Node
                    { nodeConnected = timeout 5_000_000 (readMVar taken) >>= maybe (expectationFailure "no client connected to the node within five seconds") (const (pure ()))
                    , nodeHangUp = do
                        connection <- tryTakeMVar taken
                        mapM_ Net.close connection
                        Net.close listener
                    }
        )
