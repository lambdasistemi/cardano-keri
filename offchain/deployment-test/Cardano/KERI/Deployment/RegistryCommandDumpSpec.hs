{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryCommandDumpSpec
Description : the transactions the installed registry commands make from fixed inputs, written down so that two builds can be compared

The commands of the installed command line, each run whole over an in-memory chain with fixed terms, keys,
parameters, tip and clock: the deployment, three registrations, two folds on supplied state and the return of
the third request. The command makes its own choices (the payer's outputs, the window, the references); only
the opener it reaches its node through is the test's. Every accepted transaction is written, in order, with the
command that made it, to the file the variable KERI_COMMAND_DUMP names when it is set. The same inputs under
two revisions of a dependency must give the same lines: a difference is what the dependency changed in what a
command built. Without the variable the example only checks that every command succeeded.
-}
module Cardano.KERI.Deployment.RegistryCommandDumpSpec (spec) where

import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryBookingCommandSpec (Setup (..), openerOver, runCaptured, withSetup)
import Cardano.KERI.Deployment.RegistryCommand (runRegistryDeployWith)
import Cardano.KERI.Deployment.RegistryCommandSpec (settingsIn)
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), chainRuntime, newChain, noFaults, walletAddress, walletOutputs)
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), encodeSnapshot)
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, inputsTxBodyL, outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM, forM_, void)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.IORef (newIORef, readIORef)
import Data.List (stripPrefix)
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((^.))
import Paths_cardano_keri (getDataFileName)
import System.Directory (withCurrentDirectory)
import System.Environment (getEnv, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

line :: String -> Int -> ConwayTx -> String
line label index tx =
    unwords
        [ show index
        , label
        , T.unpack (renderTransactionId (transactionId tx))
        , "fee=" <> show fee
        , "size=" <> show (BS.length (serialize' (eraProtVerHigh @ConwayEra) tx))
        , "inputs=" <> show (Set.size (tx ^. bodyTxL . inputsTxBodyL))
        , "outputs=" <> show (length outputs)
        , "lovelace-out=" <> show (sum [c | out <- outputs, let Coin c = out ^. coinTxOutL])
        ]
  where
    Coin fee = tx ^. bodyTxL . feeTxBodyL
    outputs = toList (tx ^. bodyTxL . outputsTxBodyL)

-- | Run a command whole; its exit must be a success. What it printed is given back.
succeeds :: String -> IO () -> IO String
succeeds label action = do
    (code, out, err) <- runCaptured action
    if code == ExitSuccess then pure out else fail (label <> " exited with " <> show code <> ": " <> err)

-- | The value of the first line of a command's output that begins with the key.
printed :: String -> String -> IO String
printed key out = case mapMaybe (stripPrefix (key <> ": ")) (lines out) of
    value : _ -> pure value
    [] -> fail ("the command did not print " <> key)

spec :: Spec
spec = describe "#558 the transactions the installed registry commands make from fixed inputs" $
    it "are written down in order for comparison between two builds of a dependency" $ do
        blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
        -- the deployment, over a chain of its own
        deployLines <- withSystemTempDirectory "registry-command-dump" $ \directory -> do
            chainRef <- newIORef (newChain walletOutputs)
            let opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
            _ <- succeeds "deploy" (runRegistryDeployWith opener (settingsIn blueprintPath directory))
            chain <- readIORef chainRef
            pure (zipWith (line "deploy") [0 ..] (reverse (chainAccepted chain)))
        -- the registrations, the folds on supplied state and the return, over a registry already deployed
        world <- newWorld 1_000
        commandLines <- withSetup world $ \setup -> do
            single <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
            multi <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
            (registerOpener, _) <- openerOver noFaults world walletAddress
            booked <- forM [single, multi, single] $ \export -> do
                out <-
                    withCurrentDirectory (setupDirectory setup) $
                        succeeds "register" (runRegistryRegisterWith registerOpener (setupRegister setup){rgKliExport = export})
                (,) <$> printed "booking-output" out <*> printed "deadline-ms" out
            let snapshot index = setupDirectory setup </> ("snapshot-" <> show (index :: Int) <> ".json")
            BS.writeFile (snapshot 0) (encodeSnapshot (Snapshot "the empty registry" [] []))
            forM_ (zip [0 ..] (take 2 booked)) $ \(index, (request, _)) -> do
                (foldOpener, _) <- openerOver noFaults world folderAddress
                void $
                    succeeds "fold" $
                        runRegistryFoldWith
                            foldOpener
                            (setupFold setup)
                                { rfRequest = T.pack request
                                , rfSnapshot = snapshot index
                                , rfSnapshotOut = Just (snapshot (index + 1))
                                }
            -- the third request is returned once its deadline has passed
            (thirdRequest, thirdDeadline) <- case drop 2 booked of
                third : _ -> pure third
                [] -> fail "the third booking was not made"
            let slotMs = worldSlotMs world
            setTip world ((read thirdDeadline - originMs + slotMs - 1) `div` slotMs)
            (returnOpener, _) <- openerOver noFaults world folderAddress
            let fold = setupFold setup
            _ <-
                succeeds "return" $
                    runRegistryReturnWith
                        returnOpener
                        RegistryReturnSettings
                            { rnNetworkMagic = rfNetworkMagic fold
                            , rnBlueprint = rfBlueprint fold
                            , rnProvider = rfProvider fold
                            , rnFundingAddress = rfFundingAddress fold
                            , rnSigningKeyFile = rfSigningKeyFile fold
                            , rnVault = rfVault fold
                            , rnPassphraseFd = rfPassphraseFd fold
                            , rnTimeoutSeconds = rfTimeoutSeconds fold
                            , rnReleaseIdentity = rfReleaseIdentity fold
                            , rnReferenceRecord = rfReferenceRecord fold
                            , rnRequest = T.pack thirdRequest
                            }
            transactions <- accepted world
            pure (zipWith (line "commands") [0 ..] transactions)
        length deployLines `shouldSatisfy` (>= 7)
        length commandLines `shouldSatisfy` (> 12)
        lookupEnv "KERI_COMMAND_DUMP" >>= \target ->
            mapM_ (\path -> writeFile path (unlines (deployLines <> commandLines))) target
