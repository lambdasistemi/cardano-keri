{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryShortDepositSpec
Description : a booking below the registry's floor is not pre-empted by the command: the node's evaluation of the application's minting purpose refuses it

The command builds the booking whatever deposit it is given and hands it to the node's
evaluation; the application validator is what refuses a deposit below the registry's floor.
Over a chain that runs no script the evaluation is scripted to refuse, which shows what the
command does with the refusal; that the validator itself refuses is shown on the devnet.
The booking that reaches the evaluation is read back from what the node was asked, not from
the code that built it.
-}
module Cardano.KERI.Deployment.RegistryShortDepositSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (RegistrationData (..))
import Cardano.KERI.Deployment.NodeSocketRuntime (RegistryOpener)
import Cardano.KERI.Deployment.Registry (registryMinimumDeposit)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryChain (Boundary (..), RegistryRuntime (..), submitBoundary)
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults, testTerms, walletAddress)
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryProvider (ProviderChoice (..))
import Cardano.KERI.Deployment.RegistryRegister
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (UnknownTxIn))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Exception (try)
import Data.ByteString qualified as BS
import Data.Either (fromLeft)
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Lens.Micro ((^.))
import Paths_cardano_keri (getDataFileName)
import System.Directory (createDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

{- | The floor of a booking: the least deposit the application's minting purpose accepts (the registry's minimum
ADA, checkpoint deposit and freeze bond), read from the terms of the world, and one lovelace below it.
-}
floorDeposit, shortDeposit :: Integer
floorDeposit = registryMinimumDeposit testTerms
shortDeposit = floorDeposit - 1

-- | What the node answers to the evaluation of a booking: the application refuses it.
refusing :: Faults
refusing =
    noFaults
        { distortEvaluation = \_ -> Map.map (const (Left (UnknownTxIn (TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xee))))) (TxIx 0)))))
        }

-- | A runtime that keeps what the node was asked to evaluate.
watching :: RegistryRuntime -> IO (RegistryRuntime, IO [ConwayTx])
watching runtime = do
    asked <- newIORef []
    let transactions = rtTransactions runtime
    pure
        ( runtime{rtTransactions = transactions{trEvaluate = \tx -> modifyIORef' asked (tx :) >> trEvaluate transactions tx}}
        , reverse <$> readIORef asked
        )

booked :: RegistryRuntime -> RegisterRequest -> IO (Either RegisterFailure Registered)
booked runtime = registerRegistration runtime (const (pure ()))

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

spec :: Spec
spec = describe "#351 a booking with a deposit below the registry's floor" $ around_ withinOneMinute $ do
    describe "the library" $ do
        it "builds the booking with the short deposit and hands it to the node's evaluation, which refuses it: nothing is submitted, and the refusal is the node evaluation's" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (runtime, askedOf) <- watching (runtimeOf refusing world)
            sent0 <- submissionsMade world
            outcome <- booked runtime (registerRequestOf world export){registerDeposit = Just shortDeposit}
            case outcome of
                Left (RegisterTransaction failure) -> submitBoundary failure `shouldBe` NodeEvaluation
                other -> expectationFailure ("not the node evaluation's refusal: " <> show other)
            submissionsMade world >>= (`shouldBe` sent0)
            -- what the node was asked is the booking, with the short deposit and the lovelace that follows it
            asked <- askedOf
            length asked `shouldBe` 1
            case asked of
                [evaluated] -> case toList (evaluated ^. bodyTxL . outputsTxBodyL) of
                    requestOut : _ -> do
                        fmap requestDeposit (registrationOfOutput requestOut) `shouldBe` Just shortDeposit
                        requestOut ^. coinTxOutL `shouldBe` Coin (shortDeposit + 1_000_000 + 500_000)
                    [] -> expectationFailure "the booking has no output"
                other -> expectationFailure ("not one evaluation: " <> show (length other))
        it "is the same booking at the floor: asked of the node, and accepted when the node accepts it" $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            (runtime, askedOf) <- watching (runtimeOf noFaults world)
            outcome <- booked runtime (registerRequestOf world export){registerDeposit = Just floorDeposit}
            registered <- either (fail . show) pure outcome
            requestDeposit (registeredRecord registered) `shouldBe` floorDeposit
            askedOf >>= (`shouldBe` 1) . length
    describe "the command" $ do
        let run faults deposit = do
                world <- newWorld 1_000
                withSystemTempDirectory "registry-short-deposit" $ \scratch -> do
                    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
                    export <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
                    let work = scratch </> "work"
                        identityFile = scratch </> "release-identity.json"
                        recordFile = scratch </> "reference-outputs.json"
                    createDirectory work
                    written <- writeDeploymentFiles identityFile recordFile (deployedIdentity (worldDeployed world)) (deployedRecord (worldDeployed world))
                    either (fail . show) pure written
                    let settings =
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
                                , rgDeposit = Just deposit
                                }
                        opener :: RegistryOpener
                        opener _ use = use (runtimeOf faults world, walletAddress)
                    sent0 <- submissionsMade world
                    ((outcome, out), err) <-
                        capturing stderr (capturing stdout (withCurrentDirectory work (try @ExitCode (runRegistryRegisterWith opener settings))))
                    sentAfter <- submissionsMade world
                    pure (fromLeft ExitSuccess outcome, out, err, sentAfter - sent0)
        it "says the node's evaluation refused the booking, naming the application's minting purpose, with the boundary, and that nothing was submitted or spent" $ do
            (code, out, err, sent) <- run refusing shortDeposit
            code `shouldBe` ExitFailure 1
            sent `shouldBe` 0
            err `shouldSatisfy` ("the node's evaluation refused the booking: " `isInfixOf`)
            err `shouldSatisfy` ("the application's minting purpose" `isInfixOf`)
            err `shouldSatisfy` (zeroLine `isInfixOf`)
            err `shouldSatisfy` ("refused by the node's evaluation of the transaction" `isInfixOf`)
            -- not the command's own pre-emption, and not the ledger's refusal
            err `shouldSatisfy` (not . ("deposit-below-floor" `isInfixOf`))
            err `shouldSatisfy` (not . ("refused by the command" `isInfixOf`))
            err `shouldSatisfy` (not . ("refused by the ledger" `isInfixOf`))
            -- the booking was built: the window was announced before the node refused it
            out `shouldSatisfy` ("validity-interval-slots: " `isInfixOf`)
            out `shouldSatisfy` (not . ("booking-transaction" `isInfixOf`))
        it "books the same booking at the floor: the control" $ do
            (code, out, _, sent) <- run noFaults floorDeposit
            code `shouldBe` ExitSuccess
            sent `shouldBe` 1
            out `shouldSatisfy` ("booking-transaction: " `isInfixOf`)
