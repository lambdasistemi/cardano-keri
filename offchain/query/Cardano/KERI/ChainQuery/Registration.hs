{- |
Module      : Cardano.KERI.ChainQuery.Registration
Description : Registration's current-state read program (#257 S257-3)

The proof write verb's provider-neutral snapshot request
(DAT-257-REGISTRATION-SNAPSHOT, FUN-257-REGISTRATION-PROGRAM). Every current-
state input a registration phase needs — the checkpoint existence check,
board catalog, deployed reference scripts, and payer UTxOs — is expressed as
one 'Cardano.KERI.ChainQuery.Program.ChainQuery' program, plus the store
watermark. It contains no interpreter or settlement function
(DATA-INV-257-04).

Per A-001 (Q-001's ruling): the selected interpreter is the sole, fully
resolving authority — 'RegistrationSnapshot' carries the ledger-ready
'(TxIn, TxOut ConwayEra)' rows a builder consumes directly, produced by each
interpreter's own (pure, no-N2C) reconstruction of its extended response
data via "Cardano.KERI.ChainQuery.LedgerOutput". Because reconstruction can
fail closed (a hash mismatch, a malformed field), 'registrationSnapshotProgram'
returns 'Either' inside the program result rather than claiming an
unconditional 'RegistrationSnapshot' — the outer
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery' Either layer is reserved
for OPERATION failures (DAT-257-ERROR), this inner one for
post-composition candidate-resolution failures.
-}
module Cardano.KERI.ChainQuery.Registration (
    RegistrationQueryRequest (..),
    RegistrationSnapshot (..),
    registrationSnapshotProgram,
    runRegistrationSnapshot,
) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    interpreterConsistency,
    interpreterSource,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.LedgerOutput (
    chainAssetUtxoToLedgerOutput,
    chainReferenceToLedgerOutput,
 )
import Cardano.KERI.ChainQuery.Program (ChainQuery, boardCatalog, currentCheckpoint, payerUtxos, referenceScripts, storeWatermark)
import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint,
    BoardEntry,
    BoardLocator,
    ChainQueryError,
    ChainWatermark,
    CheckpointLocator,
    ColdOr,
    QuerySnapshot (..),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.TxIn (TxIn)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Text (Text)

{- | Everything one registration phase's snapshot program needs to identify
its reads. 'registrationQueryBoardLocator' is 'Nothing' exactly when the
inception export declares no witnesses (mirroring the current preflight's
"skip the board read" branch).
-}
data RegistrationQueryRequest = RegistrationQueryRequest
    { registrationQueryCheckpointLocator :: !CheckpointLocator
    , registrationQueryAid :: !Text
    , registrationQueryBoardLocator :: !(Maybe BoardLocator)
    , registrationQueryReferenceHashes :: ![Text]
    , registrationQueryPayerAddresses :: ![Text]
    }
    deriving stock (Show, Eq)

{- | Named resolved input for one registration phase
(DAT-257-REGISTRATION-SNAPSHOT). Every field belongs to the same program
result; no ambient query fills a missing field (DATA-INV-257-04). Reference
and payer rows are the exact ledger outputs a builder consumes — the
selected interpreter's own reconstruction, never N2C (A-001).
-}
data RegistrationSnapshot = RegistrationSnapshot
    { snapshotCurrentCheckpoint :: !(Maybe ActiveCheckpoint)
    , snapshotBoardCatalog :: ![BoardEntry]
    , snapshotReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , snapshotPayerUtxos :: ![(TxIn, TxOut ConwayEra)]
    , snapshotStoreWatermark :: !(ColdOr ChainWatermark)
    {- ^ A-006\/DATA-INV-257-04: the watermark belongs to this same program
    result, read once by 'registrationSnapshotProgram' itself after every
    acquisition has already resolved. Carrying it here is what lets
    'runRegistrationSnapshot' build its envelope without appending a
    second, generically composed read.
    -}
    }
    deriving stock (Show, Eq)

{- | Compose one registration phase's complete current-state read: the
checkpoint existence check, the conditional board read, deployed reference
scripts, payer UTxOs, and the store watermark, all inside the SAME
'ExceptT'-gated composition (A-006, DATA-INV-257-04\/RQ-257-08).

Each acquisition is CONVERTED IMMEDIATELY, before the next one is dispatched:
a returned reference row that fails closed (a malformed field, a
hash mismatch) rejects at that point, so no payer read and no watermark read
happens after it. "No invalid selected operation may perform its own action
or any later action" therefore covers a malformed RETURNED candidate as well
as an invalid ARGUMENT — submission 6 satisfied it only for the latter,
because it deferred every pure conversion to the end and so still performed
the payer and watermark effects first.

The watermark is read once, last, by this program itself and carried in
'snapshotStoreWatermark'. That keeps the frozen public program-result
contract @ChainQuery (Either ChainQueryError RegistrationSnapshot)@ intact
while still letting 'runRegistrationSnapshot' build its envelope without a
second, generically appended read.

NOTE-020 (DATA-INV-257-04\/RQ-257-08): the optional board\/reference\/payer
reads are each OMITTED (never dispatched as a 'ChainQuery' operation) when
their phase requests no such input — an empty reference-hash collection is
a legal no-op shape, but an empty payer-address selector is always invalid
(DAT-257-OP requires a non-empty set), so this program must never emit
'payerUtxos' with an empty list.
-}
registrationSnapshotProgram ::
    RegistrationQueryRequest -> ChainQuery (Either ChainQueryError RegistrationSnapshot)
registrationSnapshotProgram req = runExceptT $ do
    checkpointResult <-
        ExceptT (currentCheckpoint (registrationQueryCheckpointLocator req) (registrationQueryAid req))
    catalog <- case registrationQueryBoardLocator req of
        Nothing -> pure []
        Just locator -> ExceptT (boardCatalog locator)
    references <- case registrationQueryReferenceHashes req of
        [] -> pure []
        hashes -> do
            candidates <- ExceptT (referenceScripts hashes)
            ExceptT (pure (traverse chainReferenceToLedgerOutput candidates))
    payers <- case registrationQueryPayerAddresses req of
        [] -> pure []
        addresses -> do
            candidates <- ExceptT (payerUtxos addresses)
            ExceptT (pure (traverse chainAssetUtxoToLedgerOutput candidates))
    watermark <- lift storeWatermark
    pure
        RegistrationSnapshot
            { snapshotCurrentCheckpoint = checkpointResult
            , snapshotBoardCatalog = catalog
            , snapshotReferenceUtxos = references
            , snapshotPayerUtxos = payers
            , snapshotStoreWatermark = watermark
            }

{- | The one named registration snapshot for a phase (NOTE-012\/NOTE-021
repair, INV-257-BUILDER\/DATA-INV-257-03\/04): runs
'registrationSnapshotProgram' through the supplied interpreter's bare
'runChainQuery' (never a snapshot runner that composes its own watermark,
which would append a second, redundant read after this program's structural
rejection or success -- \#262 A-262-02 deleted the runner that did so
unconditionally, and this program has carried its own watermark since
NOTE-021 for exactly that reason) and
builds the one envelope from the program's own carried watermark plus the
interpreter's fixed source\/consistency. Flattens the program's own inner
candidate-resolution 'Either' into the outer result, so a caller unwraps
only once and a failure never claims a watermark that was never fetched.
This is the ONLY entry point a builder\/consumer may use to obtain a
registration phase's current-state values; there is no bare query-callback
escape.
-}
runRegistrationSnapshot ::
    (Monad effect) =>
    ChainQueryInterpreter effect ->
    RegistrationQueryRequest ->
    effect (Either ChainQueryError (QuerySnapshot RegistrationSnapshot))
runRegistrationSnapshot interpreter req = do
    outcome <- runChainQuery interpreter (registrationSnapshotProgram req)
    pure $ case outcome of
        Left err -> Left err
        Right (Left err) -> Left err
        Right (Right snapshot) ->
            Right
                QuerySnapshot
                    { snapshotValue = snapshot
                    , snapshotWatermark = snapshotStoreWatermark snapshot
                    , snapshotSource = interpreterSource interpreter
                    , snapshotConsistency = interpreterConsistency interpreter
                    }
