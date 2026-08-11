{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.ChainQuery.Program
Description : The minimal provider-neutral free chain-query program (#257, #262)

The snapshot-read operation families of #257 (DAT-257-OP) plus the
exact-output and board-with-output families of #262 (MOD-262-QUERY), each
with its typed continuation. A 'ChainQuery' value carries no provider
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

    -- * Smart operations (FUN-262-OUTPUT, FUN-262-BOARD-OUTPUTS)
    outputAt,
    boardCatalogWithOutputs,

    -- * Interpretation (for "Cardano.KERI.ChainQuery.Interpreter" only)
    foldChainQuery,
    eagerRejection,
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
    OutputLocator,
    validAid,
    validBoardLocator,
    validCheckpointLocator,
    validOutputLocator,
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
    | BoardCatalogWithOutputs !BoardLocator ([(BoardEntry, ChainAssetUtxo)] -> next)
    | PayerUtxos ![Text] ([ChainAssetUtxo] -> next)
    | OutputAt !OutputLocator (ChainAssetUtxo -> next)
    | StoreWatermark (ColdOr ChainWatermark -> next)

instance Functor ChainQueryF where
    fmap f = \case
        CurrentCheckpoint locator aid k -> CurrentCheckpoint locator aid (f . k)
        LiveCheckpoints locator k -> LiveCheckpoints locator (f . k)
        ReferenceScripts hashes k -> ReferenceScripts hashes (f . k)
        BoardCatalog locator k -> BoardCatalog locator (f . k)
        BoardCatalogWithOutputs locator k -> BoardCatalogWithOutputs locator (f . k)
        PayerUtxos addrs k -> PayerUtxos addrs (f . k)
        OutputAt locator k -> OutputAt locator (f . k)
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

{- | FUN-262-OUTPUT: the one live output at an exact @(txid,index)@ identity,
as the same provider-neutral spendable shape every other output-bearing
operation answers with (DAT-262-SPENDABLE-OUTPUT: 'ChainAssetUtxo', reused,
never a second output representation).

The result is not a 'Maybe'. Absence, duplication, a malformed identity, and
a row the neutral shape cannot faithfully carry are all operation ERRORS
(RQ-262-01): every caller of this operation is about to SPEND the row it
names, so "no output here" is never an ordinary answer it could reasonably
continue from -- unlike
'currentCheckpoint', whose 'Nothing' genuinely means "this AID is not
registered".

Validates the locator EAGERLY, exactly like every operation above
(DATA-INV-262-01): a locator whose transaction id is not canonical lowercase
32-byte hex, or whose index is negative or outside the ledger range, never
becomes a 'ChainQueryF' node.
-}
outputAt :: OutputLocator -> ChainQuery (Either ChainQueryError ChainAssetUtxo)
outputAt locator =
    case validOutputLocator locator of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (OutputAt locator id)

{- | FUN-262-BOARD-OUTPUTS: the authenticated endpoint-board catalog with the
complete neutral output of each entry's own row, as ONE all-or-nothing
observation (RQ-262-02\/DATA-INV-262-03).

Deliberately a distinct operation rather than 'boardCatalog' followed by an
'outputAt' per entry. A write verb that spends a board record must see the
entry and the row it is about to spend in the same observation; resolving
them as N+1 separate operations would let an interpreter answer them from
different states, and would make the identity agreement between an entry and
its output a caller's obligation instead of the operation's own guarantee.
-}
boardCatalogWithOutputs ::
    BoardLocator -> ChainQuery (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
boardCatalogWithOutputs locator =
    case validBoardLocator locator of
        Left err -> pure (Left err)
        Right () -> Right <$> liftOp (BoardCatalogWithOutputs locator id)

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

{- | A-262-01 (RQ-262-03\/DATA-INV-262-01): the error a program rejected its
argument with BEFORE building any operation node, if it did.

Eager rejection is already structural: a smart constructor that refuses a
concrete argument returns @'Pure' ('Left' err)@ rather than a 'Free' node,
and because @'Pure' x '>>=' f = f x@, a composed program whose first step
rejects reduces to that same @'Pure' ('Left' err)@ — the continuation is
never built, so nothing downstream of the rejection exists either. This
function is the one place that FACT is readable, and it exists because
knowing it structurally was not enough: a runner that appends its own
operation to every program — as the snapshot runner \#262 A-262-02 deleted
appended the watermark — dispatches that operation for a rejected program
too, and the rejection then reaches its caller having caused an effect after
all.

Deliberately specialised to a program whose result carries
'ChainQueryError'. A rejection is only observable where there is a channel
to observe it in, and every eagerly validating smart constructor has one.
-}
eagerRejection :: ChainQuery (Either ChainQueryError a) -> Maybe ChainQueryError
eagerRejection = \case
    Pure (Left err) -> Just err
    _ -> Nothing
