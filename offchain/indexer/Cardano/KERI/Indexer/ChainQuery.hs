{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Indexer.ChainQuery
Description : The local whole-program chain-query interpreter (#257 MOD-257-LOCAL, #240 MOD-240-LOCAL)

Translates a whole 'Cardano.KERI.ChainQuery.Program.ChainQuery' program to
the existing composable reads in "Cardano.KERI.Indexer.Query.Tx", reads the
matching rollback slot\/hash for the watermark, and invokes the existing
'Database.KV.Transaction.RunTransaction' exactly once
('runLocalChainQuery', T257-S2-03). Every field of 'localInterpreter'
answers inside the caller-supplied 'Transaction' — composing them via
ordinary 'Monad' sequencing (as
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery' already does) keeps a
whole multi-operation program, and its watermark, inside one store
transaction (INV-257-ATOMIC\/INV-257-WATERMARK).

Since #240, 'localInterpreter''s 'referenceScripts' field IS
'localReferenceScriptsTx' (T240-S1-06\/RQ-240-03): #257 permitted
'UnsupportedOperation' as ONE valid interpreter answer (RQ-257-05: "Koios,
not every interpreter, must answer every operation"), never forbade a
later interpreter from actually answering it, and #240 requires the
existing provider-neutral 'Cardano.KERI.ChainQuery.Program.referenceScripts'
operation to run through the selected LOCAL interpreter like every other
operation -- so
"Cardano.KERI.ChainQuery.Registration".'Cardano.KERI.ChainQuery.Registration.runRegistrationSnapshot'
and every other existing #257 caller of a selected interpreter keep working
completely unchanged; only the interpreter selected at the write-composition
layer differs. 'localReferenceScriptsTx' itself derives exact reference
outputs from every currently live row -- the only local read with no
address to scope the search by, since a published reference output can
live at any funding address, not a fixed one (DATA-INV-240-01).
'localSettlementObserver'\/'localReferenceObservation'\/'localTransactionSettled'
are #240's follower-backed temporal probes (RQ-240-06): fresh per-call
store observations, never 'ChainQueryF' operations and never a snapshot
claim (DATA-INV-240-05).

@INV-240-LOCALTIER@ is MET by #262. Every write build-phase read now reaches
this module as a 'Cardano.KERI.ChainQuery.Program.ChainQuery' operation
answered by 'localInterpreter', and this interpreter is the sole acquisition
authority: #262 added the two operation families whose absence forced the
seven direct 'Transaction' bundles (an exact output by @(txid,index)@, and
board entries paired with their own outputs), so the raw readers below are
private implementation details with no caller outside this module.
'runLocalQuery', 'runLocalInterpreter' and 'runLocalChainQuery' are the whole
exported acquisition boundary, and 'runLocalQuery' is the one a write build
phase uses (A-262-01: it is the only one that opens no store transaction for
an eagerly rejected locator).
-}
module Cardano.KERI.Indexer.ChainQuery (
    localInterpreter,
    runLocalChainQuery,
    runLocalInterpreter,
    runLocalQuery,
    localSettlementObserver,
    localReferenceObservation,
    localTransactionSettled,
    LocalQueryScope (..),
    queryHandleLocalScope,
    LocalSettings (..),
    withLocalQueryScope,
) where

import Cardano.Crypto.Hash.Class (hashToBytes)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive, qb64Aid)
import Cardano.KERI.ChainQuery (
    ActiveCheckpoint (..),
    BoardEntry (..),
    BoardLocator (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainQueryInterpreter,
    ChainReference (..),
    ChainReferenceScript (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    OutputLocator (..),
    QuerySnapshot (..),
    QuerySource (SourceLocal),
    SettlementObserver (..),
    SnapshotConsistency (AtomicLocal),
    chainQueryInterpreter,
    runChainQueryResultSnapshot,
    runChainQuerySnapshot,
    validPayerAddresses,
 )
import Cardano.KERI.ChainQuery.LedgerOutput (chainAssetUtxoToLedgerOutput)
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataJson)
import Cardano.KERI.ChainQuery.Program (ChainQuery, eagerRejection)
import Cardano.KERI.Deployment.EndpointBoardManifest (frozenEndpointBoardPolicyId)
import Cardano.KERI.Indexer.Board (indexedBoardCatalog)
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..), decodeCheckpointOutput)
import Cardano.KERI.Indexer.Query.Tx (
    QueryHandle (..),
    payerUtxosTxAcrossAddresses,
    scanAddressTx,
    scanAllTx,
    watermarkPointTx,
 )
import Cardano.Ledger.Address (serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), binaryDataToData)
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Binary (DecoderError, decodeFull)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, TxOut, eraProtVerLow, fromStrictMaybeL, hashScript)
import Cardano.Ledger.Hashes (ScriptHash (..), extractHash, originalBytes)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (withRocksDBIndexerRunner)
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Binary.Bech32 qualified as Bech32
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Database.KV.Transaction (RunTransaction (..), Transaction)
import Lens.Micro ((^.))

