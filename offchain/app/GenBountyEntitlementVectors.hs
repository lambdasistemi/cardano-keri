{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Main
Description : Haskell source of the S254-E entitlement parity vectors

The sole source of every committed value in
@onchain\/lib\/cardano_keri\/checkpoint\/entitlement_vectors.ak@.  Aiken
rebuilds the same fixture from its own types, recomputes each value, and the
committed module is rejected on drift by
@scripts\/check-bounty-entitlement-vectors.sh@.

__What this instrument is, and is not.__  The #271 component already has an
independent oracle: @GenBountyCommitmentVectors.hs@ mirrors the commitment
wire as explicit 'Data' trees, so a change on either side that is not mirrored
on the other breaks its vectors.  This generator is a different instrument for
a different seam.  It imports the __production__ mirror
("Cardano.KERI.AID.Checkpoint.Entitlement" and its component module) and
therefore does not re-derive the wire independently; what it establishes is
that the shipped Haskell and the shipped Aiken agree, value for value, on the
entitlement layer the component deliberately left open — the canonical digest
over the COMPLETE actual enforcement payload, and the verdict the shared
matcher returns over it.

That is exactly the seam @DATA-INV-271-02@ leaves to S254-E, and it is where a
silent disagreement would be worst: the commitment is opened over a digest one
language computes and settled against a digest the other recomputes.

__Verdict parity, not only byte parity.__  Serialization equality alone would
not catch two matchers that agree on bytes and disagree on a boundary, so the
emitted set carries the matcher's own verdict tag for a named row set, and the
Aiken side maps its own @EntitlementVerdict@ into the same tags.
-}
module Main (main) where

