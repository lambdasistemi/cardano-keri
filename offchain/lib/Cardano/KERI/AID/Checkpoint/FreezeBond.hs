{- |
Module      : Cardano.KERI.AID.Checkpoint.FreezeBond
Description : Freeze-bond floor, the checkpoint role and raw bounds

The validator-free parity model for the freeze-bond floor and the checkpoint
role: a checkpoint sits at the bare script address (active).  The raw
validity-range endpoint types are retained exactly as the ledger states them:
inclusivity is never normalized.
-}
module Cardano.KERI.AID.Checkpoint.FreezeBond (
    -- * Deployment parameters
    freezeBondFloor,
    freezeBondValid,

    -- * Checkpoint role
    Role (..),

    -- * Raw validity-range endpoints
    Inclusivity (..),
    RawBound (..),
) where

-- | Mechanical minimum deployment bond in lovelace.
freezeBondFloor :: Integer
freezeBondFloor = 5_000_000

-- | Whether the configured freeze bond meets its mechanical floor.
freezeBondValid :: Integer -> Bool
freezeBondValid = (>= freezeBondFloor)

-- | The checkpoint role. ACTIVE is a bare script address.
data Role
    = Active
    deriving stock (Show, Eq)

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
