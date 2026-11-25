{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosReadsSpec
Description : the Koios reads give a whole answer in ledger types, or one named failure

The reads run through Singular's Koios client over its recorded transport. The
accepted answers are the ones recorded from the preprod service, under
@deployment-test/fixtures/koios-recorded@, each with the request, the schema
revision, the time and the SHA-256 the recorder wrote. The shapes the live
service cannot be asked for (the first era, slot zero, the end of an epoch, a
tip whose time disagrees, a second page, an empty answer) and every refusal are
written by hand under @deployment-test/fixtures/koios@. A request that no
fixture answers is "not recorded". Every expected value is spelled out here,
read from the recorded body by a decoder apart from the code under test, or
taken from the ledger and the node's recorded slot starts, never read back from
the code under test.
-}
module Cardano.KERI.Deployment.KoiosReadsSpec (spec, riggedRecorded, recordedTipStart, walletAddress) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Crypto.Hash qualified as Hash
import Cardano.KERI.Deployment.KoiosRuntime (
    KoiosFailure (..),
    KoiosReads (..),
    evaluateLocally,
    koiosReads,
 )
import Cardano.KERI.Deployment.KoiosSettlementSpec (jsonBytes, okJson)
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
import Cardano.KERI.Deployment.RegistryTransactions (Payer (..), ValidityPlan (..), publishReferenceScript)
import Cardano.KERI.Deployment.TestNetworkTime (TestNetwork (..), testNetworkTime)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (pattern RequireTimeStart)

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
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL, datumTxOutL, mkBasicTxOut, referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..), ProtVer (..), StrictMaybe (..), TxIx (..), natVersion)
import Cardano.Ledger.Binary (decodeFull')
import Cardano.Ledger.Coin (Coin (..), CoinPerByte (..), compactCoinOrError)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, Script, fromNativeScript, ppMaxTxSizeL, ppProtocolVersionL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.Data (Datum (..), makeBinaryData)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult, SlotNo (..))
import Cardano.Slotting.EpochInfo (fixedEpochInfo)
import Cardano.Slotting.Slot (EpochNo (..), EpochSize (..))
import Cardano.Slotting.Time (SystemStart (..), mkSlotLength)
import Control.Exception (try)
import Control.Monad (forM_)
import Data.Aeson (Value (..), eitherDecodeStrict', object, withObject, (.!=), (.:), (.:?), (.=))
import Data.Aeson.Types (parseEither)
import Data.Bifunctor (second)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Short qualified as SBS
import Data.Either (isLeft)
import Data.Foldable (toList)
import Data.Function ((&))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf, sort)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, isJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
import Singular.Provider.Koios.Client qualified as Client
import Singular.Provider.Koios.Recorded (
    Fixture (..),
    FixtureFailure (..),
    FixtureSet (..),
    bodySha256,
    decodeFixture,
    encodeFixture,
    fixtureFileName,
    fixtureRequestOf,
    loadFixtureSet,
    recordedTransport,
 )
import Singular.Provider.Koios.Recorded qualified as Rec
import Singular.Provider.Koios.Wire (
    Body (..),
    Call (..),
    Request (..),
    TxInfo (..),
    UtxoInfo (..),
    addressUtxosRequest,
    cliProtocolParamsRequest,
    tipRequest,
    txInfoRequest,
    utxoInfoRequest,
 )
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.LocalEvaluation (EvaluationFailure (..))
import Singular.Registry.NetworkTime (
    NetworkTime,
    NetworkTimeFailure (..),
    slotStartMs,
    validateNetworkTime,
 )
