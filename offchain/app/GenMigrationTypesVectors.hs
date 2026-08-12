{- |
Module      : Main
Description : Shared migration-type parity vector generator for #254 S254-1A

The single Haskell computation that produces every byte string the Aiken
migration parity suite asserts against, reusing
"Cardano.KERI.AID.Migration.Types" as the sole source of truth — it never
re-implements the encoding.

@main@ writes a self-contained Aiken fixtures module
(@onchain\/lib\/cardano_keri\/migration\/types_vectors.ak@) of
@pub const \<name\>: ByteArray = #"\<hex\>"@ constants.  Both the input
fixtures and the expected encodings are emitted, so the Aiken suite builds its
values from exactly the material this generator used; a hand-copied fixture on
the Aiken side could otherwise make the comparison assert Aiken against Aiken.

Before emitting anything the generator proves its own vector set is
non-vacuous: the golden authorization must round-trip through the wire codec,
and the golden plus all fifteen named field mutations must encode to sixteen
distinct byte strings.  A generator whose negatives collide would happily emit
a suite that cannot fail.

Invocation: @gen-migration-types-vectors [OUT_PATH]@.  With a path argument the
module is written there; with none it is printed to stdout.
-}
module Main (main) where

import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    FullAddress (..),
    MigrationAuthorization (..),
    MigrationOrigin (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
    ValidatorVersion (..),
    canonicalCbor,
    canonicalCborData,
    migrationDomain,
    optionData,
 )
import Control.Monad (unless)
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
import PlutusTx.IsData.Class (
    fromBuiltinData,
    toBuiltinData,
 )
import System.Environment (
    getArgs,
 )

-- ---------------------------------------------------------
-- Fixture material
-- ---------------------------------------------------------

-- | A fixed-width value of a single repeated byte.
bytesOf :: Int -> Word8 -> ByteString
bytesOf = BS.replicate

sourcePolicy, targetPolicy, sourceTxid, mutantTxid :: ByteString
sourcePolicy = bytesOf 28 0x50
targetPolicy = bytesOf 28 0x51
sourceTxid = bytesOf 32 0x60
mutantTxid = bytesOf 32 0x61

paymentScript, stakeScript, refundVkey, pointerVkey :: ByteString
paymentScript = bytesOf 28 0x70
stakeScript = bytesOf 28 0x71
refundVkey = bytesOf 28 0x72
pointerVkey = bytesOf 28 0x73

sigA, sigB :: ByteString
sigA = bytesOf 64 0x80
sigB = bytesOf 64 0x81

-- | The domain with its version character changed: @\/v1@ becomes @\/v0@.
mutantDomain :: ByteString
mutantDomain = BS.init migrationDomain <> BS.singleton 0x30

{- | The opaque source state: a version-wrapped record the protocol layer
carries verbatim and never interprets.  Its inner shape is deliberately not a
migration type — that is the point of an opaque payload.
-}
sourceState, mutantSourceState :: Data
sourceState = stateWith 0
mutantSourceState = stateWith 1

stateWith :: Integer -> Data
stateWith counter =
    Constr
        0
        [ Constr
            0
            [ B (bytesOf 32 0xaa)
            , List [B (bytesOf 32 0x01)]
            , Constr 0 [I 1]
            , I counter
            ]
        ]

sourceRef :: OutputRef
sourceRef = OutputRef{orTransactionId = sourceTxid, orOutputIndex = 3}

origin :: MigrationOrigin
origin =
    MigrationOrigin
        { moSourceVersion = ValidatorVersion 1
        , moSourcePolicy = sourcePolicy
        , moSourceRef = sourceRef
        }

targetAddress, refundAddress, pointerAddress, plainScriptAddress :: FullAddress
targetAddress =
    FullAddress
        { faPaymentCredential = ScriptCredential paymentScript
        , faStakeCredential =
            Just (InlineStakeCredential (ScriptCredential stakeScript))
        }
refundAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential refundVkey
        , faStakeCredential = Nothing
        }
pointerAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential pointerVkey
        , faStakeCredential = Just (PointerStakeCredential 7 2 1)
        }
plainScriptAddress =
    FullAddress
        { faPaymentCredential = ScriptCredential paymentScript
        , faStakeCredential = Nothing
        }

migrationTarget, targetNoRefund, targetPointerStake :: MigrationTarget
migrationTarget =
    MigrationTarget
        { mtTargetVersion = ValidatorVersion 2
        , mtTargetPolicy = targetPolicy
        , mtTargetRole = CheckpointActive
        , mtTargetAddress = targetAddress
        , mtLegacyRefundAddress = Just refundAddress
        }
targetNoRefund =
    migrationTarget
        { mtTargetAddress = plainScriptAddress
        , mtLegacyRefundAddress = Nothing
        }
targetPointerStake = migrationTarget{mtTargetAddress = pointerAddress}

