{- |
Module      : Cardano.KERI.AID.Checkpoint.AdvanceAttestation
Description : the names and redeemers of the two-policy advance

The two policies that replace the advance observer: the fact policy mints an
attestation named by the digest of a signed fact, the change policy one named by
the digest of a claim (the action, the checkpoint policy, the spent output
reference and the index of its successor). The checkpoint's spend requires the
change attestation in the transaction's mint.

A name is the BLAKE2b-256 of the canonical serialisation of the Plutus Data of the
thing it digests, as the validators compute it. The signed fact and the claim's
envelope are passed as Plutus Data, in the layout of the Aiken types
(@SignedFact@ and @ObserverEnvelope@).
-}
module Cardano.KERI.AID.Checkpoint.AdvanceAttestation (
    serialisedData,
    signedFactName,
    advanceClaimData,
    advanceAttestationName,
    factIssueData,
    factBurnData,
    changeIssueData,
    changeBurnData,
    advanceEnvelopeData,
    datumFrozen,
    signedFactForAdvance,
    signedFactForFreeze,
) where

import Cardano.KERI.AID.Checkpoint.Datum (blake2b_256, canonicalCbor)
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))

{- | The canonical serialisation of Plutus Data, the bytes the validators digest and
the bytes a redeemer or a datum carries on the wire.
-}
serialisedData :: Data -> ByteString
serialisedData = canonicalCbor . BuiltinData

digest :: Data -> ByteString
digest = blake2b_256 . serialisedData

{- | The name of the fact attestation: the digest of the list of the fact tag, the
digest of the event bytes, the rotated current keys, their threshold, the
witnesses, the receipt threshold and the committed next keys and threshold of the
spent checkpoint (the signatures and the receipts are not part of the name). Its
argument is the @SignedFact@ record of the Aiken policy, as Plutus Data: constructor
zero of exactly nine fields, the event bytes, the current keys, their threshold, the
witnesses, the receipt threshold, the next keys, their threshold, the signatures and
the receipts, each of its type: a threshold is @Unweighted@ of an integer, or
@Weighted@ of a list of clauses, each a list of weights, each weight the pair of two
integers (the numerator and the denominator); a signature and a receipt are the pair
of a position and bytes. Any other shape has no name. This is the structure of the
wire only: whether a weight is in reduced canonical form, whether a threshold is
satisfiable by the keys and whether the signatures verify are the policy's to
decide.
-}
signedFactName :: Data -> Maybe ByteString
signedFactName fact = case fact of
    Constr 0 [B eventBytes, curKeys, curThreshold, witnesses, toad, nextKeys, nextThreshold, ctrlSigs, receipts]
        | bytesList curKeys
        , threshold curThreshold
        , bytesList witnesses
        , isInteger toad
        , bytesList nextKeys
        , threshold nextThreshold
        , pairsList ctrlSigs
        , pairsList receipts ->
            Just
                ( digest
                    ( List
                        [ B "cardano-keri/signed/v1"
                        , B (blake2b_256 eventBytes)
                        , curKeys
                        , curThreshold
                        , witnesses
                        , toad
                        , nextKeys
                        , nextThreshold
                        ]
                    )
                )
    _ -> Nothing
  where
    bytesList (List xs) = all isBytes xs
    bytesList _ = False
    isBytes (B _) = True
    isBytes _ = False
    isInteger (I _) = True
    isInteger _ = False
    threshold (Constr 0 [I _]) = True
    threshold (Constr 1 [List clauses]) = all clause clauses
    threshold _ = False
    clause (List weights) = all weight weights
    clause _ = False
    weight (Constr 0 [I _, I _]) = True
    weight _ = False
    pairsList (List xs) = all isPair xs
    pairsList _ = False
    isPair (List [I _, B _]) = True
    isPair _ = False

{- | The claim of a change attestation: the tag, the action (one for an advance, two
for a freeze), the checkpoint policy, the spent output reference (transaction
identifier and index) and the index of the successor output.
-}
advanceClaimData :: Integer -> ByteString -> (ByteString, Integer) -> Integer -> Data
advanceClaimData action checkpointPolicy (txid, index) successor =
    Constr
        0
        [ B "cardano-keri/advance/v1"
        , I action
        , B checkpointPolicy
        , Constr 0 [B txid, I index]
        , I successor
        ]

{- | The name of the change attestation: the digest of the claim
('advanceClaimData').
-}
advanceAttestationName :: Integer -> ByteString -> (ByteString, Integer) -> Integer -> ByteString
advanceAttestationName action checkpointPolicy spent successor =
    digest (advanceClaimData action checkpointPolicy spent successor)

