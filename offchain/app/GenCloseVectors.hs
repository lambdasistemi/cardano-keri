{- |
Generate the committed Aiken Close vectors for #117 S1.  Haskell is the sole
owner of fixture keys, signatures, canonical message/address bytes, and verdict
expectations.  The output is formatted by the pinned Aiken tool in the just
recipe and drift-checked in CI.
-}
module Main (main) where

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
    FullAddress (..),
    StakeCredential (..),
    closePredicate,
    reconstructCloseMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Control.Monad (unless)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.List (intercalate)
import System.Environment (getArgs)

main :: IO ()
main = do
    out <-
        getArgs >>= \case
            [path] -> pure path
            _ -> fail "usage: gen-close-vectors OUT_PATH"
    assertFixtures
    writeFile out renderModule

-- ---------------------------------------------------------
-- Canonical fixtures
-- ---------------------------------------------------------

policyId, aid, spentTxid :: ByteString
policyId = BS.replicate 28 0xCC
aid = BS.replicate 32 0xAA
spentTxid = BS.replicate 32 0xD1

refundAddress :: FullAddress
refundAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential (BS.replicate 28 0x44)
        , faStakeCredential =
            Just (InlineStakeCredential (ScriptCredential (BS.replicate 28 0x55)))
        }

redirectedAddress :: FullAddress
redirectedAddress = refundAddress{faStakeCredential = Nothing}

twoKeySigners :: [SignKeyDSIGN Ed25519DSIGN]
twoKeySigners = map repeatedSigner [0x01, 0x02]

-- Actual GLEIF seven-key inception signer seeds from the committed #115
-- keripy fixture, retaining its weighted 1/3-per-position authority shape.
gleifSigners :: [SignKeyDSIGN Ed25519DSIGN]
gleifSigners =
    map
        (genKeyDSIGN . mkSeedFromBytes . decodeHex)
        [ "622253ab1aeeac100eb22c016d520b2a2e87c3be6747e744d7b6d5e6abd6c68e"
        , "ea6656940b12ef17a39b60e96b35ff26a19421a6252d49c5ac2c2b4c69cf4fa9"
        , "c43b8d83aa3d51b532b51185f4911ede999aa9c615e8b2390260658c344e36b6"
        , "375f6c1c7671b197366f3320d1e62f88af4d3f0f2ff78d21e5f58dcaca92b5bc"
        , "36f5e87fb35ca43d0c9edae9b36e4453e93550f28bf3cbf5c07deefc319a5b88"
        , "1be33d49e850c30e4341d9c871950fa594dae4372ab4e9c0baf830577e98fc09"
        , "35d79fa854be1a5b34504e3869ea63f92ccb74abb47e03be965f3ed1cec46a2b"
        ]

twoKeyContext, gleifContext :: CloseContext
twoKeyContext = context (Unweighted 2) twoKeySigners
gleifContext = context (Weighted [replicate 7 (Weight 1 3)]) gleifSigners

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

twoKeyEvidence, gleifEvidence :: CloseEvidence
twoKeyEvidence = signedEvidence twoKeyContext twoKeySigners
gleifEvidence = signedEvidence gleifContext (take 3 gleifSigners)

signedEvidence :: CloseContext -> [SignKeyDSIGN Ed25519DSIGN] -> CloseEvidence
signedEvidence ctx signers = evidence
  where
    evidence =
        CloseEvidence
            { ceRefundAddress = refundAddress
            , ceCtrlSigs =
                [ (index, signOver signer (preimage ctx evidence))
                | (index, signer) <- zip [0 ..] signers
                ]
            }

preimage :: CloseContext -> CloseEvidence -> ByteString
preimage ctx = canonicalCbor . reconstructCloseMessage ctx

firstSignature :: CloseEvidence -> (Int, ByteString)
firstSignature evidence = case ceCtrlSigs evidence of
    signature : _ -> signature
    [] -> error "Close fixture unexpectedly has no signatures"

malformedOldContext :: CloseContext
malformedOldContext =
    twoKeyContext
        { ccOld = (ccOld twoKeyContext){cdCesrAid = BS.replicate 31 0xAA}
        }

belowThresholdEvidence, badIndexEvidence, outOfRangeEvidence :: CloseEvidence
belowThresholdEvidence =
    twoKeyEvidence{ceCtrlSigs = take 1 (ceCtrlSigs twoKeyEvidence)}
badIndexEvidence =
    twoKeyEvidence{ceCtrlSigs = [(-1, snd (firstSignature twoKeyEvidence))]}
