{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.ChainQuery.Program
Description : The minimal provider-neutral free chain-query program (#257)

Exactly the five current snapshot-read operation families (DAT-257-OP) plus
their typed continuations. A 'ChainQuery' value carries no provider
configuration, URL, token, database handle, or 'IO' effect — it is composed
with ordinary 'Monad'\/'Applicative' syntax and only gains meaning once
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery' supplies exactly one
interpreter (INV-257-PROVIDER, RQ-257-02).
-}
module Cardano.KERI.ChainQuery.Program (
    -- * The free program and operation functor
    ChainQuery,
    ChainQueryF (..),

    -- * Smart operations (FUN-257-CURRENT .. FUN-257-WATERMARK)
    currentCheckpoint,
    liveCheckpoints,
    referenceScripts,
    boardCatalog,
    payerUtxos,
    storeWatermark,

    -- * Interpretation (for "Cardano.KERI.ChainQuery.Interpreter" only)
    foldChainQuery,
) where

import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint,
    BoardEntry,
    BoardLocator,
    ChainAssetUtxo,
    ChainQueryError,
    ChainReference,
    ChainWatermark,
    CheckpointLocator,
    ColdOr,
    validAid,
    validBoardLocator,
    validCheckpointLocator,
    validPayerAddresses,
    validReferenceHashes,
 )
import Data.Text (Text)

{- | One snapshot-read operation and its typed continuation. Every family
carries only provider-neutral, validated arguments (DATA-INV-257-01) —
never a URL, token, database handle, or provider callback.
-}
data ChainQueryF next
    = CurrentCheckpoint !CheckpointLocator !Text (Maybe ActiveCheckpoint -> next)
    | LiveCheckpoints !CheckpointLocator ([ActiveCheckpoint] -> next)
    | ReferenceScripts ![Text] ([ChainReference] -> next)
    | BoardCatalog !BoardLocator ([BoardEntry] -> next)
    | PayerUtxos ![Text] ([ChainAssetUtxo] -> next)
    | StoreWatermark (ColdOr ChainWatermark -> next)

instance Functor ChainQueryF where
    fmap f = \case
        CurrentCheckpoint locator aid k -> CurrentCheckpoint locator aid (f . k)
        LiveCheckpoints locator k -> LiveCheckpoints locator (f . k)
        ReferenceScripts hashes k -> ReferenceScripts hashes (f . k)
        BoardCatalog locator k -> BoardCatalog locator (f . k)
        PayerUtxos addrs k -> PayerUtxos addrs (f . k)
        StoreWatermark k -> StoreWatermark (f . k)

{- | The provider-neutral free program (DAT-257-PROGRAM). Its type
parameter is the program result; it contains no provider configuration or
effect handle.
-}
data ChainQuery a
    = Pure a
    | Free (ChainQueryF (ChainQuery a))

instance Functor ChainQuery where
    fmap f (Pure a) = Pure (f a)
    fmap f (Free op) = Free (fmap (fmap f) op)

instance Applicative ChainQuery where
    pure = Pure
    Pure f <*> x = fmap f x
    Free op <*> x = Free (fmap (<*> x) op)

instance Monad ChainQuery where
    Pure a >>= f = f a
    Free op >>= f = Free (fmap (>>= f) op)

liftOp :: ChainQueryF a -> ChainQuery a
liftOp = Free . fmap Pure

{- | FUN-257-CURRENT: the current checkpoint UTxO for one AID, if any.

DATA-INV-257-01 (NOTE-020): validates the locator and AID EAGERLY, the
moment this operation is built from a concrete argument -- literal or
derived from any real earlier operation's result -- never enumerating
possible continuations. An invalid argument never becomes a 'ChainQueryF'
node, so no interpreter is ever given the chance to answer it; this is a
structural, not enumerable, guarantee.
-}
currentCheckpoint :: CheckpointLocator -> Text -> ChainQuery (Either ChainQueryError (Maybe ActiveCheckpoint))
currentCheckpoint locator aid =
    case validCheckpointLocator locator >> validAid aid of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (CurrentCheckpoint locator aid id)

-- | FUN-257-LIVE: every currently live checkpoint at the checkpoint address.
liveCheckpoints :: CheckpointLocator -> ChainQuery (Either ChainQueryError [ActiveCheckpoint])
liveCheckpoints locator =
    case validCheckpointLocator locator of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (LiveCheckpoints locator id)

{- | FUN-257-REFERENCES: the current UTxO holding each requested reference
script, by script hash. Zero requested hashes is a legal empty/no-op shape
(NOTE-020); every SUPPLIED hash must be canonical.
-}
referenceScripts :: [Text] -> ChainQuery (Either ChainQueryError [ChainReference])
referenceScripts hashes =
    case validReferenceHashes hashes of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (ReferenceScripts hashes id)

-- | FUN-257-BOARD: the authenticated endpoint-board catalog.
boardCatalog :: BoardLocator -> ChainQuery (Either ChainQueryError [BoardEntry])
boardCatalog locator =
    case validBoardLocator locator of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (BoardCatalog locator id)

{- | FUN-257-PAYER: every live UTxO at the given payer addresses. An empty
address SELECTOR is invalid (NOTE-020 mandate ruling: DAT-257-OP requires a
non-empty set of ledger addresses), distinct from a non-empty selector's
legal empty RESULT.
-}
payerUtxos :: [Text] -> ChainQuery (Either ChainQueryError [ChainAssetUtxo])
payerUtxos addresses =
    case validPayerAddresses addresses of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (PayerUtxos addresses id)

-- | FUN-257-WATERMARK: the provider's current slot\/hash watermark.
storeWatermark :: ChainQuery (ColdOr ChainWatermark)
storeWatermark = liftOp (StoreWatermark id)

{- | Structural interpretation of a whole program given a per-operation
handler in the target effect. This is the only way to observe a
'ChainQuery' value's internal shape; ordinary composition never needs it.
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery' is the sole caller.
-}
foldChainQuery ::
    (Monad m) =>
    (forall x. ChainQueryF (m x) -> m x) ->
    ChainQuery a ->
    m a
foldChainQuery handle = go
  where
    go (Pure a) = pure a
    go (Free op) = handle (fmap go op)