{- | #240 (N-026\/N-027): the local-write query scope. Carries the store
runner directly (never a 'QueryHandle') plus the checkpoint\/board
identities as 'Maybe' -- a write command that never dispatches a
checkpoint or board read supplies 'Nothing' rather than a fabricated
address\/policy id; 'withLocalQueryScope' constructs no dummy\/all-zero
value at all. Every checkpoint\/board-reading function below requires its
'Just' identity before any store scan (DAT-240-LOCAL-SCOPE).
-}
data LocalQueryScope cf op = LocalQueryScope
    { localScopeRunner :: !(RunTransaction IO cf Cols op)
    , localScopeCheckpointIdentity :: !(Maybe (PolicyID, Indexer.Address))
    , localScopeBoardIdentity :: !(Maybe Indexer.Address)
    }

{- | #240 (N-027): the one narrow bridge from a fully-populated read
'QueryHandle' (owned by "Cardano.KERI.CLI.Backend.Local"'s \#177 read path,
and by pre-#240 specs exercising 'localInterpreter'\/'runLocalChainQuery'
directly) to a write-scope 'LocalQueryScope' -- both identities wrapped
'Just' from the handle's own real, always-populated fields, since a read
command always has both. No #240 write verb ever calls this;
'withLocalQueryScope' is their only scope constructor.
-}
queryHandleLocalScope :: QueryHandle cf op -> LocalQueryScope cf op
queryHandleLocalScope handle =
    LocalQueryScope
        { localScopeRunner = qhRunner handle
        , localScopeCheckpointIdentity = Just (qhCheckpointPolicy handle, qhCheckpointAddress handle)
        , localScopeBoardIdentity = Just (qhBoardAddress handle)
        }

-- | Translate the whole algebra to one store 'Transaction' per operation.
localInterpreter :: LocalQueryScope cf op -> ChainQueryInterpreter (Transaction IO cf Cols op)
localInterpreter scope =
    chainQueryInterpreter
        ( \locator aid ->
            withValidCheckpointLocator scope locator (localCurrentCheckpoint scope aid)
        )
        (\locator -> withValidCheckpointLocator scope locator (localLiveCheckpoints scope))
        localReferenceScriptsTx
        (\locator -> withValidBoardLocator scope locator (localBoardCatalog scope))
        ( \locator ->
            withValidBoardLocator scope locator (localBoardCatalogWithOutputs scope)
        )
        localPayerUtxos
        localOutputAt
        localWatermark
        SourceLocal
        AtomicLocal

{- | DATA-INV-257-01: the local store answers exactly one checkpoint policy
and address, when the write command has one configured at all (N-026: it
need not). A caller-supplied locator that disagrees with that fixed
configuration fails closed with 'InvalidLocator', rather than being
silently discarded in favor of the scope's own configuration; a command
with no checkpoint identity at all fails closed the same way, before any
comparison. Emptiness and canonical shape are already guaranteed by
'Cardano.KERI.ChainQuery.Program.currentCheckpoint'\/'liveCheckpoints'
EAGERLY, structurally, before this operation's
'Cardano.KERI.ChainQuery.Program.ChainQueryF' node can even exist
(NOTE-020) -- this check is provider-specific scope identity only, run
inside the local 'Transaction' before any store read.
-}
checkpointLocatorOk :: LocalQueryScope cf op -> CheckpointLocator -> Either ChainQueryError ()
checkpointLocatorOk scope locator =
    case localScopeCheckpointIdentity scope of
        Nothing -> Left (InvalidLocator "this write command has no checkpoint identity configured")
        Just (policy, addr)
            | checkpointLocatorPolicyId locator /= policyIdHex policy ->
                Left (InvalidLocator "checkpoint locator policy id does not match the local store's checkpoint policy")
            | checkpointLocatorAddress locator /= renderIndexerAddress addr ->
                Left (InvalidLocator "checkpoint locator address does not match the local store's checkpoint address")
            | otherwise -> Right ()

{- | DATA-INV-257-01: the local store answers exactly one board marker
policy\/address, when the write command has one configured at all (N-026).
'indexedBoardCatalog' (via "Cardano.KERI.Indexer.Board") always resolves
against 'frozenEndpointBoardPolicyId', never a caller-supplied policy.
Emptiness and canonical shape are already structurally guaranteed (see
'checkpointLocatorOk'); this is the provider-specific identity check only.
-}
boardLocatorOk :: LocalQueryScope cf op -> BoardLocator -> Either ChainQueryError ()
boardLocatorOk scope locator =
    case localScopeBoardIdentity scope of
        Nothing -> Left (InvalidLocator "this write command has no board identity configured")
        Just addr
            | boardLocatorPolicyId locator /= frozenEndpointBoardPolicyId ->
                Left (InvalidLocator "board locator policy id does not match the local store's frozen board policy")
            | boardLocatorAddress locator /= renderIndexerAddress addr ->
                Left (InvalidLocator "board locator address does not match the local store's board address")
            | otherwise -> Right ()

withValidCheckpointLocator ::
    LocalQueryScope cf op ->
    CheckpointLocator ->
    Transaction IO cf Cols op (Either ChainQueryError a) ->
    Transaction IO cf Cols op (Either ChainQueryError a)
withValidCheckpointLocator scope locator action =
    either (pure . Left) (const action) (checkpointLocatorOk scope locator)