outOfRangeEvidence =
    twoKeyEvidence{ceCtrlSigs = [(99, snd (firstSignature twoKeyEvidence))]}

duplicateEvidence, wrongKeyEvidence, redirectedEvidence :: CloseEvidence
duplicateEvidence =
    twoKeyEvidence
        { ceCtrlSigs = replicate 2 (firstSignature twoKeyEvidence)
        }
wrongKeyEvidence =
    twoKeyEvidence
        { ceCtrlSigs =
            [ firstSignature twoKeyEvidence
            , (1, signOver (repeatedSigner 0xF0) (preimage twoKeyContext twoKeyEvidence))
            ]
        }
redirectedEvidence = twoKeyEvidence{ceRefundAddress = redirectedAddress}

mutatedContexts :: [CloseContext]
mutatedContexts =
    [ twoKeyContext{ccNetworkId = 0}
    , twoKeyContext{ccCheckpointPolicyId = BS.replicate 28 0xCD}
    , twoKeyContext
        { ccOld = (ccOld twoKeyContext){cdCesrAid = BS.replicate 32 0xAB}
        }
    , twoKeyContext{ccSpentTxid = BS.replicate 32 0xD2}
    , twoKeyContext{ccSpentIndex = 4}
    , twoKeyContext{ccOld = (ccOld twoKeyContext){cdSeq = 6}}
    , twoKeyContext{ccOld = (ccOld twoKeyContext){cdNativeSn = 10}}
    ]

freshOutrefContext :: CloseContext
freshOutrefContext =
    twoKeyContext
        { ccSpentTxid = BS.replicate 32 0xE1
        , ccSpentIndex = 0
        }

assertFixtures :: IO ()
assertFixtures = do
    assertAccepted "two-key" twoKeyContext twoKeyEvidence
    assertAccepted "GLEIF seven-key" gleifContext gleifEvidence
    mapM_
        (\(name, ctx, evidence) -> assertRejected name ctx evidence)
        [ ("malformed OLD", malformedOldContext, twoKeyEvidence)
        , ("below threshold", twoKeyContext, belowThresholdEvidence)
        , ("bad index", twoKeyContext, badIndexEvidence)
        , ("out-of-range index", twoKeyContext, outOfRangeEvidence)
        , ("duplicate inflation", twoKeyContext, duplicateEvidence)
        , ("wrong key", twoKeyContext, wrongKeyEvidence)
        , ("redirected address", twoKeyContext, redirectedEvidence)
        , ("fresh outref replay", freshOutrefContext, twoKeyEvidence)
        ]
    mapM_
        (\ctx -> assertRejected "mutated reconstructed field" ctx twoKeyEvidence)
        mutatedContexts
  where
    assertAccepted name ctx evidence =
        unless (closePredicate ctx evidence == Right ()) $
            fail (name <> " Close fixture unexpectedly rejected")
    assertRejected name ctx evidence =
        unless (closePredicate ctx evidence /= Right ()) $
            fail (name <> " Close fixture unexpectedly accepted")

-- ---------------------------------------------------------
-- Aiken rendering
-- ---------------------------------------------------------

renderModule :: String
renderModule =
    unlines
        [ "//// Auto-generated Aiken Close vectors for #117 — DO NOT EDIT."
        , "//// Haskell owns message/address bytes, signatures, and verdicts."
        , "//// Regenerate with `just gen-close-vectors`; drift is forbidden."
        , ""
        , "use cardano/address.{Address, Inline, Script, VerificationKey}"
        , "use cardano_keri/checkpoint/close.{CloseContext, CloseEvidence}"
        , "use cardano_keri/checkpoint/datum.{CheckpointDatumV1}"
        , "use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}"
        , ""
        , constant "golden_refund_address_cbor" "ByteArray" (hexLit (canonicalCbor refundAddress))
        , constant "golden_message_cbor_2key" "ByteArray" (hexLit (preimage twoKeyContext twoKeyEvidence))
        , constant "pos_2key_context" "CloseContext" (renderContext twoKeyContext)
        , constant "pos_2key_evidence" "CloseEvidence" (renderEvidence twoKeyEvidence)
        , constant "pos_gleif7_context" "CloseContext" (renderContext gleifContext)
        , constant "pos_gleif7_evidence" "CloseEvidence" (renderEvidence gleifEvidence)
        , constant "neg_malformed_old_context" "CloseContext" (renderContext malformedOldContext)
        , constant "neg_below_threshold_evidence" "CloseEvidence" (renderEvidence belowThresholdEvidence)
        , constant "neg_bad_index_evidence" "CloseEvidence" (renderEvidence badIndexEvidence)
        , constant "neg_out_of_range_evidence" "CloseEvidence" (renderEvidence outOfRangeEvidence)
        , constant "neg_duplicate_evidence" "CloseEvidence" (renderEvidence duplicateEvidence)
        , constant "neg_wrong_key_evidence" "CloseEvidence" (renderEvidence wrongKeyEvidence)
        , constant "neg_mutated_contexts" "List<CloseContext>" (renderList renderContext mutatedContexts)
        , constant "neg_redirected_evidence" "CloseEvidence" (renderEvidence redirectedEvidence)
        , constant "neg_fresh_outref_context" "CloseContext" (renderContext freshOutrefContext)
        ]