{- | The golden authorization.  Its source role deliberately differs from its
target role so that swapping the two positions is observable; whether they
must be equal is a later validation rule, not a wire-shape rule.
-}
authorization :: MigrationAuthorization
authorization =
    MigrationAuthorization
        { maDomain = migrationDomain
        , maNetworkId = 1
        , maSourceOrigin = origin
        , maSourceRole = CheckpointFrozen
        , maSourceState = sourceState
        , maTarget = migrationTarget
        , maControllerSignatures = [(0, sigA), (2, sigB)]
        }

-- | One past @maxBound :: Int@: representable in Aiken, not in a machine word.
wideIndex :: Integer
wideIndex = toInteger (maxBound :: Int) + 1

authorizationWideIndex, authorizationNarrowedIndex :: MigrationAuthorization
authorizationWideIndex = withIndex wideIndex
authorizationNarrowedIndex = withIndex (negate wideIndex)

withIndex :: Integer -> MigrationAuthorization
withIndex index =
    authorization{maControllerSignatures = [(0, sigA), (index, sigB)]}

{- | One mutation per redirectable field, paired with its vector name.  The
order is the contract the Aiken suite compares against element by element.
-}
mutations :: [(String, String, MigrationAuthorization)]
mutations =
    [ n "domain_mutated" "the frozen domain separator" $
        authorization{maDomain = mutantDomain}
    , n "network_mutated" "the network identity" $
        authorization{maNetworkId = 0}
    , n "source_version_bumped" "the predecessor program generation" $
        withOrigin origin{moSourceVersion = ValidatorVersion 2}
    , n "source_policy_crossed" "the predecessor minting policy" $
        withOrigin origin{moSourcePolicy = targetPolicy}
    , n "source_ref_txid_mutated" "the spent predecessor transaction" $
        withOrigin origin{moSourceRef = sourceRef{orTransactionId = mutantTxid}}
    , n "source_ref_index_bumped" "the spent predecessor output index" $
        withOrigin origin{moSourceRef = sourceRef{orOutputIndex = 4}}
    , n "source_role_board" "the predecessor lifecycle position" $
        authorization{maSourceRole = Board}
    , n "source_state_mutated" "the carried predecessor state" $
        authorization{maSourceState = mutantSourceState}
    , n "target_version_bumped" "the successor program generation" $
        withTarget migrationTarget{mtTargetVersion = ValidatorVersion 3}
    , n "target_policy_crossed" "the successor minting policy" $
        withTarget migrationTarget{mtTargetPolicy = sourcePolicy}
    , n "target_role_swapped" "the successor lifecycle position" $
        withTarget migrationTarget{mtTargetRole = CheckpointFrozen}
    , n "target_address_stake_dropped" "the successor delegation part" $
        withTarget migrationTarget{mtTargetAddress = plainScriptAddress}
    , n "refund_dropped" "the legacy refund destination" $
        withTarget migrationTarget{mtLegacyRefundAddress = Nothing}
    , n "signature_index_bumped" "a controller signature index" $
        authorization{maControllerSignatures = [(1, sigA), (2, sigB)]}
    , n "signatures_reordered" "the controller signature order" $
        authorization{maControllerSignatures = [(2, sigB), (0, sigA)]}
    ]
  where
    n name field value = ("negative_auth_" <> name, field, value)
    withOrigin value = authorization{maSourceOrigin = value}
    withTarget value = authorization{maTarget = value}

-- ---------------------------------------------------------
-- The vector set
-- ---------------------------------------------------------

-- | A single named fixture: its Aiken identifier, a one-line doc, its bytes.
data Vec = Vec String String ByteString

vectors :: [Vec]
vectors =
    fixtures <> goldens <> negatives

-- | Inputs, so both languages provably encode the same material.
fixtures :: [Vec]
fixtures =
    [ Vec "fixture_source_policy" "input: predecessor minting policy" sourcePolicy
    , Vec "fixture_target_policy" "input: successor minting policy" targetPolicy
    , Vec "fixture_source_txid" "input: spent predecessor transaction id" sourceTxid
    , Vec "fixture_mutant_txid" "input: a different transaction id" mutantTxid
    , Vec "fixture_target_payment_script" "input: successor payment script hash" paymentScript
    , Vec "fixture_target_stake_script" "input: successor stake script hash" stakeScript
    , Vec "fixture_refund_vkey" "input: legacy refund key hash" refundVkey
    , Vec "fixture_pointer_vkey" "input: pointer-address key hash" pointerVkey
    , Vec "fixture_sig_a" "input: controller signature at index 0" sigA
    , Vec "fixture_sig_b" "input: controller signature at index 2" sigB
    , Vec "fixture_mutant_domain" "input: the domain with a different version" mutantDomain
    ]

