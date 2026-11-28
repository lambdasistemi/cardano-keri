{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFutureDatumSpec
Description : The datum the builder creates for a weighted future declaration, against the signed bytes

For the three keripy inceptions of Q-069's flat weighted rows the booking record is built by the
production constructors and its initial datum decoded: the ordered commitments, and the literal
numerator and denominator of every weight, set beside the pairs of the signed event.

The governing statement is the model's booking: in draft #600 at `ce10e471`
(`lean/InceptionPrefixReference.lean`, `book` and the row "D next unreduced") the committed
datum's key state is the key state of the signed evidence, and the weights of that row are the
pair (2,4) in both; the application compares the six datum fields with the signed event "in the
same decoded domain" (the December acceptance map), and the validator's reconstruction rebuilds the
signed spelling from the datum's pairs (the NOTE-119 candidate handoff: the builder must "preserve
the signed pairs through construction and codec readback"). A signed 2/4 is therefore a datum pair
(2,4): not (1,2), and not a datum the codec cannot read.
-}
module Cardano.KERI.Deployment.RegistryFutureDatumSpec (spec) where

import Cardano.KERI.AID.Application (RegistrationData (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    checkpointDatumFromData,
    liveOfInception,
 )
import Cardano.KERI.AID.Checkpoint.EventDecoder (DecodedEstablishmentEvent (..), decodeEstablishmentEvent)
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..), parseThresholdSpelling)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (Scenario (..), scenarioOf)
import Cardano.KERI.Deployment.RegistryTransactionsSpec (deposit)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Test.Hspec (Spec, describe, it, shouldBe)

pairs :: Threshold -> [[(Integer, Integer)]]
pairs = \case
    Weighted clauses -> map (map (\(Weight n d) -> (n, d))) clauses
    Unweighted m -> [[(m, 1)]]

spec :: Spec
spec =
    describe "the builder-created datum of a weighted future declaration, against the signed bytes (Q-069)" $
        mapM_
            (\r -> row r >> codecReads r)
            [ ("future:D next unreduced", [[(2, 4), (2, 4)]], 2)
            , ("future:D next partial coverage", [[(1, 1)], [(1, 1)]], 3)
            , ("future:D next exact one", [[(1, 2), (1, 2)]], 2)
            ]
  where
    codecReads (name, signedPairs, _) = it (name <> ": the datum codec reads back a datum that carries the signed pairs") $ do
        s <- scenarioOf [(name, deposit)]
        export <- case scExports s of
            [e] -> pure e
            _ -> fail "one request was expected"
        signedThreshold <-
            either
                (\e -> fail ("the signed bytes do not decode: " <> show e))
                (either fail pure . parseThresholdSpelling . deeNt)
                (decodeEstablishmentEvent (reEventBytes (inceptionEvidence export)))
        let literalDatum =
                asPlcData
                    ( V2
                        ( liveOfInception
                            ""
                            0
                            (inceptionDatum export){cdNextThreshold = signedThreshold}
                            (inceptionQualified export)
                        )
                    )
        fmap (\d -> case d of V2 Live{lvKeys} -> pairs (kmNextThreshold lvKeys); _ -> []) (checkpointDatumFromData literalDatum)
            `shouldBe` Just signedPairs
    row (name, signedPairs, commitments) = it name $ do
        s <- scenarioOf [(name, deposit)]
        (export, record) <- case (scExports s, scRecords s) of
            ([e], [r]) -> pure (e, r)
            _ -> fail "one request was expected"
        let evidence = inceptionEvidence export
        event <- either (\e -> fail ("the signed bytes do not decode: " <> show e)) pure (decodeEstablishmentEvent (reEventBytes evidence))
        -- the signed spelling, literally
        signedThreshold <- either fail pure (parseThresholdSpelling (deeNt event))
        -- the datum the builder created, as the codec reads it
        (nextKeys, datumThreshold) <- case checkpointDatumFromData (requestInitialDatum record) of
            Just (V2 Live{lvKeys}) -> pure (kmNextKeys lvKeys, kmNextThreshold lvKeys)
            _ -> fail "the initial datum of the booking record is not read back by the codec"
        -- the datum a fixture would hold if the signed weights were kept as they are
        let literalDatum =
                asPlcData
                    ( V2
                        ( liveOfInception
                            ""
                            0
                            (inceptionDatum export){cdNextThreshold = signedThreshold}
                            (inceptionQualified export)
                        )
                    )
            literalReadBack = void (checkpointDatumFromData literalDatum)
        putStrLn $
            "  "
                <> name
                <> ": signed nt "
                <> B8.unpack (deeNt event)
                <> " = "
                <> show (pairs signedThreshold)
                <> "; fixture datum with the signed weights "
                <> show (pairs signedThreshold)
                <> ", read back by the codec: "
                <> show literalReadBack
                <> "; builder datum "
                <> show (pairs datumThreshold)
                <> "; indexed controller signatures "
                <> show (map fst (reCtrlSigs evidence))
                <> "; ordered commitments "
                <> show (map (BS.take 6) nextKeys)
                <> " ("
                <> show (length nextKeys)
                <> ")"
        pairs signedThreshold `shouldBe` signedPairs
        -- the builder's datum carries the signed pairs, literally
        pairs datumThreshold `shouldBe` signedPairs
        datumThreshold `shouldBe` signedThreshold
        length nextKeys `shouldBe` commitments
        -- the commitments are the signed ones, in order, as 32 raw bytes
        nextKeys `shouldBe` cdNextKeys (inceptionDatum export)
