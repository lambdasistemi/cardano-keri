{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosReadsSpec
Description : the Koios reads give a whole answer in ledger types, or one named failure

The reads run through Singular's Koios client over its recorded transport. The
answers are written by hand from the documented answer shapes of the service,
under @deployment-test/fixtures/koios@; a request that no fixture answers is
"not recorded". Every expected value is spelled out here or taken from the
ledger and the node's recorded slot starts, never read back from the code under
test.
-}
module Cardano.KERI.Deployment.KoiosReadsSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.KoiosRuntime (
    KoiosFailure (..),
    KoiosReads (..),
    evaluateLocally,
    koiosReads,
 )
import Cardano.KERI.Deployment.RegistryBookingChain (
    World (..),
    loadExport,
    newWorld,
    registerRequestOf,
    runtimeOf,
 )
import Cardano.KERI.Deployment.RegistryChain (
    Observation (..),
    Refusal (..),
    RegistryRuntime (..),
    bookingWindow,
    foldWindow,
 )
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), noFaults)
import Cardano.KERI.Deployment.RegistryRegister (registerRegistration)
import Cardano.KERI.Deployment.RegistryTransactions (ValidityPlan (..))
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.Ledger.Address (Addr (..))

import Cardano.Ledger.Alonzo.Plutus.Evaluate (evalTxExUnits)
import Cardano.Ledger.Api.PParams (
    ppCoinsPerUTxOByteL,
    ppCollateralPercentageL,
    ppMaxCollateralInputsL,
    ppMaxTxExUnitsL,
    ppMinPoolCostL,
    ppTxFeeFixedL,
    ppTxFeePerByteL,
 )
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL, mkBasicTxBody)
import Cardano.Ledger.Api.Tx.Out (TxOut, datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (..), ProtVer (..), TxIx (..), natVersion)
import Cardano.Ledger.Binary (decodeFull')
import Cardano.Ledger.Coin (Coin (..), CoinPerByte (..), compactCoinOrError)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppMaxTxSizeL, ppProtocolVersionL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.Data (Datum (..), makeBinaryData)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult, SlotNo (..))
import Cardano.Slotting.EpochInfo (fixedEpochInfo)
import Cardano.Slotting.Slot (EpochSize (..))
import Cardano.Slotting.Time (SystemStart (..), mkSlotLength)
import Control.Exception (try)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import Data.Word (Word8)
import Lens.Micro ((.~), (^.))
import Paths_cardano_keri (getDataFileName)
import Singular.Provider.Koios.Client (
    Answer (..),
    ClientConfig (..),
    ClientFailure (..),
    FailureReason (..),
    Koios (..),
    PageRefusal (..),
    RawRequest (..),
    Transport (..),
    defaultClientConfig,
    rawRequest,
 )
import Singular.Provider.Koios.Recorded (
    Fixture (..),
    FixtureSet (..),
    bodySha256,
    fixtureRequestOf,
    recordedTransport,
 )
import Singular.Provider.Koios.Wire (
    Call (..),
    Request (..),
    addressUtxosRequest,
    cliProtocolParamsRequest,
    tipRequest,
    txInfoRequest,
    utxoInfoRequest,
 )
import Singular.Registry.LocalEvaluation (EvaluationFailure (..))
import Singular.Registry.NetworkTime (
    NetworkTime,
    NetworkTimeFailure (..),
    validateNetworkTime,
 )
import Singular.Registry.TimeSource (TimeSource (..), loadPinnedSource)
import Test.Hspec

spec :: Spec
spec = describe "the Koios reads of a registry runtime" $ do
    outputsAtAddressSpec
    outputsUnderReferencesSpec
    protocolParametersSpec
    observationSpec
    evaluationSpec

-- ---------------------------------------------------------------------
-- The outputs at an address
-- ---------------------------------------------------------------------

