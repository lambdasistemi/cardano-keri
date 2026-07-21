{- |
Module      : Cardano.KERI.AID.Checkpoint.FreezeBond
Description : Freeze-bond schema and raw deadline model, #116

The validator-free parity model for the freeze-bond parameters, lifecycle
roles, versioned @ArmedV1@ wire datum, and validity-range endpoint rules.
Endpoint inclusivity is retained as raw ledger data and never normalized into
a synthetic "greatest included" timestamp.
-}
module Cardano.KERI.AID.Checkpoint.FreezeBond (
    -- * Deployment parameters
    freezeBondFloor,
    freezeBondValid,
    freezeWindowValid,

    -- * Lifecycle roles
    Role (..),
    roleTag,
    roleHash,

    -- * Versioned ARMED datum
    ArmedDatum (..),
    ArmedDatumError (..),
    armedDatumWellFormed,

    -- * Raw validity-range endpoints
    Inclusivity (..),
    RawBound (..),
    DeadlineError (..),
    armDeadline,
    responseBeforeDeadline,
    claimAtOrAfterDeadline,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_224,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1,
 )
import Control.Monad (
    unless,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Proxy (
    Proxy (..),
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- | Mechanical minimum deployment bond in lovelace.
freezeBondFloor :: Integer
freezeBondFloor = 5_000_000

-- | Whether the configured freeze bond meets its mechanical floor.
freezeBondValid :: Integer -> Bool
freezeBondValid = (>= freezeBondFloor)

-- | The freeze window must contain at least one validity-range time unit.
freezeWindowValid :: Integer -> Bool
freezeWindowValid = (> 0)

-- | Full checkpoint lifecycle roles delivered through #116.
data Role
    = Active
    | Frozen
    | Tombstone
    | Armed
    deriving stock (Show, Eq)

-- | Frozen staking-role byte tag. ACTIVE remains a bare script address.
roleTag :: Role -> Maybe ByteString
roleTag Active = Nothing
roleTag Frozen = Just "\x00"
roleTag Tombstone = Just "\x01"
roleTag Armed = Just "\x02"

-- | Deterministic staking-script hash for a tagged role.
roleHash :: ByteString -> Role -> Maybe ByteString
roleHash policy role =
    fmap
        (\tag -> digest (Proxy @Blake2b_224) (BS.concat [roleDomain, policy, tag]))
        (roleTag role)

roleDomain :: ByteString
roleDomain = "cardano-keri/checkpoint/role/v1"

{- | Versioned ARMED datum. The @ArmedV1@ constructor is the wire version tag
(@Constr 0@), with the unchanged inner 'CheckpointDatumV1', hunter key hash,
and hard deadline as its three fields.
-}
data ArmedDatum = ArmedV1
    { adCheckpoint :: !CheckpointDatumV1
    , adHunterPkh :: !ByteString
    , adDeadline :: !Integer
    }
    deriving stock (Show, Eq)

-- | Strip the 'BuiltinData' wrapper from a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

instance ToData ArmedDatum where
    toBuiltinData ArmedV1{..} =
        BuiltinData $
            Constr
                0
                [ asData adCheckpoint
                , B adHunterPkh
                , I adDeadline
                ]

instance FromData ArmedDatum where
    fromBuiltinData (BuiltinData (Constr 0 [checkpoint, B hunter, I deadline])) = do
        adCheckpoint <- fromBuiltinData (BuiltinData checkpoint)
        pure
            ArmedV1
                { adCheckpoint = adCheckpoint
                , adHunterPkh = hunter
                , adDeadline = deadline
                }
    fromBuiltinData _ = Nothing

-- | ARMED datum well-formedness rejection reason.
data ArmedDatumError
    = HunterPkhWidth
    deriving stock (Show, Eq)

-- | The recorded hunter must be an exact 28-byte Cardano key hash.
armedDatumWellFormed :: ArmedDatum -> Either ArmedDatumError ()
armedDatumWellFormed ArmedV1{..} =
    unless (BS.length adHunterPkh == 28) (Left HunterPkhWidth)

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

-- | Failure to derive the arming deadline from the required raw upper bound.
data DeadlineError
    = MissingUpperBound
    | NonFiniteUpperBound
    | NonPositiveFreezeWindow
    deriving stock (Show, Eq)

{- | Derive the hard deadline from the raw finite upper endpoint. Integer
addition is exact and arbitrary precision; inclusivity does not move @u@.
-}
armDeadline :: Integer -> Maybe RawBound -> Either DeadlineError Integer
armDeadline freezeWindow upper = do
    unless (freezeWindowValid freezeWindow) (Left NonPositiveFreezeWindow)
    case upper of
        Nothing -> Left MissingUpperBound
        Just (Finite u _) -> Right (u + freezeWindow)
        Just NegativeInfinity -> Left NonFiniteUpperBound
        Just PositiveInfinity -> Left NonFiniteUpperBound

-- | A response requires a finite raw upper endpoint strictly before deadline.
responseBeforeDeadline :: Integer -> Maybe RawBound -> Bool
responseBeforeDeadline deadline (Just (Finite upper _)) = upper < deadline
responseBeforeDeadline _ _ = False

-- | A claim requires a finite raw lower endpoint at or after deadline.
claimAtOrAfterDeadline :: Integer -> Maybe RawBound -> Bool
claimAtOrAfterDeadline deadline (Just (Finite lower _)) = lower >= deadline
claimAtOrAfterDeadline _ _ = False
