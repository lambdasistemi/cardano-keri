{- |
Module      : Cardano.KERI.AID.Checkpoint.CloseSpec
Description : #117 S1 Close message bytes and controller authorization

RED-first tests for the validator-free Close model.  The message golden fixes
constructor 0, all ten fields, and the byte-for-byte Plutus Data encoding of a
full refund address with a staking credential.  Authorization exercises the
ordinary two-key shape and the full GLEIF seven-key weighted shape, then proves
that malformed OLD, insufficient/distorted evidence, reconstructed-field
mutation, and fresh-outref replay all reject.
-}
module Cardano.KERI.AID.Checkpoint.CloseSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    CloseContext (..),
    CloseEvidence (..),
    CloseMessage (..),
    ClosePredicateError (..),
    FullAddress (..),
    StakeCredential (..),
    closeDomain,
    closePredicate,
    closeSpendRedeemerData,
    reconstructCloseMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (decodeHex)
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = do
    describe "Close message wire contract" $ do
        it "freezes the v1 domain and all ten reconstructed fields" $ do
            closeDomain `shouldBe` "cardano-keri/checkpoint/close/v1"
            let CloseMessage{..} = reconstructCloseMessage twoKeyContext twoKeyEvidence
            cmDomain `shouldBe` closeDomain
            cmNetworkId `shouldBe` 1
            cmCheckpointPolicyId `shouldBe` policyId
            cmAidAssetName `shouldBe` deriveAidAssetName aid
            cmCesrAid `shouldBe` aid
            cmSpentTxid `shouldBe` spentTxid
            cmSpentIndex `shouldBe` 3
            cmPriorSeq `shouldBe` 5
            cmPriorNativeSn `shouldBe` 9
            cmRefundAddress `shouldBe` refundAddress

        it "encodes the full refund address byte-for-byte as Aiken Address" $
            canonicalCbor refundAddress `shouldBe` goldenRefundAddressCbor

        it "encodes constructor 0 and the exact ten-field order canonically" $
            canonicalCbor (reconstructCloseMessage twoKeyContext twoKeyEvidence)
                `shouldBe` goldenCloseMessageCbor

        it "encodes Close signature tuples as two-item lists for Aiken" $
            closeSpendRedeemerData twoKeyEvidence
                `shouldBe` Constr
                    0
                    [ Constr
                        0
                        [ Constr
                            0
                            [ Constr 0 [B (BS.replicate 28 0x44)]
                            , Constr
                                0
                                [ Constr
                                    0
                                    [Constr 1 [B (BS.replicate 28 0x55)]]
                                ]
                            ]
                        , List
                            [ List [I (fromIntegral index), B signature]
                            | (index, signature) <- ceCtrlSigs twoKeyEvidence
                            ]
                        ]
                    ]

    describe "Close current-controller authorization" $ do
        it "accepts the ordinary two-key threshold" $
            closePredicate twoKeyContext twoKeyEvidence `shouldBe` Right ()

        it "accepts the full GLEIF seven-key weighted threshold" $
            closePredicate gleifContext gleifEvidence `shouldBe` Right ()

        it "rejects malformed OLD before signature authorization" $
            closePredicate
                ( twoKeyContext
                    { ccOld = (ccOld twoKeyContext){cdCesrAid = BS.replicate 31 0xAA}
                    }
                )
                twoKeyEvidence
                `shouldBe` Left CloseDatumInvalid

        it "rejects below-threshold controller evidence" $
            closePredicate
                twoKeyContext
                twoKeyEvidence{ceCtrlSigs = take 1 (ceCtrlSigs twoKeyEvidence)}
                `shouldBe` Left CloseControllerQuorumUnsatisfied

        it "rejects negative and out-of-range signature indices" $ do
            let (_, sig0) = firstIndexedSignature twoKeyEvidence
            closePredicate twoKeyContext twoKeyEvidence{ceCtrlSigs = [(-1, sig0)]}
                `shouldBe` Left CloseControllerQuorumUnsatisfied
            closePredicate twoKeyContext twoKeyEvidence{ceCtrlSigs = [(99, sig0)]}
                `shouldBe` Left CloseControllerQuorumUnsatisfied

        it "counts a duplicate valid index once" $ do
            let sig0 = firstIndexedSignature twoKeyEvidence
            closePredicate twoKeyContext twoKeyEvidence{ceCtrlSigs = [sig0, sig0]}
                `shouldBe` Left CloseControllerQuorumUnsatisfied

        it "rejects when a distinct in-range index carries the wrong key" $ do
            let outsider = signer 0xF0
                (_, sig0) = firstIndexedSignature twoKeyEvidence
                forged = (1, signOver outsider (closePreimage twoKeyContext twoKeyEvidence))
            closePredicate
                twoKeyContext
                twoKeyEvidence{ceCtrlSigs = [(0, sig0), forged]}
                `shouldBe` Left CloseControllerQuorumUnsatisfied

        it "binds every reconstructed deployment, datum, and outref field" $
            mapM_
                ( \mutated ->
                    closePredicate mutated twoKeyEvidence
                        `shouldBe` Left CloseControllerQuorumUnsatisfied
                )
                [ twoKeyContext{ccNetworkId = 0}
                , twoKeyContext{ccCheckpointPolicyId = BS.replicate 28 0xCD}
                , twoKeyContext
                    { ccOld = (ccOld twoKeyContext){cdCesrAid = BS.replicate 32 0xAB}
                    }
                , twoKeyContext{ccSpentTxid = BS.replicate 32 0xD2}
                , twoKeyContext{ccSpentIndex = 4}
                , twoKeyContext
                    { ccOld = (ccOld twoKeyContext){cdSeq = 6}
                    }
                , twoKeyContext
                    { ccOld = (ccOld twoKeyContext){cdNativeSn = 10}
                    }
                ]

        it "binds the complete refund address, including staking credential" $ do
            let redirected =
                    twoKeyEvidence
                        { ceRefundAddress =
                            refundAddress
                                { faStakeCredential = Nothing
                                }
                        }
            closePredicate twoKeyContext redirected
                `shouldBe` Left CloseControllerQuorumUnsatisfied

        it "rejects replay against a fresh registration outref" $
            closePredicate
                ( twoKeyContext
                    { ccSpentTxid = BS.replicate 32 0xE1
                    , ccSpentIndex = 0
                    }
                )
                twoKeyEvidence
                `shouldBe` Left CloseControllerQuorumUnsatisfied

