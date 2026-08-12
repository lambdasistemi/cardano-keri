{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Main
Description : Canonical Haskell oracle for the #271 bounty-commitment wire

The family-independent parity oracle for @MOD-271-OFFCHAIN@: one Haskell
computation is the sole source of every committed canonical byte string,
commitment hash, and marker name in
@onchain\/lib\/cardano_keri\/bounty_commitment_vectors.ak@. Aiken recomputes
each one, and the committed module is rejected on drift by
@scripts\/check-bounty-commitment-vectors.sh@.

This slice may not add a Cabal component (build configuration is outside its
fence), so the program is self-contained and runs interpreted:

> cd offchain && nix develop --no-write-lock-file -c runghc app/GenBountyCommitmentVectors.hs OUT

It mirrors the Aiken wire shapes as explicit Plutus 'Data' trees rather than
deriving them from the on-chain types, which is what makes it an independent
oracle: a change on either side that is not mirrored on the other breaks the
committed vectors.
-}
module Main (main) where

import Crypto.Hash (
    Blake2b_256 (..),
    hashWith,
 )
import Data.Bits (
    xor,
 )
import Data.ByteArray (
    convert,
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
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins (
    serialiseData,
 )
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
    BuiltinData (..),
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
        _ -> error "usage: GenBountyCommitmentVectors.hs [OUT_PATH]"

-- ---------------------------------------------------------
-- Frozen protocol surface (mirrors cardano_keri/bounty_commitment)
-- ---------------------------------------------------------

commitmentDomain :: ByteString
commitmentDomain = "cardano-keri/bounty-commitment"

commitmentSchema :: Integer
commitmentSchema = 1

commitMinAge :: Integer
commitMinAge = 1

commitDepositFloor :: Integer
commitDepositFloor = 5000000

-- ---------------------------------------------------------
-- Wire mirrors
-- ---------------------------------------------------------

-- | An @OutputReference@: a one-constructor record.
outRef :: ByteString -> Integer -> Data
outRef txId index = Constr 0 [B txId, I index]

-- | @FreezeEntitlement@ is constructor 0, @ConvictEntitlement@ is 1.
freezeAction :: Data
freezeAction = Constr 0 []

convictAction :: Data
convictAction = Constr 1 []

-- | The @BountyScope@ mirror.
data Scope = Scope
    { scDomain :: ByteString
    , scSchema :: Integer
    , scNetwork :: Integer
    , scCheckpointPolicy :: ByteString
    , scCheckpointRef :: Data
    , scAction :: Data
    , scMarker :: ByteString
    , scCommitUpper :: Integer
    , scEligibleAfter :: Integer
    , scExpiresAt :: Integer
    }

scopeData :: Scope -> Data
scopeData s =
    Constr
        0
        [ B (scDomain s)
        , I (scSchema s)
        , I (scNetwork s)
        , B (scCheckpointPolicy s)
        , scCheckpointRef s
        , scAction s
        , B (scMarker s)
        , I (scCommitUpper s)
        , I (scEligibleAfter s)
        , I (scExpiresAt s)
        ]

-- | The @BountyCommitmentPreimage@ mirror.
data Preimage = Preimage
    { piScope :: Scope
    , piDigest :: ByteString
    , piPayee :: ByteString
    , piNonce :: ByteString
    }

preimageData :: Preimage -> Data
preimageData p =
    Constr
        0
        [ scopeData (piScope p)
        , B (piDigest p)
        , B (piPayee p)
        , B (piNonce p)
        ]

-- | @BountyCommitmentV1@: scope, payee, opaque hash, marker.
commitmentData :: Scope -> ByteString -> ByteString -> ByteString -> Data
commitmentData s pkh hash mkr =
    Constr 0 [scopeData s, B pkh, B hash, B mkr]

-- | @BountyRevealV1@.
revealData :: Data -> ByteString -> Integer -> Data
revealData commitmentRef n refundIndex =
    Constr 0 [commitmentRef, B n, I refundIndex]

-- | @ExpiredCommitmentSweepV1@.
sweepData :: ByteString -> Integer -> Data
sweepData rcpt payoutIndex = Constr 0 [B rcpt, I payoutIndex]

-- ---------------------------------------------------------
-- Canonical encoding and hashing
-- ---------------------------------------------------------

-- | Canonical Plutus 'Data' CBOR — the bytes Aiken @cbor.serialise@ emits.
canonical :: Data -> ByteString
canonical d = let BuiltinByteString bs = serialiseData (BuiltinData d) in bs

{- | The Plutus @blake2b_256@ builtin's digest. Cross-checked against
coreutils @b2sum -l 256@ so the oracle is not self-certifying.
-}
blake2b256 :: ByteString -> ByteString
blake2b256 = convert . hashWith Blake2b_256

commitmentHash :: Preimage -> ByteString
commitmentHash = blake2b256 . canonical . preimageData

markerName :: Data -> ByteString
markerName = blake2b256 . canonical

-- ---------------------------------------------------------
-- The canonical fixture
-- ---------------------------------------------------------

seedTxId :: ByteString
seedTxId = BS.replicate 32 0x5e

seedIndex :: Integer
seedIndex = 7

seedRef :: Data
seedRef = outRef seedTxId seedIndex

otherSeedRef :: Data
otherSeedRef = outRef seedTxId (seedIndex + 1)

marker :: ByteString
marker = markerName seedRef

otherMarker :: ByteString
otherMarker = markerName otherSeedRef

checkpointPolicy :: ByteString
checkpointPolicy = BS.replicate 28 0xc1

checkpointTxId :: ByteString
checkpointTxId = BS.replicate 32 0xc2

checkpointIndex :: Integer
checkpointIndex = 3

checkpointRef :: Data
checkpointRef = outRef checkpointTxId checkpointIndex

payee :: ByteString
payee = BS.replicate 28 0x9a

recipient :: ByteString
recipient = BS.replicate 28 0x7e

digest :: ByteString
digest = BS.replicate 32 0xed

nonce :: ByteString
nonce = BS.replicate 32 0x11

commitUpper :: Integer
commitUpper = 1000

{- | The release lifetime this fixture's deployment chose, in slots.

An explicitly named example, not a protocol default: the release magnitude
is an applied parameter of the on-chain program, so neither language
publishes a mandated value for it. Only the *derived* boundary below is
emitted as a vector, and the Aiken side binds it back to its own named
example, so changing this without changing that reddens a proof instead of
regenerating quietly.
-}
exampleLifetime :: Integer
exampleLifetime = 10000

eligibleAfter :: Integer
eligibleAfter = commitUpper + commitMinAge

expiresAt :: Integer
expiresAt = commitUpper + exampleLifetime

refundIndex :: Integer
refundIndex = 1

payoutIndex :: Integer
payoutIndex = 0

scope :: Scope
scope =
    Scope
        { scDomain = commitmentDomain
        , scSchema = commitmentSchema
        , scNetwork = 42
        , scCheckpointPolicy = checkpointPolicy
        , scCheckpointRef = checkpointRef
        , scAction = freezeAction
        , scMarker = marker
        , scCommitUpper = commitUpper
        , scEligibleAfter = eligibleAfter
        , scExpiresAt = expiresAt
        }

preimage :: Preimage
preimage =
    Preimage
        { piScope = scope
        , piDigest = digest
        , piPayee = payee
        , piNonce = nonce
        }

canonicalHash :: ByteString
canonicalHash = commitmentHash preimage

-- ---------------------------------------------------------
-- One-field mutants: every independently changed field must move the hash
-- ---------------------------------------------------------

-- | Flip the low bit of the last byte, leaving the width unchanged.
flipLast :: ByteString -> ByteString
flipLast bs = case BS.unsnoc bs of
    Nothing -> bs
    Just (initial, final) -> BS.snoc initial (final `xor` 1)

withScope :: (Scope -> Scope) -> Preimage
withScope f = preimage{piScope = f scope}

-- | @(vector name, mutated preimage)@ — the name is the emitted constant.
mutants :: [(String, Preimage)]
mutants =
    [ ("mut_domain", withScope (\s -> s{scDomain = "cardano-keri/other"}))
    , ("mut_schema", withScope (\s -> s{scSchema = commitmentSchema + 1}))
    , ("mut_network", withScope (\s -> s{scNetwork = 2}))
    ,
        ( "mut_checkpoint_policy"
        , withScope (\s -> s{scCheckpointPolicy = flipLast checkpointPolicy})
        )
    ,
        ( "mut_checkpoint_txid"
        , withScope
            (\s -> s{scCheckpointRef = outRef (flipLast checkpointTxId) checkpointIndex})
        )
    ,
        ( "mut_checkpoint_index"
        , withScope
            (\s -> s{scCheckpointRef = outRef checkpointTxId (checkpointIndex + 1)})
        )
    , ("mut_action", withScope (\s -> s{scAction = convictAction}))
    , ("mut_marker", withScope (\s -> s{scMarker = otherMarker}))
    ,
        ( "mut_window"
        , withScope
            ( \s ->
                s
                    { scCommitUpper = commitUpper + 1
                    , scEligibleAfter = eligibleAfter + 1
                    , scExpiresAt = expiresAt + 1
                    }
            )
        )
    ,
        ( "mut_eligible_after"
        , withScope (\s -> s{scEligibleAfter = eligibleAfter + 1})
        )
    , ("mut_expires_at", withScope (\s -> s{scExpiresAt = expiresAt + 1}))
    , ("mut_payee", preimage{piPayee = flipLast payee})
    , ("mut_digest", preimage{piDigest = flipLast digest})
    , ("mut_nonce", preimage{piNonce = flipLast nonce})
    ]

-- ---------------------------------------------------------
-- Emission
-- ---------------------------------------------------------

output :: String
output =
    unlines
        ( [ "//// GENERATED by offchain/app/GenBountyCommitmentVectors.hs. DO NOT EDIT."
          , "//// `scripts/check-bounty-commitment-vectors.sh` regenerates and rejects drift."
          , ""
          , byteConst "domain" commitmentDomain
          , intConst "schema" commitmentSchema
          , intConst "network" 42
          , intConst "commit_min_age" commitMinAge
          , intConst "commit_deposit_floor" commitDepositFloor
          , intConst "commit_deposit" appliedDeposit
          , intConst "commit_upper" commitUpper
          , intConst "eligible_after" eligibleAfter
          , intConst "expires_at" expiresAt
          , intConst "refund_index" refundIndex
          , intConst "payout_index" payoutIndex
          , intConst "seed_index" seedIndex
          , intConst "checkpoint_index" checkpointIndex
          , byteConst "seed_txid" seedTxId
          , byteConst "checkpoint_txid" checkpointTxId
          , byteConst "checkpoint_policy" checkpointPolicy
          , byteConst "payee" payee
          , byteConst "recipient" recipient
          , byteConst "evidence_digest" digest
          , byteConst "nonce" nonce
          , byteConst "marker" marker
          , byteConst "other_marker" otherMarker
          , byteConst "commitment_hash" canonicalHash
          , byteConst "golden_seed_ref" (canonical seedRef)
          , byteConst "golden_checkpoint_ref" (canonical checkpointRef)
          , byteConst "golden_action_freeze" (canonical freezeAction)
          , byteConst "golden_action_convict" (canonical convictAction)
          , byteConst "golden_scope" (canonical (scopeData scope))
          , byteConst "golden_preimage" (canonical (preimageData preimage))
          , byteConst "golden_commitment" (canonical commitmentDatum)
          , byteConst "golden_reveal" (canonical revealRedeemer)
          , byteConst "golden_sweep" (canonical sweepRedeemer)
          , byteConst "golden_spend_reveal" (canonical (Constr 0 [revealRedeemer]))
          , byteConst "golden_spend_sweep" (canonical (Constr 1 [sweepRedeemer]))
          , byteConst "golden_mint_open" (canonical (Constr 0 [seedRef]))
          , byteConst "golden_mint_retire" (canonical (Constr 1 []))
          ]
            <> map mutantConst mutants
        )

appliedDeposit :: Integer
appliedDeposit = commitDepositFloor + 1000000

commitmentDatum :: Data
commitmentDatum = commitmentData scope payee canonicalHash marker

revealRedeemer :: Data
revealRedeemer =
    revealData (outRef (BS.replicate 32 0x0c) 0) nonce refundIndex

sweepRedeemer :: Data
sweepRedeemer = sweepData recipient payoutIndex

mutantConst :: (String, Preimage) -> String
mutantConst (name, mutant) = byteConst name (commitmentHash mutant)

byteConst :: String -> ByteString -> String
byteConst name value =
    "pub const " <> name <> ": ByteArray = #\"" <> hex value <> "\"\n"

intConst :: String -> Integer -> String
intConst name value = "pub const " <> name <> ": Int = " <> show value <> "\n"

hex :: ByteString -> String
hex = BC.unpack . convertToBase Base16
