{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryTransactionDumpSpec
Description : the transactions the registry builders make from fixed inputs, written down so that two builds of the library can be compared

A registry deployed, three bookings made, two of them folded and the third returned, all with the
library's own builders over an in-memory chain, with fixed terms, keys, parameters and clock. Every
accepted transaction is written, in order, as its identifier, fee, size, number of inputs and outputs and
the lovelace its outputs hold, to the file the environment variable KERI_TX_DUMP names when it is set. The
same inputs under two revisions of a dependency must give the same lines: a difference is a change of the
transactions the dependency made. Without the variable the example only checks that transactions were made.
-}
module Cardano.KERI.Deployment.RegistryTransactionDumpSpec (spec) where

import Cardano.KERI.AID.Application (RegistrationData (..))
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (noFaults)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistryReturn
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, inputsTxBodyL, outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((^.))
import System.Environment (lookupEnv)
import Test.Hspec

inputOf :: World -> TxIn -> Snapshot -> FoldInput
inputOf world request snapshot =
    FoldInput
        { foldBlueprint = worldBlueprint world
        , foldIdentity = deployedIdentity (worldDeployed world)
        , foldRecord = deployedRecord (worldDeployed world)
        , foldRequestOutput = request
        , foldSnapshot = snapshot
        , foldPayerAddress = folderAddress
        }

line :: Int -> ConwayTx -> String
line index tx =
    unwords
        [ show index
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

spec :: Spec
spec = describe "#558 the transactions the registry builders make from fixed inputs" $
    it "are written down in order for comparison between two revisions of a dependency" $ do
        world <- newWorld 1_000
        single <- loadExport "kli-export-single.cesr"
        multi <- loadExport "kli-export-2-of-5.cesr"
        (first', _) <- bookDirectly world single
        (second', _) <- bookDirectly world multi
        (third, thirdRecord) <- bookDirectly world single
        let runtime = runtimeOf noFaults world
            silent = const (pure ())
        foldedFirst <- foldBookedRequest runtime silent (inputOf world first' (Snapshot "the empty registry" [] []))
        done <- either (fail . show) pure foldedFirst
        void . either (fail . show) pure =<< foldBookedRequest runtime silent (inputOf world second' (doneSnapshot done))
        let slotMs = worldSlotMs world
        setTip world ((requestProcessDeadline thirdRecord - originMs + slotMs - 1) `div` slotMs)
        void . either (fail . show) pure
            =<< returnBookedRequest
                runtime
                silent
                ReturnInput
                    { returnBlueprint = worldBlueprint world
                    , returnIdentity = deployedIdentity (worldDeployed world)
                    , returnRecord = deployedRecord (worldDeployed world)
                    , returnRequestOutput = third
                    , returnPayerAddress = folderAddress
                    }
        transactions <- accepted world
        transactions `shouldSatisfy` ((> 12) . length)
        lookupEnv "KERI_TX_DUMP" >>= \target ->
            mapM_ (\path -> writeFile path (unlines (zipWith line [0 ..] transactions))) target
