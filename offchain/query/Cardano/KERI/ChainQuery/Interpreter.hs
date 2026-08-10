{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoFieldSelectors #-}

{- |
Module      : Cardano.KERI.ChainQuery.Interpreter
Description : Interpreter values and program execution (#257 FUN-257-RUN)

'ChainQueryInterpreter' is the only execution authority a
'Cardano.KERI.ChainQuery.Program.ChainQuery' program ever receives
(INV-257-PROVIDER): 'runChainQuery' selects no provider itself and never
falls through to another interpreter on an unsupported operation.

DATA-INV-257-01 (NOTE-025): 'ChainQueryInterpreter' is ABSTRACT here. Neither
its data constructor nor its operation labels are exported, so an external
caller cannot use the raw constructor, record construction or update,
explicit-field or @NamedFieldPuns@ destructuring, or positional matching to
build a value or project a raw operation out of one. It can assemble an
interpreter only through the controlled 'chainQueryInterpreter' factory, and
the validated 'runChainQuery' \/ 'runChainQuerySnapshot' runners are the only
public OPERATION eliminators — the provenance accessors below are public too,
but perform no effect. So the only way to reach a provider's effect is a
'Cardano.KERI.ChainQuery.Program.ChainQuery' value, which only
"Cardano.KERI.ChainQuery.Program"'s eagerly validating smart constructors can
build. Invalid input therefore cannot reach a store or HTTP effect on any
publicly reachable path.

Submission 7 claimed @NoFieldSelectors@ alone closed this. That was false and
the audit disproved it: the pragma suppresses generated selector FUNCTIONS,
while the exported constructor and field labels left record syntax as a fully
open route. The pragma is retained only as defence in depth behind the export
boundary, which is what actually closes the hatch.
-}
module Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    interpreterSource,
    interpreterConsistency,
    runChainQuery,
    runChainQuerySnapshot,
    runChainQueryResultSnapshot,
) where

import Cardano.KERI.ChainQuery.Program (
    ChainQuery,
    ChainQueryF (..),
    eagerRejection,
    foldChainQuery,
    storeWatermark,
 )
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
    QuerySnapshot (..),
    QuerySource,
    SnapshotConsistency,
 )
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Text (Text)

{- | One provider's answer to every operation in
'Cardano.KERI.ChainQuery.Program.ChainQueryF', plus its fixed provenance and
consistency claim. The local constructor accepts the existing transaction
runner and store identity required by @Indexer.Query.Tx@; the Koios
constructor is the only query-algebra boundary accepting Koios URL or token
settings (that construction lives in each interpreter's own module, not
here).
-}
data ChainQueryInterpreter effect = ChainQueryInterpreter
    { interpretCurrentCheckpoint ::
        CheckpointLocator -> Text -> effect (Either ChainQueryError (Maybe ActiveCheckpoint))
    , interpretLiveCheckpoints ::
        CheckpointLocator -> effect (Either ChainQueryError [ActiveCheckpoint])
    , interpretReferenceScripts ::
        [Text] -> effect (Either ChainQueryError [ChainReference])
    , interpretBoardCatalog ::
        BoardLocator -> effect (Either ChainQueryError [BoardEntry])
    , interpretBoardCatalogWithOutputs ::
        BoardLocator -> effect (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
    , interpretPayerUtxos ::
        [Text] -> effect (Either ChainQueryError [ChainAssetUtxo])
    , interpretOutputAt ::
        OutputLocator -> effect (Either ChainQueryError ChainAssetUtxo)
    , interpretStoreWatermark ::
        effect (Either ChainQueryError (ColdOr ChainWatermark))
    , interpreterSource :: !QuerySource
    , interpreterConsistency :: !SnapshotConsistency
    }

{- | Assemble one provider's interpreter (DATA-INV-257-01, NOTE-025). This is
the ONLY way to build a 'ChainQueryInterpreter': the type is abstract, so this
module exports neither its constructor nor its field labels, and an external
caller therefore cannot reach the raw constructor or use record
construction\/update\/destructuring\/positional matching either to make a
value or to take one apart. Assembly here, 'runChainQuery' out — and because a
'Cardano.KERI.ChainQuery.Program.ChainQuery' value can only be built by that
module's eagerly validating smart constructors, every provider effect stays
behind argument validation on every publicly reachable path.

Submission 7 tried to do this with @NoFieldSelectors@ alone, which suppresses
generated selector FUNCTIONS but leaves the exported constructor and field
labels fully usable through record syntax. That is the leak this closes.
-}
chainQueryInterpreter ::
    (CheckpointLocator -> Text -> effect (Either ChainQueryError (Maybe ActiveCheckpoint))) ->
    (CheckpointLocator -> effect (Either ChainQueryError [ActiveCheckpoint])) ->
    ([Text] -> effect (Either ChainQueryError [ChainReference])) ->
    (BoardLocator -> effect (Either ChainQueryError [BoardEntry])) ->
    (BoardLocator -> effect (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])) ->
    ([Text] -> effect (Either ChainQueryError [ChainAssetUtxo])) ->
    (OutputLocator -> effect (Either ChainQueryError ChainAssetUtxo)) ->
    effect (Either ChainQueryError (ColdOr ChainWatermark)) ->
    QuerySource ->
    SnapshotConsistency ->
    ChainQueryInterpreter effect
