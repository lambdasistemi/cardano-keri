{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Indexer.ChainQuery
Description : The local whole-program chain-query interpreter (#257 MOD-257-LOCAL)

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

'referenceScripts' has no script-hash index in the current store schema and
returns 'UnsupportedOperation' rather than an invented answer (RQ-257-05
requires Koios, not every interpreter, to answer every operation).
-}
module Cardano.KERI.Indexer.ChainQuery (
    localInterpreter,
    runLocalChainQuery,
) where

import Cardano.Crypto.Hash.Class (hashToBytes)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive, qb64Aid)
import Cardano.KERI.ChainQuery (
    ActiveCheckpoint (..),
    BoardEntry,
    BoardLocator (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainQueryInterpreter,
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySnapshot,
    QuerySource (SourceLocal),
    SnapshotConsistency (AtomicLocal),
    chainQueryInterpreter,
    runChainQuerySnapshot,
    validPayerAddresses,
 )
import Cardano.KERI.ChainQuery.Program (ChainQuery)
import Cardano.KERI.Deployment.EndpointBoardManifest (frozenEndpointBoardPolicyId)
import Cardano.KERI.Indexer.Board (indexedBoardCatalog)
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..), decodeCheckpointOutput)
import Cardano.KERI.Indexer.Query.Tx (
    QueryHandle (..),
    payerUtxosTxAcrossAddresses,
    scanAddressTx,
    watermarkPointTx,
 )
import Cardano.Ledger.Address (serialiseAddr)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, valueTxOutL)
import Cardano.Ledger.Binary (DecoderError, decodeFull)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
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

-- | Translate the whole algebra to one store 'Transaction' per operation.
localInterpreter :: QueryHandle cf op -> ChainQueryInterpreter (Transaction IO cf Cols op)
localInterpreter handle =
    chainQueryInterpreter
        ( \locator aid ->
            withValidCheckpointLocator handle locator (localCurrentCheckpoint handle aid)
        )
        (\locator -> withValidCheckpointLocator handle locator (localLiveCheckpoints handle))
        ( \_hashes ->
            pure (Left (UnsupportedOperation "referenceScripts: the local store has no script-hash index"))
        )
        (\locator -> withValidBoardLocator handle locator (localBoardCatalog handle))
        localPayerUtxos
        localWatermark
        SourceLocal
        AtomicLocal

{- | DATA-INV-257-01: the local store answers exactly one checkpoint policy
and address, fixed at 'QueryHandle' construction. A caller-supplied locator
that disagrees with that fixed configuration fails closed with
'InvalidLocator', rather than being silently discarded in favor of the
handle's own configuration. Emptiness and canonical shape are already
guaranteed by 'Cardano.KERI.ChainQuery.Program.currentCheckpoint'\/
'liveCheckpoints' EAGERLY, structurally, before this operation's
'Cardano.KERI.ChainQuery.Program.ChainQueryF' node can even exist
(NOTE-020) -- this check is provider-specific handle identity only, run
inside the local 'Transaction' before any store read.
-}
checkpointLocatorOk :: QueryHandle cf op -> CheckpointLocator -> Either ChainQueryError ()
checkpointLocatorOk handle locator
    | checkpointLocatorPolicyId locator /= policyIdHex (qhCheckpointPolicy handle) =
        Left (InvalidLocator "checkpoint locator policy id does not match the local store's checkpoint policy")
    | checkpointLocatorAddress locator /= renderIndexerAddress (qhCheckpointAddress handle) =
        Left (InvalidLocator "checkpoint locator address does not match the local store's checkpoint address")
    | otherwise = Right ()

{- | DATA-INV-257-01: the local store answers exactly one board marker
policy\/address, fixed at 'QueryHandle' construction and the frozen manifest
('indexedBoardCatalog', via "Cardano.KERI.Indexer.Board", always resolves
against 'frozenEndpointBoardPolicyId', never a caller-supplied policy).
Emptiness and canonical shape are already structurally guaranteed (see
'checkpointLocatorOk'); this is the provider-specific identity check only.
-}
boardLocatorOk :: QueryHandle cf op -> BoardLocator -> Either ChainQueryError ()
boardLocatorOk handle locator
    | boardLocatorPolicyId locator /= frozenEndpointBoardPolicyId =
        Left (InvalidLocator "board locator policy id does not match the local store's frozen board policy")
    | boardLocatorAddress locator /= renderIndexerAddress (qhBoardAddress handle) =
        Left (InvalidLocator "board locator address does not match the local store's board address")
    | otherwise = Right ()

withValidCheckpointLocator ::
    QueryHandle cf op ->
    CheckpointLocator ->
    Transaction IO cf Cols op (Either ChainQueryError a) ->
    Transaction IO cf Cols op (Either ChainQueryError a)
withValidCheckpointLocator handle locator action =
    either (pure . Left) (const action) (checkpointLocatorOk handle locator)

withValidBoardLocator ::
    QueryHandle cf op ->
    BoardLocator ->
    Transaction IO cf Cols op (Either ChainQueryError a) ->
    Transaction IO cf Cols op (Either ChainQueryError a)
