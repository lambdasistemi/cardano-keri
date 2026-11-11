{- |
Module      : Cardano.KERI.Deployment.RegistryFixture
Description : A registry identity for the specs that derive the release scripts

The checkpoint validator is applied to a registry's state policy and name. The
specs that derive the whole artifact set need some registry; this one is a
fixed stand-in, never a deployed identity.
-}
module Cardano.KERI.Deployment.RegistryFixture (
    fixtureRegistry,
    fixtureApplicationPolicy,
) where

import Cardano.KERI.Deployment.Script (RegistryIdentity (..))
import Data.ByteString qualified as BS

{- | The policy of an application, fixed filler bytes: the checkpoint validator is
applied to it. Like 'fixtureRegistry' it is never a deployed identity.
-}
fixtureApplicationPolicy :: BS.ByteString
fixtureApplicationPolicy = BS.replicate 28 0x5c

-- | A registry whose state policy and name are fixed filler bytes.
fixtureRegistry :: RegistryIdentity
fixtureRegistry =
    RegistryIdentity
        { registryStatePolicy = BS.replicate 28 0x5a
        , registryName = BS.replicate 32 0x5b
        }