chainQueryInterpreter = ChainQueryInterpreter

{- | The interpreter's own fixed provenance (DATA-INV-257-03). Provided as an
explicit accessor because the type is abstract and @NoFieldSelectors@
suppresses every generated selector; unlike the operation fields, reading
provenance performs no effect, so exposing it opens no bypass.
-}
interpreterSource :: ChainQueryInterpreter effect -> QuerySource
interpreterSource ChainQueryInterpreter{interpreterSource = source} = source

{- | The interpreter's own fixed consistency claim (INV-257-CONSISTENCY). See
'interpreterSource' for why this is an explicit accessor and why it is safe.
-}
interpreterConsistency :: ChainQueryInterpreter effect -> SnapshotConsistency
interpreterConsistency ChainQueryInterpreter{interpreterConsistency = consistency} =
    consistency

{- | Execute a whole program with only the supplied interpreter
(FUN-257-RUN). Selects no provider; short-circuits on the first
'ChainQueryError' — via 'ExceptT' over the target effect — without invoking
any later operation.
-}
runChainQuery ::
    forall effect a.
    (Monad effect) =>
    ChainQueryInterpreter effect ->
    ChainQuery a ->
    effect (Either ChainQueryError a)
runChainQuery interpreter program =
    runExceptT (foldChainQuery dispatch program)
  where
    ChainQueryInterpreter
        { interpretCurrentCheckpoint
        , interpretLiveCheckpoints
        , interpretReferenceScripts
        , interpretBoardCatalog
        , interpretBoardCatalogWithOutputs
        , interpretPayerUtxos
        , interpretOutputAt
        , interpretStoreWatermark
        } = interpreter
    dispatch :: forall x. ChainQueryF (ExceptT ChainQueryError effect x) -> ExceptT ChainQueryError effect x
    dispatch = \case
        CurrentCheckpoint locator aid k ->
            ExceptT (interpretCurrentCheckpoint locator aid) >>= k
        LiveCheckpoints locator k ->
            ExceptT (interpretLiveCheckpoints locator) >>= k
        ReferenceScripts hashes k ->
            ExceptT (interpretReferenceScripts hashes) >>= k
        BoardCatalog locator k ->
            ExceptT (interpretBoardCatalog locator) >>= k
        BoardCatalogWithOutputs locator k ->
            ExceptT (interpretBoardCatalogWithOutputs locator) >>= k
        PayerUtxos addrs k ->
            ExceptT (interpretPayerUtxos addrs) >>= k
        OutputAt locator k ->
            ExceptT (interpretOutputAt locator) >>= k
        StoreWatermark k ->
            ExceptT interpretStoreWatermark >>= k

