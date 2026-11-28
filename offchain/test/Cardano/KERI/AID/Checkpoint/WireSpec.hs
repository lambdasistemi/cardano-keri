{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.WireSpec
Description : Offline regression for the Register observer wire
-}
module Cardano.KERI.AID.Checkpoint.WireSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.BountyCommitment (BountyRevealV1 (..))
import Cardano.KERI.AID.Checkpoint.Datum (KeyMaterial (..))
import Cardano.KERI.AID.Checkpoint.Deposit (BondOption (..))
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Entitlement (EnforcementProofV1 (..))
import Cardano.KERI.AID.Checkpoint.Freeze (FreezeEvidence (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceEvidenceData,
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    bookingAttestationBurnData,
    bookingAttestationClaimData,
    bookingAttestationIssueData,
    bookingAttestationName,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    enforcementEvidenceData,
    enforcementProofData,
    freezeEvidenceData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
    registerObserverRedeemerData,
    registrationEvidenceData,
    topUpSpendRedeemerData,
 )
import Cardano.KERI.AID.Migration.Types (OutputRef (..))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinByteString (..), BuiltinData (..), serialiseData)
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

evidence :: RegistrationEvidence
evidence =
    RegistrationEvidence
        { reEventBytes = "icp"
        , reCtrlSigs = [(0, BS.replicate 64 0xa1)]
        , reWitReceipts = [(1, BS.replicate 64 0xb1)]
        }

-- | A second request's evidence: every field differs from 'evidence'.
otherEvidence :: RegistrationEvidence
otherEvidence =
    RegistrationEvidence
        { reEventBytes = "icq"
        , reCtrlSigs = [(1, BS.replicate 64 0xa2), (2, BS.replicate 64 0xb2)]
        , reWitReceipts = []
        }

advanceEvidence :: AdvanceEvidence
advanceEvidence =
    AdvanceEvidence
        { aeEventBytes = "rot"
        , aeWitCut = ["cut"]
        , aeWitAdd = ["add"]
        , aeCtrlSigs = [(0, BS.replicate 64 0xc1)]
        , aeWitReceipts = [(1, BS.replicate 64 0xd1)]
        }

enforcementEvidence :: EnforcementEvidence
enforcementEvidence =
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
enforcementProof :: EnforcementProofV1
enforcementProof =
    EnforcementProofV1
        { epEvidence = enforcementEvidence
        , epPayeePkh = BS.replicate 28 0x9a
        , epReveal =
            BountyRevealV1
                { brCommitmentRef = OutputRef (BS.replicate 32 0x0c) 0
                , brNonce = BS.replicate 32 0x11
                , brRefundIndex = 1
                }
        }

freezeEvidence :: FreezeEvidence
freezeEvidence =
    FreezeEvidence
        { feRotatedKeys =
            KeyMaterial
                { kmCurKeys = [BS.replicate 32 0x01]
                , kmCurThreshold = Unweighted 1
                , kmNextKeys = [BS.replicate 32 0x02]
                , kmNextThreshold = Unweighted 1
                , kmWitnesses = []
                , kmToad = 0
                }
        , feRotatedSn = 6
        , feRotation = advanceEvidence
        }

