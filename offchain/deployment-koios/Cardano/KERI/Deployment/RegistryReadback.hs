{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReadback
Description : The checkpoint of a booked identifier, read back through the ledger provider

A checkpoint is looked up by the identifier exactly as it was signed and booked
(a basic prefix of code B or D, or a self-addressing one of code E). The answer
is the stored identifier and the stored current keys, as spelled, with the
references that tie them to the inception that was booked: the checkpoint
output, the fold transaction that created it, the pending request output that
fold consumed, the booking transaction that created that request and the index
of the output in it. The signed bytes are read from the evidence of the Issue
redeemer at that index; the identifier in them is compared with the stored one
and the inception digest is recomputed from them. A digest is never inferred:
when a link cannot be followed through the provider the stored state is
returned marked not linked, naming the link that failed.
-}
module Cardano.KERI.Deployment.RegistryReadback (
    Readback (..),
    Link (..),
    Linked (..),
    LinkFailure (..),
    readCheckpoint,
    signedDigest,
) where

import Cardano.KERI.AID.Application (RegistrationData (..), activeTokenName)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    checkpointDatumFromData,
 )
import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistryTransactions (
    RegistryDeployment,
    applicationPolicyId,
    approval,
    attestationPolicyId,
    deploymentScripts,
    statePolicyId,
 )
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (txIxToInt)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MultiAsset (..), PolicyID)
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import PlutusCore.Data qualified as PLC
import Singular.Registry.Evidence (Evidenced (..))
import Singular.Registry.LedgerProvider (
    HistoricalTransaction (..),
    HistoryBlock (..),
    HistoryFailure,
    HistoryRange (..),
    HistoryStream (..),
    OutputQuery (..),
    ReadFailure (..),
    Session (..),
 )

-- | The links of the chain of evidence, in the order they are followed.
data Link
    = FoldTransaction
    | PendingOutput
    | BookingTransaction
    | BookingEvidence
    | SignedIdentifier
    deriving stock (Eq, Show)

-- | Why a link could not be followed.
data LinkFailure
    = -- | the provider does not show the transaction or output the link names
      NotShown !Link
    | -- | the provider refused the read
      ProviderRefused !Link !String
    | -- | the signed identifier differs from the stored one
      IdentifierDiffers
    | -- | the signed bytes do not bind their own digest
      DigestDoesNotBind
    deriving stock (Eq, Show)

-- | A complete chain of evidence.
data Linked = Linked
    { linkedFold :: !TxId
    , linkedPending :: !TxIn
    , linkedBooking :: !TxId
    , linkedIndex :: !Integer
    , linkedDigest :: !ByteString
    -- ^ the inception's own digest, 32 raw bytes, recomputed from the signed bytes
    }
    deriving stock (Eq, Show)

data Readback = Readback
    { readbackIdentifier :: !ByteString
    -- ^ the identifier as stored
    , readbackKeys :: ![ByteString]
    -- ^ the current keys as stored, in order
    , readbackCheckpoint :: !TxIn
    , readbackLinks :: !(Either (Link, LinkFailure) Linked)
    }
    deriving stock (Eq, Show)

{- | The checkpoint holding the active token of the identifier, with the evidence
chain. 'Nothing' when the provider shows no holder.
-}
readCheckpoint ::
    RegistryDeployment ->
    Session w IO ->
    -- | the identifier exactly as signed and booked
    ByteString ->
    IO (Either ReadFailure (Maybe Readback))
readCheckpoint deployment session identifier =
    outputs session (HoldingAsset activeAsset) >>= \case
        Left failure -> pure (Left failure)
        Right Evidenced{value = held} -> case held of
            [] -> pure (Right Nothing)
            [(out, txOut)] -> case rawInlineData txOut >>= checkpointDatumFromData of
                Just (V2 Live{lvAid, lvKeys}) | lvAid == identifier -> do
                    links <- follow deployment session identifier out activeAsset
                    pure (Right (Just (Readback lvAid (kmCurKeys lvKeys) out links)))
                _ -> pure (Left (BackendReadFailure "the holder of the active token does not carry the live datum of the identifier"))
            _ -> pure (Left (BackendReadFailure "more than one output holds the active token"))
  where
    activeAsset =
        ( statePolicyId deployment
        , AssetName (SBS.toShort (activeTokenName (scriptsRegistry (deploymentScripts deployment)) identifier))
        )