outputsAtAddressSpec :: Spec
outputsAtAddressSpec = describe "the outputs at an address" $ do
    it "are all of them, converted to ledger outputs: value, token, inline datum" $ do
        (reads', _) <- rigged [pagedFile (addressUtxosRequest [addressA]) "0-1/2" "address-utxos-two.json"]
        found <- readUtxosAt reads' addressA
        found `shouldBe` [(reference 0x11 0, plain 5_000_000), (reference 0x11 1, tokened)]
    it "are the rows of every page, not those of the first: two pages of two rows state three in all" $ do
        (reads', calls) <-
            riggedPaged
                2
                [ pagedFileAt 0 2 (addressUtxosRequest [addressA]) "0-1/3" "address-utxos-two.json"
                , pagedFileAt 2 2 (addressUtxosRequest [addressA]) "2-2/3" "address-utxos-page-2.json"
                ]
        found <- readUtxosAt reads' addressA
        found
            `shouldBe` [ (reference 0x11 0, plain 5_000_000)
                       , (reference 0x11 1, tokened)
                       , (reference 0x22 0, plain 4_000_000)
                       ]
        readIORef calls >>= (`shouldBe` 2)
    it "are an empty answer, not a failure, for an address that holds nothing" $ do
        (reads', _) <- rigged [pagedFile (addressUtxosRequest [addressA]) "*/0" "empty-list.json"]
        readUtxosAt reads' addressA >>= (`shouldBe` [])
    it "are refused when the page says more exist than arrived, with Singular's class" $ do
        (reads', _) <- rigged [pagedFile (addressUtxosRequest [addressA]) "0-0/2" "address-utxos-incomplete.json"]
        outcome <- try @KoiosFailure (readUtxosAt reads' addressA)
        outcome `shouldBe` Left (KoiosCallFailed (ClientFailure CallAddressUtxos 1 (IncompletePage (RowsMissing 2 1))))
    it "are refused when the body does not decode, naming the call" $ do
        (reads', _) <- rigged [pagedFile (addressUtxosRequest [addressA]) "0-0/1" "address-utxos-undecodable.json"]
        outcome <- try @KoiosFailure (readUtxosAt reads' addressA)
        shouldFailWith CallAddressUtxos isUndecodable outcome
    it "are refused as not recorded when no fixture answers the request" $ do
        (reads', _) <- rigged []
        outcome <- try @KoiosFailure (readUtxosAt reads' addressA)
        shouldFailWith CallAddressUtxos isNotRecorded outcome
    it "are refused by name when the answer holds an output at another address than the one asked" $ do
        (reads', _) <- rigged [pagedFile (addressUtxosRequest [addressA]) "0-1/2" "address-utxos-foreign.json"]
        outcome <- try @KoiosFailure (readUtxosAt reads' addressA)
        outcome `shouldBe` Left (OutputAtAnotherAddress (reference 0x11 1) (scriptAddress 0xb1))

-- ---------------------------------------------------------------------
-- The outputs under exact references
-- ---------------------------------------------------------------------

outputsUnderReferencesSpec :: Spec
outputsUnderReferencesSpec = describe "the outputs under exact references" $ do
    it "are the unspent ones only: a spent reference and an unknown one are absent from the answer" $ do
        let asked = Set.fromList [reference 0x11 0, reference 0x11 1, reference 0x22 1, reference 0x33 0, reference 0x44 0]
        (reads', _) <-
            rigged
                [ singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-mixed.json"
                , singleFile (txInfoRequest [txIdOfByte 0x11, txIdOfByte 0x22]) "tx-info-two.json"
                ]
        found <- readOutputs reads' asked
        found
            `shouldBe` Map.fromList
                [ (reference 0x11 0, plain 5_000_000)
                , (reference 0x11 1, tokened)
                , (reference 0x22 1, plain 3_000_000)
                ]
    it "ask nothing for no references" $ do
        (reads', calls) <- rigged []
        readOutputs reads' Set.empty >>= (`shouldBe` Map.empty)
        readIORef calls >>= (`shouldBe` 0)
    it "are refused when the answer names an unspent output its transaction does not have" $ do
        let asked = Set.fromList [reference 0x55 2]
        (reads', _) <-
            rigged
                [ singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-beyond.json"
                , singleFile (txInfoRequest [txIdOfByte 0x55]) "tx-info-short.json"
                ]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        outcome `shouldBe` Left (OutputMissingFromTransaction (reference 0x55 2))
    it "are refused when the spent-or-not answer does not decode, naming the call" $ do
        let asked = Set.fromList [reference 0x44 0]
        (reads', _) <- rigged [singleFile (utxoInfoRequest (Set.toList asked)) "not-a-list.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallUtxoInfo isUndecodable outcome
    it "are refused as not recorded when the producing transaction has no recording" $ do
        let asked = Set.fromList [reference 0x66 0]
        (reads', _) <- rigged [singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-orphan.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallTxInfo isNotRecorded outcome
    it "are refused as not recorded when the spent-or-not answer has no recording" $ do
        (reads', _) <- rigged []
        outcome <- try @KoiosFailure (readOutputs reads' (Set.fromList [reference 0x77 0]))
        shouldFailWith CallUtxoInfo isNotRecorded outcome
    it "are refused as incomplete when the spent-or-not answer states more rows than it holds" $ do
        let asked = Set.fromList [reference 0x11 0, reference 0x11 1]
        (reads', _) <- rigged [singleFileRange (utxoInfoRequest (Set.toList asked)) "0-0/2" "utxo-info-partial.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallUtxoInfo isIncomplete outcome
    it "are refused as incomplete when the service answers 206, whatever the range says" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <- rigged [singleFileStated (utxoInfoRequest (Set.toList asked)) 206 "0-0/*" "utxo-info-first.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallUtxoInfo isIncomplete outcome
    it "are refused as incomplete when the range stated starts after the first row" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <- rigged [singleFileRange (utxoInfoRequest (Set.toList asked)) "1-1/*" "utxo-info-first.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallUtxoInfo isIncomplete outcome
    it "are refused as incomplete when the range stated ends before the rows the answer holds" $ do
        let asked = Set.fromList [reference 0x11 0, reference 0x11 1]
        (reads', _) <- rigged [singleFileRange (utxoInfoRequest (Set.toList asked)) "0-0/*" "utxo-info-two-rows.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        shouldFailWith CallUtxoInfo isIncomplete outcome
    it "are read from an answer whose total the service does not state, which is not a partial answer" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <-
            rigged
                [ singleFileRange (utxoInfoRequest (Set.toList asked)) "0-0/*" "utxo-info-first.json"
                , singleFile (txInfoRequest [txIdOfByte 0x11]) "tx-info-two.json"
                ]
        readOutputs reads' asked >>= (`shouldBe` Map.singleton (reference 0x11 0) (plain 5_000_000))
    it "are refused by name when one reference is stated both spent and unspent" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <- rigged [singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-contradictory.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        outcome `shouldBe` Left (ContradictorySpentStatus (reference 0x11 0))
    it "are refused by name when the answer names a reference that was not asked" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <- rigged [singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-unasked.json"]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        outcome `shouldBe` Left (UnaskedReference (reference 0x22 1))
    it "are refused by name when the answer for a transaction holds an output of another transaction" $ do
        let asked = Set.fromList [reference 0x11 0]
        (reads', _) <-
            rigged
                [ singleFile (utxoInfoRequest (Set.toList asked)) "utxo-info-first.json"
                , singleFile (txInfoRequest [txIdOfByte 0x11]) "tx-info-foreign-output.json"
                ]
        outcome <- try @KoiosFailure (readOutputs reads' asked)
        outcome `shouldBe` Left (OutputOfAnotherTransaction (txIdOfByte 0x11) (reference 0x22 0))

-- ---------------------------------------------------------------------
-- The protocol parameters
-- ---------------------------------------------------------------------

protocolParametersSpec :: Spec
protocolParametersSpec = describe "the protocol parameters" $ do
    it "are the ledger's, read from the node's own JSON form as the service documents it" $ do
        (reads', _) <- rigged [singleFile cliProtocolParamsRequest "cli-protocol-params.json"]
        parameters <- readProtocolParameters reads'
        parameters ^. ppProtocolVersionL `shouldBe` ProtVer (natVersion @11) 0
        parameters ^. ppMaxTxExUnitsL `shouldBe` ExUnits 17_500_000 10_000_000_000
        parameters ^. ppMaxTxSizeL `shouldBe` 16_384
        parameters ^. ppTxFeeFixedL `shouldBe` Coin 155_381
        parameters ^. ppTxFeePerByteL `shouldBe` CoinPerByte (compactCoinOrError (Coin 44))
        parameters ^. ppCoinsPerUTxOByteL `shouldBe` CoinPerByte (compactCoinOrError (Coin 4_310))
        parameters ^. ppCollateralPercentageL `shouldBe` 150
        parameters ^. ppMaxCollateralInputsL `shouldBe` 3
        parameters ^. ppMinPoolCostL `shouldBe` Coin 170_000_000
    it "are refused when the body does not decode, naming the call" $ do
        (reads', _) <- rigged [singleBytes cliProtocolParamsRequest "{\"protocolVersion\": 11}"]
        outcome <- try @KoiosFailure (readProtocolParameters reads')
        shouldFailWith CallCliProtocolParams isUndecodable outcome
    it "are refused as not recorded when no fixture answers the request" $ do
        (reads', _) <- rigged []
        outcome <- try @KoiosFailure (readProtocolParameters reads')
        shouldFailWith CallCliProtocolParams isNotRecorded outcome

-- ---------------------------------------------------------------------
-- The observation
-- ---------------------------------------------------------------------

{- | The node's recorded slot starts (Singular's preprod package, from the
node itself) give slot 68,774,400 the start 1,724,457,600,000. One slot lasts a
second there. That slot is the first of its epoch, which is where the horizon
is anchored: the tip plus the stability window 3k/f = 129,600 slots lies in the
epoch that ends at slot 69,206,400, so the last slot the node converts is
69,206,399.
-}
tipSlot, tipStart, lastConvertible :: Integer
tipSlot = 68_774_400
tipStart = 1_724_457_600_000
lastConvertible = 69_206_399

{- | Three tips, each with the start of its slot and the last slot converted.
Slot 69,106,399 is 331,999 slots after the first, so it starts 331,999,000 ms
later; the window it forecasts reaches slot 69,235,999, which lies in the next
epoch, so its horizon is the end of that epoch, slot 69,638,399. Slot
135,453,946 starts 280,453 s before slot 135,734,399, which the node records at
1,791,417,599,000 ms, and its horizon is the last slot of the captured history,
135,734,399, where the node itself stops converting. Slot 10,000 is
in the first era, whose slots last 20 s (the node records slot 86,400 at 1,728,000 s,
86,400 slots of 20 s after slot 0): it starts 200,000 s after slot 0 and its horizon is the
last slot before epoch 5, slot 518,399. Slot 86,399 is the last of
that era and lasts 20 s, and slot 86,400, the first of the next, starts where it ends and lasts a second:
the length of a slot is its own, not that of the slot before it.
-}
tips :: [(FilePath, Integer, Integer, Integer, Integer)]
tips =
    [ ("tip.json", tipSlot, tipStart, 1_000, lastConvertible)
    , ("tip-epoch-end.json", 69_106_399, 1_724_789_599_000, 1_000, 69_638_399)
    , ("tip-latest.json", 135_453_946, 1_791_137_146_000, 1_000, 135_734_399)
    , ("tip-byron.json", 10_000, 1_654_241_600_000, 20_000, 518_399)
    , ("tip-last-first-era.json", 86_399, 1_655_769_580_000, 20_000, 518_399)
    , ("tip-first-second-era.json", 86_400, 1_655_769_600_000, 1_000, 518_399)
    ]

observationSpec :: Spec
observationSpec = describe "the observation" $ do
    forM_ tips $ \(file, slot, start, slotLength, horizon) ->
        it ("takes the tip from Koios, the slot starts and the horizon from the pinned network time: slot " <> show slot) $ do
            (reads', _) <- riggedAt (pure (start + 500)) [singleFile tipRequest file]
            observed <- readObservation reads'
            observed
                `shouldBe` Observation
                    { obsTipSlot = SlotNo (fromInteger slot)
                    , obsTipStartMs = start
                    , obsSlotLengthMs = slotLength
                    , obsClockMs = start + 500
                    , obsHorizonSlot = SlotNo (fromInteger horizon)
                    }
    it "reads the machine's clock once, whatever the clock then says" $ do
        readings <- newIORef (0 :: Integer)
        let clock = modifyIORef' readings (+ 1) >> ((tipStart +) . (* 1_000) <$> readIORef readings)
        (reads', _) <- riggedAt clock [singleFile tipRequest "tip.json"]
        observed <- readObservation reads'
        readIORef readings >>= (`shouldBe` 1)
        obsClockMs observed `shouldBe` tipStart + 1_000
    it "carries a clock beyond the horizon as it is, and the window rules refuse it by name" $ do
        let clock = tipStart + 500_000_000
            deadline = clock + 1_000_000
        (reads', _) <- riggedAt (pure clock) [singleFile tipRequest "tip.json"]
        observed <- readObservation reads'
        obsClockMs observed `shouldBe` clock
        obsHorizonSlot observed `shouldBe` SlotNo (fromInteger lastConvertible)
        foldWindow observed 5_000 deadline `shouldBe` Left (NoIntervalYet deadline clock)
        fmap upperSlot (bookingWindow observed 5_000) `shouldBe` Just (SlotNo (fromInteger tipSlot + 5))
    it "is refused when the tip's block time is not the start of its slot in the pinned network time" $ do
        (reads', _) <- riggedAt (pure tipStart) [singleFile tipRequest "tip-time-disagrees.json"]
        outcome <- try @KoiosFailure (readObservation reads')
        outcome `shouldBe` Left (TipTimeDisagrees 1_724_457_601_000 tipStart)
    it "reads slot zero as a slot of the first era, with the length of its own" $ do
        (reads', _) <- riggedAt (pure 1_654_041_600_000) [singleFile tipRequest "tip-slot-zero.json"]
        observed <- readObservation reads'
        observed
            `shouldBe` Observation
                { obsTipSlot = SlotNo 0
                , obsTipStartMs = 1_654_041_600_000
                , obsSlotLengthMs = 20_000
                , obsClockMs = 1_654_041_600_000
                , obsHorizonSlot = SlotNo 518_399
                }
    it "is refused when the tip does not decode, naming the call" $ do
        (reads', _) <- riggedAt (pure tipStart) [singleFile tipRequest "tip-undecodable.json"]
        outcome <- try @KoiosFailure (readObservation reads')
        shouldFailWith CallTip isUndecodable outcome
    it "is refused as not recorded when no fixture answers the tip" $ do
        (reads', _) <- riggedAt (pure tipStart) []
        outcome <- try @KoiosFailure (readObservation reads')
        shouldFailWith CallTip isNotRecorded outcome
    it "is built on network time that refuses bytes other than the pinned ones" $ do
        TimeSource manifest genesis eras <- preprodSource
        either Just (const Nothing) (validateNetworkTime 1 manifest genesis (BS.cons 0 eras))
            `shouldBe` Just (TimeSourceMismatch "era history")

-- ---------------------------------------------------------------------
-- Evaluation
-- ---------------------------------------------------------------------

evaluationSpec :: Spec
evaluationSpec = describe "the evaluation of a transaction" $ do
    it "answers the purposes the scripted evaluation answers, each with positive units inside the maximum" $ do
        (tx, chainBefore, scripted) <- bookingTransaction
        time <- preprodTime
        parameters <- preprodParameters
        local <- evaluateLocally time (pure parameters) (resolveFrom chainBefore) tx
        Map.keysSet local `shouldBe` Map.keysSet scripted
        Map.null local `shouldBe` False
        let ExUnits maxMem maxSteps = parameters ^. ppMaxTxExUnitsL
        mapM_
            ( \case
                Right (ExUnits mem steps) -> do
                    mem `shouldSatisfy` (\n -> n > 0 && n <= maxMem)
                    steps `shouldSatisfy` (\n -> n > 0 && n <= maxSteps)
                Left failure -> expectationFailure ("a purpose failed: " <> show failure)
            )
            (Map.elems local)
    it "gives the units the ledger's own evaluator gives, from an era history built apart from Singular's" $ do
        (tx, chainBefore, _) <- bookingTransaction
        time <- preprodTime
        parameters <- preprodParameters
        local <- evaluateLocally time (pure parameters) (resolveFrom chainBefore) tx
        let independent =
                evalTxExUnits
                    parameters
                    tx
                    (UTxO chainBefore)
                    (fixedEpochInfo (EpochSize 432_000) (mkSlotLength 1))
                    shiftedSystemStart
        Map.map (either show show) local `shouldBe` Map.map (either show show) independent
    it "is refused by name when an input of the transaction is not among the resolved outputs" $ do
        (tx, chainBefore, _) <- bookingTransaction
        time <- preprodTime
        parameters <- preprodParameters
        let missing = Set.findMin (Map.keysSet chainBefore `Set.intersection` (tx ^. bodyTxL . inputsTxBodyL))
        outcome <- try @KoiosFailure (evaluateLocally time (pure parameters) (resolveFrom (Map.delete missing chainBefore)) tx)
        outcome `shouldBe` Left (EvaluationRefused (MissingEvaluationInputs (Set.singleton missing)))
    it "is refused when the protocol parameters are of another protocol major than the pinned one" $ do
        (tx, chainBefore, _) <- bookingTransaction
        time <- preprodTime
        parameters <- preprodParameters
        let older = parameters & ppProtocolVersionL .~ ProtVer (natVersion @10) 0
        outcome <- try @KoiosFailure (evaluateLocally time (pure older) (resolveFrom chainBefore) tx)
        outcome `shouldBe` Left (NetworkTimeRefused (EraBeyondPinned 11 10))
    it "reads its inputs through the client: an input Koios does not hold unspent refuses the evaluation" $ do
        let tx = spending [reference 0x44 0]
        (reads', _) <-
            rigged
                [ singleFile cliProtocolParamsRequest "cli-protocol-params.json"
                , singleBytes (utxoInfoRequest [reference 0x44 0]) "[]"
                ]
        outcome <- try @KoiosFailure (readEvaluation reads' tx)
        outcome `shouldBe` Left (EvaluationRefused (MissingEvaluationInputs (Set.singleton (reference 0x44 0))))
    it "reads its inputs through the client: a transaction without scripts has no purpose to answer" $ do
        let tx = spending [reference 0x11 0]
        (reads', _) <-
            rigged
                [ singleFile cliProtocolParamsRequest "cli-protocol-params.json"
                , singleFile (utxoInfoRequest [reference 0x11 0]) "utxo-info-first.json"
                , singleFile (txInfoRequest [txIdOfByte 0x11]) "tx-info-two.json"
                ]
        readEvaluation reads' tx >>= (`shouldBe` Map.empty)
  where
    -- the time of a slot after the first four epochs of 20 s slots is the genesis start plus the
    -- 1,641,600 s those epochs add (86,400 slots of 20 s, less 86,400 slots of 1 s)
    shiftedSystemStart = SystemStart (addUTCTime 1_641_600 (UTCTime (fromGregorian 2022 6 1) 0))
    spending inputs = mkBasicTx (mkBasicTxBody & inputsTxBodyL .~ Set.fromList inputs) :: ConwayTx

{- | A booking of the registry, built over the world of the booking specs with its
clock taken from a fixed observation of the preprod tip (the one the first tip
answer gives, written out, so the reads under test are not part of it): the transaction, the
outputs that stood on the chain before it, and what the scripted evaluation of
that chain answers for it. The booking carries a validity interval of whole
slots from the tip, and the registry's script judges the booked time against it,
so the evaluation converts slots to times with the network's era history.
-}
bookingTransaction :: IO (ConwayTx, Map TxIn (TxOut ConwayEra), EvaluateTxResult ConwayEra)
bookingTransaction = do
    world <- newWorld 1_000
    export <- loadExport "kli-export-single.cesr"
    let observed =
            Observation
                { obsTipSlot = SlotNo (fromInteger tipSlot)
                , obsTipStartMs = tipStart
                , obsSlotLengthMs = 1_000
                , obsClockMs = tipStart + 100
                , obsHorizonSlot = SlotNo (fromInteger lastConvertible)
                }
        runtime = (runtimeOf noFaults world){rtObserve = pure observed, rtNowMs = pure (tipStart + 100)}
    standing <- chainOutputs <$> readIORef (worldChain world)
    outcome <- registerRegistration runtime (\_ -> pure ()) (registerRequestOf world export)
    _ <- either (fail . show) pure outcome
    chain <- readIORef (worldChain world)
    booking <- case chainAccepted chain of
        tx : _ -> pure tx
        [] -> fail "the booking landed no transaction"
    scripted <- trEvaluate (rtTransactions runtime) booking
    pure (booking, standing, scripted)

resolveFrom :: Map TxIn (TxOut ConwayEra) -> Set TxIn -> IO (Map TxIn (TxOut ConwayEra))
resolveFrom world wanted = pure (Map.restrictKeys world wanted)

-- ---------------------------------------------------------------------
-- Recordings and the rig
-- ---------------------------------------------------------------------

-- | A request, the headers the service answered with, and the body.
data Recording = Recording RawRequest Int [(Text, Text)] ByteString

fixtureBody :: FilePath -> IO ByteString
fixtureBody name = getDataFileName ("deployment-test/fixtures/koios/" <> name) >>= BS.readFile

-- | An unpaged request answered by a hand-written file.
singleFile :: Request a -> FilePath -> IO Recording
singleFile req name = Recording (rawRequest req) 200 [] <$> fixtureBody name

-- | An unpaged request answered by a hand-written file, with the range the service states.
singleFileRange :: Request a -> Text -> FilePath -> IO Recording
singleFileRange req range name = Recording (rawRequest req) 200 [("content-range", range)] <$> fixtureBody name

-- | An unpaged request answered with a status and a range by a hand-written file.
singleFileStated :: Request a -> Int -> Text -> FilePath -> IO Recording
singleFileStated req status range name = Recording (rawRequest req) status [("content-range", range)] <$> fixtureBody name

-- | An unpaged request answered by these bytes.
singleBytes :: Request a -> ByteString -> IO Recording
singleBytes req body = pure (Recording (rawRequest req) 200 [] body)

{- | The first page of a paged request, answered by a hand-written file with
the range the service states. A page of the client is asked with the order of
the request, the offset and the page size.
-}
pagedFile :: Request a -> Text -> FilePath -> IO Recording
pagedFile = pagedFileAt 0 1_000

-- | The page at an offset, of a stated size.
pagedFileAt :: Int -> Int -> Request a -> Text -> FilePath -> IO Recording
pagedFileAt offset size req range name =
    Recording
        raw
            { rawQuery =
                rawQuery raw
                    <> maybe [] (\o -> [("order", o)]) (requestOrder req)
                    <> [("offset", T.pack (show offset)), ("limit", T.pack (show size))]
            }
        200
        [("content-range", range)]
        <$> fixtureBody name
  where
    raw = rawRequest req

fixtureOf :: Recording -> Fixture
fixtureOf (Recording raw status headers body) =
    Fixture
        { fixtureRequest = fixtureRequestOf raw
        , fixtureRevision = "test"
        , fixtureRecordedAt = UTCTime (fromGregorian 2026 11 23) 0
        , fixtureSha256 = bodySha256 body
        , fixtureAnswer = Answer status headers body
        }

-- | The reads over a client answering from these recordings, and how many requests it saw.
riggedAt :: IO Integer -> [IO Recording] -> IO (KoiosReads, IORef Int)
riggedAt = riggedWith defaultClientConfig

-- | The same over pages of a stated size.
riggedPaged :: Int -> [IO Recording] -> IO (KoiosReads, IORef Int)
riggedPaged size = riggedWith defaultClientConfig{pageSize = size} (pure tipStart)

riggedWith :: ClientConfig -> IO Integer -> [IO Recording] -> IO (KoiosReads, IORef Int)
riggedWith config clock makers = do
    recordings <- sequence makers
    time <- preprodTime
    calls <- newIORef 0
    let base = recordedTransport (FixtureSet "test" (map fixtureOf recordings))
        counting = Transport (\raw -> modifyIORef' calls (+ 1) >> exchange base raw)
    pure (koiosReads (Koios config counting) time clock, calls)

rigged :: [IO Recording] -> IO (KoiosReads, IORef Int)
rigged = riggedAt (pure tipStart)

shouldFailWith :: Call -> (FailureReason -> Bool) -> Either KoiosFailure a -> Expectation
shouldFailWith call wanted = \case
    Left (KoiosCallFailed (ClientFailure failed attempts reason))
        | failed == call && attempts == 1 && wanted reason -> pure ()
    Left other -> expectationFailure ("another failure: " <> show other)
    Right _ -> expectationFailure "no failure"

isUndecodable, isNotRecorded, isIncomplete :: FailureReason -> Bool
isIncomplete = \case IncompletePage _ -> True; _ -> False
isUndecodable = \case Undecodable _ -> True; _ -> False
isNotRecorded = \case NotRecorded _ -> True; _ -> False

preprodSource :: IO TimeSource
preprodSource = loadPinnedSource 1 Nothing >>= either (fail . show) pure

preprodTime :: IO NetworkTime
preprodTime = do
    TimeSource manifest genesis eras <- preprodSource
    either (fail . show) pure (validateNetworkTime 1 manifest genesis eras)

{- | The preprod protocol parameters, as the ledger decodes the bytes recorded
from the node, and the node's own JSON form of them.
-}
preprodParameters :: IO (PParams ConwayEra)
preprodParameters = do
    bytes <- fixtureBody "preprod-protocol-parameters.cbor"
    either (fail . show) pure (decodeFull' (natVersion @11) bytes)

-- ---------------------------------------------------------------------
-- Ledger values
-- ---------------------------------------------------------------------

txIdOfByte :: Word8 -> TxId
txIdOfByte b = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 b))))

reference :: Word8 -> Integer -> TxIn
reference b i = TxIn (txIdOfByte b) (TxIx (fromInteger i))

-- | The address the hand-written answers spell as @addr_test1wzs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rggqxgwml@.
addressA :: Addr
addressA = scriptAddress 0xa1

scriptAddress :: Word8 -> Addr
scriptAddress b = Addr Testnet (ScriptHashObj (ScriptHash (fromJust (hashFromBytes (BS.replicate 28 b))))) StakeRefNull

plain :: Integer -> TxOut ConwayEra
plain n = mkBasicTxOut addressA (MaryValue (Coin n) (MultiAsset Map.empty))

tokened :: TxOut ConwayEra
tokened =
    mkBasicTxOut
        addressA
        ( MaryValue
            (Coin 2_000_000)
            (MultiAsset (Map.singleton policy (Map.singleton (AssetName (SBS.toShort "token")) 3)))
        )
        & datumTxOutL .~ Datum (either error id (makeBinaryData (SBS.toShort (BS.pack [0xd8, 0x79, 0x80]))))
  where
    policy = PolicyID (ScriptHash (fromJust (hashFromBytes (BS.replicate 28 0xaa))))