policyId :: ByteString
policyId = BS.replicate 28 0xCC

aid :: ByteString
aid = BS.replicate 32 0xAA

spentTxid :: ByteString
spentTxid = BS.replicate 32 0xD1

refundAddress :: FullAddress
refundAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential (BS.replicate 28 0x44)
        , faStakeCredential =
            Just (InlineStakeCredential (ScriptCredential (BS.replicate 28 0x55)))
        }

goldenRefundAddressCbor :: ByteString
goldenRefundAddressCbor =
    hex
        "d8799fd8799f581c44444444444444444444444444444444444444444444444444444444ffd8799fd8799fd87a9f581c55555555555555555555555555555555555555555555555555555555ffffffff"

goldenCloseMessageCbor :: ByteString
goldenCloseMessageCbor =
    hex
        "d8799f582063617264616e6f2d6b6572692f636865636b706f696e742f636c6f73652f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c2361ae6e0e735e83aaf94c3d6376854ba7808da9757eb7a20c5a6439b55b2685820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5820d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1030509d8799fd8799f581c44444444444444444444444444444444444444444444444444444444ffd8799fd8799fd87a9f581c55555555555555555555555555555555555555555555555555555555ffffffffff"

twoKeySigners :: [SignKeyDSIGN Ed25519DSIGN]
twoKeySigners = map signer [0x01, 0x02]

gleifSigners :: [SignKeyDSIGN Ed25519DSIGN]
gleifSigners = map signer [0x11 .. 0x17]

twoKeyContext :: CloseContext
twoKeyContext = context (Unweighted 2) twoKeySigners

gleifContext :: CloseContext
gleifContext =
    context
        (Weighted [replicate 7 (Weight 1 3)])
        gleifSigners

context :: Threshold -> [SignKeyDSIGN Ed25519DSIGN] -> CloseContext
context threshold signers =
    CloseContext
        { ccNetworkId = 1
        , ccCheckpointPolicyId = policyId
        , ccSpentTxid = spentTxid
        , ccSpentIndex = 3
        , ccOld =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = map verkeyOf signers
                , cdCurThreshold = threshold
                , cdNextKeys = [BS.replicate 32 0x77]
                , cdNextThreshold = Unweighted 1
                , cdWitnesses = []
                , cdToad = 0
                , cdSeq = 5
                , cdNativeSn = 9
                }
        }

twoKeyEvidence :: CloseEvidence
twoKeyEvidence = signedEvidence twoKeyContext twoKeySigners

gleifEvidence :: CloseEvidence
gleifEvidence = signedEvidence gleifContext (take 3 gleifSigners)

signedEvidence :: CloseContext -> [SignKeyDSIGN Ed25519DSIGN] -> CloseEvidence
signedEvidence ctx signers = evidence
  where
    evidence =
        CloseEvidence
            { ceRefundAddress = refundAddress
            , ceCtrlSigs =
                [ (idx, signOver sk (closePreimage ctx evidence))
                | (idx, sk) <- zip [0 ..] signers
                ]
            }

closePreimage :: CloseContext -> CloseEvidence -> ByteString
closePreimage ctx = canonicalCbor . reconstructCloseMessage ctx

signer :: Word -> SignKeyDSIGN Ed25519DSIGN
signer byte = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 (fromIntegral byte)))

verkeyOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
verkeyOf = rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN

signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver sk msg = rawSerialiseSigDSIGN (signDSIGN () msg sk)

firstIndexedSignature :: CloseEvidence -> (Int, ByteString)
firstIndexedSignature evidence = case ceCtrlSigs evidence of
    signature : _ -> signature
    [] -> error "Close fixture unexpectedly has no controller signatures"

hex :: Text -> ByteString
hex encoded = case decodeHex encoded of
    Right bytes -> bytes
    Left err -> error err
