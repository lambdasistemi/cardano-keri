{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryOneOutputSpec
Description : a wallet that holds exactly one ada-only output runs every registry command: the output funds the transaction and is its collateral

A freshly funded wallet holds one output. Public Singular funds a transaction and collateralises it from one
ada-only output of the wallet; the registry commands must too. Each case runs a command over the in-memory chain
with a payer whose wallet is one output of five thousand ada and nothing else, and reads the transaction that
landed: it spends that output, and that output is its only collateral input.
-}
module Cardano.KERI.Deployment.RegistryOneOutputSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (RegistrationData (..))
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryDeploy (DeployRequest (..), Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), deployOn, loadTestBlueprint, newChain, noFaults, testTerms)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistryReturn
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx)
import Cardano.Ledger.Api.Tx.Body (collateralInputsTxBodyL, inputsTxBodyL, outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Credential (Credential (KeyHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.IORef (newIORef, readIORef)
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Lens.Micro ((^.))
import Test.Hspec

-- | A payer whose wallet is one output.
lonely :: Addr
lonely = Addr Testnet (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 0x44))))) StakeRefNull

-- | The transaction spends the output and the output is its one collateral input.
fundsAndCollateralises :: TxIn -> ConwayTx -> Expectation
fundsAndCollateralises funding tx = do
    (funding `Set.member` (tx ^. bodyTxL . inputsTxBodyL)) `shouldBe` True
    (tx ^. bodyTxL . collateralInputsTxBodyL) `shouldBe` Set.singleton funding

spec :: Spec
spec = describe "#558 a wallet of exactly one ada-only output runs every registry command" $ do
    it "folds a booked request: the one output funds the fold and is its collateral" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        (request, _) <- bookDirectly world export
        funding <- plantWallet world lonely 5_000_000_000
        base <- length <$> accepted world
        outcome <-
            foldBookedRequest
                (runtimeOf noFaults world)
                (const (pure ()))
                FoldInput
                    { foldBlueprint = worldBlueprint world
                    , foldIdentity = deployedIdentity (worldDeployed world)
                    , foldRecord = deployedRecord (worldDeployed world)
                    , foldRequestOutput = request
                    , foldSnapshot = Snapshot "the empty registry" [] []
                    , foldPayerAddress = lonely
                    }
        either (fail . show) (const (pure ())) outcome
        transactions <- accepted world
        length transactions `shouldBe` base + 1
        fundsAndCollateralises funding (last transactions)
    it "returns a booked request after its deadline: the one output funds the return and is its collateral" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        (request, record) <- bookDirectly world export
        funding <- plantWallet world lonely 5_000_000_000
        setTip world ((requestProcessDeadline record - originMs + worldSlotMs world - 1) `div` worldSlotMs world)
        base <- length <$> accepted world
        outcome <-
            returnBookedRequest
                (runtimeOf noFaults world)
                (const (pure ()))
                ReturnInput
                    { returnBlueprint = worldBlueprint world
                    , returnIdentity = deployedIdentity (worldDeployed world)
                    , returnRecord = deployedRecord (worldDeployed world)
                    , returnRequestOutput = request
                    , returnPayerAddress = lonely
                    }
        either (fail . show) (const (pure ())) outcome
        transactions <- accepted world
        length transactions `shouldBe` base + 1
        fundsAndCollateralises funding (last transactions)
    it "books a registration: the premint and the booking are each funded and collateralised by one output of the wallet" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        funding <- plantWallet world lonely 5_000_000_000
        base <- length <$> accepted world
        _ <- bookFrom world lonely export
        transactions <- accepted world
        length transactions `shouldBe` base + 2
        (premint, booking) <- case drop base transactions of
            [a, b] -> pure (a, b)
            other -> fail ("expected two transactions, found " <> show (length other))
        fundsAndCollateralises funding premint
        -- the booking is funded by what the premint left of the wallet, besides the proof output it spends
        Set.size (booking ^. bodyTxL . collateralInputsTxBodyL) `shouldBe` 1
        (booking ^. bodyTxL . collateralInputsTxBodyL) `shouldSatisfy` (`Set.isSubsetOf` (booking ^. bodyTxL . inputsTxBodyL))
    it "deploys a registry: every transaction of the deployment lands from a wallet of one output" $ do
        blueprint <- loadTestBlueprint
        let seedRef = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xc8))))) (TxIx 0)
        chainRef <- newIORef (newChain [(seedRef, mkBasicTxOut lonely (inject (Coin 5_000_000_000)))])
        outcome <-
            deployOn
                noFaults
                chainRef
                DeployRequest
                    { requestTerms = testTerms
                    , requestBlueprint = blueprint
                    , requestPayer = lonely
                    , requestReferenceLovelace = Nothing
                    }
        deployed <- either (fail . show) pure outcome
        length (deployedLanded deployed) `shouldBe` 7
        chain <- readIORef chainRef
        let landed = reverse (chainAccepted chain)
        forM_ landed $ \tx ->
            Set.size (tx ^. bodyTxL . collateralInputsTxBodyL) `shouldSatisfy` (<= 1)
        -- the first publication made the seed, after the template and before the change, and the genesis spent it
        (first, genesis) <- case (landed, reverse landed) of
            (a : _, z : _) -> pure (a, z)
            _ -> fail "nothing landed"
        let created = toList (first ^. bodyTxL . outputsTxBodyL)
        length created `shouldBe` 3
        fmap (\out -> let Coin c = out ^. coinTxOutL in c) (take 1 (drop 1 created)) `shouldBe` [10_000_000]
        (TxIn (txIdTx first) (TxIx 1) `Set.member` (genesis ^. bodyTxL . inputsTxBodyL)) `shouldBe` True