withValidBoardLocator handle locator action =
    either (pure . Left) (const action) (boardLocatorOk handle locator)

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
    QueryHandle cf op -> ChainQuery a -> IO (Either ChainQueryError (QuerySnapshot a))
runLocalChainQuery handle program =
    runTransaction (qhRunner handle) (runChainQuerySnapshot (localInterpreter handle) program)

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
-}
localCurrentCheckpoint ::
    QueryHandle cf op -> Text -> Transaction IO cf Cols op (Either ChainQueryError (Maybe ActiveCheckpoint))
localCurrentCheckpoint handle aidText =
    case decodeAidBytes aidText of
        Left err -> pure (Left (InvalidLocator err))
        Right targetAid -> do
            entries <- scanAddressTx (qhCheckpointAddress handle)
            let matching =
                    [ entry
                    | entry@(txIn, txOut) <- entries
                    , Right record <-
                        [decodeCheckpointOutput (qhCheckpointPolicy handle) txIn (qhCheckpointAddress handle) txOut]
                    , crAid record == targetAid
                    ]
            pure $ case traverse (decodeActiveCheckpoint handle aidText) matching of
                Left err -> Left err
                Right [] -> Right Nothing
                Right [one] -> Right (Just one)
                Right (_ : _ : _) ->
                    Left (AmbiguousCurrentState "more than one live checkpoint output for this AID")

{- | Every live checkpoint at the checkpoint address, each rendered with its
own decoded AID (CESR-encoded from the datum).
-}
localLiveCheckpoints :: QueryHandle cf op -> Transaction IO cf Cols op (Either ChainQueryError [ActiveCheckpoint])
localLiveCheckpoints handle = do
    entries <- scanAddressTx (qhCheckpointAddress handle)
    let decoded =
            [ (entry, TE.decodeUtf8 (qb64Aid (crAid record)))
            | entry@(txIn, txOut) <- entries
            , Right record <-
                [decodeCheckpointOutput (qhCheckpointPolicy handle) txIn (qhCheckpointAddress handle) txOut]
            ]
    pure (traverse (\(entry, aidText) -> decodeActiveCheckpoint handle aidText entry) decoded)

{- | Decode one indexed output into 'ActiveCheckpoint': datum via the
existing 'decodeCheckpointOutput'; lovelace\/assets via a fresh ledger
decode of the same raw bytes (mirroring
"Cardano.KERI.Indexer.Board"'s established pattern); the address is the
caller's own checkpoint address (every scanned entry is at it, by
construction of 'scanAddressTx'), rendered the same bech32 form Koios
reports so 'ActiveCheckpoint' is source-independent.
-}
decodeActiveCheckpoint ::
    QueryHandle cf op -> Text -> (Indexer.TxIn, Indexer.TxOut) -> Either ChainQueryError ActiveCheckpoint
decodeActiveCheckpoint handle aidText (txIn, indexerTxOut@(Indexer.TxOut rawTxOut)) = do
    record <-
        first (DecodingFailure . T.pack . show) $
            decodeCheckpointOutput (qhCheckpointPolicy handle) txIn (qhCheckpointAddress handle) indexerTxOut
    ledgerTxOut <-
        first
            (DecodingFailure . T.pack . show)
            (decodeFull (eraProtVerLow @ConwayEra) (BSL.fromStrict rawTxOut) :: Either DecoderError (TxOut ConwayEra))
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
    pure
        ActiveCheckpoint
            { activeCheckpointAid = aidText
            , activeCheckpointAssetName = hexBytes (crAssetName record)
            , activeCheckpointTxId = hexBytes (Indexer.txInId txIn)
            , activeCheckpointIndex = fromIntegral (Indexer.txInIx txIn)
            , activeCheckpointAddress = renderIndexerAddress (qhCheckpointAddress handle)
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

localBoardCatalog :: QueryHandle cf op -> Transaction IO cf Cols op (Either ChainQueryError [BoardEntry])
localBoardCatalog handle = do
    entries <- scanAddressTx (qhBoardAddress handle)
    pure $
        first (DecodingFailure . T.pack) $
            indexedBoardCatalog (qhBoardAddress handle) entries

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
the address is not known statically per row).
-}
toChainAssetUtxo :: (Indexer.TxIn, Indexer.TxOut) -> Either ChainQueryError ChainAssetUtxo
toChainAssetUtxo (txIn, Indexer.TxOut rawTxOut) = do
    ledgerTxOut <-
        first
            (DecodingFailure . T.pack . show)
            (decodeFull (eraProtVerLow @ConwayEra) (BSL.fromStrict rawTxOut) :: Either DecoderError (TxOut ConwayEra))
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
    pure
        ChainAssetUtxo
            { chainAssetTxId = hexBytes (Indexer.txInId txIn)
            , chainAssetIndex = fromIntegral (Indexer.txInIx txIn)
            , chainAssetAddress = address
            , chainAssetLovelace = lovelace
            , chainAssetList = assets
            , chainAssetInlineDatum = Nothing
            , chainAssetReferenceScript = Nothing
            }
