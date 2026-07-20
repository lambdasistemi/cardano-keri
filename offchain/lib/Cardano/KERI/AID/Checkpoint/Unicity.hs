{- |
Module      : Cardano.KERI.AID.Checkpoint.Unicity
Description : Append-only registration-registry reference model, #116 S3

Pure Haskell mirror of the frozen registry labels and MPFS absence transition.
The same functions feed the committed Aiken depth-0/8/16 vectors.
-}
module Cardano.KERI.AID.Checkpoint.Unicity (
    RegistrySeed (..),
    roleDomain,
    registryThreadDomain,
    registeredDomain,
    roleHash,
    registryThreadName,
    registeredMarker,
    emptyRegistryRoot,
    transitionRoots,
    validAbsenceTransition,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_224,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Cardano.KERI.AID.Cage.Types (
    ProofStep,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    blake2b_256,
    canonicalCbor,
 )
import Cardano.KERI.AID.E2E.Mpf (
    emptyRoot,
 )
import Cardano.KERI.AID.E2E.MpfProof (
    excludingRoot,
    includingRoot,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Proxy (
    Proxy (..),
 )
import Data.Word (
    Word8,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
 )

-- | Minimal cross-language representation of Cardano's @OutputReference@.
data RegistrySeed = RegistrySeed
    { registrySeedTxId :: !ByteString
    , registrySeedIndex :: !Integer
    }
    deriving stock (Show, Eq)

instance ToData RegistrySeed where
    toBuiltinData RegistrySeed{..} =
        BuiltinData (Constr 0 [B registrySeedTxId, I registrySeedIndex])

-- | Domain for policy-specific staking-role hashes.
roleDomain :: ByteString
roleDomain = "cardano-keri/checkpoint/role/v1"

-- | Domain for the one-shot registry thread asset name.
registryThreadDomain :: ByteString
registryThreadDomain = "cardano-keri/checkpoint/registry-thread/v1"

-- | Domain whose digest is stored as the immutable set value.
registeredDomain :: ByteString
registeredDomain = "cardano-keri/checkpoint/registered/v1"

-- | @blake2b_224(roleDomain || appliedPolicyHash || tag)@.
roleHash :: ByteString -> Word8 -> ByteString
roleHash policy tag = digest (Proxy @Blake2b_224) (roleDomain <> policy <> BS.singleton tag)

-- | @blake2b_256(registryThreadDomain || cbor.serialise(seed))@.
registryThreadName :: RegistrySeed -> ByteString
registryThreadName seed =
    blake2b_256 (registryThreadDomain <> canonicalCbor seed)

-- | Fixed value inserted for every registered AID key.
registeredMarker :: ByteString
registeredMarker = blake2b_256 registeredDomain

-- | MPFS empty root.
emptyRegistryRoot :: ByteString
emptyRegistryRoot = emptyRoot

-- | Roots before and after inserting the fixed marker with an absence proof.
transitionRoots :: ByteString -> [ProofStep] -> (ByteString, ByteString)
transitionRoots key proof =
    ( excludingRoot key proof
    , includingRoot key registeredMarker proof
    )

-- | Exact mirror of the live validator's old-root and successor-root checks.
validAbsenceTransition :: ByteString -> ByteString -> ByteString -> [ProofStep] -> Bool
validAbsenceTransition oldRoot newRoot key proof =
    transitionRoots key proof == (oldRoot, newRoot)
