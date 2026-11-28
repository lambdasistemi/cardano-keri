{- |
Module      : Cardano.KERI.AID.Checkpoint.Advance
Description : The advance evidence, the binding of a signed rotation to the successor datum, and the receipt gate

Validator-free schema-support layer for the advance path, mirroring `checkpoint/advance.ak`: pure predicates over an
'AdvanceEvidence' record plus the spent and created checkpoint state, returning @Either AdvancePredicateError ()@.

The evidence carries the signed @rot@, the witness-delta lists, the controller signatures and the incoming-set witness
receipts. Nothing in it is positioned by the prover: the canonical rotation is rebuilt from the successor datum's
qualified spellings and the evidence's witness deltas and compared with the signed bytes whole ('eventBinding').
Controller signatures verify over the rotation's own bytes at distinct positions of @cdCurKeys new@; the incoming-set
witness receipt gate counts distinct valid receipts indexed into the created datum's own witness list. No digest
proof is taken over the rot bytes: @d@ is read as an @E@ digest and @p@ likewise, and neither is checked further.
-}
module Cardano.KERI.AID.Checkpoint.Advance (
    -- * Advance evidence
    AdvanceEvidence (..),

    -- * Message reconstruction (V4)
    reconstructAdvanceMessage,

    -- * Event binding (V6, AE1-AE10)
    AdvanceEventError (..),
    eventBinding,

    -- * The advance predicate
    AdvancePredicateError (..),
    advancePredicate,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    KeyStateView (..),
    Verkey,
 )
import Cardano.KERI.AID.Checkpoint.EventScan (anchorAfter)
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError,
    AdvanceMessage,
    RevealedSuccessorSigners (..),
    SpentCheckpoint (..),
    advanceEqualities,
    advanceMessage,
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Qualified (digestPayload)
import Cardano.KERI.AID.Checkpoint.Registration (
    QualifiedSpelling (..),
    hex6,
    listJson,
    qb64WitnessVerkey,
    respellHex,
    thresholdJson,
 )
import Cardano.KERI.AID.Ed25519 (
    verifyEd25519,
 )
import Control.Monad (
    unless,
 )