withValidBoardLocator ::
    LocalQueryScope cf op ->
    BoardLocator ->
    Transaction IO cf Cols op (Either ChainQueryError a) ->
    Transaction IO cf Cols op (Either ChainQueryError a)
withValidBoardLocator scope locator action =
    either (pure . Left) (const action) (boardLocatorOk scope locator)

{- | Run a whole program through exactly one 'RunTransaction' invocation
(T257-S2-03). DATA-INV-257-01's canonical-shape\/emptiness validation now
happens STRUCTURALLY, inside
'Cardano.KERI.ChainQuery.Program.currentCheckpoint'\/'boardCatalog'\/
'payerUtxos'\/'referenceScripts' themselves, the moment each operation is
built from a concrete argument -- so an invalid operation never becomes a
'Cardano.KERI.ChainQuery.Program.ChainQueryF' node in the first place and
this interpreter's own field is never invoked for it, regardless of
whether the caller derived the argument from a literal or a real earlier
operation's result (no finite placeholder enumeration needed, NOTE-020).
The watermark is always attached inside the very same composed
'Transaction' as the caller's program via
'Cardano.KERI.ChainQuery.Interpreter.runChainQuerySnapshot'.
-}
runLocalChainQuery ::
    LocalQueryScope cf op -> ChainQuery a -> IO (Either ChainQueryError (QuerySnapshot a))
runLocalChainQuery scope program =
    runLocalInterpreter scope (`runChainQuerySnapshot` program)

{- | #262 (RQ-262-05\/MOD-262-LOCAL): the whole exported acquisition boundary,
alongside 'runLocalChainQuery'. Hand this the way you want a program run --
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery',
'runChainQuerySnapshot', or
'Cardano.KERI.ChainQuery.Registration.runRegistrationSnapshot', each of which
composes its own watermark differently -- and it supplies the local
interpreter and spends exactly one 'RunTransaction' invocation on it.

The rank-2 callback is what makes this the boundary rather than a
convenience. Its argument is polymorphic in the effect, so a caller can
compose 'Cardano.KERI.ChainQuery.Program.ChainQuery' operations and nothing
else: the store 'Transaction' this interpreter actually runs in is not a type
the callback can name, and no raw reader is reachable through it. That is
what replaced the raw snapshot runner \#240 exported to write composition,
and it is why the seven direct bundles could be withdrawn without leaving a
second acquisition route behind.
-}
runLocalInterpreter ::
    LocalQueryScope cf op ->
    ( forall effect.
      (Monad effect) =>
      ChainQueryInterpreter effect ->
      effect result
    ) ->
    IO result
runLocalInterpreter scope run =
    runTransaction (localScopeRunner scope) (run (localInterpreter scope))

{- | A-262-01 (RQ-262-03\/DATA-INV-262-01): the write path's own runner. Runs
one build phase's composed program against the local interpreter and answers
the resolved value, spending exactly one 'RunTransaction' invocation — or,
for a program that rejected its argument eagerly, none at all.

The short-circuit is repeated here rather than left to
'Cardano.KERI.ChainQuery.Interpreter.runChainQueryResultSnapshot' because
the two guard DIFFERENT effects at different layers, and only one of them is
visible from the query layer. That runner can stop an interpreter HANDLER
from being invoked; it cannot stop this module from opening a store
transaction to hand it an interpreter in the first place, because
'runLocalInterpreter' takes a rank-2 callback and cannot see the program.
"Zero handlers" and "zero store transactions" are therefore two claims, and
this is where the second one is either true or false.
-}
runLocalQuery ::
    LocalQueryScope cf op ->
    ChainQuery (Either ChainQueryError a) ->
    IO (Either ChainQueryError (QuerySnapshot a))
runLocalQuery scope program =
    case eagerRejection program of
        Just err -> pure (Left err)
        Nothing -> runLocalInterpreter scope (`runChainQueryResultSnapshot` program)

localWatermark :: Transaction IO cf Cols op (Either ChainQueryError (ColdOr ChainWatermark))
localWatermark = do
    point <- watermarkPointTx
    pure $ Right $ case point of
        Nothing -> Cold
        Just (slot, blockHash) ->
            Populated
                ChainWatermark
                    { watermarkSlot = fromIntegral (Indexer.unSlotNo slot)
                    , watermarkBlockHash = hexBytes (Indexer.unBlockHash blockHash)
                    }

{- | Find the exactly-one live checkpoint output whose decoded AID matches
the requested text; more than one match fails closed (INV-257-PROVIDER).

\#240 exported this so a write-composition phase could compose it with the
other raw readers inside one caller-run 'Transaction', because the free
algebra of the day could answer only one operation per dispatch and had no
way to express the other reads that phase needed. \#262 removed that reason:
the algebra now carries every build-phase read, its 'Monad' instance joins
them, and 'runLocalChainQuery' runs the whole composed program in the one
'RunTransaction' invocation the snapshot contract requires. This is private
again, as it always should have been.
-}
localCurrentCheckpoint ::
    LocalQueryScope cf op -> Text -> Transaction IO cf Cols op (Either ChainQueryError (Maybe ActiveCheckpoint))
