{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.WireSpec
Description : Offline regression for the Register observer wire
-}
module Cardano.KERI.AID.Checkpoint.WireSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    registerObserverRedeemerData,
    registrationEvidenceData,
 )
import Data.ByteString qualified as BS
import PlutusCore.Data (Data (..))
import Test.Hspec (Spec, describe, it, shouldBe)

evidence :: RegistrationEvidence
evidence =
    RegistrationEvidence
        { reEventBytes = "icp"
        , reOffT = 1
        , reOffI = 2
        , reOffS = 3
        , reOffK = [4]
        , reOffKt = 5
        , reOffN = [6]
        , reOffNt = 7
        , reOffB = [8]
        , reOffBt = 9
        , reCtrlSigs = [(0, BS.replicate 64 0xa1)]
        , reWitReceipts = [(1, BS.replicate 64 0xb1)]
        }

spec :: Spec
spec = describe "#136 Register observer wire" $ do
    it "encodes both indexed-signature collections as lists of two-item lists" $
        registrationEvidenceData evidence
            `shouldBe` Constr
                0
                [ B "icp"
                , I 1
                , I 2
                , I 3
                , List [I 4]
                , I 5
                , List [I 6]
                , I 7
                , List [I 8]
                , I 9
                , List [List [I 0, B (BS.replicate 64 0xa1)]]
                , List [List [I 1, B (BS.replicate 64 0xb1)]]
                ]

    it "nests the exact claim and 12-field evidence shape consumed live" $
        registerObserverRedeemerData (BS.replicate 28 0xc0) evidence
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ I 0
                    , B (BS.replicate 28 0xc0)
                    , Constr 1 []
                    ]
                , registrationEvidenceData evidence
                ]
