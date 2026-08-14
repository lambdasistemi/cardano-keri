{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.WireSpec
Description : Offline regression for the Register observer wire
-}
module Cardano.KERI.AID.Checkpoint.WireSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.BountyCommitment (BountyRevealV1 (..))
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Entitlement (EnforcementProofV1 (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceEvidenceData,
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    claimFreezeSpendRedeemerData,
    convictBurnRedeemerData,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    enforcementEvidenceData,
    enforcementProofData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
    registerObserverRedeemerData,
    registrationEvidenceData,
    responseAdvanceObserverRedeemerData,
 )
import Cardano.KERI.AID.Migration.Types (OutputRef (..))
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

advanceEvidence :: AdvanceEvidence
advanceEvidence =
    AdvanceEvidence
        { aeEventBytes = "rot"
        , aeOffT = 1
        , aeOffI = 2
        , aeOffS = 3
        , aeOffK = [4]
        , aeOffKt = 5
        , aeOffN = [6]
        , aeOffNt = 7
        , aeOffBr = [8]
        , aeOffBa = [9]
        , aeOffBt = 10
        , aeWitCut = ["cut"]
        , aeWitAdd = ["add"]
        , aeCtrlSigs = [(0, BS.replicate 64 0xc1)]
        , aeWitReceipts = [(1, BS.replicate 64 0xd1)]
        }

freezeEvidence :: EnforcementEvidence
freezeEvidence =
    EnforcementEvidence
        { eneEventBytes = "rot-2-conflict"
        , eneOffT = 1
        , eneOffI = 2
        , eneOffS = 3
        , eneOffD = 4
        , eneOffK = [5, 6]
        , eneOffKt = 7
        , eneOffN = [8, 9]
        , eneOffNt = 10
        , eneOffBt = 11
        , eneNativeSn = 2
        , eneSaid = BS.replicate 32 0xa2
        , eneRevealedKeys = [BS.replicate 32 0xb2, BS.replicate 32 0xb3]
        , eneNextKeys = [BS.replicate 32 0xc2, BS.replicate 32 0xc3]
        , eneCurThreshold = Unweighted 2
        , eneNextThreshold = Unweighted 2
        , eneToad = 2
        , eneCtrlSigs =
            [ (0, BS.replicate 64 0xd2)
            , (1, BS.replicate 64 0xd3)
            ]
        , eneWitSigs =
            [ (0, BS.replicate 64 0xe2)
            , (2, BS.replicate 64 0xe3)
            ]
        }

{- | S254-E: the enforcement observer no longer carries bare evidence.  The
proof adds the payee the register will bind and the reveal that names the
reservation earning it.
-}
freezeProof :: EnforcementProofV1
freezeProof =
    EnforcementProofV1
        { epEvidence = freezeEvidence
        , epPayeePkh = BS.replicate 28 0x9a
        , epReveal =
            BountyRevealV1
                { brCommitmentRef = OutputRef (BS.replicate 32 0x0c) 0
                , brNonce = BS.replicate 32 0x11
                , brRefundIndex = 1
                }
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

    it "encodes the small Advance arm without changing Close constructor zero" $
        advanceSpendRedeemerData
            `shouldBe` Constr 1 []

    it "forwards Advance evidence in the observer envelope for the named input" $
        advanceObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xe0)
            7
            advanceEvidence
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ I 1
                    , B (BS.replicate 28 0xc0)
                    , Constr
                        0
                        [ Constr
                            0
                            [ B (BS.replicate 32 0xe0)
                            , I 7
                            ]
                        ]
                    ]
                , advanceEvidenceData advanceEvidence
                ]

    it "uses action three to route an Armed response Advance" $
        responseAdvanceObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xe0)
            7
            advanceEvidence
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ I 3
                    , B (BS.replicate 28 0xc0)
                    , Constr
                        0
                        [ Constr
                            0
                            [ B (BS.replicate 32 0xe0)
                            , I 7
                            ]
                        ]
                    ]
                , advanceEvidenceData advanceEvidence
                ]

    it "encodes Advance signature tuples as two-item lists" $
        advanceEvidenceData advanceEvidence
            `shouldBe` Constr
                0
                [ B "rot"
                , I 1
                , I 2
                , I 3
                , List [I 4]
                , I 5
                , List [I 6]
                , I 7
                , List [I 8]
                , List [I 9]
                , I 10
                , List [B "cut"]
                , List [B "add"]
                , List [List [I 0, B (BS.replicate 64 0xc1)]]
                , List [List [I 1, B (BS.replicate 64 0xd1)]]
                ]

    it "encodes the thin Freeze arm without opening ClaimFreeze" $
        freezeSpendRedeemerData (BS.replicate 28 0x42)
            `shouldBe` Constr 2 [B (BS.replicate 28 0x42)]

    it "opens only ClaimFreeze at constructor three with its payout index" $
        claimFreezeSpendRedeemerData 5
            `shouldBe` Constr 3 [I 5]

    it "forwards the exact Freeze proof under observer action two" $
        freezeObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xf0)
            9
            freezeProof
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ I 2
                    , B (BS.replicate 28 0xc0)
                    , Constr
                        0
                        [ Constr
                            0
                            [ B (BS.replicate 32 0xf0)
                            , I 9
                            ]
                        ]
                    ]
                , enforcementProofData freezeProof
                ]

    it "S254-E pins the EnforcementProofV1 field order as wire surface" $
        enforcementProofData freezeProof
            `shouldBe` Constr
                0
                [ enforcementEvidenceData freezeEvidence
                , B (BS.replicate 28 0x9a)
                , Constr
                    0
                    [ Constr 0 [B (BS.replicate 32 0x0c), I 0]
                    , B (BS.replicate 32 0x11)
                    , I 1
                    ]
                ]

    it "encodes enforcement signature tuples as two-item lists" $
        enforcementEvidenceData freezeEvidence
            `shouldBe` Constr
                0
                [ B "rot-2-conflict"
                , I 1
                , I 2
                , I 3
                , I 4
                , List [I 5, I 6]
                , I 7
                , List [I 8, I 9]
                , I 10
                , I 11
                , I 2
                , B (BS.replicate 32 0xa2)
                , List [B (BS.replicate 32 0xb2), B (BS.replicate 32 0xb3)]
                , List [B (BS.replicate 32 0xc2), B (BS.replicate 32 0xc3)]
                , Constr 0 [I 2]
                , Constr 0 [I 2]
                , I 2
                , List
                    [ List [I 0, B (BS.replicate 64 0xd2)]
                    , List [I 1, B (BS.replicate 64 0xd3)]
                    ]
                , List
                    [ List [I 0, B (BS.replicate 64 0xe2)]
                    , List [I 2, B (BS.replicate 64 0xe3)]
                    ]
                ]

    it "keeps ConvictBurn at mint constructor two and names the checkpoint input" $
        convictBurnRedeemerData (BS.replicate 32 0xf1) 11
            `shouldBe` Constr
                2
                [ Constr
                    0
                    [ B (BS.replicate 32 0xf1)
                    , I 11
                    ]
                ]

    it "keeps Convict at spend constructor four with exact payout indices" $
        convictSpendRedeemerData (BS.replicate 28 0x51) 3 7
            `shouldBe` Constr
                4
                [ B (BS.replicate 28 0x51)
                , I 3
                , I 7
                ]

    it "forwards the witnessed-conflict proof under isolated observer action four" $
        convictObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xf1)
            11
            freezeProof
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ I 4
                    , B (BS.replicate 28 0xc0)
                    , Constr
                        0
                        [ Constr
                            0
                            [ B (BS.replicate 32 0xf1)
                            , I 11
                            ]
                        ]
                    ]
                , enforcementProofData freezeProof
                ]
