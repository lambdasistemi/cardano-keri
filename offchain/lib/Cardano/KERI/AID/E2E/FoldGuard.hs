{- |
Module      : Cardano.KERI.AID.E2E.FoldGuard
Description : what the fold and booking builders refuse before they compute anything

The fold builder asks this module before it computes anything for a fold: a
request whose key the registry already holds, active or terminated, is refused,
by name, and no transaction is built. The termination booking builder asks it
before it builds a booking: a key with no pending output at the checkpoint
validator is refused. The functions are pure; they take the keys the caller
read from the chain (or recorded after a terminating fold it built) and the
request's key.

The set of terminated keys is supplied by the caller. The guard does not
discover it: a key the caller does not list is not refused here, and the
registry's own insertion is what refuses it at the ledger.
-}
module Cardano.KERI.AID.E2E.FoldGuard (
    FoldRefusal (..),
    foldRefusal,
    BookingRefusal (..),
    bookingRefusal,
) where

import Control.Exception (Exception)
import Data.ByteString (ByteString)

-- | Why the builder will not build a fold.
data FoldRefusal
    = -- | the registry already holds the request's key, active
      KeyAlreadyRegistered ByteString
    | -- | the registry holds the request's key, terminated
      KeyIsTerminal ByteString
    | -- | the keys the builder was given are not the keys the chain's registry holds
      KeysAreNotTheRegistry
    deriving stock (Eq, Show)

instance Exception FoldRefusal

{- | The refusal for a request key, given the active keys and the terminated keys
the registry holds, or nothing when the key is new.
-}
foldRefusal :: [ByteString] -> [ByteString] -> ByteString -> Maybe FoldRefusal
foldRefusal registered terminated key
    | key `elem` terminated = Just (KeyIsTerminal key)
    | key `elem` registered = Just (KeyAlreadyRegistered key)
    | otherwise = Nothing

-- | Why the builder will not build a termination booking.
newtype BookingRefusal
    = -- | no pending output of a convicted checkpoint holds the key's active token
      NoPendingOutput ByteString
    deriving stock (Eq, Show)

instance Exception BookingRefusal

{- | The refusal for a termination booking of a key, given the keys of the pending
outputs at the checkpoint validator: a key without one has not been convicted,
was already booked, or is terminal (its active token is gone).
-}
bookingRefusal :: [ByteString] -> ByteString -> Maybe BookingRefusal
bookingRefusal pending key
    | key `elem` pending = Nothing
    | otherwise = Just (NoPendingOutput key)