-- | The fact policy's Issue redeemer: the signed facts the transaction mints.
factIssueData :: [Data] -> Data
factIssueData facts = Constr 0 [List facts]

-- | The fact policy's Burn redeemer: nothing is minted.
factBurnData :: Data
factBurnData = Constr 1 []

{- | The change policy's Issue redeemer: the claims the transaction mints, each the
observer envelope (claim and evidence) and the index of its successor output.
-}
changeIssueData :: [(Data, Integer)] -> Data
changeIssueData claims = Constr 0 [List [Constr 0 [envelope, I index] | (envelope, index) <- claims]]

-- | The change policy's Burn redeemer: nothing is minted.
changeBurnData :: Data
changeBurnData = Constr 1 []

{- | The observer envelope of a claim: the action, the checkpoint policy, the spent output
reference it names (transaction identifier and index), and the evidence of the advance (an
@AdvanceEvidence@) or of the freeze (a @FreezeEvidence@).
-}
advanceEnvelopeData :: Integer -> ByteString -> (ByteString, Integer) -> Data -> Data
advanceEnvelopeData action checkpointPolicy (txid, index) payload =
    Constr
        0
        [ Constr 0 [I action, B checkpointPolicy, Constr 0 [Constr 0 [B txid, I index]]]
        , payload
        ]

-- | The fields of a version 2 live checkpoint datum: the identifier, the native sequence number, the epoch, the flags and the key material.
liveFields :: Data -> Maybe [Data]
liveFields datum = case datum of
    Constr 1 [Constr 0 fields] | length fields == 9 -> Just fields
    _ -> Nothing

-- | Whether a live checkpoint datum is frozen (its fifth field); nothing for any other datum.
datumFrozen :: Data -> Maybe Bool
datumFrozen datum = case liveFields datum of
    Just [_, _, _, _, Constr frozen [], _, _, _, _] | frozen <= 1 -> Just (frozen == 1)
    _ -> Nothing

-- | The six fields of the key material of a live datum.
keyMaterial :: Data -> Maybe (Data, Data, Data, Data, Data, Data)
keyMaterial datum = case liveFields datum of
    Just [_, _, _, _, _, _, _, _, Constr 0 [curKeys, curThreshold, nextKeys, nextThreshold, witnesses, toad]] ->
        Just (curKeys, curThreshold, nextKeys, nextThreshold, witnesses, toad)
    _ -> Nothing

{- | The signed fact of an advance: the rotation's event bytes, the signatures and the
receipts of its evidence, with the successor's current keys, threshold, witnesses and receipt
threshold and the spent checkpoint's committed next keys and threshold. The same fact the fact
policy attests.
-}
signedFactForAdvance :: Data -> Data -> Data -> Maybe Data
signedFactForAdvance spent successor evidence = do
    (_, _, spentNextKeys, spentNextThreshold, _, _) <- keyMaterial spent
    (curKeys, curThreshold, _, _, witnesses, toad) <- keyMaterial successor
    (eventBytes, signatures, receipts) <- evidenceParts evidence
    shapely (Constr 0 [eventBytes, curKeys, curThreshold, witnesses, toad, spentNextKeys, spentNextThreshold, signatures, receipts])

{- | The signed fact of a freeze: the same, the rotated key material read from the freeze evidence
(the key material of the rotation, its sequence number and the rotation's evidence).
-}
signedFactForFreeze :: Data -> Data -> Maybe Data
signedFactForFreeze spent payload = do
    (_, _, spentNextKeys, spentNextThreshold, _, _) <- keyMaterial spent
    case payload of
        Constr 0 [Constr 0 [curKeys, curThreshold, _, _, witnesses, toad], _, rotation] -> do
            (eventBytes, signatures, receipts) <- evidenceParts rotation
            shapely (Constr 0 [eventBytes, curKeys, curThreshold, witnesses, toad, spentNextKeys, spentNextThreshold, signatures, receipts])
        _ -> Nothing

{- | A fact only when it has the shape of the record the fact policy decodes ('signedFactName'): the evidence the
fact is read from is checked structurally here, before anything is built from it. Whether the signatures verify is
the policy's.
-}
shapely :: Data -> Maybe Data
shapely fact = fact <$ signedFactName fact

-- | The event bytes, signatures and receipts of an @AdvanceEvidence@ (fifteen fields).
evidenceParts :: Data -> Maybe (Data, Data, Data)
evidenceParts evidence = case evidence of
    Constr 0 fields
        | length fields == 15
        , eventBytes : _ <- fields
        , [signatures, receipts] <- drop 13 fields ->
            Just (eventBytes, signatures, receipts)
    _ -> Nothing