localCurrentCheckpoint scope aidText =
    case localScopeCheckpointIdentity scope of
        Nothing -> pure (Left (InvalidLocator "this write command has no checkpoint identity configured"))
        Just (policy, addr) ->
            case decodeAidBytes aidText of
                Left err -> pure (Left (InvalidLocator err))
                Right targetAid -> do
                    entries <- scanAddressTx addr
                    pure $ do
                        rows <- decodedCheckpointRows policy addr entries
                        let matching =
                                [entry | (entry, record) <- rows, crAid record == targetAid]
                        actives <- traverse (decodeActiveCheckpoint policy addr aidText) matching
                        case actives of
                            [] -> Right Nothing
                            [one] -> Right (Just one)
                            (_ : _ : _) ->
                                Left (AmbiguousCurrentState "more than one live checkpoint output for this AID")

{- | Every live checkpoint at the checkpoint address, each rendered with its
own decoded AID (CESR-encoded from the datum).
-}
localLiveCheckpoints :: LocalQueryScope cf op -> Transaction IO cf Cols op (Either ChainQueryError [ActiveCheckpoint])
localLiveCheckpoints scope =
    case localScopeCheckpointIdentity scope of
        Nothing -> pure (Left (InvalidLocator "this write command has no checkpoint identity configured"))
        Just (policy, addr) -> do
            entries <- scanAddressTx addr
            pure $ do
                rows <- decodedCheckpointRows policy addr entries
                traverse
                    ( \(entry, record) ->
                        decodeActiveCheckpoint
                            policy
                            addr
                            (TE.decodeUtf8 (qb64Aid (crAid record)))
                            entry
                    )
                    rows

{- | #240 (A-013 finding 3, INV-240-PARITY): decode EVERY scanned checkpoint
row, failing closed on the first row that does not decode.

Both checkpoint readers above previously selected rows with a
@Right record <- [decodeCheckpointOutput ...]@ pattern guard. That guard
silently DROPS a row whose datum is undecodable or schema-malformed and then
reports the survivors as the whole truth: a corrupted live checkpoint read as
"this AID has no checkpoint" through 'localCurrentCheckpoint', and simply
vanished from 'localLiveCheckpoints', while the frozen base provider answers
@Left (DecodingFailure ...)@ for the very same storage. Divergence in the
fail-open direction is the worst available one — a write verb would proceed
against a state it could not read.

This is the ONE decode both readers now share, and it is @traverse@-shaped
rather than a filter, so the fail-open form cannot be reintroduced in one
reader alone without deleting this function from under the other.
-}
decodedCheckpointRows ::
    PolicyID ->
    Indexer.Address ->
    [(Indexer.TxIn, Indexer.TxOut)] ->
    Either ChainQueryError [((Indexer.TxIn, Indexer.TxOut), CheckpointRecord)]
decodedCheckpointRows policy addr =
    traverse decodeRow
  where
    decodeRow entry@(txIn, txOut) =
        (,) entry
            <$> first
                (DecodingFailure . T.pack . show)
                (decodeCheckpointOutput policy txIn addr txOut)

{- | Decode one indexed output into 'ActiveCheckpoint': datum via the
existing 'decodeCheckpointOutput'; lovelace\/assets via a fresh ledger
decode of the same raw bytes (mirroring
"Cardano.KERI.Indexer.Board"'s established pattern); the address is the
caller's own checkpoint address (every scanned entry is at it, by
construction of 'scanAddressTx'), rendered the same bech32 form Koios
reports so 'ActiveCheckpoint' is source-independent.
-}
decodeActiveCheckpoint ::
    PolicyID -> Indexer.Address -> Text -> (Indexer.TxIn, Indexer.TxOut) -> Either ChainQueryError ActiveCheckpoint
decodeActiveCheckpoint policy addr aidText (txIn, indexerTxOut@(Indexer.TxOut rawTxOut)) = do
    record <-
        first (DecodingFailure . T.pack . show) $
            decodeCheckpointOutput policy txIn addr indexerTxOut
    ledgerTxOut <- decodeConwayTxOut rawTxOut
    let MaryValue (Coin lovelace) (MultiAsset policies) = ledgerTxOut ^. valueTxOutL
        assets =
            [ ChainAsset
                { chainAssetPolicy = policyIdHex assetPolicy
                , chainAssetName = assetNameHex name
                , chainAssetQuantity = quantity
                }
            | (assetPolicy, byName) <- Map.toList policies
            , (name, quantity) <- Map.toList byName
            ]
    pure
        ActiveCheckpoint
            { activeCheckpointAid = aidText
            , activeCheckpointAssetName = hexBytes (crAssetName record)
            , activeCheckpointTxId = hexBytes (Indexer.txInId txIn)
            , activeCheckpointIndex = fromIntegral (Indexer.txInIx txIn)
            , activeCheckpointAddress = renderIndexerAddress addr
            , activeCheckpointLovelace = lovelace
            , activeCheckpointAssets = assets
            , activeCheckpointDatum = crDatum record
            }

{- | Render raw indexer address bytes the same bech32 form the Koios
interpreter reports, so 'ActiveCheckpoint'\/'ChainAssetUtxo' are
source-independent.
-}
renderIndexerAddress :: Indexer.Address -> Text
renderIndexerAddress (Indexer.Address bytes) =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes bytes)

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

