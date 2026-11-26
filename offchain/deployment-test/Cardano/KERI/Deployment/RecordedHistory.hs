{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RecordedHistory
Description : The transactions a chain accepted, served as the public history of an asset

A ledger-provider session whose only answer is the history of an asset. It is
made from the transactions a test chain accepted, each resolved against the
outputs live before it and placed in a block of its own, so the replay reads
what a provider's history read gives it: complete transaction bytes, the
outputs they spent and created, and their validity. Every other read refuses
by name: a replay that asked for more than the history would say so.

This is a component fixture. It establishes what the replay and its caller do
with those bytes; it is not the connected journey.
-}
module Cardano.KERI.Deployment.RecordedHistory (
    recordedBlocks,
    recordedSession,
    streamFailingAfter,
    failingSession,
    countingHistory,
    singularIdentityOf,
    touchesToken,
    withFoldRedeemer,
    terminatingFold,
) where

import Cardano.KERI.AID.Application (RegistryIdentity (..))
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.Tx (IsValid (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (getPlutusData)
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (bodyTxL, isValidTxL, mkBasicTx, txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL, mintTxBodyL, mkBasicTxBody, outputsTxBodyL, referenceInputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, datumTxOutL, valueTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Binary (serialize)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Tracer (nullTracer)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Word (Word64)
import Lens.Micro ((&), (.~), (^.))
import Singular.Registry.Evidence (NoWitness, SessionBinding (..), SessionId (..))
import Singular.Registry.LedgerProvider
import Singular.Registry.TrieState qualified as Singular
import Singular.State.Records (Change (..), decodeFoldRedeemer, foldRedeemer, stateDatum)

-- | The registry as Singular names it.
singularIdentityOf :: RegistryIdentity -> Singular.RegistryIdentity
singularIdentityOf (RegistryIdentity policy name) =
    Singular.RegistryIdentity (Singular.StatePolicyId policy) (AssetName (SBS.toShort name))

{- | One block per transaction, in the order given, each transaction resolved against the
outputs live before it (the first argument is what was live at the start). An input that
nothing resolves is left out of the record, as a provider does for funding it does not know.
-}
recordedBlocks :: Map TxIn (TxOut ConwayEra) -> [ConwayTx] -> [HistoryBlock]
recordedBlocks start = go start 1 []
  where
    go :: Map TxIn (TxOut ConwayEra) -> Word64 -> [HistoryBlock] -> [ConwayTx] -> [HistoryBlock]
    go _ _ done [] = reverse done
    go live height done (tx : rest) =
        let txid = txIdTx tx
            inputs = tx ^. bodyTxL . inputsTxBodyL
            resolved ins = [(i, out) | i <- Set.toList ins, Just out <- [Map.lookup i live]]
            created =
                zipWith
                    (\ix out -> (TxIn txid (TxIx ix), out))
                    [0 ..]
                    (toList (tx ^. bodyTxL . outputsTxBodyL))
            record =
                HistoricalTransaction
                    { historicalId = txid
                    , historicalCbor = BL.toStrict (serialize (eraProtVerHigh @ConwayEra) tx)
                    , historicalTx = tx
                    , spentOutputs = resolved inputs
                    , referenceOutputs = resolved (tx ^. bodyTxL . referenceInputsTxBodyL)
                    , createdOutputs = created
                    , scriptValid = tx ^. isValidTxL == IsValid True
                    }
            live' = foldr (uncurry Map.insert) (foldr Map.delete live (Set.toList inputs)) created
         in go live' (height + 1) (HistoryBlock height (record :| []) : done) rest

-- | A session whose history answers with the blocks that touch the asset, and nothing else.
recordedSession :: [HistoryBlock] -> Session NoWitness IO
recordedSession blocks =
    refusing{history = \asset _ -> pure (Right (streamOf (filter (touches asset) blocks)))}

{- | A session whose history serves the first blocks that touch the asset and then fails on the
next read, as a provider's later page would.
-}
streamFailingAfter :: Int -> Text -> [HistoryBlock] -> Session NoWitness IO
streamFailingAfter served why blocks =
    refusing
        { history = \asset _ ->
            pure (Right (cut served (filter (touches asset) blocks)))
        }
  where
    cut n bs
        | n <= 0 = HistoryStream (pure (Left (HistoryReadFailure (BackendReadFailure why))))
        | otherwise = case bs of
            [] -> HistoryStream (pure (Right Nothing))
            b : more -> HistoryStream (pure (Right (Just (b, cut (n - 1) more))))

-- | A session whose first history read fails, as the provider's would.
failingSession :: Text -> Session NoWitness IO
failingSession why =
    refusing{history = \_ _ -> pure (Left (HistoryReadFailure (BackendReadFailure why)))}

refusing :: Session NoWitness IO
refusing =
    Session
        { sessionNetwork = Network 42
        , servedNetwork = refused "served network"
        , sessionId = SessionId "recorded-history"
        , sessionBinding = Unbound
        , sessionTracer = nullTracer
        , sessionEvaluated = \_ -> pure ()
        , outputs = \_ -> refused "outputs"
        , protocolParameters = refused "protocol parameters"
        , tipObservation = refused "tip"
        , networkTime = refused "network time"
        , scriptRegistered = \_ -> refused "script registration"
        , mintRecord = \_ -> refused "mint record"
        , history = \_ _ -> pure (Left (HistoryReadFailure (BackendReadFailure "the recorded session serves no history")))
        , inclusion = \_ -> refused "inclusion"
        }
  where
    refused what = pure (Left (BackendReadFailure ("the recorded session serves no " <> what)))

streamOf :: [HistoryBlock] -> HistoryStream IO
streamOf = \case
    [] -> HistoryStream (pure (Right Nothing))
    b : more -> HistoryStream (pure (Right (Just (b, streamOf more))))

-- | Whether a recorded block's transaction spends, references, creates, mints or burns the asset.
touches :: Asset -> HistoryBlock -> Bool
touches (policy, name) block = any involved (NE.toList (blockTransactions block))
  where
    involved record =
        any (holds . snd) (spentOutputs record <> referenceOutputs record <> createdOutputs record)
            || minted (historicalTx record ^. bodyTxL . mintTxBodyL)
    holds out = let MaryValue _ assets = out ^. valueTxOutL in minted assets
    minted (MultiAsset assets) =
        maybe False ((/= 0) . Map.findWithDefault 0 name) (Map.lookup policy assets)

-- | Whether a transaction touches the asset: spends, creates or mints it.
touchesToken :: Asset -> ConwayTx -> Bool
touchesToken asset tx = any (touches asset) (recordedBlocks Map.empty [tx])

{- | The same transaction with the changes of its fold redeemer replaced. Only the witness set
changes, so the transaction keeps its identity and its bytes stay consistent with it.
-}
withFoldRedeemer :: ([Change] -> [Change]) -> ConwayTx -> ConwayTx
withFoldRedeemer edit tx = tx & witsTxL . rdmrsTxWitsL .~ Redeemers (Map.map change declared)
  where
    Redeemers declared = tx ^. witsTxL . rdmrsTxWitsL
    change (datum, units) = case decodeFoldRedeemer (getPlutusData datum) of
        Just (seed, changes) -> (Ledger.Data (foldRedeemer seed (edit changes)), units)
        Nothing -> (datum, units)

{- | A fold that terminates a key: it spends the state output, carries the fold redeemer with one
Terminate change, and writes the state output again with the given root. Built in test code to give
the replay a genuine active-to-terminal edge; it is not the installed fold and no script runs on it.
-}
terminatingFold ::
    -- | the seed that names the registry
    TxIn ->
    -- | the state output it spends, and what it holds
    (TxIn, TxOut ConwayEra) ->
    -- | the request the termination consumes
    TxIn ->
    -- | the key
    ByteString ->
    -- | the root after the termination
    ByteString ->
    ConwayTx
terminatingFold seed (stateIn, stateOut) request key root =
    mkBasicTx
        ( mkBasicTxBody
            & inputsTxBodyL .~ Set.singleton stateIn
            & outputsTxBodyL .~ StrictSeq.fromList [stateOut & datumTxOutL .~ inline]
        )
        & witsTxL . rdmrsTxWitsL
            .~ Redeemers
                ( Map.singleton
                    (ConwaySpending (AsIx 0))
                    (Ledger.Data (foldRedeemer seed [Terminate request key []]), ExUnits 0 0)
                )
  where
    inline = mkInlineDatum (stateDatum root)

{- | The session with a count of the history reads it was asked for, so a caller that stopped
before reading history can be told from one that read it.
-}
countingHistory :: Session NoWitness IO -> IO (Session NoWitness IO, IO Int)
countingHistory session = do
    reads' <- newIORef 0
    let counted asset range = modifyIORef' reads' (+ 1) >> history session asset range
    pure (session{history = counted}, readIORef reads')