{- | 'runChainQuery' plus the always-attached watermark, source, and
consistency envelope (DAT-257-RESULT). The watermark read is composed into
the very SAME 'ChainQuery' value as the caller's program (via ordinary
'Monad' sequencing) rather than issued as a second, separate
'runChainQuery' call — for the local interpreter this is exactly what keeps
a multi-operation program plus its watermark inside one store transaction
(see "Cardano.KERI.Indexer.ChainQuery").

A-262-01, stated here because this is the function it is about: "always"
means ALWAYS, including for a program that rejected its own argument before
building a single operation. This runner cannot do otherwise — its program
type is @'ChainQuery' a@, so it has no result channel to inspect — and that
is precisely why it is NOT the write path's runner. A caller whose program
can reject eagerly must use 'runChainQueryResultSnapshot'; write composition
is forbidden by an executing source property from naming this one.
-}
runChainQuerySnapshot ::
    (Monad effect) =>
    ChainQueryInterpreter effect ->
    ChainQuery a ->
    effect (Either ChainQueryError (QuerySnapshot a))
runChainQuerySnapshot interpreter program = do
    result <- runChainQuery interpreter combined
    pure (fmap toSnapshot result)
  where
    combined = do
        value <- program
        watermark <- storeWatermark
        pure (value, watermark)
    toSnapshot (value, watermark) =
        QuerySnapshot
            { snapshotValue = value
            , snapshotWatermark = watermark
            , snapshotSource = interpreterSource interpreter
            , snapshotConsistency = interpreterConsistency interpreter
            }

{- | A-262-01 (RQ-262-03\/DATA-INV-262-01): the snapshot runner for a program
that can FAIL, which is every program built from an eagerly validating smart
constructor — so this is the runner a write build phase uses.

Two differences from 'runChainQuerySnapshot', both of them the repair:

  * an eagerly rejected argument short-circuits BEFORE interpretation, so
    the rejection reaches the caller having invoked no handler at all — not
    the operation's, and not the watermark's;
  * the watermark is composed INSIDE the caller's own failure channel rather
    than appended outside it, so an operation failure or a post-acquisition
    resolution failure does not read a watermark either. This is the shape
    'Cardano.KERI.ChainQuery.Registration.runRegistrationSnapshot' already
    used for exactly this reason (NOTE-021\/A-006); \#262's write programs
    reached for the generic runner instead and inherited the defect.

For a program that RESOLVES, the watermark is still read last, in the same
composed 'ChainQuery' value, so the local interpreter's one-store-transaction
guarantee and the 'AtomicLocal' claim are unchanged.

The two 'Either' layers are flattened into one: a caller unwraps once, and a
failure never carries a watermark that was never fetched.
-}
runChainQueryResultSnapshot ::
    (Monad effect) =>
    ChainQueryInterpreter effect ->
    ChainQuery (Either ChainQueryError a) ->
    effect (Either ChainQueryError (QuerySnapshot a))
runChainQueryResultSnapshot interpreter program =
    case eagerRejection program of
        Just err -> pure (Left err)
        Nothing -> do
            outcome <- runChainQuery interpreter withWatermark
            pure $ case outcome of
                Left err -> Left err
                Right (Left err) -> Left err
                Right (Right (value, watermark)) ->
                    Right
                        QuerySnapshot
                            { snapshotValue = value
                            , snapshotWatermark = watermark
                            , snapshotSource = interpreterSource interpreter
                            , snapshotConsistency = interpreterConsistency interpreter
                            }
  where
    withWatermark = do
        outcome <- program
        case outcome of
            Left err -> pure (Left err)
            Right value -> Right . (,) value <$> storeWatermark