follow ::
    RegistryDeployment ->
    Session w IO ->
    ByteString ->
    TxIn ->
    (PolicyID, AssetName) ->
    IO (Either (Link, LinkFailure) Linked)
follow deployment session identifier (TxIn foldId _) activeAsset =
    transactionsOf session FoldTransaction activeAsset >>= \case
        Left failure -> pure (Left failure)
        Right folds -> case find ((== foldId) . historicalId) folds of
            Nothing -> pure (Left (FoldTransaction, NotShown FoldTransaction))
            Just foldTx -> case find (isRequestOf identifier) (spentOutputs foldTx) of
                Nothing -> pure (Left (PendingOutput, NotShown PendingOutput))
                Just (pendingIn, pendingOut) -> case registrationOfOutput pendingOut of
                    Nothing -> pure (Left (PendingOutput, NotShown PendingOutput))
                    Just record -> do
                        let TxIn bookingId ix = pendingIn
                            index = txIxToInt ix
                            approvalAsset = (applicationPolicyId deployment, AssetName (SBS.toShort (approval record)))
                        transactionsOf session BookingTransaction approvalAsset >>= \case
                            Left failure -> pure (Left failure)
                            Right bookings -> pure $ case find ((== bookingId) . historicalId) bookings of
                                Nothing -> Left (BookingTransaction, NotShown BookingTransaction)
                                Just bookingTx -> do
                                    event <-
                                        maybe
                                            (Left (BookingEvidence, NotShown BookingEvidence))
                                            Right
                                            (issueEvidence deployment (historicalTx bookingTx) (fromIntegral index))
                                    digest <- first (SignedIdentifier,) (signedDigest identifier event)
                                    Right
                                        Linked
                                            { linkedFold = foldId
                                            , linkedPending = pendingIn
                                            , linkedBooking = bookingId
                                            , linkedIndex = fromIntegral index
                                            , linkedDigest = digest
                                            }
  where
    isRequestOf aid (_, out) = maybe False ((== aid) . requestKey) (registrationOfOutput out)

-- | Every transaction the provider shows for an asset, in the order it gives them.
transactionsOf ::
    Session w IO ->
    Link ->
    (PolicyID, AssetName) ->
    IO (Either (Link, LinkFailure) [HistoricalTransaction])
transactionsOf session link asset =
    history session asset (HistoryRange Nothing Nothing) >>= \case
        Left failure -> pure (refused failure)
        Right stream -> collect [] stream
  where
    refused :: HistoryFailure -> Either (Link, LinkFailure) a
    refused failure = Left (link, ProviderRefused link (show failure))
    collect acc stream =
        nextBlock stream >>= \case
            Left failure -> pure (refused failure)
            Right Nothing -> pure (Right (reverse acc))
            Right (Just (block, rest)) -> collect (reverse (toList (blockTransactions block)) <> acc) rest

{- | The signed bytes of the Issue evidence at an output index of a booking
transaction: the redeemer of its attestation policy.
-}
issueEvidence :: RegistryDeployment -> ConwayTx -> Integer -> Maybe ByteString
issueEvidence deployment tx index = do
    let Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
        MultiAsset minted = tx ^. bodyTxL . mintTxBodyL
    position <- Map.lookupIndex (attestationPolicyId deployment) minted
    (Data (PLC.Constr 0 [PLC.B _, PLC.List entries]), _) <- Map.lookup (ConwayMinting (AsIx (fromIntegral position))) redeemers
    evidence <- lookup index [(i, e) | PLC.Constr 0 [PLC.I i, e] <- entries]
    case evidence of
        PLC.Constr 0 (PLC.B event : _) -> Just event
        _ -> Nothing

{- | The own digest of a signed inception, recomputed from its bytes, when the
identifier in them is the stored one and the digest they carry is the one they
bind. Never inferred: any other case is a failure.
-}
signedDigest :: ByteString -> ByteString -> Either LinkFailure ByteString
signedDigest identifier raw = do
    event <- either (const (Left (NotShown BookingEvidence))) Right (decodeEstablishmentEvent raw)
    if deeAid event == identifier then Right () else Left IdentifierDiffers
    let recomputed = blake3Hash (deeSaidPreimage event)
    case parsePrimitive (deeSaid event) of
        Right (SelfAddressing carried, rest)
            | BS.null rest && carried == recomputed -> Right recomputed
        _ -> Left DigestDoesNotBind