goldens :: [Vec]
goldens =
    [ Vec "golden_migration_domain" "domain: the frozen UTF-8 separator" migrationDomain
    , Vec "golden_version_zero" "version: generation 0" (canonicalCbor (ValidatorVersion 0))
    , Vec "golden_version_one" "version: generation 1" (canonicalCbor (ValidatorVersion 1))
    , Vec "golden_role_checkpoint_active" "role: checkpoint active" (canonicalCbor CheckpointActive)
    , Vec "golden_role_checkpoint_frozen" "role: checkpoint frozen" (canonicalCbor CheckpointFrozen)
    , Vec "golden_role_checkpoint_armed" "role: checkpoint armed" (canonicalCbor CheckpointArmed)
    , Vec "golden_role_board" "role: board" (canonicalCbor Board)
    , Vec "golden_origin" "origin: the immediate predecessor" (canonicalCbor origin)
    , Vec "golden_origin_present" "origin: present (migrated state)" (canonicalCborData (optionData (Just origin)))
    , Vec "golden_origin_absent" "origin: absent (native state)" (canonicalCborData (optionData noOrigin))
    , Vec "golden_target" "target: delegated address with legacy refund" (canonicalCbor migrationTarget)
    , Vec "golden_target_no_refund" "target: undelegated address, no refund" (canonicalCbor targetNoRefund)
    , Vec "golden_target_pointer_stake" "target: pointer stake credential" (canonicalCbor targetPointerStake)
    , Vec "golden_source_state" "state: the carried predecessor payload" (canonicalCborData sourceState)
    , Vec "mutant_source_state" "state: a different predecessor payload" (canonicalCborData mutantSourceState)
    , Vec "golden_authorization" "authorization: every redirectable field" (canonicalCbor authorization)
    , Vec "golden_auth_wide_index" "authorization: controller index past the machine word" (canonicalCbor authorizationWideIndex)
    ]
  where
    noOrigin = Nothing :: Maybe MigrationOrigin

negatives :: [Vec]
negatives =
    Vec
        "negative_version_bare_int"
        "version negative: the bare integer a version must never alias"
        (canonicalCborData (I 1))
        : Vec "negative_auth_wide_index_narrowed" "authorization negative: the wide controller index aliased to a machine word" (canonicalCbor authorizationNarrowedIndex)
        : [ Vec name ("authorization negative: " <> field <> " mutated") (canonicalCbor value)
          | (name, field, value) <- mutations
          ]

-- ---------------------------------------------------------
-- Self-checks: a vector set that cannot fail is worthless
-- ---------------------------------------------------------

{- | Prove the emitted set is non-vacuous before writing it: the golden
authorization must survive a wire round-trip, and no named mutation may
collide with the golden or with another mutation.
-}
selfCheck :: IO ()
selfCheck = do
    let roundTripped =
            fromBuiltinData (toBuiltinData authorization)
                == Just authorization
    unless roundTripped $
        fail "golden authorization does not round-trip through the wire codec"
    unless (canonicalCbor authorizationWideIndex /= canonicalCbor authorizationNarrowedIndex) $
        fail "the wide controller index and its machine-word alias encode alike"
    let encodings =
            canonicalCbor authorization
                : [canonicalCbor value | (_, _, value) <- mutations]
    unless (length (nub encodings) == length encodings) $
        fail "named authorization mutations collide; the negatives prove nothing"

-- ---------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------

-- | Lowercase hex of a 'ByteString'.
toHex :: ByteString -> String
toHex = BC.unpack . convertToBase Base16

{- | Render one fixture as a documented Aiken constant.  @aiken fmt@ (run by
@just gen-migration-types-vectors@) collapses short constants back onto a
single line, yielding canonical, drift-stable output.
-}
renderVec :: Vec -> String
renderVec (Vec name doc bytes) =
    unlines
        [ "/// " <> doc
        , "pub const " <> name <> ": ByteArray ="
        , "  #\"" <> toHex bytes <> "\""
        ]

-- | The full self-contained Aiken fixtures module.
render :: String
render =
    header <> "\n" <> concatMap (\v -> renderVec v <> "\n") vectors
  where
    header =
        unlines
            [ "//// Auto-generated Aiken migration parity fixtures for #254 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-migration-types-vectors` (runs"
            , "//// offchain/app/GenMigrationTypesVectors.hs). Every constant is computed"
            , "//// by the Haskell wire codec in Cardano.KERI.AID.Migration.Types: the"
            , "//// `fixture_` inputs both languages build their values from, the `golden_`"
            , "//// canonical Plutus-Data CBOR the Aiken encoder must reproduce, and the"
            , "//// `negative_` encodings of one named field mutation each."
            , "//// `just check-migration-types-vectors` forbids drift."
            ]

-- ---------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------

-- | Write the fixtures module to the argv path, or to stdout when none given.
main :: IO ()
main = do
    selfCheck
    args <- getArgs
    case args of
        (out : _) -> writeFile out render
        [] -> putStr render
