{- |
Module      : Main
Description : Checkpoint-migration parity vector generator for #254 S254-1B

The single Haskell computation that produces every byte string the Aiken
checkpoint-migration suite asserts against, reusing
"Cardano.KERI.AID.Migration.Checkpoint" as the sole source of truth — it never
re-implements the encoding or the verdicts.

@main@ writes a self-contained Aiken fixtures module
(@onchain\/lib\/cardano_keri\/migration\/checkpoint_vectors.ak@) of
@pub const \<name\>: ByteArray = #"\<hex\>"@ constants.  Both the input
fixtures and the expected encodings are emitted, so the Aiken suite builds its
values from exactly the material this generator used; a hand-copied fixture on
the Aiken side could otherwise make the comparison assert Aiken against Aiken.

Before emitting anything the generator proves its own vector set is
non-vacuous:

* the golden message must round-trip and every named field mutation must
  produce a distinct encoding — negatives that collide prove nothing;
* the golden signature set must actually satisfy the controller quorum, and
  each named authority negative must actually fail it.  A negative that the
  oracle accepts would ship an Aiken control that cannot fail.

Invocation: @gen-checkpoint-migration-vectors [OUT_PATH]@.
-}
module Main (main) where

import Cardano.Crypto.DSIGN (
    Ed25519DSIGN,
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.Seed (
    mkSeedFromBytes,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.AID.Migration.Checkpoint (
    LegacyCheckpointIdentity (..),
    MigrationError (..),
    MigrationMessage,
    MigrationSource (..),
    Predecessor (..),
    VersionedCheckpoint (..),
    checkpointMigrationAuthorized,
    encodeMigrationMessage,
    migrationMessage,
    preprodV0,
 )
import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    FullAddress (..),
    MigrationOrigin (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
    ValidatorVersion (..),
    canonicalCborData,
    migrationDomain,
 )
import Control.Monad (
    unless,
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
import Data.Word (
    Word8,
 )
import PlutusCore.Data (
    Data (..),
 )
import System.Environment (
    getArgs,
 )

-- ---------------------------------------------------------
-- Key material
-- ---------------------------------------------------------

-- | A deterministic signer from a single repeated seed byte.
signerOf :: Word8 -> SignKeyDSIGN Ed25519DSIGN
signerOf byte = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 byte))

verkeyOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
verkeyOf = rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN

signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver signer message = rawSerialiseSigDSIGN (signDSIGN () message signer)

-- | Three controllers of the source checkpoint, plus one outsider.
controller0, controller1, controller2, foreigner :: SignKeyDSIGN Ed25519DSIGN
controller0 = signerOf 0xc0
controller1 = signerOf 0xc1
controller2 = signerOf 0xc2
foreigner = signerOf 0xf0

controllerKeys :: [ByteString]
controllerKeys = map verkeyOf [controller0, controller1, controller2]

-- ---------------------------------------------------------
-- Fixture material
-- ---------------------------------------------------------

bytesOf :: Int -> Word8 -> ByteString
bytesOf = BS.replicate

cesrAid, sourcePolicy, targetPolicy, sourceTxid, mutantTxid :: ByteString
cesrAid = bytesOf 32 0xaa
sourcePolicy = bytesOf 28 0x50
targetPolicy = bytesOf 28 0x51
sourceTxid = bytesOf 32 0x60
mutantTxid = bytesOf 32 0x61

targetScript, targetStakeScript, refundVkey, witnessKey :: ByteString
targetScript = bytesOf 28 0x70
targetStakeScript = bytesOf 28 0x71
refundVkey = bytesOf 28 0x72
witnessKey = bytesOf 32 0x90

nextKeyDigest0, nextKeyDigest1 :: ByteString
nextKeyDigest0 = bytesOf 32 0xd0
nextKeyDigest1 = bytesOf 32 0xd1

-- | The AID token label both policies must agree on across the move.
aidAssetName :: ByteString
aidAssetName = deriveAidAssetName cesrAid

{- | The source checkpoint projection.  Threshold is 2-of-3 so that a single
signature is genuinely below quorum and two distinct ones genuinely meet it —
a 1-of-n fixture could not tell a working quorum rule from a missing one.
-}
sourceDatum :: CheckpointDatumV1
sourceDatum =
    CheckpointDatumV1
        { cdCesrAid = cesrAid
        , cdCurKeys = controllerKeys
        , cdCurThreshold = Unweighted 2
        , cdNextKeys = [nextKeyDigest0, nextKeyDigest1]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = [witnessKey]
        , cdToad = 1
        , cdSeq = 7
        , cdNativeSn = 4
        }

-- | The carried projection, verbatim, exactly as the authorization carries it.
sourceStateData :: Data
sourceStateData = checkpointTree

{- | The projection as a @Data@ tree, in the exact constructor-0 layout the
frozen @CheckpointDatum@ codec emits: the version sum wrapping the inner
record.  This wrapped form is what the authorization carries verbatim.
-}
checkpointTree :: Data
checkpointTree = Constr 0 [innerCheckpointTree]

{- | The inner nine-field record alone.  'VersionedCheckpoint' embeds the
projection __unwrapped__ — the version sum belongs to the v0 datum, and
re-wrapping it inside the versioned record would nest two version tags.
-}
innerCheckpointTree :: Data
innerCheckpointTree =
    Constr
        0
        [ B (cdCesrAid sourceDatum)
        , List [B k | k <- cdCurKeys sourceDatum]
        , Constr 0 [I 2]
        , List [B k | k <- cdNextKeys sourceDatum]
        , Constr 0 [I 1]
        , List [B w | w <- cdWitnesses sourceDatum]
        , I (cdToad sourceDatum)
        , I (cdSeq sourceDatum)
        , I (cdNativeSn sourceDatum)
        ]

sourceRef, mutantRef :: OutputRef
sourceRef = OutputRef{orTransactionId = sourceTxid, orOutputIndex = 1}
mutantRef = OutputRef{orTransactionId = mutantTxid, orOutputIndex = 1}

sourceOrigin :: MigrationOrigin
sourceOrigin =
    MigrationOrigin
        { moSourceVersion = ValidatorVersion 1
        , moSourcePolicy = sourcePolicy
        , moSourceRef = sourceRef
        }

targetAddress, refundAddress :: FullAddress
targetAddress =
    FullAddress
        { faPaymentCredential = ScriptCredential targetScript
        , faStakeCredential =
            Just (InlineStakeCredential (ScriptCredential targetStakeScript))
        }
refundAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential refundVkey
        , faStakeCredential = Nothing
        }

-- | The permanent-family target: version 2 succeeding version 1, no refund.
migrationTarget :: MigrationTarget
migrationTarget =
    MigrationTarget
        { mtTargetVersion = ValidatorVersion 2
        , mtTargetPolicy = targetPolicy
        , mtTargetRole = CheckpointActive
        , mtTargetAddress = targetAddress
        , mtLegacyRefundAddress = Nothing
        }

-- | The legacy-bridge target: version 1 succeeding deployed v0, with refund.
legacyTarget :: MigrationTarget
legacyTarget =
    migrationTarget
        { mtTargetVersion = ValidatorVersion 1
        , mtLegacyRefundAddress = Just refundAddress
        }

-- | The permanent-family source: an ACTIVE version-1 row on network 1.
source :: MigrationSource
source =
    MigrationSource
        { msNetworkId = 1
        , msSourceVersion = ValidatorVersion 1
        , msSourcePolicy = sourcePolicy
        , msSourceRef = sourceRef
        , msSourceRole = CheckpointActive
        , msSourceState = sourceStateData
        }

{- | The legacy source: the exact committed preprod v0 ACTIVE row.  Its policy
and version come from 'preprodV0' in the oracle rather than being restated
here, so the released identity has exactly one definition.
-}
legacySource :: MigrationSource
legacySource =
    source
        { msNetworkId = lcNetworkId preprodV0
        , msSourceVersion = lcVersion preprodV0
        , msSourcePolicy = legacyPolicyBytes
        }

-- | The frozen preprod v0 minting policy, as released.
legacyPolicyBytes :: ByteString
legacyPolicyBytes = lcPolicy preprodV0

-- ---------------------------------------------------------
-- The golden message and its named mutants
-- ---------------------------------------------------------

goldenMessage :: MigrationMessage
goldenMessage = migrationMessage source migrationTarget

goldenBytes :: ByteString
goldenBytes = encodeMigrationMessage source migrationTarget

legacyBytes :: ByteString
legacyBytes = encodeMigrationMessage legacySource legacyTarget

{- | One mutation per redirectable field.  These are the replay/redirect
negatives: a controller signature over the golden message must not authorize
any of them, which is exactly what makes the package unreplayable.
-}
messageMutants :: [(String, String, ByteString)]
messageMutants =
    [ m "network" "the chain identity" $
        encodeMigrationMessage source{msNetworkId = 0} migrationTarget
    , m "source_version" "the source generation" $
        encodeMigrationMessage
            source{msSourceVersion = ValidatorVersion 2}
            migrationTarget
    , m "source_policy" "the source minting policy" $
        encodeMigrationMessage source{msSourcePolicy = targetPolicy} migrationTarget
    , m "source_ref" "the exact consumed source output" $
        encodeMigrationMessage source{msSourceRef = mutantRef} migrationTarget
    , m "source_role" "the source lifecycle position" $
        encodeMigrationMessage source{msSourceRole = CheckpointFrozen} migrationTarget
    , m "source_state" "the carried source projection" $
        encodeMigrationMessage source{msSourceState = mutantStateData} migrationTarget
    , m "target_version" "the successor generation" $
        encodeMigrationMessage
            source
            migrationTarget{mtTargetVersion = ValidatorVersion 3}
    , m "target_policy" "the successor minting policy" $
        encodeMigrationMessage source migrationTarget{mtTargetPolicy = sourcePolicy}
    , m "target_role" "the successor lifecycle position" $
        encodeMigrationMessage
            source
            migrationTarget{mtTargetRole = CheckpointFrozen}
    , m "target_address" "the successor address" $
        encodeMigrationMessage
            source
            migrationTarget
                { mtTargetAddress =
                    targetAddress{faStakeCredential = Nothing}
                }
    , m "refund" "the legacy refund destination" $
        encodeMigrationMessage
            source
            migrationTarget{mtLegacyRefundAddress = Just refundAddress}
    ]
  where
    m name field bytes = ("negative_message_" <> name, field, bytes)

-- | A source projection differing only in its advance counter.
mutantStateData :: Data
mutantStateData =
    case checkpointTree of
        Constr 0 [Constr 0 fields] ->
            Constr 0 [Constr 0 (replaceSeq fields)]
        other -> other
  where
    replaceSeq fields =
        [ if index == (7 :: Int) then I 8 else field
        | (index, field) <- zip [0 ..] fields
        ]

-- ---------------------------------------------------------
-- Signature material
-- ---------------------------------------------------------

sig0, sig1, sig2, foreignSig, sig0OverMutant :: ByteString
sig0 = signOver controller0 goldenBytes
sig1 = signOver controller1 goldenBytes
sig2 = signOver controller2 goldenBytes
foreignSig = signOver foreigner goldenBytes
sig0OverMutant = signOver controller0 (mutantBytesFor "negative_message_source_ref")

legacySig0, legacySig1 :: ByteString
legacySig0 = signOver controller0 legacyBytes
legacySig1 = signOver controller1 legacyBytes

-- | The bytes of a named message mutant.
mutantBytesFor :: String -> ByteString
mutantBytesFor wanted =
    case [bytes | (name, _, bytes) <- messageMutants, name == wanted] of
        (bytes : _) -> bytes
        [] -> error ("no message mutant named " <> wanted)

-- | The satisfying quorum: two distinct controllers over the golden message.
goldenSignatures :: [(Integer, ByteString)]
goldenSignatures = [(0, sig0), (1, sig1)]

{- | The named authority negatives, each with the reason it must fail.  Every
one is asserted against the oracle below before it is emitted.
-}
authorityNegatives :: [(String, [(Integer, ByteString)])]
authorityNegatives =
    [ ("missing", [])
    , ("single_below_threshold", [(0, sig0)])
    , ("foreign_signer", [(0, sig0), (1, foreignSig)])
    , ("duplicate_index", [(0, sig0), (0, sig0)])
    , ("out_of_range_index", [(0, sig0), (9, sig2)])
    , ("replayed_from_mutant", [(0, sig0OverMutant), (1, sig1)])
    ]

-- ---------------------------------------------------------
-- Successor material
-- ---------------------------------------------------------

-- | The successor record a correct migration lands.
successor :: VersionedCheckpoint
successor =
    VersionedCheckpoint
        { vcValidatorVersion = ValidatorVersion 2
        , vcMigrationOrigin = Just sourceOrigin
        , vcState = sourceDatum
        }

-- | A natively registered row: applied version, and deliberately no origin.
nativeSuccessor :: VersionedCheckpoint
nativeSuccessor =
    successor
        { vcValidatorVersion = ValidatorVersion 1
        , vcMigrationOrigin = Nothing
        }

-- | The pinned predecessor the target program compiles in.
pinnedPredecessor :: Predecessor
pinnedPredecessor =
    Predecessor
        { pdPredecessorVersion = ValidatorVersion 1
        , pdPredecessorPolicy = sourcePolicy
        }

-- ---------------------------------------------------------
-- The vector set
-- ---------------------------------------------------------

data Vec = Vec String String ByteString

vectors :: [Vec]
vectors = fixtures <> goldens <> negatives

fixtures :: [Vec]
fixtures =
    [ Vec "fixture_cesr_aid" "input: the source AID" cesrAid
    , Vec "fixture_aid_asset_name" "input: the AID token label both policies carry" aidAssetName
    , Vec "fixture_source_policy" "input: source minting policy" sourcePolicy
    , Vec "fixture_target_policy" "input: target minting policy" targetPolicy
    , Vec "fixture_legacy_policy" "input: the committed preprod v0 policy" legacyPolicyBytes
    , Vec "fixture_source_txid" "input: consumed source transaction id" sourceTxid
    , Vec "fixture_mutant_txid" "input: a different transaction id" mutantTxid
    , Vec "fixture_target_script" "input: successor payment script hash" targetScript
    , Vec "fixture_target_stake_script" "input: successor stake script hash" targetStakeScript
    , Vec "fixture_refund_vkey" "input: legacy refund key hash" refundVkey
    , Vec "fixture_witness_key" "input: the source witness verkey" witnessKey
    , Vec "fixture_next_key_0" "input: first pre-rotation digest" nextKeyDigest0
    , Vec "fixture_next_key_1" "input: second pre-rotation digest" nextKeyDigest1
    , Vec "fixture_ctrl_key_0" "input: controller verkey at index 0" (verkeyOf controller0)
    , Vec "fixture_ctrl_key_1" "input: controller verkey at index 1" (verkeyOf controller1)
    , Vec "fixture_ctrl_key_2" "input: controller verkey at index 2" (verkeyOf controller2)
    , Vec "fixture_foreign_key" "input: a verkey outside the controller set" (verkeyOf foreigner)
    , Vec "fixture_sig_0" "input: controller 0 over the golden message" sig0
    , Vec "fixture_sig_1" "input: controller 1 over the golden message" sig1
    , Vec "fixture_sig_2" "input: controller 2 over the golden message" sig2
    , Vec "fixture_foreign_sig" "input: the outsider over the golden message" foreignSig
    , Vec "fixture_sig_0_over_mutant" "input: controller 0 over a redirected message" sig0OverMutant
    , Vec "fixture_legacy_sig_0" "input: controller 0 over the legacy message" legacySig0
    , Vec "fixture_legacy_sig_1" "input: controller 1 over the legacy message" legacySig1
    ]

goldens :: [Vec]
goldens =
    [ Vec "golden_migration_domain" "domain: the frozen separator the message carries" migrationDomain
    , Vec "golden_source_datum" "state: the source projection, canonical" (canonicalCbor (V1 sourceDatum))
    , Vec "golden_source_state" "state: the carried payload, verbatim" (canonicalCborData sourceStateData)
    , Vec "golden_mutant_source_state" "state: a projection with a bumped counter" (canonicalCborData mutantStateData)
    , Vec "golden_message" "message: the canonical permanent-family preimage" goldenBytes
    , Vec "golden_legacy_message" "message: the canonical legacy-bridge preimage" legacyBytes
    , Vec "golden_origin" "origin: the actual consumed predecessor" (canonicalCbor sourceOrigin)
    , Vec "golden_target" "target: the permanent-family successor identity" (canonicalCbor migrationTarget)
    , Vec "golden_legacy_target" "target: the legacy successor identity with refund" (canonicalCbor legacyTarget)
    , Vec "golden_successor" "successor: the migrated versioned record" (canonicalCborData (successorTree successor))
    , Vec "golden_native_successor" "successor: a natively registered row, no origin" (canonicalCborData (successorTree nativeSuccessor))
    , Vec "golden_predecessor_version" "edge: the pinned predecessor generation" (canonicalCbor (pdPredecessorVersion pinnedPredecessor))
    ]

negatives :: [Vec]
negatives =
    [ Vec name ("message negative: " <> field <> " mutated") bytes
    | (name, field, bytes) <- messageMutants
    ]

{- | The successor record as a @Data@ tree, matching the Aiken
@VersionedCheckpoint@ constructor-0 layout.
-}
successorTree :: VersionedCheckpoint -> Data
successorTree VersionedCheckpoint{..} =
    Constr
        0
        [ Constr 0 [I (vvValue vcValidatorVersion)]
        , maybe (Constr 1 []) (\o -> Constr 0 [originTree o]) vcMigrationOrigin
        , innerCheckpointTree
        ]
  where
    originTree MigrationOrigin{..} =
        Constr
            0
            [ Constr 0 [I (vvValue moSourceVersion)]
            , B moSourcePolicy
            , Constr
                0
                [ B (orTransactionId moSourceRef)
                , I (orOutputIndex moSourceRef)
                ]
            ]

-- ---------------------------------------------------------
-- Self-checks: a vector set that cannot fail is worthless
-- ---------------------------------------------------------

{- | Prove the emitted set is non-vacuous before writing it.

The message half is the same distinctness argument the S254-1A generator
makes.  The authority half is stronger and is the one that matters here: the
golden signature set must actually satisfy the quorum, and every named
authority negative must actually be refused by the oracle.  Without this, a
control asserting "this package is rejected" could be passing because the
fixture is malformed rather than because the rule works.
-}
selfCheck :: IO ()
selfCheck = do
    let encodings = goldenBytes : [bytes | (_, _, bytes) <- messageMutants]
    unless (length (nub encodings) == length encodings) $
        fail "named message mutations collide; the negatives prove nothing"
    unless (goldenBytes /= legacyBytes) $
        fail "the permanent and legacy messages encode alike"
    unless (BS.isInfixOf migrationDomain goldenBytes) $
        fail "the canonical message does not carry the frozen domain"

    case checkpointMigrationAuthorized sourceDatum goldenMessage goldenSignatures of
        Right () -> pure ()
        Left e -> fail ("the golden quorum is not accepted: " <> show e)

    mapM_ requireRefused authorityNegatives
  where
    requireRefused (name, signatures) =
        case checkpointMigrationAuthorized sourceDatum goldenMessage signatures of
            Left MigrationQuorumUnsatisfied -> pure ()
            Left e ->
                fail
                    ("authority negative " <> name <> " failed for the wrong reason: " <> show e)
            Right () ->
                fail
                    ("authority negative " <> name <> " was ACCEPTED; the control cannot fail")

-- ---------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------

toHex :: ByteString -> String
toHex = BC.unpack . convertToBase Base16

renderVec :: Vec -> String
renderVec (Vec name doc bytes) =
    unlines
        [ "/// " <> doc
        , "pub const " <> name <> ": ByteArray ="
        , "  #\"" <> toHex bytes <> "\""
        ]

render :: String
render = header <> "\n" <> concatMap (\v -> renderVec v <> "\n") vectors
  where
    header =
        unlines
            [ "//// Auto-generated Aiken checkpoint-migration fixtures for #254 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-checkpoint-migration-vectors` (runs"
            , "//// offchain/app/GenCheckpointMigrationVectors.hs). Every constant is"
            , "//// computed by the Haskell oracle in"
            , "//// Cardano.KERI.AID.Migration.Checkpoint: the `fixture_` inputs both"
            , "//// languages build their values from, the `golden_` canonical"
            , "//// Plutus-Data CBOR the Aiken encoder must reproduce, and the"
            , "//// `negative_` encodings of one redirected field each."
            , "//// `just check-checkpoint-migration-vectors` forbids drift."
            ]

main :: IO ()
main = do
    selfCheck
    args <- getArgs
    case args of
        (out : _) -> writeFile out render
        [] -> putStr render