constant :: String -> String -> String -> String
constant name ty value = "pub const " <> name <> ": " <> ty <> " =\n  " <> value <> "\n"

renderContext :: CloseContext -> String
renderContext CloseContext{..} =
    "CloseContext { network_id: "
        <> show ccNetworkId
        <> ", checkpoint_policy_id: "
        <> hexLit ccCheckpointPolicyId
        <> ", spent_txid: "
        <> hexLit ccSpentTxid
        <> ", spent_index: "
        <> show ccSpentIndex
        <> ", old: "
        <> renderDatum ccOld
        <> " }"

renderDatum :: CheckpointDatumV1 -> String
renderDatum CheckpointDatumV1{..} =
    "CheckpointDatumV1 { cesr_aid: "
        <> hexLit cdCesrAid
        <> ", cur_keys: "
        <> renderList hexLit cdCurKeys
        <> ", cur_threshold: "
        <> renderThreshold cdCurThreshold
        <> ", next_keys: "
        <> renderList hexLit cdNextKeys
        <> ", next_threshold: "
        <> renderThreshold cdNextThreshold
        <> ", witnesses: "
        <> renderList hexLit cdWitnesses
        <> ", toad: "
        <> show cdToad
        <> ", seq: "
        <> show cdSeq
        <> ", native_sn: "
        <> show cdNativeSn
        <> " }"

renderThreshold :: Threshold -> String
renderThreshold = \case
    Unweighted value -> "Unweighted(" <> show value <> ")"
    Weighted clauses -> "Weighted(" <> renderList (renderList renderWeight) clauses <> ")"
  where
    renderWeight (Weight num den) =
        "Weight { num: " <> show num <> ", den: " <> show den <> " }"

renderEvidence :: CloseEvidence -> String
renderEvidence CloseEvidence{..} =
    "CloseEvidence { refund_address: "
        <> renderAddress ceRefundAddress
        <> ", ctrl_sigs: "
        <> renderList renderSignature ceCtrlSigs
        <> " }"
  where
    renderSignature (index, signature) =
        "(" <> show index <> ", " <> hexLit signature <> ")"

renderAddress :: FullAddress -> String
renderAddress FullAddress{..} =
    "Address { payment_credential: "
        <> renderCredential faPaymentCredential
        <> ", stake_credential: "
        <> maybe "None" (\stake -> "Some(" <> renderStake stake <> ")") faStakeCredential
        <> " }"
  where
    renderCredential = \case
        VerificationKeyCredential hash -> "VerificationKey(" <> hexLit hash <> ")"
        ScriptCredential hash -> "Script(" <> hexLit hash <> ")"
    renderStake = \case
        InlineStakeCredential credential ->
            "Inline(" <> renderCredential credential <> ")"
        PointerStakeCredential slot txIndex certIndex ->
            "Pointer { slot_number: "
                <> show slot
                <> ", transaction_index: "
                <> show txIndex
                <> ", certificate_index: "
                <> show certIndex
                <> " }"

renderList :: (a -> String) -> [a] -> String
renderList render values = "[" <> intercalate ", " (map render values) <> "]"

hexLit :: ByteString -> String
hexLit bytes = "#\"" <> BSC.unpack (convertToBase Base16 bytes) <> "\""

decodeHex :: ByteString -> ByteString
decodeHex encoded = case convertFromBase Base16 encoded of
    Right bytes -> bytes
    Left err -> error err

repeatedSigner :: Word -> SignKeyDSIGN Ed25519DSIGN
repeatedSigner byte =
    genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 (fromIntegral byte)))

verkeyOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
verkeyOf = rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN

signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver signer message = rawSerialiseSigDSIGN (signDSIGN () message signer)