import Data.Bifunctor (
    first,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet

-- ---------------------------------------------------------
-- Advance evidence
-- ---------------------------------------------------------

{- | The @Advance@ redeemer evidence: the signed @rot@, the ordered witness-delta lists, the controller signatures and the
incoming-set witness receipts.

'aeCtrlSigs' index into @NEW.cur_keys@ and sign 'aeEventBytes' directly. 'aeWitReceipts' index into the __derived__
incoming witness set (@new_set@, W3) and sign 'aeEventBytes' exactly (O1).
-}
data AdvanceEvidence = AdvanceEvidence
    { aeEventBytes :: !ByteString
    -- ^ the full keripy @rot@ serialization (@serder.raw@)
    , aeWitCut :: ![Verkey]
    -- ^ KERI @br@ — raw verkeys cut, in event order
    , aeWitAdd :: ![Verkey]
    -- ^ KERI @ba@ — raw verkeys added, in event order
    , aeCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into new_cur_keys, sig over event_bytes)@
    , aeWitReceipts :: ![(Int, ByteString)]
    -- ^ @(index into the derived new_set, sig over event_bytes)@
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Message reconstruction (V4)
-- ---------------------------------------------------------

{- | The __reconstructed__ 'AdvanceMessage': the spent context's
deployment\/outref\/prior fields, the created (successor) datum's own
key-state fields, and the evidence's witness-delta lists.

Retained only for 'Cardano.KERI.Deployment.Advance.mkAdvancePackage'
(offchain\/deployment, out of #219 phase-1 scope) — dead to
'advancePredicate' since #219, which verifies 'aeCtrlSigs' against
'aeEventBytes' directly. Tracked fast-follow deletion after #181.
-}
reconstructAdvanceMessage ::
    SpentCheckpoint ->
    -- | The created (successor) datum @NEW@.
    KeyStateView ->
    -- | @wit_cut@ (KERI @br@).
    [Verkey] ->
    -- | @wit_add@ (KERI @ba@).
    [Verkey] ->
    AdvanceMessage
reconstructAdvanceMessage sc new witCut witAdd =
    advanceMessage
        (scNetworkId sc)
        (scPolicyId sc)
        (deriveAidAssetName (cdCesrAid new))
        (cdCesrAid new)
        (scTxid sc)
        (scIndex sc)
        (scSeq sc)
        (scNativeSn sc)
        (cdCurKeys new)
        (cdCurThreshold new)
        (cdNextKeys new)
        (cdNextThreshold new)
        witCut
        witAdd
        (cdToad new)
        (cdSeq new)
        (cdNativeSn new)

-- ---------------------------------------------------------
-- Event binding (V6, AE1-AE10)
-- ---------------------------------------------------------

-- | Why the event binding rejected.
data AdvanceEventError
    = {- | The signed bytes are not the canonical rotation of the successor datum and the witness deltas: rebuilt from
      them they differ anywhere before the anchor, @d@ or @p@ is not an @E@ digest, or the anchor is not one complete
      array that the closing brace follows.
      -}
      AEEventNotCanonical
    deriving stock (Show, Eq)

{- | V6 — the binding of the event to the successor datum, by reconstruction: the canonical rotation is rebuilt from the
successor datum's spellings and the evidence's witness deltas, the digests @d@ and @p@ read at their places, and the
whole event compared once up to the anchor, which the one anchor scanner then reads and ends at the closing brace.
-}
eventBinding ::
    -- | The created (successor) datum @NEW@.
    KeyStateView ->
    QualifiedSpelling ->
    AdvanceEvidence ->
    Either AdvanceEventError ()
eventBinding new q e
    | size < 1 || size > 1024 = notCanonical
    | n >= size || at + 44 >= size = notCanonical
    | Nothing <- digestPayload said = notCanonical
    | Nothing <- digestPayload prior = notCanonical
    | BS.take n raw /= prefix = notCanonical
    | otherwise = case anchorAfter raw n of
        Just (_, end) | end + 1 == size && BS.index raw end == 125 -> Right ()
        _ -> notCanonical
  where
    notCanonical = Left AEEventNotCanonical
    raw = aeEventBytes e
    size = BS.length raw
    said = BS.take 44 (BS.drop 40 raw)
    lead =
        BS.concat
            [ "{\"v\":\"KERI10JSON"
            , hex6 size
            , "_\",\"t\":\"rot\",\"d\":\""
            , said
            , "\",\"i\":\""
            , qsAid q
            , "\",\"s\":\""
            , respellHex (cdNativeSn new)
            , "\",\"p\":\""
            ]
    at = BS.length lead
    prior = BS.take 44 (BS.drop at raw)
    prefix =
        BS.concat
            [ lead
            , prior
            , "\",\"kt\":"
            , thresholdJson (cdCurThreshold new)
            , ",\"k\":"
            , listJson (qsCurKeys q)
            , ",\"nt\":"
            , thresholdJson (cdNextThreshold new)
            , ",\"n\":"
            , listJson (map qb64Aid (cdNextKeys new))
            , ",\"bt\":\""
            , respellHex (cdToad new)
            , "\",\"br\":"
            , listJson (map qb64WitnessVerkey (aeWitCut e))
            , ",\"ba\":"
            , listJson (map qb64WitnessVerkey (aeWitAdd e))
            , ",\"a\":"
            ]
    n = BS.length prefix

-- ---------------------------------------------------------
-- The advance predicate
-- ---------------------------------------------------------

{- | Which advance validation rejected: message equalities, event
binding, or the receipt quorum.
-}
data AdvancePredicateError
    = {- | V4: 'advanceEqualities' rejected (eq1-eq5, W1\/W2, eq6
      dual-threshold — including the controller-evidence gate,
      amended eq7, eq8).
      -}
      AdvMessageInvalid AdvanceError
    | -- | V6: the event binding rejected.
      AdvEventBinding AdvanceEventError
    | {- | V7: the count of distinct valid incoming-set witness
      receipts is below @NEW.toad@.
      -}
      AdvReceiptQuorumUnsatisfied
    deriving stock (Show, Eq)

{- | The pure advance predicate: V4 (direct @spent@-vs-@new@ equalities,
with V5's controller-signature evidence folded in as the @signers@
argument), V6 (AE1-AE10 event binding), V7 (incoming-set witness
receipt gate), in order.

V5's controller evidence is the distinct positions of 'aeCtrlSigs' whose
signature verifies over 'aeEventBytes' directly (#219) against
@NEW.cur_keys@ at that position (bad index or bad signature never
counts, never aborts — the @verified_positions@ convention).

V7 counts distinct indices of 'aeWitReceipts' whose signature verifies
over 'aeEventBytes' against the created datum's own witness list at
that position. Because V4's eq7 (amended, W3) already pins that list to
be exactly the derived incoming set, no separate re-derivation is
needed here: a cut witness sits at no position of it, so its receipt
can never count — structurally, not by filter. When @NEW.toad == 0@,
the evidence must carry literally no receipt entries (the brief's
downgrade rule): a non-empty list is rejected outright, even one whose
entries could never verify, rather than silently ignored.
-}
advancePredicate ::
    SpentCheckpoint ->
    -- | The created (successor) datum @NEW@.
    KeyStateView ->
    QualifiedSpelling ->
    AdvanceEvidence ->
    Either AdvancePredicateError ()
advancePredicate sc new q e = do
    let signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- aeCtrlSigs e
                , Just k <- [cdCurKeys new `atMay` idx]
                , verifyEd25519 k (aeEventBytes e) sig
                ]
        revealed =
            RevealedSuccessorSigners
                [ k
                | (idx, k) <- zip [0 ..] (cdCurKeys new)
                , idx `IntSet.member` signed
                ]
    first
        AdvMessageInvalid
        (advanceEqualities sc new (aeWitCut e) (aeWitAdd e) revealed)
    first AdvEventBinding (eventBinding new q e)
    if cdToad new == 0
        then unless (null (aeWitReceipts e)) (Left AdvReceiptQuorumUnsatisfied)
        else
            let receipted =
                    IntSet.fromList
                        [ idx
                        | (idx, sig) <- aeWitReceipts e
                        , Just w <- [cdWitnesses new `atMay` idx]
                        , verifyEd25519 w (aeEventBytes e) sig
                        ]
             in unless
                    (fromIntegral (IntSet.size receipted) >= cdToad new)
                    (Left AdvReceiptQuorumUnsatisfied)

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing
