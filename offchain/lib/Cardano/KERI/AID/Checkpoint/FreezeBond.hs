{- |
Module      : Cardano.KERI.AID.Checkpoint.FreezeBond
Description : Freeze-bond floor, checkpoint lifecycle roles and raw bounds

The validator-free parity model for the freeze-bond floor and the checkpoint
lifecycle roles.  A checkpoint is either at the bare script address (active)
or, once convicted, at the tombstone role address.  The raw validity-range
endpoint types are retained exactly as the ledger states them: inclusivity is
never normalized.
-}
module Cardano.KERI.AID.Checkpoint.FreezeBond (
    -- * Deployment parameters
    freezeBondFloor,
    freezeBondValid,

    -- * Lifecycle roles
    Role (..),
    roleTag,
    roleHash,

    -- * Raw validity-range endpoints
    Inclusivity (..),
    RawBound (..),
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_224,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Proxy (
    Proxy (..),
 )

-- | Mechanical minimum deployment bond in lovelace.
freezeBondFloor :: Integer
freezeBondFloor = 5_000_000

-- | Whether the configured freeze bond meets its mechanical floor.
freezeBondValid :: Integer -> Bool
freezeBondValid = (>= freezeBondFloor)

-- | Checkpoint lifecycle roles.
data Role
    = Active
    | Tombstone
    deriving stock (Show, Eq)

-- | Staking-role byte tag. ACTIVE remains a bare script address.
roleTag :: Role -> Maybe ByteString
roleTag Active = Nothing
roleTag Tombstone = Just "\x01"

-- | Deterministic staking-script hash for a tagged role.
roleHash :: ByteString -> Role -> Maybe ByteString
roleHash policy role =
    fmap
        (\tag -> digest (Proxy @Blake2b_224) (BS.concat [roleDomain, policy, tag]))
        (roleTag role)

roleDomain :: ByteString
roleDomain = "cardano-keri/checkpoint/role/v1"

-- | Raw ledger endpoint inclusivity. It is preserved, never normalized.
data Inclusivity
    = Inclusive
    | Exclusive
    deriving stock (Show, Eq)

-- | A raw validity-range bound, including its infinities and inclusion flag.
data RawBound
    = NegativeInfinity
    | Finite !Integer !Inclusivity
    | PositiveInfinity
    deriving stock (Show, Eq)