hexBytes :: ByteString -> Text
hexBytes = TE.decodeUtf8 . convertToBase Base16

decodeAidBytes :: Text -> Either Text ByteString
decodeAidBytes aid =
    case parsePrimitive (TE.encodeUtf8 aid) of
        Right (SelfAddressing raw, rest) | BS.null rest -> Right raw
        _ -> Left "AID must be one 44-character KERI E-code identifier"

decodeAddressBytes :: Text -> Either ChainQueryError Indexer.Address
decodeAddressBytes bech32Text =
    case Bech32.decodeLenient bech32Text of
        Left err -> Left (InvalidLocator (T.pack (show err)))
        Right (_hrp, dataPart) ->
            case Bech32.dataPartToBytes dataPart of
                Nothing -> Left (InvalidLocator "address data part is invalid")
                Just bytes -> Right (Indexer.Address bytes)

policyIdHex :: PolicyID -> Text
policyIdHex (PolicyID (ScriptHash h)) = hexBytes (hashToBytes h)

assetNameHex :: AssetName -> Text
assetNameHex (AssetName name) = hexBytes (SBS.fromShort name)

localBoardCatalog :: LocalQueryScope cf op -> Transaction IO cf Cols op (Either ChainQueryError [BoardEntry])
localBoardCatalog scope =
    case localScopeBoardIdentity scope of
        Nothing -> pure (Left (InvalidLocator "this write command has no board identity configured"))
        Just addr -> do
            entries <- scanAddressTx addr
            pure $
                first (DecodingFailure . T.pack) $
                    indexedBoardCatalog addr entries

