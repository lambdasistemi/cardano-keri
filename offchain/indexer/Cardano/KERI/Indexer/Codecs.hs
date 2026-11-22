{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Indexer.Codecs
Description : Decode checkpoint records from upstream UTxO index entries

Consumes 'Cardano.Node.Client.UTxOIndexer.Types' values and inverts the Conway
@TxOut@ serialisation performed by
'Cardano.Node.Client.UTxOIndexer.BlockExtract'.  Checkpoint datum and asset-name
semantics come from 'Cardano.KERI.AID.Checkpoint.Datum' and
'Cardano.KERI.AID.Checkpoint.Message'.
-}
module Cardano.KERI.Indexer.Codecs (
    CheckpointRecord (..),
    CheckpointDecodeError (..),
    decodeCheckpointOutput,
    Holding (..),
    HoldingKind (..),
    HoldingRefusal (..),
    checkpointAddressOf,
    decodeHoldingOutput,
) where

import Cardano.Crypto.Hash.Class (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Application (Credential (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    checkpointDatumFromData,
    datumFacts,
    isTerminationPending,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.AID.Checkpoint.Value (withValue)
import Cardano.KERI.AID.Consumer (
    DecodedCheckpoint (..),
    Environment (..),
    ObservedOutput (..),
    decodeCheckpoint,
    representativeAsset,
    representativeQuantity,
 )
import Cardano.KERI.AID.Release (
    ReleaseIdentity (..),
    releaseContext,
    releaseEnvironment,
 )
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    binaryDataToData,
 )
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    datumTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (
    DecoderError,
    decodeFull,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (
    ConwayEra,
 )
import Cardano.Ledger.Core (
    TxOut,
    eraProtVerLow,
 )
import Cardano.Ledger.Credential (StakeReference (StakeRefNull))
import Cardano.Ledger.Credential qualified as Ledger
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
    TxIn,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Serialise (serialise)
import Control.Monad (when)
import Data.Bifunctor (
    first,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Lens.Micro (
    (^.),
 )
import PlutusCore.Data qualified as PLC

-- | A live checkpoint recovered from one indexed UTxO.
data CheckpointRecord = CheckpointRecord
    { crAid :: !ByteString
    -- ^ Raw E-code-stripped 32-byte AID, sourced from the datum.
    , crAssetName :: !ByteString
    -- ^ Checkpoint NFT asset name carried by the output.
    , crTxIn :: !TxIn
    -- ^ Upstream indexed transaction input.
    , crAddress :: !Address
    -- ^ Upstream indexed address.
    , crDatum :: !KeyStateView
    -- ^ Decoded checkpoint key state.
    , crFacts :: !CheckpointDatumV2
    -- ^ The version 2 datum the output carries.
    }
    deriving stock (Eq, Show)

-- | Why an indexed output is not a checkpoint record.
data CheckpointDecodeError
    = TxOutUndecodable !String
    | NoInlineDatum
    | DatumUndecodable
    | -- | A convicted checkpoint: the token stays but the checkpoint is over.
      TerminationPendingOutput
    | NoCheckpointAsset
    | AssetNameMismatch
    | MultipleCheckpointAssets
    deriving stock (Eq, Show)

-- | Decode one upstream indexed output under the deployment checkpoint policy.
decodeCheckpointOutput ::
    PolicyID ->
    TxIn ->
    Address ->
    Indexer.TxOut ->
    Either CheckpointDecodeError CheckpointRecord
decodeCheckpointOutput checkpointPolicy txIn address (Indexer.TxOut rawTxOut) = do
    ledgerTxOut <-
        first
            (TxOutUndecodable . show)
            ( decodeFull
                (eraProtVerLow @ConwayEra)
                (BSL.fromStrict rawTxOut) ::
                Either DecoderError (TxOut ConwayEra)
            )
    (facts, datum) <-
        case ledgerTxOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutusDatum = binaryDataToData binaryDatum
                 in case checkpointDatumFromData plutusDatum of
                        Just decoded
                            | isTerminationPending decoded -> Left TerminationPendingOutput
                            | otherwise -> maybe (Left DatumUndecodable) Right (datumFacts decoded)
                        Nothing -> Left DatumUndecodable
            NoDatum -> Left NoInlineDatum
            DatumHash _ -> Left NoInlineDatum
    let aid = cdCesrAid datum
        expectedAssetName = deriveAidAssetName aid
        MaryValue _ (MultiAsset policies) = ledgerTxOut ^. valueTxOutL
        checkpointAssets =
            maybe [] Map.keys (Map.lookup checkpointPolicy policies)
    carriedAssetName <-
        case checkpointAssets of
            [] -> Left NoCheckpointAsset
            [AssetName name] -> Right (SBS.fromShort name)
            _ -> Left MultipleCheckpointAssets
    if carriedAssetName /= expectedAssetName
        then Left AssetNameMismatch
        else
            Right
                CheckpointRecord
                    { crAid = aid
                    , crAssetName = carriedAssetName
                    , crTxIn = txIn
                    , crAddress = address
                    , crDatum = datum
                    , crFacts = facts
                    }

-- ---------------------------------------------------------------------------
-- The registry's holdings (release-identity mode)

{- | A holding at the release's checkpoint validator, classified. The AID is the
qualified CESR text the datum carries.
-}
data Holding = Holding
    { holdingAid :: !ByteString
    , holdingSn :: !Integer
    , holdingEpoch :: !Integer
    , holdingTxIn :: !TxIn
    , holdingLovelace :: !Integer
    , holdingKind :: !HoldingKind
    }
    deriving stock (Eq, Show)

-- | What a holding is: a live checkpoint with its facts, or a pending termination.
data HoldingKind
    = HeldCheckpoint
        { hcPoisoned :: !Bool
        , hcFrozen :: !Bool
        , hcBornAt :: !Integer
        , hcRefund :: !ByteString
        , hcToppedUp :: !Bool
        , hcKeys :: !KeyMaterial
        , hcDeposit :: !Integer
        , hcFreezeBond :: !Integer
        , hcPool :: !Integer
        }
    | HeldPendingTermination
    deriving stock (Eq, Show)

-- | Why an output at the checkpoint validator is not a holding of the release.
data HoldingRefusal
    = -- | the output bytes are not a Conway output
      OutputUndecodable !String
    | -- | the address network (first) is not the release's (second)
      WrongNetwork !Integer !Integer
    | -- | the output is not at the release's checkpoint validator
      NotAtCheckpointValidator
    | -- | the datum is no version 2 checkpoint datum
      MalformedDatum
    | -- | tokens only under policies other than the release's state policy
      UnknownRelease
    | -- | a token of the state policy whose name is not this registry's for the datum's AID
      AnotherRegistrysAsset
    | -- | the quantity of the representative asset is not one
      WrongQuantity !Integer
    | -- | the lovelace the datum's facts cannot hold
      LovelaceNotHeld !Integer
    deriving stock (Eq, Show)

{- | The checkpoint validator's address of a release: its script credential, no
stake part, on the release's network. The validator hash is a 28-byte script
hash (the release identity file guarantees it).
-}
checkpointAddressOf :: ReleaseIdentity -> Indexer.Address
checkpointAddressOf ri =
    Indexer.Address . serialiseAddr $
        Addr
            (if riNetwork ri == 0 then Testnet else Mainnet)
            (Ledger.ScriptHashObj (ScriptHash validator))
            StakeRefNull
  where
    validator =
        fromMaybe
            (error "checkpointAddressOf: the checkpoint validator is not a 28-byte hash")
            (hashFromBytes (riCheckpointValidator ri))

{- | Classify one output of the store under a release identity. The checks run
in this order and the first that fails is the refusal: the network, the
checkpoint validator, the datum, the key material, the representative asset
(through 'representativeAsset' of the release's context, the one definition),
and the lovelace the datum's facts hold.
-}
decodeHoldingOutput ::
    ReleaseIdentity ->
    TxIn ->
    Indexer.TxOut ->
    Either HoldingRefusal Holding
decodeHoldingOutput ri txIn (Indexer.TxOut rawTxOut) = do
    ledgerTxOut <-
        first
            (OutputUndecodable . show)
            ( decodeFull
                (eraProtVerLow @ConwayEra)
                (BSL.fromStrict rawTxOut) ::
                Either DecoderError (TxOut ConwayEra)
            )
    let environment = releaseEnvironment ri
        MaryValue (Coin lovelace) (MultiAsset policies) = ledgerTxOut ^. valueTxOutL
        assets =
            [ (hashToBytes policyHash, SBS.fromShort name, quantity)
            | (PolicyID (ScriptHash policyHash), byName) <- Map.toList policies
            , (AssetName name, quantity) <- Map.toList byName
            ]
    (network, credential) <- case ledgerTxOut ^. addrTxOutL of
        Addr net payment _ -> Right (networkNumber net, ledgerCredential payment)
        AddrBootstrap _ -> Left NotAtCheckpointValidator
    when (network /= envNetwork environment) $
        Left (WrongNetwork network (envNetwork environment))
    when (Just credential /= envCheckpointCredential environment) $
        Left NotAtCheckpointValidator
    plutusDatum <- case ledgerTxOut ^. datumTxOutL of
        Datum binaryDatum -> let Data d = binaryDataToData binaryDatum in Right d
        _ -> Left MalformedDatum
    let datumBytes = BSL.toStrict (serialise plutusDatum)
    decoded <- maybe (Left MalformedDatum) Right (decodeCheckpoint datumBytes)
    let context = releaseContext ri (dcAid decoded)
        (statePolicyBytes, _) = representativeAsset context
        observed =
            ObservedOutput
                { ooCredential = credential
                , ooAssets = assets
                , ooDatum = Just datumBytes
                }
        quantity = representativeQuantity context observed
        stateTokens = [() | (p, _, _) <- assets, p == statePolicyBytes]
    -- The Lean decode admitted the datum by shape; the fields it does not
    -- return are read from the same shape, so reading them cannot fail.
    (facts, kind) <- case decoded of
        DecodedLive{dcAid, dcSn, dcEpoch, dcPoisoned, dcFrozen, dcBornAt} -> do
            (refund, toppedUp, keys) <- maybe (Left MalformedDatum) Right (readLive plutusDatum)
            let live =
                    Live
                        { lvAid = dcAid
                        , lvSn = dcSn
                        , lvEpoch = dcEpoch
                        , lvPoisoned = dcPoisoned
                        , lvFrozen = dcFrozen
                        , lvBornAt = dcBornAt
                        , lvRefundTo = refund
                        , lvToppedUp = toppedUp
                        , lvKeys = keys
                        }
            Right
                ( live
                , \pool ->
                    HeldCheckpoint
                        { hcPoisoned = dcPoisoned
                        , hcFrozen = dcFrozen
                        , hcBornAt = dcBornAt
                        , hcRefund = refund
                        , hcToppedUp = toppedUp
                        , hcKeys = keys
                        , hcDeposit = riDeposit ri
                        , hcFreezeBond = if dcFrozen then 0 else riFreezeBond ri
                        , hcPool = pool
                        }
                )
        DecodedPending{dcAid, dcSn, dcEpoch} ->
            Right (TerminationPending dcAid dcSn dcEpoch, const HeldPendingTermination)
    when (quantity /= 1) $
        Left
            ( if quantity /= 0
                then WrongQuantity quantity
                else
                    if not (null stateTokens)
                        then AnotherRegistrysAsset
                        else
                            if null assets
                                then WrongQuantity 0
                                else UnknownRelease
            )
    pool <-
        maybe
            (Left (LovelaceNotHeld lovelace))
            Right
            (withValue (riMinimumAda ri) (riDeposit ri) (riFreezeBond ri) facts lovelace)
    pure
        Holding
            { holdingAid = dcAid decoded
            , holdingSn = dcSn decoded
            , holdingEpoch = dcEpoch decoded
            , holdingTxIn = txIn
            , holdingLovelace = lovelace
            , holdingKind = kind pool
            }
  where
    networkNumber Testnet = 0
    networkNumber Mainnet = 1
    ledgerCredential = \case
        Ledger.ScriptHashObj (ScriptHash h) -> ScriptCredential (hashToBytes h)
        Ledger.KeyHashObj (KeyHash h) -> KeyCredential (hashToBytes h)

{- | The fields of a live datum the consumer decoder does not return: the refund
address, the top-up mark and the key material, read from the Plutus data as the
consumer decoder checked it, and judged by no other rule.
-}
readLive :: PLC.Data -> Maybe (ByteString, Bool, KeyMaterial)
readLive = \case
    PLC.Constr
        1
        [ PLC.Constr
                0
                [_, _, _, _, _, _, PLC.B refund, toppedUp, keys]
            ] -> (,,) refund <$> boolOf toppedUp <*> readKeys keys
    _ -> Nothing
  where
    boolOf (PLC.Constr 0 []) = Just False
    boolOf (PLC.Constr 1 []) = Just True
    boolOf _ = Nothing

-- | The six key fields, each as the consumer decoder checked its shape.
readKeys :: PLC.Data -> Maybe KeyMaterial
readKeys = \case
    PLC.Constr 0 [cur, curThreshold, next, nextThreshold, witnesses, PLC.I toad] ->
        KeyMaterial
            <$> bytesList cur
            <*> threshold curThreshold
            <*> bytesList next
            <*> threshold nextThreshold
            <*> bytesList witnesses
            <*> pure toad
    _ -> Nothing
  where
    bytesList (PLC.List items) = traverse bytesOf items
    bytesList _ = Nothing
    bytesOf (PLC.B b) = Just b
    bytesOf _ = Nothing
    threshold = \case
        PLC.Constr 0 [PLC.I m] -> Just (Unweighted m)
        PLC.Constr 1 [PLC.List clauses] -> Weighted <$> traverse clause clauses
        _ -> Nothing
    clause (PLC.List weights) = traverse weight weights
    clause _ = Nothing
    weight (PLC.Constr 0 [PLC.I n, PLC.I d]) = Just (Weight n d)
    weight _ = Nothing
