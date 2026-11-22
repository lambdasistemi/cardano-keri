{- |
Module      : Cardano.KERI.AID.Release
Description : The identity of one release of the registry (#353)

One value names everything a program needs to follow and read one release of
the registry: the network, the release of the application (the Lean
@PublishedRelease@: the application's policy and credential, the registry's
state script and its policy), the seed that created the registry, the script
hash of the checkpoint validator and the amounts the registry was created with
(the checkpoint deposit, the freeze bond, the premium, the minimum ADA of a
checkpoint output, the termination carrier and the application's parameters).

The deployment that creates a registry and the readers that follow it share
this type; a reader has no field of its own. From it the consumer's relying
contract is built: 'releaseContext' for an AID (the Lean @Context@),
'releaseEnvironment' (the Lean @Environment@, resolved from the same identity)
and 'registryIdentityOf' (the registry the active tokens are named after).

The type has no JSON instance; the file format is
"Cardano.KERI.ChainQuery.ReleaseIdentity".
-}
module Cardano.KERI.AID.Release (
    ReleaseIdentity (..),
    releaseContext,
    releaseEnvironment,
    registryIdentityOf,
) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    Credential (..),
    OutputReference (..),
    RegistryIdentity (..),
    stateTokenName,
 )
import Cardano.KERI.AID.Consumer (
    Context (..),
    Environment (..),
    Release (..),
 )
import Data.ByteString (ByteString)

{- | One release of the registry. The hashes are of the lengths of the chain's
script hashes (28 bytes) and the seed's transaction id (32 bytes); the file
codec checks that, this type does not.
-}
data ReleaseIdentity = ReleaseIdentity
    { riNetwork :: !Integer
    -- ^ the network discriminator: 0 for a test network, 1 for the main one
    , riRelease :: !Release
    -- ^ the application's policy and credential, the state program and its policy
    , riSeed :: !OutputReference
    -- ^ the output the registry was created from
    , riCheckpointValidator :: !ByteString
    -- ^ the script hash of the checkpoint validator, the payment credential of its address
    , riDeposit :: !Integer
    -- ^ the checkpoint deposit (Lean @D@)
    , riFreezeBond :: !Integer
    -- ^ the freeze bond (Lean @B@)
    , riPremium :: !Integer
    -- ^ the premium paid out of the pool at each rotation
    , riMinimumAda :: !Integer
    -- ^ the minimum ADA of a checkpoint output (Lean @Mc@)
    , riTerminationCarrier :: !Integer
    -- ^ what a termination request holds besides the tip
    , riApplicationParameters :: !ApplicationParameters
    -- ^ the application's registration cost, minimum tip, process time and booking width
    }
    deriving stock (Eq, Show)

{- | The relying contract for one AID (qualified CESR text): the identity's
network, release and seed, and the payment credential of the checkpoint
validator, where the registry's checkpoints live.
-}
releaseContext :: ReleaseIdentity -> ByteString -> Context
releaseContext ri aid =
    Context
        { cxNetwork = riNetwork ri
        , cxRelease = riRelease ri
        , cxSeed = riSeed ri
        , cxAid = aid
        , cxCheckpointCredential = ScriptCredential (riCheckpointValidator ri)
        }

{- | The network, release and checkpoint credential the integration resolved:
all three are those of the identity.
-}
releaseEnvironment :: ReleaseIdentity -> Environment
releaseEnvironment ri =
    Environment
        { envNetwork = riNetwork ri
        , envRelease = Just (riRelease ri)
        , envCheckpointCredential = Just (ScriptCredential (riCheckpointValidator ri))
        }

{- | The registry of the identity: the policy of its state script and the
name of the state token its seed names.
-}
registryIdentityOf :: ReleaseIdentity -> RegistryIdentity
registryIdentityOf ri =
    RegistryIdentity
        (rlStatePolicy (riRelease ri))
        (stateTokenName (riSeed ri))