{- | #262 (FUN-262-LOCAL-BOARD-OUTPUTS, RQ-262-02): each authenticated board
entry paired with the complete PROVIDER-NEUTRAL output of its own row, as one
all-or-nothing observation.

\#240's version of this answered ledger @(TxIn, TxOut ConwayEra)@ pairs,
which is why it could never be an algebra operation: a raw ledger output is
not something a Koios interpreter could ever produce, so putting it in the
cross-provider vocabulary would have made the algebra local-only in all but
name. Answering 'ChainAssetUtxo' -- the ONE neutral spendable shape
(PROMOTE-262-01) -- is what let this become an operation, and the ledger
reconstruction moved to
'Cardano.KERI.ChainQuery.LedgerOutput.chainAssetUtxoToLedgerOutput', which is
pure and runs after interpretation.

A second address scan against the SAME open store 'Transaction' (same
snapshot: INV-240-SNAPSHOT is a per-bracket, not per-scan, guarantee), so a
write verb that selects one entry and then spends it never needs a second
store transaction.
-}
localBoardCatalogWithOutputs ::
    LocalQueryScope cf op ->
    Transaction IO cf Cols op (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
localBoardCatalogWithOutputs scope =
    case localScopeBoardIdentity scope of
        Nothing -> pure (Left (InvalidLocator "this write command has no board identity configured"))
        Just addr -> do
            catalogResult <- localBoardCatalog scope
            case catalogResult of
                Left err -> pure (Left err)
                Right entries -> do
                    rows <- scanAddressTx addr
                    pure (traverse (pairEntryWithOutput rows) entries)

pairEntryWithOutput ::
    [(Indexer.TxIn, Indexer.TxOut)] ->
    BoardEntry ->
    Either ChainQueryError (BoardEntry, ChainAssetUtxo)
pairEntryWithOutput rows entry =
    case [row | row@(indexerTxIn, _) <- rows, matchesEntry indexerTxIn] of
        [row] -> (,) entry <$> spendableOutput row
        [] -> Left (DecodingFailure ("board catalog entry has no matching stored row: " <> boardTxId entry))
        _ -> Left (AmbiguousCurrentState ("more than one stored row matches one board catalog entry: " <> boardTxId entry))
  where
    matchesEntry indexerTxIn =
        hexBytes (Indexer.txInId indexerTxIn) == boardTxId entry
            && fromIntegral (Indexer.txInIx indexerTxIn) == boardIndex entry

{- | DATA-INV-257-01: validates the address selector itself (non-empty,
canonical -- reusing the same 'validPayerAddresses' every provider and
'Cardano.KERI.ChainQuery.Program.payerUtxos' share) before any store effect.

A-006 correction: submission 6 justified this check by claiming the field was
"directly reachable by any caller that constructs a 'localInterpreter' value".
That is no longer true, and relying on it was the defect the audit found —
validation reached inside the local 'Transaction' only AFTER the store runner
had been entered, so it never established "no store effect" for a caller using
that route. "Cardano.KERI.ChainQuery.Interpreter" now suppresses the field
selectors outright, so no such caller can exist and the only route in is
'Cardano.KERI.ChainQuery.Program's eager validation. This check is retained as
defence in depth for the provider itself, not as the boundary.
-}
localPayerUtxos :: [Text] -> Transaction IO cf Cols op (Either ChainQueryError [ChainAssetUtxo])
localPayerUtxos addresses =
    case validPayerAddresses addresses >> traverse decodeAddressBytes addresses of
        Left err -> pure (Left err)
        Right addrs -> do
            entries <- payerUtxosTxAcrossAddresses addrs
            pure (traverse toChainAssetUtxo entries)

{- | Decode one indexed payer output into 'ChainAssetUtxo', including its
own address from the ledger 'TxOut' (unlike the checkpoint\/board scans,
'payerUtxosTxAcrossAddresses' can merge rows from several addresses, so
the address is not known statically per row) and, since #240, any
reference script it happens to carry (T240-S1-06: 'localReferenceScriptsTx'
reuses this same decode to derive reference outputs from live stored rows
-- one honest decoding, not two).
-}
toChainAssetUtxo :: (Indexer.TxIn, Indexer.TxOut) -> Either ChainQueryError ChainAssetUtxo
toChainAssetUtxo (txIn, Indexer.TxOut rawTxOut) = do
    ledgerTxOut <- decodeConwayTxOut rawTxOut
    let MaryValue (Coin lovelace) (MultiAsset policies) = ledgerTxOut ^. valueTxOutL
        assets =
            [ ChainAsset
                { chainAssetPolicy = policyIdHex policy
                , chainAssetName = assetNameHex name
                , chainAssetQuantity = quantity
                }
            | (policy, byName) <- Map.toList policies
            , (name, quantity) <- Map.toList byName
            ]
        address = renderIndexerAddress (Indexer.Address (serialiseAddr (ledgerTxOut ^. addrTxOutL)))
        referenceScript = encodeReferenceScript <$> ledgerTxOut ^. (referenceScriptTxOutL . fromStrictMaybeL)
        inlineDatum = case ledgerTxOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutusDatum = binaryDataToData binaryDatum
                 in Just (plutusDataJson plutusDatum)
            NoDatum -> Nothing
            DatumHash _ -> Nothing
    pure
        ChainAssetUtxo
            { chainAssetTxId = hexBytes (Indexer.txInId txIn)
            , chainAssetIndex = fromIntegral (Indexer.txInIx txIn)
            , chainAssetAddress = address
            , chainAssetLovelace = lovelace
            , chainAssetList = assets
            , chainAssetInlineDatum = inlineDatum
            , chainAssetReferenceScript = referenceScript
            }

{- | T240-S1-06: the local store's counterpart to
"Cardano.KERI.ChainQuery.LedgerOutput".decodeScript's inverse -- a stored
reference script's hash, type, and raw bytes, read directly off the ledger
value the follower already decoded (never re-fetched). This system deploys
exactly one Plutus language, PlutusV3 ('Cardano.KERI.Deployment.Script.mkCageScript'
is hard-coded to it), so no language detection is needed; 'originalBytes'
(the same 'SafeToHash' memoized-bytes accessor
"Cardano.Tx.Scripts".refScriptsSize already uses to size reference scripts
for fee estimation) returns exactly the bytes a requested hash is checked
against, round-tripping through 'Cardano.KERI.ChainQuery.LedgerOutput.decodeScript'.
-}
encodeReferenceScript :: Script ConwayEra -> ChainReferenceScript
encodeReferenceScript script =
    ChainReferenceScript
        { chainReferenceScriptHashField = scriptHashHex (hashScript script)
        , chainReferenceScriptType = "PlutusV3"
        , chainReferenceScriptBytes = hexBytes (originalBytes script)
        }

scriptHashHex :: ScriptHash -> Text
scriptHashHex (ScriptHash h) = hexBytes (hashToBytes h)

{- | T240-S1-06\/RQ-240-05 (DATA-INV-240-01): derive exact reference outputs
from every currently live row, across the whole store -- unlike every other
composed read in this module, no address scopes the search: a published
reference output can live at any funding address, never a fixed one (#181's
'Cardano.KERI.Deployment.Publisher' places every reference output at the
publish transaction's own funding address). Zero requested hashes is the
existing legal empty result (NOTE-020); a non-empty request resolves EVERY
hash exactly once, in the caller's own stable order, or fails closed with a
named 'ChainQueryError' on the first absent, duplicated, or malformed
candidate -- never a partial list. This is a plain 'Transaction', never a
'Cardano.KERI.ChainQuery.Program.ChainQueryF' operation
(RQ-257-05\/DATA-INV-240-01): #240's write path calls it directly, outside
the free-program algebra 'localInterpreter' answers.
-}
localReferenceScriptsTx :: [Text] -> Transaction IO cf Cols op (Either ChainQueryError [ChainReference])
localReferenceScriptsTx [] = pure (Right [])
localReferenceScriptsTx hashes = do
    rows <- scanAllTx
    pure $ do
        utxos <- traverse toChainAssetUtxo rows
        let candidates =
                [ (chainReferenceScriptHashField scriptInfo, utxo)
                | utxo <- utxos
                , Just scriptInfo <- [chainAssetReferenceScript utxo]
                ]
        traverse (resolveOneReference candidates) hashes

resolveOneReference :: [(Text, ChainAssetUtxo)] -> Text -> Either ChainQueryError ChainReference
resolveOneReference candidates hash =
    case [utxo | (candidateHash, utxo) <- candidates, candidateHash == hash] of
        [utxo] ->
            Right
                ChainReference
                    { chainReferenceScriptHash = hash
                    , chainReferenceOutput = utxo
                    }
        [] -> Left (DecodingFailure ("no live output carries the requested reference script hash: " <> hash))
        _ ->
            Left
                ( AmbiguousCurrentState
                    ("more than one live output carries the requested reference script hash: " <> hash)
                )

{- | RQ-240-06: the same exact derivation 'localReferenceScriptsTx' uses,
run through the caller-supplied 'QueryHandle''s own transaction runner, for
exactly one requested script hash -- never a second, independently varying
implementation.
-}
localReferenceObservation :: LocalQueryScope cf op -> Text -> IO (Either ChainQueryError [ChainReference])
localReferenceObservation scope scriptHash =
    runTransaction (localScopeRunner scope) (localReferenceScriptsTx [scriptHash])

{- | RQ-240-06\/DAT-240-SETTLEMENT-PROBES: a fresh follower-store
observation per probe, never a snapshot claim (DATA-INV-240-05) and never a
'ChainQueryF' operation. Matches every live output carrying the requested
(policy, asset name) pair, regardless of quantity or address --
'Cardano.KERI.ChainQuery.Settlement.observeSettlement' (this observer's
only caller) already filters the returned rows by the exact tx id, address,
and quantity==1 the target names, the same contract every provider's
observer already satisfies. A decode failure on an unrelated stored row
answers an empty match set for THIS probe rather than raising -- unlike
'localReferenceScriptsTx', 'SettlementObserver' has no error channel to
report it through, so this is the closed, fail-safe-by-timeout answer
(matching every provider's own @try@-and-retry precedent in
"Cardano.KERI.ChainQuery.Settlement".'observeSettlement'), not a silent
success.
-}
localSettlementObserver :: LocalQueryScope cf op -> SettlementObserver IO
localSettlementObserver scope =
    SettlementObserver $ \policyHex assetHex ->
        runTransaction (localScopeRunner scope) $ do
            rows <- scanAllTx
            pure $ case traverse toChainAssetUtxo rows of
                Left _decodeFailure -> []
                Right utxos -> filter (carriesAsset policyHex assetHex) utxos

carriesAsset :: Text -> Text -> ChainAssetUtxo -> Bool
carriesAsset policyHex assetHex utxo =
    any
        (\asset -> chainAssetPolicy asset == policyHex && chainAssetName asset == assetHex)
        (chainAssetList utxo)

{- | RQ-240-06\/DAT-240-SETTLEMENT-PROBES: whether the follower currently
tracks any live output of the exact transaction id -- a fresh temporal
observation (DATA-INV-240-05), never a 'ChainQueryF' operation.
-}
localTransactionSettled :: LocalQueryScope cf op -> TxId -> IO Bool
localTransactionSettled scope txId =
    runTransaction (localScopeRunner scope) $
        any ((== wantedTxIdBytes) . Indexer.txInId . fst) <$> scanAllTx
  where
    wantedTxIdBytes = hashToBytes (extractHash (unTxId txId))

{- | #262 (FUN-262-LOCAL-OUTPUT, RQ-262-01): exact local output lookup by
@(txid,index)@, answered as the provider-neutral spendable shape. Fails
closed on absence, on an impossible duplicate, and -- see 'spendableOutput'
-- on a row the neutral shape cannot faithfully carry. Never falls back to
N2C.

The locator's canonical shape is already guaranteed structurally, before this
operation's node can exist ('Cardano.KERI.ChainQuery.Program.outputAt',
DATA-INV-262-01), so this function performs no shape validation of its own
and the search below can compare against the store's own lower-case
rendering without further qualification.
-}
localOutputAt ::
    OutputLocator -> Transaction IO cf Cols op (Either ChainQueryError ChainAssetUtxo)
localOutputAt locator = do
    rows <- scanAllTx
    pure $
        case [row | row@(indexerTxIn, _) <- rows, matchesLocator indexerTxIn] of
            [row] -> spendableOutput row
            [] -> Left (DecodingFailure ("no live output at the requested reference: " <> locatorText))
            _ -> Left (AmbiguousCurrentState ("more than one live output at the requested reference: " <> locatorText))
  where
    matchesLocator indexerTxIn =
        hexBytes (Indexer.txInId indexerTxIn) == outputLocatorTxId locator
            && fromIntegral (Indexer.txInIx indexerTxIn) == outputLocatorIndex locator
    locatorText =
        outputLocatorTxId locator <> "#" <> T.pack (show (outputLocatorIndex locator))

{- | #262 (DATA-INV-262-02): decode one stored row into the neutral spendable
shape AND establish, for that row, that the shape actually carries it.

This exists because \#262 moved two families of output onto a route \#240 did
not use for them. \#240 handed a builder the checkpoint output it was about
to spend, and each board record it was about to spend, as a ledger 'TxOut'
decoded straight from the stored bytes. Those outputs now travel as
'ChainAssetUtxo' and are rebuilt by
'Cardano.KERI.ChainQuery.LedgerOutput.chainAssetUtxoToLedgerOutput'. A field
the neutral shape cannot represent would therefore no longer be a wrong READ
-- it would be a wrong TRANSACTION, built against an output that silently
lost part of itself on the way.

So the row proves the round trip before it is returned: address, value,
inline datum, and reference script are compared against the output actually
stored, and any difference is a named failure rather than a reduced answer.
A datum HASH is rejected by name, because it is the one difference a
comparison of rebuilt-versus-stored could otherwise MISS -- both sides read
as "no inline datum" and agree.

Scope, stated plainly: this guards the two families \#262 adds. The payer and
reference-script routes \#240 already shipped keep their existing conversion
untouched, so this slice changes no value they produce.
-}
spendableOutput :: (Indexer.TxIn, Indexer.TxOut) -> Either ChainQueryError ChainAssetUtxo
spendableOutput row@(_, Indexer.TxOut rawTxOut) = do
    stored <- decodeConwayTxOut rawTxOut
    utxo <- toChainAssetUtxo row
    (_txIn, rebuilt) <- chainAssetUtxoToLedgerOutput utxo
    preserved "address" (rebuilt ^. addrTxOutL) (stored ^. addrTxOutL)
    preserved "value" (rebuilt ^. valueTxOutL) (stored ^. valueTxOutL)
    preserved
        "reference script"
        (rebuilt ^. (referenceScriptTxOutL . fromStrictMaybeL))
        (stored ^. (referenceScriptTxOutL . fromStrictMaybeL))
    datumPreserved stored rebuilt
    pure utxo
  where
    preserved :: (Eq a) => Text -> a -> a -> Either ChainQueryError ()
    preserved field rebuilt stored
        | rebuilt == stored = Right ()
        | otherwise =
            Left
                ( DecodingFailure
                    ( "the provider-neutral output shape cannot carry this row's "
                        <> field
                        <> "; it would reach a transaction builder changed"
                    )
                )

datumPreserved :: TxOut ConwayEra -> TxOut ConwayEra -> Either ChainQueryError ()
datumPreserved stored rebuilt =
    case (stored ^. datumTxOutL, rebuilt ^. datumTxOutL) of
        (NoDatum, NoDatum) -> Right ()
        (Datum storedDatum, Datum rebuiltDatum)
            | plutusOf storedDatum == plutusOf rebuiltDatum -> Right ()
        (DatumHash _, _) ->
            Left
                ( DecodingFailure
                    "this row carries a datum hash, which the provider-neutral output \
                    \shape cannot carry; it would reach a transaction builder with no datum"
                )
        _ ->
            Left
                ( DecodingFailure
                    "the provider-neutral output shape cannot carry this row's inline \
                    \datum; it would reach a transaction builder changed"
                )
  where
    plutusOf binaryDatum = let Data plutus = binaryDataToData binaryDatum in plutus

decodeConwayTxOut :: ByteString -> Either ChainQueryError (TxOut ConwayEra)
decodeConwayTxOut rawTxOut =
    first
        (DecodingFailure . T.pack . show)
        (decodeFull (eraProtVerLow @ConwayEra) (BSL.fromStrict rawTxOut) :: Either DecoderError (TxOut ConwayEra))

{- | DAT-240-LOCAL-SETTINGS: write local-store configuration. Contains no
provider URL, token, endpoint, or provider selector (RQ-240-07\/
DATA-INV-240-02). #240 (N-026\/N-027): the checkpoint\/board identities are
'Maybe' -- a write command supplies one only for an operation it actually
dispatches (e.g. deploy dispatches neither, so both are 'Nothing'; a board
write's checkpoint identity is 'Nothing'). No dummy\/all-zero value is ever
constructed for the absent case; 'localCurrentCheckpoint'\/'localBoardCatalog'\/
'localBoardCatalogWithOutputs' fail closed on 'Nothing' before any store
scan (DAT-240-LOCAL-SCOPE).
-}
data LocalSettings = LocalSettings
    { localStorePath :: !FilePath
    , localCheckpointIdentity :: !(Maybe (PolicyID, Indexer.Address))
    , localBoardIdentity :: !(Maybe Indexer.Address)
    }

{- | T240-S1-04\/06\/07 (RQ-240-03\/04): brackets ONE store transaction
runner for a whole write runner\/action -- every snapshot and temporal call
the action makes runs against the SAME held-open runner, never a fresh
bracket per query or per settlement poll (DAT-240-WRITE-RUNTIME: "one local
scope"; DATA-INV-240-03: "a local query scope cannot outlive its store
bracket" — the rank-2 callback type is what makes that a compiler-enforced
guarantee, not a convention, exactly like every other abstract-scope value
in this codebase, e.g. 'Cardano.KERI.ChainQuery.Interpreter.ChainQueryInterpreter').
No provider fallback: 'withRocksDBIndexerRunner' failing to open the store
propagates as an ordinary exception, never a silently degraded answer.
Constructs no dummy\/all-zero checkpoint or board identity (N-027): the
'LocalQueryScope' callers receive carries exactly the 'Maybe' identities
'LocalSettings' was given, nothing more.
-}
withLocalQueryScope ::
    LocalSettings -> (forall cf op. LocalQueryScope cf op -> IO result) -> IO result
withLocalQueryScope settings action =
    withRocksDBIndexerRunner (localStorePath settings) $ \_handle runner ->
        action
            LocalQueryScope
                { localScopeRunner = runner
                , localScopeCheckpointIdentity = localCheckpointIdentity settings
                , localScopeBoardIdentity = localBoardIdentity settings
                }
