{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryKoiosRecordedSpec
Description : @ckeri registry deploy@ on Koios leaves the wallet's reference-script outputs unspent

The wallet is the one recorded from preprod: fifteen outputs, six of which carry
a reference script. The command runs whole on the Koios instance with the
recorded reads, and the first transaction it hands over is read: it spends
outputs of the wallet, and none of the six. The control is a wallet of those six
with their scripts taken off, from which the command does spend.
-}
module Cardano.KERI.Deployment.RegistryKoiosRecordedSpec (spec) where

import Cardano.KERI.Deployment.KoiosReadsSpec (recordedTipStart, riggedRecorded, walletAddress)
import Cardano.KERI.Deployment.KoiosRegistryRuntime (KoiosParts (..), koiosRegistryRuntime)
import Cardano.KERI.Deployment.KoiosRuntime (KoiosReads (..))
import Cardano.KERI.Deployment.KoiosSettlement (Settlement (..))
import Cardano.KERI.Deployment.KoiosSubmission (Handoff (..), HandoffResult (..))
import Cardano.KERI.Deployment.RegistryChain (ValidityEnd (..))
import Cardano.KERI.Deployment.RegistryCommand
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryProvider
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Address (AccountAddress)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, referenceScriptTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Exception (try)
import Data.Bifunctor (second)
import Data.Either (fromLeft)
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Set qualified as Set
import Lens.Micro ((&), (.~), (^.))
import Singular.Registry.Signing (signedTx)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

type Funds = [(TxIn, TxOut ConwayEra)]

spec :: Spec
spec = describe "#546 registry deploy on Koios, over the wallet recorded from preprod" $ do
    it "spends outputs of the wallet for its first publication, and none of the six that carry a reference script" $ do
        funds <- walletFunds
        first' <- firstPublication enlarged
        let scripted = scriptedOf funds
            spent = spentBy first'
        length funds `shouldBe` 15
        Set.size scripted `shouldBe` 6
        spent `shouldSatisfy` (not . Set.null)
        spent `shouldSatisfy` (`Set.isSubsetOf` Set.fromList (map fst funds))
        Set.intersection spent scripted `shouldBe` Set.empty
    it "does spend them when their scripts are taken off and they are the largest: the check can fail" $ do
        funds <- walletFunds
        first' <- firstPublication (map (second (referenceScriptTxOutL .~ SNothing)) . enlarged)
        Set.intersection (spentBy first') (scriptedOf funds) `shouldSatisfy` (not . Set.null)
    it "asks no reward account whether it is registered, and hands over its first publication" $ do
        (_, accounts) <- deployed id
        accounts `shouldBe` []
  where
    -- the six hold more than any other output, so that the spending order prefers them: only their script keeps them unspent
    enlarged = map (\(ref, out) -> (ref, if isScripted out then out & coinTxOutL .~ Coin 400_000_000 else out))
    scriptedOf funds = Set.fromList [ref | (ref, out) <- funds, isScripted out]
    spentBy tx = Set.fromList (toList (tx ^. bodyTxL . inputsTxBodyL))

-- | The wallet as the recorded reads give it.
walletFunds :: IO Funds
walletFunds = do
    (reads', _) <- riggedRecorded (pure recordedTipStart)
    readUtxosAt reads' (snd walletAddress)

isScripted :: TxOut ConwayEra -> Bool
isScripted out = case out ^. referenceScriptTxOutL of
    SJust _ -> True
    SNothing -> False

-- | The first transaction the command hands over to the provider, over the wallet as the function gives it.
firstPublication :: (Funds -> Funds) -> IO ConwayTx
firstPublication transform = fst <$> deployed transform

-- | The same, with the reward accounts the command asked about before its first transaction.
deployed :: (Funds -> Funds) -> IO (ConwayTx, [AccountAddress])
deployed transform = do
    asked <- newIORef []
    (reads', _) <- riggedRecorded (pure recordedTipStart)
    funds <- transform <$> readUtxosAt reads' (snd walletAddress)
    ran <-
        deployOver
            reads'
                { readUtxosAt = \_ -> pure funds
                , readRewardRegistered = \account -> modifyIORef' asked (<> [account]) >> pure False
                }
    case ranHanded ran of
        first' : _ -> (,) first' <$> readIORef asked
        [] -> fail "the command handed nothing over"

-- | What a run of the command left: its exit, what it printed and what it handed to the provider.
data Ran = Ran
    { ranCode :: ExitCode
    , ranOut :: String
    , ranErr :: String
    , ranHanded :: [ConwayTx]
    }

-- | The command run whole on the Koios instance over these reads, every handoff refused.
deployOver :: KoiosReads -> IO Ran
deployOver reads' = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    let payer = snd walletAddress
    handed <- newIORef []
    let koiosOpener _ use = do
            runtime <-
                koiosRegistryRuntime
                    KoiosParts
                        { partReads = reads'
                        , partSign = pure . Right
                        , partHandoff = \signed -> do
                            modifyIORef' handed (<> [signedTx signed])
                            pure (Handoff (transactionId (signedTx signed)) 1 (Refused "stop here"))
                        , partSettle = \_ -> pure (Right Settled)
                        , partReport = \_ -> pure ()
                        , partClock = pure recordedTipStart
                        , partWindow = pure EndNotSet
                        }
            use (runtime, payer)
        openers = Openers{openersNode = \_ _ -> fail "the node was reached", openersKoios = koiosOpener}
    withSystemTempDirectory "registry-koios-recorded" $ \directory -> do
        ((outcome, out), err) <-
            capturing stderr $
                capturing stdout $
                    try @ExitCode $
                        runRegistryDeployOver
                            openers
                            RegistryDeploySettings
                                { rdNetworkMagic = 1
                                , rdBlueprint = blueprint
                                , rdProvider = ProviderChoice Nothing (Just "http://recorded.invalid/api/v1") Nothing Nothing
                                , rdFundingAddress = "addr_test1unused"
                                , rdSigningKeyFile = Just "no-key.skey"
                                , rdVault = Nothing
                                , rdPassphraseFd = Nothing
                                , rdTimeoutSeconds = 5
                                , rdReferenceLovelace = Nothing
                                , rdReleaseIdentityOut = directory </> "release-identity.json"
                                , rdReferenceRecordOut = directory </> "reference-outputs.json"
                                , rdRegistrationCost = 1_000_000
                                , rdMinimumTip = 500_000
                                , rdProcessTime = 90_000
                                , rdBookingWidth = 5_000
                                , rdDeposit = 1_000_000_000
                                , rdFreezeBond = 5_000_000
                                , rdPremium = 2_000_000
                                , rdMinimumAda = 2_000_000
                                , rdTerminationCarrier = 1_500_000
                                }
        txs <- readIORef handed
        pure Ran{ranCode = fromLeft ExitSuccess outcome, ranOut = out, ranErr = err, ranHanded = txs}
