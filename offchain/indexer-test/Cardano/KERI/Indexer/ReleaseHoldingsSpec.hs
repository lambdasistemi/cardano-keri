{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.ReleaseHoldingsSpec
Description : The reader's classification of the registry's holdings (#353)

Checks 'decodeHoldingOutput' and 'holdingsTx' against the library's own
producers: the expected asset of an AID is 'representativeAsset' of the
release's context, the expected lovelace of a holding is
'Cardano.KERI.AID.Checkpoint.Value.heldValue' of the release's amounts. Each
refusal is reached by a single change to an output that is otherwise accepted,
at two registries and at several amounts.
-}
module Cardano.KERI.Indexer.ReleaseHoldingsSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..), KeyMaterial (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.AID.Checkpoint.Value (heldValue)
import Cardano.KERI.AID.Consumer (decodeCheckpoint)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Indexer.Codecs (
    Holding (..),
    HoldingKind (..),
    HoldingRefusal (..),
    checkpointAddressOf,
    decodeHoldingOutput,
 )
import Cardano.KERI.Indexer.Query.Tx (HoldingsRead (..), holdingsTx)
import Cardano.KERI.Indexer.ReleaseFixtures
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Serialise (serialise)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Maybe (isJust)
import Database.KV.Transaction (RunTransaction (..))
import PlutusCore.Data qualified as PLC
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

rawA, rawB :: ByteString
rawA = BS.replicate 32 0x31
rawB = BS.replicate 32 0x32

classify :: ReleaseIdentity -> Indexer.TxOut -> Either HoldingRefusal Holding
classify ri = decodeHoldingOutput ri (txInAt 1)

spec :: Spec
spec = describe "Cardano.KERI.Indexer.Codecs holdings" $ do
    describe "checkpointAddressOf" $
        it "is the validator's script address on the release's network, with no stake part" $ do
            checkpointAddressOf testRelease
                `shouldBe` Indexer.Address (serialiseAddr (Addr Testnet (ScriptHashObj (scriptHashOf (riCheckpointValidator testRelease))) StakeRefNull))
            checkpointAddressOf testRelease{riNetwork = 1}
                `shouldBe` Indexer.Address (serialiseAddr (releaseAddr testRelease{riNetwork = 1}))
    describe "classification" $ do
        it "reads a live checkpoint with its facts, its amounts from the lovelace and its output reference" $
            mapM_
                ( \(ri, raw, flags@(frozen, poisoned, toppedUp), pool) ->
                    let facts = liveWith flags raw
                     in classify ri (liveOutputWith ri facts raw pool)
                            `shouldBe` Right
                                Holding
                                    { holdingAid = aidText raw
                                    , holdingSn = 5
                                    , holdingEpoch = 2
                                    , holdingTxIn = txInAt 1
                                    , holdingLovelace =
                                        heldValue (riMinimumAda ri) (riDeposit ri) (riFreezeBond ri) facts pool
                                    , holdingKind =
                                        HeldCheckpoint
                                            { hcPoisoned = poisoned
                                            , hcFrozen = frozen
                                            , hcBornAt = 1_700_000_000_000
                                            , hcRefund = BS.replicate 29 0x70
                                            , hcToppedUp = toppedUp
                                            , hcKeys = lvKeys facts
                                            , hcDeposit = riDeposit ri
                                            , hcFreezeBond = if frozen then 0 else riFreezeBond ri
                                            , hcPool = pool
                                            }
                                    }
                )
                [ (ri, raw, flags, pool)
                | ri <- [testRelease, otherRegistry]
                , raw <- [rawA, rawB]
                , flags <- [(f, p, t) | f <- [False, True], p <- [False, True], t <- [False, True]]
                , pool <- [0, 3, 5_000_000]
                ]
        it "admits exactly the datums the consumer decoder admits: key material is reported as read, never judged" $
            mapM_
                ( \keys ->
                    let facts = liveShaped keys (5, 2, 1) rawA
                     in do
                            decodeCheckpoint (datumBytes facts) `shouldSatisfy` isJust
                            fmap (hcKeys . holdingKind) (classify testRelease (liveOutputWith testRelease facts rawA 0))
                                `shouldBe` Right keys
                )
                oddKeyMaterial
        it "refuses a datum the consumer decoder refuses, however well formed the rest" $
            mapM_
                ( \facts -> do
                    decodeCheckpoint (datumBytes facts) `shouldBe` Nothing
                    classify testRelease (liveOutputWith testRelease facts rawA 0)
                        `shouldBe` Left MalformedDatum
                )
                [ liveShaped (lvKeys (liveFacts rawA)) (-1, 2, 1) rawA
                , liveShaped (lvKeys (liveFacts rawA)) (5, -3, 1) rawA
                , liveShaped (lvKeys (liveFacts rawA)) (5, 2, -1) rawA
                ]
        it "reads a pending termination holding exactly the minimum ADA, with no amounts" $
            mapM_
                ( \(ri, raw) ->
                    classify ri (pendingOutput ri raw (riMinimumAda ri))
                        `shouldBe` Right
                            Holding
                                { holdingAid = aidText raw
                                , holdingSn = 5
                                , holdingEpoch = 2
                                , holdingTxIn = txInAt 1
                                , holdingLovelace = riMinimumAda ri
                                , holdingKind = HeldPendingTermination
                                }
                )
                [(ri, raw) | ri <- [testRelease, otherRegistry], raw <- [rawA, rawB]]
    describe "named refusals" $ do
        let good = liveOutput testRelease rawA False 3
            facts = liveFacts rawA
            floorOf = heldValue (riMinimumAda testRelease) (riDeposit testRelease) (riFreezeBond testRelease) facts 0
        it "wrong network: an address on the other network" $
            classify
                testRelease
                (outputAt (releaseAddr testRelease{riNetwork = 1}) floorOf [asset testRelease rawA] (Just (datumOf facts)))
                `shouldBe` Left (WrongNetwork 1 0)
        it "not at the validator: another script credential" $
            classify
                testRelease
                (outputAt (releaseAddr testRelease{riCheckpointValidator = BS.replicate 28 0x77}) floorOf [asset testRelease rawA] (Just (datumOf facts)))
                `shouldBe` Left NotAtCheckpointValidator
        it "malformed datum: no datum, another datum, undecodable bytes" $ do
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [asset testRelease rawA] Nothing)
                `shouldBe` Left MalformedDatum
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [asset testRelease rawA] (Just (PLC.Constr 1 [])))
                `shouldBe` Left MalformedDatum
            classify testRelease (Indexer.TxOut "not an output")
                `shouldSatisfy` isUndecodable
        it "unknown release: tokens only under policies that are not the state policy" $
            classify
                testRelease
                ( outputAt
                    (releaseAddr testRelease)
                    floorOf
                    [(BS.replicate 28 0x99, let (_, n, _) = asset testRelease rawA in n, 1)]
                    (Just (datumOf facts))
                )
                `shouldBe` Left UnknownRelease
        it "another registry's asset: this registry's token name for no AID of the datum" $ do
            let (_, otherName) = assetOf otherRegistry rawA
                (p, _) = assetOf testRelease rawA
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [(p, otherName, 1)] (Just (datumOf facts)))
                `shouldBe` Left AnotherRegistrysAsset
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [(p, deriveAidAssetName rawA, 1)] (Just (datumOf facts)))
                `shouldBe` Left AnotherRegistrysAsset
        it "another registry's asset: the same output read under the other registry" $
            classify otherRegistry good `shouldBe` Left AnotherRegistrysAsset
        it "wrong quantity: two tokens, and no token" $ do
            let (p, n, _) = asset testRelease rawA
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [(p, n, 2)] (Just (datumOf facts)))
                `shouldBe` Left (WrongQuantity 2)
            classify testRelease (outputAt (releaseAddr testRelease) floorOf [] (Just (datumOf facts)))
                `shouldBe` Left (WrongQuantity 0)
        it "a lovelace the facts cannot hold: live below the floor, pending away from the minimum ADA" $ do
            classify testRelease (outputAt (releaseAddr testRelease) (floorOf - 1) [asset testRelease rawA] (Just (datumOf facts)))
                `shouldBe` Left (LovelaceNotHeld (floorOf - 1))
            mapM_
                ( \l ->
                    classify testRelease (pendingOutput testRelease rawA l)
                        `shouldBe` Left (LovelaceNotHeld l)
                )
                [riMinimumAda testRelease - 1, riMinimumAda testRelease + 1]
        it "reports the first problem when an output has several" $
            classify
                testRelease
                (outputAt (releaseAddr testRelease{riNetwork = 1}) 1 [] Nothing)
                `shouldBe` Left (WrongNetwork 1 0)
    describe "holdingsTx" $
        it "answers every output at the validator, accepted or refused, with the store's chain point" $
            withInMemoryIndexerRunner $ \handle runner -> do
                let addr = checkpointAddressOf testRelease
                    ops =
                        [ UtxoCreate (txInAt 1) addr (liveOutput testRelease rawA False 0)
                        , UtxoCreate (txInAt 2) addr (liveOutput otherRegistry rawB False 0)
                        , UtxoCreate (txInAt 3) addr (pendingOutput testRelease rawB (riMinimumAda testRelease))
                        , UtxoCreate (txInAt 4) addr (Indexer.TxOut "not an output")
                        ]
                applyAtSlot handle (Indexer.SlotNo 12) (Indexer.BlockHash (BS.replicate 32 0x0b)) ops
                result <- runTransaction runner (holdingsTx testRelease)
                hrPoint result `shouldBe` Just (Indexer.SlotNo 12, Indexer.BlockHash (BS.replicate 32 0x0b))
                map fst (hrOutputs result) `shouldBe` map txInAt [1, 2, 3, 4]
                map (either refusalKind (const "holding") . snd) (hrOutputs result)
                    `shouldBe` ["holding", "AnotherRegistrysAsset", "holding", "OutputUndecodable"]
  where
    isUndecodable (Left (OutputUndecodable _)) = True
    isUndecodable _ = False
    refusalKind = takeWhile (/= ' ') . show

-- | The bytes of the inline datum of some facts.
datumBytes :: CheckpointDatumV2 -> ByteString
datumBytes = BSL.toStrict . serialise . datumOf

{- | Key material the consumer decoder admits by shape and the write side would
refuse: an unreduced weighted threshold, a key that is not 32 bytes, repeated
keys, no keys, a threshold of zero.
-}
oddKeyMaterial :: [KeyMaterial]
oddKeyMaterial =
    [ base{kmCurThreshold = Weighted [[Weight 2 4, Weight 1 2]]}
    , base{kmCurKeys = [BS.replicate 31 1, BS.replicate 31 1]}
    , base{kmCurKeys = []}
    , base{kmCurThreshold = Unweighted 0, kmNextThreshold = Unweighted 7}
    , base{kmNextKeys = [BS.replicate 5 9], kmWitnesses = [BS.replicate 3 8, BS.replicate 3 8], kmToad = 9}
    ]
  where
    base = lvKeys (liveFacts rawA)