import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    BountyAction (..),
    BountyCommitment (..),
    BountyRevealV1 (..),
    BountyScope (..),
    CommitmentFamily (..),
    CommitmentParameters (..),
    EntitlementError (..),
    EntitlementVerdict (..),
    commitDepositFloor,
    commitMinAge,
    commitmentDomain,
    commitmentHash,
    commitmentPreimage,
    commitmentSchema,
    markerName,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    EnforcementEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Entitlement (
    EnforcementProofV1 (..),
    enforcementEvidenceDigest,
    entitlementMatches,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    ArmedDatum (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    enforcementProofData,
 )
import Cardano.KERI.AID.Migration.Types (
    OutputRef (..),
    canonicalCbor,
    canonicalCborData,
 )
import Data.Bits (
    xor,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertToBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (
    nub,
 )
import System.Environment (
    getArgs,
 )

main :: IO ()
main = do
    args <- getArgs
    case args of
        [] -> putStr output
        [path] -> writeFile path output
        _ -> error "usage: GenBountyEntitlementVectors.hs [OUT_PATH]"

-- ---------------------------------------------------------
-- The canonical fixture
-- ---------------------------------------------------------

parameters :: CommitmentParameters
parameters =
    CommitmentParameters
        { cpNetwork = 42
        , cpCommitMinAge = commitMinAge
        , cpCommitmentLifetime = 10_000
        , cpCommitDeposit = commitDepositFloor + 1_000_000
        }

commitmentPolicy :: ByteString
commitmentPolicy = BS.replicate 28 0xb0

checkpointPolicy :: ByteString
checkpointPolicy = BS.replicate 28 0xc1

seedRef :: OutputRef
seedRef = OutputRef (BS.replicate 32 0x5e) 7

otherSeedRef :: OutputRef
otherSeedRef = OutputRef (BS.replicate 32 0x5e) 8

commitmentRef :: OutputRef
commitmentRef = OutputRef (BS.replicate 32 0x0c) 0

checkpointRef :: OutputRef
checkpointRef = OutputRef (BS.replicate 32 0xc2) 3

otherCheckpointRef :: OutputRef
otherCheckpointRef = OutputRef (BS.replicate 32 0xc2) 4

marker :: ByteString
marker = markerName seedRef

payee :: ByteString
payee = BS.replicate 28 0x9a

hunter :: ByteString
hunter = BS.replicate 28 0x8b

nonce :: ByteString
nonce = BS.replicate 32 0x11

shortNonce :: ByteString
shortNonce = BS.replicate 31 0x11

commitUpper :: Integer
commitUpper = 1000

deadline :: Integer
deadline = 1500

refundIndex :: Integer
refundIndex = 1

scope :: BountyScope
scope =
    BountyScope
        { bsDomain = commitmentDomain
        , bsSchema = commitmentSchema
        , bsNetwork = cpNetwork parameters
        , bsCheckpointPolicy = checkpointPolicy
        , bsCheckpointRef = checkpointRef
        , bsAction = FreezeEntitlement
        , bsMarker = marker
        , bsCommitUpper = commitUpper
        , bsEligibleAfter = commitUpper + cpCommitMinAge parameters
        , bsExpiresAt = commitUpper + cpCommitmentLifetime parameters
        }

-- | The honest reservation, opened over the digest of the actual evidence.
commitment :: BountyCommitment
commitment =
    BountyCommitmentV1
        { bcScope = scope
        , bcPayeePkh = payee
        , bcHash =
            commitmentHash $
                commitmentPreimage scope evidenceDigest payee nonce
        , bcMarker = marker
        }

reveal :: BountyRevealV1
reveal =
    BountyRevealV1
        { brCommitmentRef = commitmentRef
        , brNonce = nonce
        , brRefundIndex = refundIndex
        }

family :: CommitmentFamily
family = CommitmentFamily commitmentPolicy parameters

-- ---------------------------------------------------------
-- The complete actual enforcement payload
-- ---------------------------------------------------------

eventBytes :: ByteString
eventBytes = "{\"v\":\"KERI10JSON000000_\",\"t\":\"rot\"}"

said :: ByteString
said = BS.replicate 32 0x44

verkey :: ByteString
verkey = BS.replicate 32 0x02

keyDigest :: ByteString
keyDigest = BS.replicate 32 0x03

controllerSignature :: ByteString
controllerSignature = BS.replicate 64 0x77

witnessSignature :: ByteString
witnessSignature = BS.replicate 64 0x78

evidence :: EnforcementEvidence
evidence =
    EnforcementEvidence
        { eneEventBytes = eventBytes
        , eneOffT = 1
        , eneOffI = 2
        , eneOffS = 3
        , eneOffD = 4
        , eneOffK = [5]
        , eneOffKt = 6
        , eneOffN = [7]
        , eneOffNt = 8
        , eneOffBt = 9
        , eneNativeSn = 10
        , eneSaid = said
        , eneRevealedKeys = [verkey]
        , eneNextKeys = [keyDigest]
        , eneCurThreshold = Unweighted 1
        , eneNextThreshold = Unweighted 1
        , eneToad = 0
        , eneCtrlSigs = [(0, controllerSignature)]
        , eneWitSigs = [(0, witnessSignature)]
        }

evidenceDigest :: ByteString
evidenceDigest = enforcementEvidenceDigest evidence

proof :: EnforcementProofV1
proof =
    EnforcementProofV1
        { epEvidence = evidence
        , epPayeePkh = payee
        , epReveal = reveal
        }

checkpointState :: CheckpointDatumV1
checkpointState =
    CheckpointDatumV1
        { cdCesrAid = BS.replicate 32 0x01
        , cdCurKeys = [verkey]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [keyDigest]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 1
        , cdNativeSn = 1
        }

-- ---------------------------------------------------------
-- Per-field evidence mutants
-- ---------------------------------------------------------

{- | One independent single-field mutation per field of the payload.

The digest is only a real constraint if every field is inside it, so the
committed set carries one digest per field and the generator refuses to emit a
set in which any two of them — or any one and the honest digest — collide.
-}
evidenceMutants :: [(String, EnforcementEvidence)]
evidenceMutants =
    [ ("event_bytes", evidence{eneEventBytes = flipLast eventBytes})
    , ("off_t", evidence{eneOffT = 11})
    , ("off_i", evidence{eneOffI = 12})
    , ("off_s", evidence{eneOffS = 13})
    , ("off_d", evidence{eneOffD = 14})
    , ("off_k", evidence{eneOffK = [15]})
    , ("off_kt", evidence{eneOffKt = 16})
    , ("off_n", evidence{eneOffN = [17]})
    , ("off_nt", evidence{eneOffNt = 18})
    , ("off_bt", evidence{eneOffBt = 19})
    , ("native_sn", evidence{eneNativeSn = 20})
    , ("said", evidence{eneSaid = flipLast said})
    , ("revealed_keys", evidence{eneRevealedKeys = [flipLast verkey]})
    , ("next_keys", evidence{eneNextKeys = [flipLast keyDigest]})
    , ("cur_threshold", evidence{eneCurThreshold = Unweighted 2})
    , ("next_threshold", evidence{eneNextThreshold = Unweighted 2})
    , ("toad", evidence{eneToad = 1})
    ,
        ( "ctrl_sigs"
        , evidence{eneCtrlSigs = [(0, flipLast controllerSignature)]}
        )
    , ("wit_sigs", evidence{eneWitSigs = [(1, witnessSignature)]})
    ]

-- ---------------------------------------------------------
-- Verdict rows
-- ---------------------------------------------------------

{- | The matcher's verdict as a stable integer tag.

Aiken maps its own @EntitlementVerdict@ into these same tags, so a row proves
the two languages reach the same /reason/, not merely the same yes-or-no.
-}
verdictTag :: EntitlementVerdict -> Integer
verdictTag = \case
    EntitlementValid -> 0
    EntitlementInvalid EntitlementDigestWidth -> 1
    EntitlementInvalid EntitlementNonceWidth -> 2
    EntitlementInvalid EntitlementAction -> 3
    EntitlementInvalid EntitlementCheckpoint -> 4
    EntitlementInvalid EntitlementMarker -> 5
    EntitlementInvalid EntitlementHash -> 6

{- | The named verdict rows, each varying exactly one input of the shared
matcher over ACTUAL evidence.

Widths of the digest are deliberately absent: at this layer the digest is
derived from the payload and is a full blake2b-256 by construction, so
@EntitlementDigestWidth@ is unreachable here and belongs to the component's own
vectors rather than to a row that could never fire.
-}
verdictRows :: [(String, EntitlementVerdict)]
verdictRows =
    [ ("honest", matches commitment checkpointRef FreezeEntitlement evidence nonce)
    ,
        ( "short_nonce"
        , matches commitment checkpointRef FreezeEntitlement evidence shortNonce
        )
    ,
        ( "convict_action"
        , matches commitment checkpointRef ConvictEntitlement evidence nonce
        )
    ,
        ( "other_checkpoint"
        , matches commitment otherCheckpointRef FreezeEntitlement evidence nonce
        )
    ,
        ( "marker_left_scope"
        , matches
            commitment{bcMarker = markerName otherSeedRef}
            checkpointRef
            FreezeEntitlement
            evidence
            nonce
        )
    ,
        ( "substituted_evidence"
        , matches
            commitment
            checkpointRef
            FreezeEntitlement
            evidence{eneEventBytes = flipLast eventBytes}
            nonce
        )
    ,
        ( "substituted_nonce"
        , matches
            commitment
            checkpointRef
            FreezeEntitlement
            evidence
            (flipLast nonce)
        )
    ,
        ( "substituted_payee"
        , matches
            commitment{bcPayeePkh = BS.replicate 28 0xaa}
            checkpointRef
            FreezeEntitlement
            evidence
            nonce
        )
    ]
  where
    matches = entitlementMatches

-- ---------------------------------------------------------
-- Emission
-- ---------------------------------------------------------

output :: String
output
    | length (nub digests) /= length digests =
        error
            "GenBountyEntitlementVectors: two evidence field mutants share a \
            \digest; the emitted set would not prove the field is inside the \
            \hash"
    | evidenceDigest `elem` map snd mutantDigests =
        error
            "GenBountyEntitlementVectors: an evidence field mutant reproduces \
            \the honest digest"
    | verdictTag (snd (head' verdictRows)) /= 0 =
        error
            "GenBountyEntitlementVectors: the honest row is not accepted; the \
            \rejection rows below would have no accepted neighbour"
    | length (nub (map (verdictTag . snd) verdictRows)) < 2 =
        error
            "GenBountyEntitlementVectors: every verdict row agrees; the set \
            \could not distinguish a matcher from a constant"
    | otherwise =
        unlines
            ( [ "//// GENERATED by offchain/app/GenBountyEntitlementVectors.hs. DO NOT EDIT."
              , "//// `scripts/check-bounty-entitlement-vectors.sh` regenerates and rejects drift."
              , ""
              , intConst "network" (cpNetwork parameters)
              , intConst "commit_min_age" (cpCommitMinAge parameters)
              , -- The fixture's release lifetime is deliberately NOT emitted
                -- as a named constant: only the boundary it derives is. A
                -- lifetime constant sitting in a shared module is how a
                -- deployment magnitude becomes a protocol default, and this
                -- family has no default. Its value still reaches Aiken inside
                -- `golden_commitment_parameters`, where it is an applied
                -- argument rather than a publishable one.
                intConst "commit_deposit" (cpCommitDeposit parameters)
              , intConst "commit_upper" commitUpper
              , intConst "eligible_after" (bsEligibleAfter scope)
              , intConst "expires_at" (bsExpiresAt scope)
              , intConst "refund_index" refundIndex
              , intConst "deadline" deadline
              , intConst "seed_index" (orOutputIndex seedRef)
              , intConst "other_seed_index" (orOutputIndex otherSeedRef)
              , intConst "commitment_index" (orOutputIndex commitmentRef)
              , intConst "checkpoint_index" (orOutputIndex checkpointRef)
              , intConst "other_checkpoint_index" (orOutputIndex otherCheckpointRef)
              , byteConst "seed_txid" (orTransactionId seedRef)
              , byteConst "commitment_txid" (orTransactionId commitmentRef)
              , byteConst "checkpoint_txid" (orTransactionId checkpointRef)
              , byteConst "commitment_policy" commitmentPolicy
              , byteConst "checkpoint_policy" checkpointPolicy
              , byteConst "payee" payee
              , byteConst "hunter" hunter
              , byteConst "nonce" nonce
              , byteConst "short_nonce" shortNonce
              , byteConst "marker" marker
              , byteConst "other_marker" (markerName otherSeedRef)
              , byteConst "commitment_hash" (bcHash commitment)
              , ""
              , "// The complete actual enforcement payload the reservation was"
              , "// opened over. Aiken rebuilds this record field for field."
              , byteConst "event_bytes" eventBytes
              , byteConst "said" said
              , byteConst "verkey" verkey
              , byteConst "key_digest" keyDigest
              , byteConst "controller_signature" controllerSignature
              , byteConst "witness_signature" witnessSignature
              , ""
              , byteConst "golden_evidence" (canonicalCbor evidence)
              , byteConst "evidence_digest" evidenceDigest
              , byteConst
                    "golden_enforcement_proof"
                    (canonicalCborData (enforcementProofData proof))
              , byteConst "golden_commitment" (canonicalCbor commitment)
              , byteConst "golden_reveal" (canonicalCbor reveal)
              , byteConst "golden_commitment_parameters" (canonicalCbor parameters)
              , byteConst "golden_commitment_family" (canonicalCbor family)
              , byteConst "golden_armed_v1" (canonicalCbor armedV1)
              , byteConst "golden_armed_v2" (canonicalCbor armedV2)
              ]
                <> map mutantConst mutantDigests
                <> map verdictConst verdictRows
            )
  where
    head' (row : _) = row
    head' [] = error "GenBountyEntitlementVectors: no verdict rows"
    digests = evidenceDigest : map snd mutantDigests

armedV1 :: ArmedDatum
armedV1 = ArmedV1 checkpointState hunter deadline

armedV2 :: ArmedDatum
armedV2 = ArmedV2 checkpointState hunter deadline

mutantDigests :: [(String, ByteString)]
mutantDigests =
    [ (name, enforcementEvidenceDigest mutant)
    | (name, mutant) <- evidenceMutants
    ]

mutantConst :: (String, ByteString) -> String
mutantConst (name, value) = byteConst ("mut_ev_" <> name) value

verdictConst :: (String, EntitlementVerdict) -> String
verdictConst (name, verdict) =
    intConst ("verdict_" <> name) (verdictTag verdict)

byteConst :: String -> ByteString -> String
byteConst name value =
    "pub const " <> name <> ": ByteArray = #\"" <> hex value <> "\"\n"

intConst :: String -> Integer -> String
intConst name value = "pub const " <> name <> ": Int = " <> show value <> "\n"

hex :: ByteString -> String
hex = BC.unpack . convertToBase Base16

-- | Flip the low bit of the last byte, leaving the width unchanged.
flipLast :: ByteString -> ByteString
flipLast bs = case BS.unsnoc bs of
    Nothing -> bs
    Just (initial, final) -> BS.snoc initial (final `xor` 1)