spec :: Spec
spec = describe "#136 Register observer wire" $ do
    it "encodes both indexed-signature collections as lists of two-item lists" $
        registrationEvidenceData evidence
            `shouldBe` Constr
                0
                [ B "icp"
                , List [List [I 0, B (BS.replicate 64 0xa1)]]
                , List [List [I 1, B (BS.replicate 64 0xb1)]]
                ]

    it "nests the exact claim and three-field evidence shape the validators read" $
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

    it "nests the Issue redeemer and keeps each booked request with its own evidence" $
        bookingAttestationIssueData (BS.replicate 28 0xc0) [(3, evidence), (5, otherEvidence)]
            `shouldBe` Constr
                0
                [ B (BS.replicate 28 0xc0)
                , List
                    [ Constr 0 [I 3, registrationEvidenceData evidence]
                    , Constr 0 [I 5, registrationEvidenceData otherEvidence]
                    ]
                ]

    it "does not move the evidence of a request to another request's index" $
        bookingAttestationIssueData (BS.replicate 28 0xc0) [(3, evidence), (5, otherEvidence)]
            `shouldNotBe` bookingAttestationIssueData (BS.replicate 28 0xc0) [(3, otherEvidence), (5, evidence)]

    it "encodes Burn as constructor one with no field" $
        bookingAttestationBurnData `shouldBe` Constr 1 []

    it "writes, for two booked requests with distinct evidence, the three-field bytes (the nine offsets of the earlier layout removed from both records, every other byte unchanged)" $
        let BuiltinByteString bytes =
                serialiseData
                    ( BuiltinData
                        ( bookingAttestationIssueData
                            (BS.replicate 28 0xc0)
                            [(3, evidence), (5, otherEvidence)]
                        )
                    )
         in convertToBase Base16 bytes
                `shouldBe` ("d8799f581cc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c09fd8799f03d8799f436963709f9f005840a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1ffff9f9f015840b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1ffffffffd8799f05d8799f436963719f9f015840a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2ff9f025840b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ffff80ffffffff" :: BS.ByteString)

    it "writes the claim of a booking and the name that digests it as the validators do" $ do
        let claim =
                bookingAttestationClaimData
                    (BS.replicate 28 0xc0)
                    3
                    (Constr 1 [B "initial", I 7])
                    1_009_000_000
            BuiltinByteString bytes = serialiseData (BuiltinData claim)
        convertToBase Base16 bytes
            `shouldBe` ("d8799f582163617264616e6f2d6b6572692f626f6f6b2d726567697374726174696f6e2f7631581cc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c003d87a9f47696e697469616c07ff1a3c241e40ff" :: BS.ByteString)
        convertToBase
            Base16
            ( bookingAttestationName
                (BS.replicate 28 0xc0)
                3
                (Constr 1 [B "initial", I 7])
                1_009_000_000
            )
            `shouldBe` ("4364c47043472214a864ab1e196061b4b0c00066407ec312ca2b94381e9ea934" :: BS.ByteString)

    it "encodes the Advance arm at spend constructor zero with its payee output index and the keep option" $
        advanceSpendRedeemerData 4 Keep
            `shouldBe` Constr 0 [I 4, Constr 0 []]

    it "encodes the Advance arm with the deposit option and its signatures" $
        advanceSpendRedeemerData 4 (Deposit [(1, BS.replicate 64 0xa1)])
            `shouldBe` Constr
                0
                [ I 4
                , Constr 1 [List [List [I 1, B (BS.replicate 64 0xa1)]]]
                ]

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

    it "encodes Advance signature tuples as two-item lists" $
        advanceEvidenceData advanceEvidence
            `shouldBe` Constr
                0
                [ B "rot"
                , List [B "cut"]
                , List [B "add"]
                , List [List [I 0, B (BS.replicate 64 0xc1)]]
                , List [List [I 1, B (BS.replicate 64 0xd1)]]
                ]

    it "S254-E pins the EnforcementProofV1 field order as wire surface" $
        enforcementProofData enforcementProof
            `shouldBe` Constr
                0
                [ enforcementEvidenceData enforcementEvidence
                , B (BS.replicate 28 0x9a)
                , Constr
                    0
                    [ Constr 0 [B (BS.replicate 32 0x0c), I 0]
                    , B (BS.replicate 32 0x11)
                    , I 1
                    ]
                ]

    it "encodes enforcement signature tuples as two-item lists" $
        enforcementEvidenceData enforcementEvidence
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

    it "puts Convict at spend constructor one with its convictor and payout index" $
        convictSpendRedeemerData (BS.replicate 28 0x51) 3
            `shouldBe` Constr
                1
                [ B (BS.replicate 28 0x51)
                , I 3
                ]

    it "forwards the witnessed-conflict proof under isolated observer action four" $
        convictObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xf1)
            11
            enforcementProof
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
                , enforcementProofData enforcementProof
                ]

    it "appends the Freeze arm at spend constructor three, after the retired migration index" $
        freezeSpendRedeemerData 5 `shouldBe` Constr 3 [I 5]

    it "appends the TopUp arm at spend constructor four, after Freeze" $
        topUpSpendRedeemerData 2_000_000 `shouldBe` Constr 4 [I 2_000_000]

    it "encodes the freeze evidence as the rotated keys, their sequence number and the rotation" $
        freezeEvidenceData freezeEvidence
            `shouldBe` Constr
                0
                [ Constr
                    0
                    [ List [B (BS.replicate 32 0x01)]
                    , Constr 0 [I 1]
                    , List [B (BS.replicate 32 0x02)]
                    , Constr 0 [I 1]
                    , List []
                    , I 0
                    ]
                , I 6
                , advanceEvidenceData advanceEvidence
                ]

    it "forwards the freeze evidence in the observer envelope under action two for the named input" $
        freezeObserverRedeemerData
            (BS.replicate 28 0xc0)
            (BS.replicate 32 0xe0)
            7
            freezeEvidence
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
                            [ B (BS.replicate 32 0xe0)
                            , I 7
                            ]
                        ]
                    ]
                , freezeEvidenceData freezeEvidence
                ]
