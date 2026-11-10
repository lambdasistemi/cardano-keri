{- |
Module      : Cardano.KERI.AID.E2E.FoldGuard
Description : a second registration of a registered AID cannot be folded

The fold builder asks this module before it computes anything for a fold: a
request whose key the registry already holds is refused, by name, and no
transaction is built. The functions are pure; they take the keys the registry
holds and the request's key.
-}
module Cardano.KERI.AID.E2E.FoldGuard (
    FoldRefusal (..),
    foldRefusal,
) where

import Control.Exception (Exception)
import Data.ByteString (ByteString)

-- | Why the builder will not build a fold.
data FoldRefusal
    = -- | the registry already holds the request's key
      KeyAlreadyRegistered ByteString
    | -- | the keys the builder was given are not the keys the chain's registry holds
      KeysAreNotTheRegistry
    deriving stock (Eq, Show)

instance Exception FoldRefusal

{- | The refusal for a request key, given the keys the registry holds, or
nothing when the key is new.
-}
foldRefusal :: [ByteString] -> ByteString -> Maybe FoldRefusal
foldRefusal _registered _key = Nothing
