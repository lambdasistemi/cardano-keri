{- |
Module      : Cardano.KERI.AID.Checkpoint.WireSpec
Description : A-045 — the off-chain wire spelling of indexed signatures

The off-chain\/on-chain encoding boundary that PR #132's PV11
lifecycle failure ran into: Aiken spells a tuple @(Int, ByteArray)@
as a Plutus __list__ of exactly two items, so every
@List<(Int, ByteArray)>@ signature collection
("Cardano.KERI.AID.Checkpoint.Wire") must encode each element as
@List [I index, B signature]@. Encoding it as a record-shaped
@Constr 0 [I index, B signature]@ makes the observer's @unListData@
abort on the very first element.

One example per production call site of the shared element encoder —
registration controller signatures and witness receipts, advance
controller signatures and witness receipts, enforcement controller
signatures and witness signatures — plus the assembled registration
observer envelope. The per-site split is deliberate: the shared
helper fixes all six at once, but a correction inlined at a single
call site does not, and grouped assertions would let such a partial
fix pass.

Every signature collection under test is non-empty. The failing live
vector carried @wit_receipts = []@, and an empty list encodes
identically under both the correct and the incorrect element
spelling, so an inherited empty fixture would look covered while
testing nothing.
-}
module Cardano.KERI.AID.Checkpoint.WireSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceEvidenceData,
    enforcementEvidenceData,
    registerObserverRedeemerData,
    registrationEvidenceData,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import PlutusCore.Data (Data (..))
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------
-- Deterministic fixtures
-- ---------------------------------------------------------

-- | A deterministic 64-byte Ed25519 signature body.
signatureOf :: Word -> ByteString
signatureOf tag = BS.replicate 64 (fromIntegral tag)

ctrlSigA, ctrlSigB, witSigA :: ByteString
ctrlSigA = signatureOf 0xa1
ctrlSigB = signatureOf 0xa2
witSigA = signatureOf 0xb1

-- | The 28-byte checkpoint policy id carried by the observer claim.
checkpointPolicy :: ByteString
checkpointPolicy = BS.replicate 28 0xc0

{- | Minimal registration evidence with both signature collections
populated.
-}
registrationEvidence :: RegistrationEvidence
registrationEvidence =
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
        , reCtrlSigs = [(0, ctrlSigA), (1, ctrlSigB)]
        , reWitReceipts = [(0, witSigA)]
        }

-- | Minimal advance evidence with both signature collections populated.
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
        , aeWitCut = []
        , aeWitAdd = []
        , aeCtrlSigs = [(0, ctrlSigA), (1, ctrlSigB)]
        , aeWitReceipts = [(0, witSigA)]
        }

{- | Minimal enforcement evidence with both signature collections
populated.
-}
enforcementEvidence :: EnforcementEvidence
enforcementEvidence =
    EnforcementEvidence
        { eneEventBytes = "rot"
        , eneOffT = 1
        , eneOffI = 2
        , eneOffS = 3
        , eneOffD = 4
        , eneOffK = [5]
        , eneOffKt = 6
        , eneOffN = [7]
        , eneOffNt = 8
        , eneOffBt = 9
        , eneNativeSn = 1
        , eneSaid = "said"
        , eneRevealedKeys = []
        , eneNextKeys = []
        , eneCurThreshold = Unweighted 1
        , eneNextThreshold = Unweighted 1
        , eneToad = 0
        , eneCtrlSigs = [(0, ctrlSigA), (1, ctrlSigB)]
        , eneWitSigs = [(0, witSigA)]
        }

-- ---------------------------------------------------------
-- Structural readers over the encoded Data
-- ---------------------------------------------------------

-- | The field list of an evidence record encoded as a Plutus constructor.
recordFields :: Data -> [Data]
recordFields (Constr _ fields) = fields
recordFields other = [other]

{- | The elements of the signature collection sitting at field @index@ of
an evidence record. A non-list collection is surfaced as a single
element so the assertion reports the shape it actually found.
-}
signatureElements :: Int -> Data -> [Data]
signatureElements index evidence =
    case drop index (recordFields evidence) of
        (List elements : _) -> elements
        (other : _) -> [other]
        [] -> []

-- | The observer envelope's claim triple.
envelopeClaim :: Data -> Data
envelopeClaim (Constr _ (claim : _)) = claim
envelopeClaim other = other

-- | The observer envelope's evidence payload.
envelopePayload :: Data -> Data
envelopePayload (Constr _ [_, payload]) = payload
envelopePayload other = other

{- | The expected spelling of an indexed signature: an Aiken tuple, which
is a Plutus list of exactly two items.
-}
indexedSignature :: Integer -> ByteString -> Data
indexedSignature index signature = List [I index, B signature]

-- ---------------------------------------------------------
-- Spec
-- ---------------------------------------------------------

spec :: Spec
spec = describe "A-045 checkpoint wire encoding" $ do
    it "1. registrationEvidenceData encodes ctrl_sigs elements as two-item Data lists" $
        signatureElements 10 (registrationEvidenceData registrationEvidence)
            `shouldBe` [ indexedSignature 0 ctrlSigA
                       , indexedSignature 1 ctrlSigB
                       ]

    it "2. registrationEvidenceData encodes non-empty wit_receipts elements as two-item Data lists" $
        signatureElements 11 (registrationEvidenceData registrationEvidence)
            `shouldBe` [indexedSignature 0 witSigA]

    it "3. advanceEvidenceData encodes ctrl_sigs elements as two-item Data lists" $
        signatureElements 13 (advanceEvidenceData advanceEvidence)
            `shouldBe` [ indexedSignature 0 ctrlSigA
                       , indexedSignature 1 ctrlSigB
                       ]

    it "4. advanceEvidenceData encodes non-empty wit_receipts elements as two-item Data lists" $
        signatureElements 14 (advanceEvidenceData advanceEvidence)
            `shouldBe` [indexedSignature 0 witSigA]

    it "5. enforcementEvidenceData encodes ctrl_sigs elements as two-item Data lists" $
        signatureElements 17 (enforcementEvidenceData enforcementEvidence)
            `shouldBe` [ indexedSignature 0 ctrlSigA
                       , indexedSignature 1 ctrlSigB
                       ]

    it "6. enforcementEvidenceData encodes non-empty wit_sigs elements as two-item Data lists" $
        signatureElements 18 (enforcementEvidenceData enforcementEvidence)
            `shouldBe` [indexedSignature 0 witSigA]

    it "7. registerObserverRedeemerData nests a 12-field evidence record whose signature elements are two-item Data lists" $ do
        let envelope =
                registerObserverRedeemerData checkpointPolicy registrationEvidence
            payload = envelopePayload envelope
        envelopeClaim envelope
            `shouldBe` Constr 0 [I 0, B checkpointPolicy, Constr 1 []]
        length (recordFields payload) `shouldBe` 12
        signatureElements 10 payload
            `shouldBe` [ indexedSignature 0 ctrlSigA
                       , indexedSignature 1 ctrlSigB
                       ]
        signatureElements 11 payload
            `shouldBe` [indexedSignature 0 witSigA]