import Singular.Registry.TimeSource (TimeSource (..), loadPinnedSource)
import System.Directory (listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "the Koios reads of a registry runtime" $ do
    outputsAtAddressSpec
    outputsUnderReferencesSpec
    protocolParametersSpec
    observationSpec
    subSecondSpec
    evaluationSpec
    recordedProvenanceSpec
    recordedObservationSpec
    recordedOutputsSpec
    recordedReferencesSpec
    recordedReferenceScriptSpec

-- ---------------------------------------------------------------------
-- The outputs at an address
-- ---------------------------------------------------------------------

outputsAtAddressSpec :: Spec
outputsAtAddressSpec = describe "the outputs at an address" $ do
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
        (reads', _) <- rigged [recordedOf CallCliProtocolParams]
        parameters <- readProtocolParameters reads'
        parameters ^. ppProtocolVersionL `shouldBe` ProtVer (natVersion @11) 0
        parameters ^. ppMaxTxExUnitsL `shouldBe` ExUnits 17_500_000 10_000_000_000
        parameters ^. ppMaxTxSizeL `shouldBe` 16_384
        parameters ^. ppTxFeeFixedL `shouldBe` Coin 155_381
        parameters ^. ppTxFeePerByteL `shouldBe` CoinPerByte (compactCoinOrError (Coin 44))
        parameters ^. ppCoinsPerUTxOByteL `shouldBe` CoinPerByte (compactCoinOrError (Coin 4_310))
        parameters ^. ppCollateralPercentageL `shouldBe` 150
        parameters ^. ppMaxCollateralInputsL `shouldBe` 3
        parameters ^. ppMinPoolCostL `shouldBe` Coin 75_000_000
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

{- | The tips written by hand, each with the start of its slot and the last slot
converted: the shapes the live service cannot be asked for. The tip recorded from
preprod has its own test. Slot 69,106,399 is 331,999 slots after the first, so it
starts 331,999,000 ms later; the window it forecasts reaches slot 69,235,999,
which lies in the next epoch, so its horizon is the end of that epoch, slot
69,638,399. Slot 10,000 is
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
    , ("tip-byron.json", 10_000, 1_654_241_600_000, 20_000, 518_399)
    , ("tip-last-first-era.json", 86_399, 1_655_769_580_000, 20_000, 518_399)
    , ("tip-first-second-era.json", 86_400, 1_655_769_600_000, 1_000, 518_399)
    ]

{- | A network whose slots last a tenth of a second, as the local test chain's do, and a provider that states the
time of its tip in whole seconds, as Koios does (its @block_time@ is UNIX seconds): the slot starts at some tenth
of a second, and the second it falls in is what the provider states. The observation takes that tip whatever tenth
of its second it starts at, and still refuses a tip stated in another second.
-}
subSecondSpec :: Spec
subSecondSpec = describe "the observation of a network whose slots are shorter than a second" $ do
    let network = TestNetwork{slotSeconds = 1 / 10, epochLength = 432_000, securityParam = 2_160, activeSlotsCoeff = 0.05, zeroMs = 1_790_000_000_000, laterEra = Nothing}
        observeAt slot stated = do
            time <- testNetworkTime network
            start <- either (fail . show) pure (slotStartMs time (SlotNo (fromInteger slot)))
            let row =
                    object
                        [ "abs_slot" .= slot
                        , "hash" .= T.replicate 32 "ab"
                        , "block_height" .= (1 :: Int)
                        , "epoch_no" .= (0 :: Int)
                        , "block_time" .= stated start
                        ]
                transport = Client.Transport $ \_ -> pure (okJson 200 [] (jsonBytes [row]))
            (,) start <$> try @KoiosFailure (readObservation (koiosReads (Koios defaultClientConfig transport) time (pure 0)))
    forM_ [100 .. 109 :: Integer] $ \slot ->
        it ("takes the tip of slot " <> show slot <> ", which starts " <> show ((slot - 100) * 100) <> " ms into its second, as the second the provider states") $ do
            (start, outcome) <- observeAt slot (`div` 1_000)
            fmap obsTipStartMs outcome `shouldBe` Right start
    it "refuses a tip the provider states in another second than the one its slot starts in" $ do
        (start, outcome) <- observeAt 105 ((+ 1) . (`div` 1_000))
        outcome `shouldBe` Left (TipTimeDisagrees ((start `div` 1_000 + 1) * 1_000) start)

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
                [ recordedOf CallCliProtocolParams
                , singleBytes (utxoInfoRequest [reference 0x44 0]) "[]"
                ]
        outcome <- try @KoiosFailure (readEvaluation reads' tx)
        outcome `shouldBe` Left (EvaluationRefused (MissingEvaluationInputs (Set.singleton (reference 0x44 0))))
    it "reads its inputs through the client: a transaction without scripts has no purpose to answer" $ do
        let tx = spending [reference 0x11 0]
        (reads', _) <-
            rigged
                [ recordedOf CallCliProtocolParams
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

-- | An answer for the rig: written by hand, or recorded from the service.
data Recording
    = -- | A request, the headers the service answered with, and the body.
      Recording RawRequest Int [(Text, Text)] ByteString
    | -- | A recording as the recorder wrote it.
      Recorded Fixture

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
fixtureOf (Recorded fixture) = fixture
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
    let counting = countedTransport calls (map fixtureOf recordings)
    pure (koiosReads (Koios config counting) time clock, calls)

-- | A transport answering from these fixtures, counting the requests it sees.
countedTransport :: IORef Int -> [Fixture] -> Transport IO
countedTransport calls fixtures =
    Transport (\raw -> modifyIORef' calls (+ 1) >> exchange base raw)
  where
    base = recordedTransport (FixtureSet "test" fixtures)

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

-- ---------------------------------------------------------------------
-- The answers recorded from preprod
-- ---------------------------------------------------------------------

-- | Where the recorder's files are, as the package installs them.
recordedDirectory :: IO FilePath
recordedDirectory = getDataFileName "deployment-test/fixtures/koios-recorded"

-- | Every recording, loaded as Singular's recorded transport loads a directory.
recordedSet :: IO FixtureSet
recordedSet =
    recordedDirectory
        >>= loadFixtureSet
        >>= either (fail . ("the recordings do not load: " <>) . show) pure

-- | The only recording of a call.
recordedOf :: Call -> IO Recording
recordedOf call = do
    set <- recordedSet
    case [fixture | fixture <- setFixtures set, Rec.fixtureCall (fixtureRequest fixture) == call] of
        [fixture] -> pure (Recorded fixture)
        found -> fail ("one recording of " <> show call <> " is wanted, " <> show (length found) <> " found")

-- | The recording of the outputs at one address, asked as the client asks.
recordedFixtureAt :: Text -> IO Fixture
recordedFixtureAt bech32 = do
    set <- recordedSet
    case [fixture | fixture <- setFixtures set, Rec.fixtureBody (fixtureRequest fixture) == asked] of
        [fixture] -> pure fixture
        found -> fail ("one recording at " <> T.unpack bech32 <> " is wanted, " <> show (length found) <> " found")
  where
    asked = JsonBody (object ["_addresses" .= [bech32], "_extended" .= True])

-- | The reads over a client answering from every recording, and how many requests it saw.
riggedRecorded :: IO Integer -> IO (KoiosReads, IORef Int)
riggedRecorded clock = do
    set <- recordedSet
    time <- preprodTime
    calls <- newIORef 0
    pure (koiosReads (Koios defaultClientConfig (countedTransport calls (setFixtures set))) time clock, calls)

-- | The client over every recording, for the calls the reads do not make.
recordedClient :: IO (Koios IO)
recordedClient = Koios defaultClientConfig . recordedTransport <$> recordedSet

{- | The tip the recording holds, written out from its body: slot, start of the slot, and the
last slot the node converts (the end of the epoch its tip lies in: epoch 327 starts at slot
139,807,358 less its slot 184,958 in the epoch, and lasts 432,000 slots).
-}
recordedTipSlot, recordedTipStart, recordedHorizon :: Integer
recordedTipSlot = 139_807_358
recordedTipStart = 1_795_490_558_000
recordedHorizon = 139_622_400 + 432_000 - 1

-- | What a recorded output holds, apart from the address it is at.
data Shape = Shape
    { shLovelace :: Integer
    , shAssets :: [(ByteString, ByteString, Integer)]
    , shDatum :: Datum ConwayEra
    , shScripted :: Bool
    }
    deriving stock (Eq, Show)

-- | The shape of a ledger output.
shapeOf :: TxOut ConwayEra -> Shape
shapeOf out =
    Shape
        { shLovelace = let Coin c = out ^. coinTxOutL in c
        , shAssets =
            sort
                [ (hashToBytes policy, SBS.fromShort name, quantity)
                | let MaryValue _ (MultiAsset assets) = out ^. valueTxOutL
                , (PolicyID (ScriptHash policy), named) <- Map.toList assets
                , (AssetName name, quantity) <- Map.toList named
                ]
        , shDatum = out ^. datumTxOutL
        , shScripted = out ^. referenceScriptTxOutL /= SNothing
        }

-- | The rows a recorded body states, read by a decoder apart from the client's.
recordedRows :: ByteString -> Either String [(TxIn, Shape)]
recordedRows body = eitherDecodeStrict' body >>= traverse (parseEither row)
  where
    row = withObject "row" $ \o -> do
        transaction <- o .: "tx_hash" >>= unhex
        index <- o .: "tx_index"
        lovelace <- o .: "value" >>= number
        assets <-
            o .:? "asset_list" .!= []
                >>= traverse
                    ( withObject "asset" $ \a ->
                        (,,)
                            <$> (a .: "policy_id" >>= unhex)
                            <*> (a .: "asset_name" >>= unhex)
                            <*> (a .: "quantity" >>= number)
                    )
        inline <- o .:? "inline_datum" >>= traverse (withObject "datum" (\d -> d .: "bytes" >>= unhex))
        script <- o .:? "reference_script"
        pure
            ( TxIn (txIdOfBytes transaction) (TxIx (fromInteger index))
            , Shape
                { shLovelace = lovelace
                , shAssets = sort assets
                , shDatum = maybe NoDatum (Datum . either error id . makeBinaryData . SBS.toShort) inline
                , shScripted = isJust (script :: Maybe Value)
                }
            )
    unhex = either fail pure . convertFromBase Base16 . TE.encodeUtf8
    number text = case reads (T.unpack text) of
        [(n, "")] -> pure (n :: Integer)
        _ -> fail ("not a number: " <> T.unpack text)

txIdOfBytes :: ByteString -> TxId
txIdOfBytes = TxId . unsafeMakeSafeHash . fromJust . hashFromBytes

-- | A transaction identifier or a hash, written in hexadecimal.
hexBytes :: Text -> ByteString
hexBytes = either error id . convertFromBase Base16 . TE.encodeUtf8

-- | The three addresses the recording holds outputs of, as bech32 and as ledger addresses.
scriptAddressOne, scriptAddressTwo, walletAddress :: (Text, Addr)
scriptAddressOne =
    ( "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"
    , Addr Testnet (ScriptHashObj (ScriptHash (hashOfHex "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"))) StakeRefNull
    )
scriptAddressTwo =
    ( "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
    , Addr Testnet (ScriptHashObj (ScriptHash (hashOfHex "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"))) StakeRefNull
    )
walletAddress =
    ( "addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx"
    , Addr Testnet (KeyHashObj (KeyHash (hashOfHex "9a096d653c3663ec9a4d39cdbe0245f843a52abe42aceabd2b941cdd"))) StakeRefNull
    )

hashOfHex :: (Hash.HashAlgorithm h) => Text -> Hash.Hash h a
hashOfHex = fromJust . hashFromBytes . hexBytes

-- ---------------------------------------------------------------------
-- What the recorder kept
-- ---------------------------------------------------------------------

recordedProvenanceSpec :: Spec
recordedProvenanceSpec = describe "the recorded answers" $ do
    it "are the nine the recorder wrote, loading together under one schema revision" $ do
        directory <- recordedDirectory
        names <- filter (".json" `isSuffixOf`) <$> listDirectory directory
        length names `shouldBe` 9
        set <- recordedSet
        setRevision set `shouldBe` "v1.4.2"
        length (setFixtures set) `shouldBe` 9
    it "keep each request, the schema revision, the time and the SHA-256 of the body, and the SHA-256 is the body's" $ do
        directory <- recordedDirectory
        names <- filter (".json" `isSuffixOf`) <$> listDirectory directory
        length names `shouldSatisfy` (> 0)
        forM_ names $ \name -> do
            bytes <- LBS.readFile (directory </> name)
            fixture <- either (fail . T.unpack) pure (decodeFixture bytes)
            fixtureSha256 fixture `shouldBe` bodySha256 (answerBody (fixtureAnswer fixture))
            fixtureRevision fixture `shouldBe` "v1.4.2"
            fixtureRecordedAt fixture `shouldSatisfy` (>= UTCTime (fromGregorian 2026 11 24) 0)
            answerStatus (fixtureAnswer fixture) `shouldBe` 200
            name `shouldBe` fixtureFileName (fixtureRequest fixture)
    it "are refused by name when one byte of a body is not the one hashed, and loaded when it is" $ do
        set <- recordedSet
        original <- case setFixtures set of
            fixture : _ -> pure fixture
            [] -> fail "no recording"
        let answer = fixtureAnswer original
            altered = original{fixtureAnswer = answer{answerBody = BS.snoc (answerBody answer) 0x20}}
        withSystemTempDirectory "recorded" $ \directory -> do
            LBS.writeFile (directory </> "original.json") (encodeFixture original)
            loadFixtureSet directory >>= (`shouldSatisfy` either (const False) (const True))
            LBS.writeFile (directory </> "altered.json") (encodeFixture altered)
            outcome <- loadFixtureSet directory
            outcome `shouldBe` Left (FixtureHashMismatch (directory </> "altered.json"))

-- ---------------------------------------------------------------------
-- The observation of the recorded tip
-- ---------------------------------------------------------------------

recordedObservationSpec :: Spec
recordedObservationSpec = describe "the observation, over the tip recorded from preprod" $ do
    it "takes the tip from Koios, the slot start and the horizon from the pinned network time: slot 139,807,358" $ do
        (reads', calls) <- riggedRecorded (pure (recordedTipStart + 500))
        observed <- readObservation reads'
        observed
            `shouldBe` Observation
                { obsTipSlot = SlotNo (fromInteger recordedTipSlot)
                , obsTipStartMs = recordedTipStart
                , obsSlotLengthMs = 1_000
                , obsClockMs = recordedTipStart + 500
                , obsHorizonSlot = SlotNo (fromInteger recordedHorizon)
                }
        readIORef calls >>= (`shouldBe` 1)
    it "reads the block's hash, height and epoch as the service stated them" $ do
        client <- recordedClient
        Client.tip client
            >>= ( `shouldBe`
                    Right
                        Wire.Tip
                            { Wire.tipSlot = SlotNo (fromInteger recordedTipSlot)
                            , Wire.tipBlockHash = hexBytes "af151eed701bc345b449225163bc90d734612d50eb9182b47921ea85654a26c4"
                            , Wire.tipBlockHeight = 5_448_807
                            , Wire.tipEpoch = EpochNo 327
                            , Wire.tipBlockTime = 1_795_490_558
                            }
                )

-- ---------------------------------------------------------------------
-- The outputs at the recorded addresses
-- ---------------------------------------------------------------------

recordedOutputsSpec :: Spec
recordedOutputsSpec = describe "the outputs at an address, over the answers recorded from preprod" $ do
    forM_
        [
            ( "three outputs of a script address, each with a token and an inline datum"
            , scriptAddressOne
            , 3
            , 12_000_000
            , txInOf "0d130e108d6b3c1193c6fa6bf5f63e0474bef5b0c0be1ba95e2cf90c5410b1f9" 0
            )
        ,
            ( "eleven outputs of another script address, each with a token and an inline datum"
            , scriptAddressTwo
            , 11
            , 11_077_000_000
            , txInOf "27637ebb9ca9c7f5dcb2e960512d6858e0e4f9f7f093ef6e7acdf4b3aacdc1e1" 0
            )
        ,
            ( "fifteen outputs of the wallet that deployed before: plain, with tokens, six with a reference script"
            , walletAddress
            , 15
            , 1_067_147_761
            , txInOf "1ae4fdd31978f024632bb0b5d786161b471c98ba606c8e0487bb8a68f142a064" 0
            )
        ]
        $ \(label, (bech32, address), count, total, first') ->
            it ("are all of them, converted to ledger outputs as the recording states them: " <> label) $ do
                (reads', calls) <- riggedRecorded (pure recordedTipStart)
                found <- readUtxosAt reads' address
                recorded <- recordedFixtureAt bech32
                expected <- either fail pure (recordedRows (answerBody (fixtureAnswer recorded)))
                length found `shouldBe` count
                sum [shLovelace (shapeOf out) | (_, out) <- found] `shouldBe` total
                fmap fst (take 1 found) `shouldBe` [first']
                [(reference', shapeOf out) | (reference', out) <- found] `shouldBe` expected
                readIORef calls >>= (`shouldBe` 1)

txInOf :: Text -> Integer -> TxIn
txInOf transaction index = TxIn (txIdOfBytes (hexBytes transaction)) (TxIx (fromInteger index))

-- ---------------------------------------------------------------------
-- The outputs under references, over the recorded calls
-- ---------------------------------------------------------------------

{- | The recording holds two spent-or-not answers and one transaction answer.
The transaction answer pairs with the second spent-or-not answer, so the read of
outputs under exact references runs end to end on recorded answers over the two
references of that pair; the first spent-or-not answer is checked at the client.
-}
recordedReferencesSpec :: Spec
recordedReferencesSpec = describe "the spent-or-not and transaction answers recorded from preprod" $ do
    let first' = txInOf "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c" 0
        second' = txInOf "c1ebe8b9a69160a04a9e490d4ab1149882f945774fba0cffac2dec7e6886b26f" 0
        third' = txInOf "967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4" 0
        publisher = Addr Testnet (KeyHashObj (KeyHash (hashOfHex "8883cdb714313b7ac38246c1dd8d6fc3f804f153c1f1c4ca38561ba0"))) StakeRefNull
    it "are the outputs under exact references, whole: two unspent references and the transactions that made them" $ do
        (reads', calls) <- riggedRecorded (pure recordedTipStart)
        found <- readOutputs reads' (Set.fromList [first', third'])
        Map.keys found `shouldBe` [first', third']
        [(out ^. addrTxOutL, shapeOf out) | out <- Map.elems found]
            `shouldBe` replicate 2 (publisher, Shape 100_000_000 [] NoDatum True)
        readIORef calls >>= (`shouldBe` 2)
    it "state the two references of the other spent-or-not answer unspent" $ do
        client <- recordedClient
        Client.utxoInfo client (first' NE.:| [second'])
            >>= (`shouldBe` Right [UtxoInfo first' False, UtxoInfo second' False])
    it "give the outputs of the two transactions asked, with the reference script of the first output" $ do
        client <- recordedClient
        let wanted = [txIdOfBytes (hexBytes "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c"), txIdOfBytes (hexBytes "967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4")]
        answered <- Client.txInfo client wanted >>= either (fail . show) pure
        map txInfoId answered `shouldBe` wanted
        map txInfoBlockHeight answered `shouldBe` [4_989_276, 4_992_785]
        [ [(ix, shLovelace (shapeOf out), shScripted (shapeOf out)) | (TxIn _ ix, out) <- txInfoOutputs info]
          | info <- answered
          ]
            `shouldBe` [ [(TxIx 0, 100_000_000, True), (TxIx 1, 899_423_099, False)]
                       , [(TxIx 0, 100_000_000, True), (TxIx 1, 906_690_399, False)]
                       ]

-- ---------------------------------------------------------------------
-- The old deployment's reference scripts
-- ---------------------------------------------------------------------

{- | The fifteen outputs of the wallet hold six that carry a reference script:
the old deployment's. A transaction that spends one destroys it. The payer
selection of the registry commands leaves them out, whether the outputs are the
ones the Koios read converted or ledger outputs built in the test from the recorded
rows, and takes them when they carry no script. The read of the node is not
exercised here.
-}
recordedReferenceScriptSpec :: Spec
recordedReferenceScriptSpec = describe "the wallet's outputs that carry a reference script" $ do
    let scriptedReferences =
            Set.fromList
                [ txInOf "1ae4fdd31978f024632bb0b5d786161b471c98ba606c8e0487bb8a68f142a064" 0
                , txInOf "1c04c6ffb445644dedaf3178a70b6e45511043949035e786962118c6750be99c" 0
                , txInOf "346ad9590e0889017d900c34de992693334c04bffc7431ab383568425f0938a7" 0
                , txInOf "6a2368686087b42273ffe63d8474594b84b7a194796ef1dcdf12123ea3b08616" 0
                , txInOf "ccae188d11e5ae617f2ad7e022afb91d0e9b03e7d8c8553d0c917e123e6aaf0c" 0
                , txInOf "f5ae7e437f4f42a40380f76e73f39acc72911bdc04756b903ffefef5b8706662" 0
                ]
        (bech32, address) = walletAddress
        -- ledger outputs built in the test from the recorded rows, not read by the client, with a
        -- stand-in script where the recording shows one
        builtFunds = do
            recorded <- recordedFixtureAt bech32
            rows <- either fail pure (recordedRows (answerBody (fixtureAnswer recorded)))
            pure [(reference', ledgerOutput address shape) | (reference', shape) <- rows]
        koiosFunds = do
            (reads', _) <- riggedRecorded (pure recordedTipStart)
            readUtxosAt reads' address
        parametersOf = do
            (reads', _) <- riggedRecorded (pure recordedTipStart)
            readProtocolParameters reads'
        publication parameters funds lovelace =
            either (Left . show) Right $
                publishReferenceScript Nothing parameters (Payer address funds) (Coin lovelace) standIn
        stripped = map (second (referenceScriptTxOutL .~ SNothing))
        spentBy tx = Set.fromList (toList (tx ^. bodyTxL . inputsTxBodyL))
    it "keep their reference scripts through the Koios read: six of fifteen, at the references the recording states" $ do
        funds <- koiosFunds
        Set.fromList [reference' | (reference', out) <- funds, shScripted (shapeOf out)] `shouldBe` scriptedReferences
        length funds `shouldBe` 15
    forM_ [("converted by the Koios read", koiosFunds), ("built in the test from the recorded rows", builtFunds)] $ \(backend, fundsOf) -> do
        it ("are not spent by a publication the other outputs cover, outputs " <> backend) $ do
            funds <- fundsOf
            parameters <- parametersOf
            tx <- either fail pure (publication parameters funds 915_000_000)
            Set.intersection (spentBy tx) scriptedReferences `shouldBe` Set.empty
        it ("are not spent when the other outputs do not cover the payment, which is then refused, outputs " <> backend) $ do
            funds <- fundsOf
            parameters <- parametersOf
            publication parameters funds 980_000_000 `shouldSatisfy` isLeft
        it ("are the only difference: the same outputs without the scripts cover that payment, and the publication spends some of the six, outputs " <> backend) $ do
            funds <- stripped <$> fundsOf
            parameters <- parametersOf
            tx <- either fail pure (publication parameters funds 980_000_000)
            Set.intersection (spentBy tx) scriptedReferences `shouldSatisfy` (not . Set.null)

-- | A script of no consequence, standing for the one a recording shows.
standIn :: Script ConwayEra
standIn = fromNativeScript (RequireTimeStart (SlotNo 0))

-- | The output of a shape at an address.
ledgerOutput :: Addr -> Shape -> TxOut ConwayEra
ledgerOutput address Shape{..} =
    mkBasicTxOut address (MaryValue (Coin shLovelace) (MultiAsset assets))
        & datumTxOutL .~ shDatum
        & referenceScriptTxOutL .~ (if shScripted then SJust standIn else SNothing)
  where
    assets =
        Map.fromListWith
            (Map.unionWith (+))
            [ (PolicyID (ScriptHash (hashOfBytes policy)), Map.singleton (AssetName (SBS.toShort name)) quantity)
            | (policy, name, quantity) <- shAssets
            ]
    hashOfBytes = fromJust . hashFromBytes
