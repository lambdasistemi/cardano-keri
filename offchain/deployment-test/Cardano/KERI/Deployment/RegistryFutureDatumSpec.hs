{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFutureDatumSpec
Description : The datum the builder creates for a weighted future declaration, against the signed bytes

For the three keripy inceptions of Q-069's flat weighted rows the booking record is built by the
production constructors and its initial datum decoded: the ordered commitments, and the literal
numerator and denominator of every weight, set beside the pairs of the signed event. Three things
are kept apart for the literal @2/4@ row: the signed spelling (@2/4@), the datum a fixture would
carry if the weights were not reduced (@2/4@, which the datum codec cannot read back), and the datum
the builder creates (@1/2@).
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
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..), normaliseWeights, parseThresholdSpelling)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (Scenario (..), scenarioOf)
import Cardano.KERI.Deployment.RegistryTransactionsSpec (deposit)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

pairs :: Threshold -> [[(Integer, Integer)]]
pairs = \case
    Weighted clauses -> map (map (\(Weight n d) -> (n, d))) clauses
    Unweighted m -> [[(m, 1)]]

spec :: Spec
spec =
    describe "the builder-created datum of a weighted future declaration, against the signed bytes (Q-069)" $
        mapM_
            row
            [ ("future:D next unreduced", [[(2, 4), (2, 4)]], [[(1, 2), (1, 2)]], 2)
            , ("future:D next partial coverage", [[(1, 1)], [(1, 1)]], [[(1, 1)], [(1, 1)]], 3)
            , ("future:D next exact one", [[(1, 2), (1, 2)]], [[(1, 2), (1, 2)]], 2)
            ]
  where
    row (name, signedPairs, datumPairs, commitments) = it name $ do
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
        pairs datumThreshold `shouldBe` datumPairs
        datumThreshold `shouldBe` normaliseWeights signedThreshold
        length nextKeys `shouldBe` commitments
        -- the commitments are the signed ones, in order, as 32 raw bytes
        nextKeys `shouldBe` cdNextKeys (inceptionDatum export)
        case literalReadBack of
            Nothing | signedPairs /= datumPairs -> pure ()
            Just () | signedPairs == datumPairs -> pure ()
            other -> expectationFailure ("the codec reads the literal weights as " <> show other)
