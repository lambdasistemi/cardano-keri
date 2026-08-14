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
    armedCheckpoint,
    armedHunter,
    armedDeadline,

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

{- | Versioned ARMED datum, one shared sum with two wire versions.

@ArmedV1@ is constructor 0 and @ArmedV2@ is constructor 1; both carry the
unchanged inner 'CheckpointDatumV1', hunter key hash, and hard deadline as
their three fields.  #254 S254-E's lean successor is deliberately identical in
shape: it carries no version integer, migration origin, commitment wrapper, or
arbitration state, because a freeze under the entitled family differs from a
legacy one in /how it was earned/, not in what it records.

A freeze PRODUCES @ArmedV2@.  Both constructors stay decodable and every
reader goes through 'armedCheckpoint', 'armedHunter' and 'armedDeadline', so
existing @ArmedV1@ state remains spendable and no consumer can quietly become
version-specific.
-}
data ArmedDatum
    = ArmedV1
        { adCheckpoint :: !CheckpointDatumV1
        , adHunterPkh :: !ByteString
        , adDeadline :: !Integer
        }
    | ArmedV2
        { adCheckpoint :: !CheckpointDatumV1
        , adHunterPkh :: !ByteString
        , adDeadline :: !Integer
        }
    deriving stock (Show, Eq)

-- | Strip the 'BuiltinData' wrapper from a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- | The carried checkpoint state, whichever ARMED version holds it.
armedCheckpoint :: ArmedDatum -> CheckpointDatumV1
armedCheckpoint = adCheckpoint

-- | The stored hunter, whichever ARMED version holds it.
armedHunter :: ArmedDatum -> ByteString
armedHunter = adHunterPkh

-- | The stored hard deadline, whichever ARMED version holds it.
armedDeadline :: ArmedDatum -> Integer
armedDeadline = adDeadline

instance ToData ArmedDatum where
    toBuiltinData armed =
        BuiltinData $
            Constr
                (armedConstructor armed)
                [ asData (armedCheckpoint armed)
                , B (armedHunter armed)
                , I (armedDeadline armed)
                ]

-- | The wire version tag of an ARMED datum.
armedConstructor :: ArmedDatum -> Integer
armedConstructor ArmedV1{} = 0
armedConstructor ArmedV2{} = 1

instance FromData ArmedDatum where
    fromBuiltinData (BuiltinData (Constr tag [checkpoint, B hunter, I deadline]))
        | tag == 0 = decoded ArmedV1
        | tag == 1 = decoded ArmedV2
      where
        decoded construct = do
            inner <- fromBuiltinData (BuiltinData checkpoint)
            pure (construct inner hunter deadline)
    fromBuiltinData _ = Nothing

-- | ARMED datum well-formedness rejection reason.
data ArmedDatumError
    = HunterPkhWidth
    deriving stock (Show, Eq)

{- | The recorded hunter must be an exact 28-byte Cardano key hash.  Both
versions are held to the same rule; there is no relaxed successor.
-}
armedDatumWellFormed :: ArmedDatum -> Either ArmedDatumError ()
armedDatumWellFormed armed =
    unless (BS.length (armedHunter armed) == 28) (Left HunterPkhWidth)

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
