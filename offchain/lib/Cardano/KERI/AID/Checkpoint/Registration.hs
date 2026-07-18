{- |
Module      : Cardano.KERI.AID.Checkpoint.Registration
Description : #114 registration predicate + E1-E9 event binding

Validator-free schema-support layer for the registration path (the
@Register@ mint branch), same shape as
"Cardano.KERI.AID.Checkpoint.Enforcement": pure predicates over an
evidence record plus the genesis datum, returning
@Either RegistrationError ()@ with one constructor per check.

The evidence carries the full keripy @icp@ serialization and
prover-supplied per-field offsets. Offsets __locate__ content, they
never define it: every expected slice is computed from the datum
(derivation-code-prefixed qb64 or an exact keripy re-spelling), so
pointing an offset at a different field of the genuine event
compares differently-coded bytes and fails (the A-001
offset-misdirection argument; spec "Why offset misdirection
fails").

Checks composed here are the pure R3\/R4\/R6\/R7\/R8 subset:

* __R3__ — genesis datum: @seq == 0@ and the datum equals
  'inceptionDatum' of the reconstructed message. The
  'InceptionMessage' is rebuilt from the deployment context and the
  datum's own fields ('registrationMessage'); nothing message-shaped
  is caller-supplied.
* __R6__ — the E1-E9 event-binding slice set ('eventBinding'). E1
  runs before R4 because the verified @t@ slice is what derives
  R4's 'EventType' (spec E1 "feeds R4's event_type"): a @dip@\/
  @drt@\/@rot@ event rejects at E1.
* __R4__ — the frozen #68 schema predicate 'validateInception',
  reused, never re-derived.
* __R7__ — controller signatures over the canonical-CBOR preimage
  of the reconstructed message (never the KERI event bytes); the
  distinct verified positions must satisfy the datum's own
  @cur_threshold@ (the event's @kt@, pinned by E5).
* __R8__ — deposit arithmetic over the deployment context.

Transaction-shape checks (R1\/R2\/R5 token presence) are the S5
validator layer; R5 appears here only as the proof-token name
derivation 'proofTokenName'. The H1 @<= 1024@ byte length tier is
the S4 hash-proof policy's scope — this predicate carries no length
guard.
-}
module Cardano.KERI.AID.Checkpoint.Registration (
    -- * Deployment context
    DeploymentContext (..),

    -- * Registration evidence
    RegistrationEvidence (..),

    -- * B-code qb64 and canonical keripy re-spelling
    qb64WitnessVerkey,
    respellHex,
    respellThreshold,

    -- * Proof-token name (R5 derivation)
    proofTokenName,

    -- * Message reconstruction (R3)
    registrationMessage,

    -- * The registration predicate
    RegistrationError (..),
    eventBinding,
    registrationPredicate,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    CheckpointDatumV1 (..),
    Verkey,
    blake2b_256,
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    EventType (..),
    InceptionError,
    InceptionMessage,
    deriveAidAssetName,
    inceptionDatum,
    inceptionMessage,
    validateInception,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
    evaluate,
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
import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertToBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.IntSet qualified as IntSet

-- ---------------------------------------------------------
-- Deployment context
-- ---------------------------------------------------------

{- | The deployment the registration validates against: the frozen
validator parameters (@network_id@, the checkpoint policy = own
script hash, @d_reg@) plus the ledger @min_ada@ floor the R8
arithmetic runs over.
-}
data DeploymentContext = DeploymentContext
    { dcNetworkId :: !Integer
    -- ^ deployment network id (message field 2)
    , dcCheckpointPolicyId :: !ByteString
    -- ^ the checkpoint policy id — the combined script's own hash
    , dcMinAda :: !Integer
    -- ^ ledger min-ADA floor of the state output
    , dcDReg :: !Integer
    -- ^ the registration deposit parameter (economics = O3, #117)
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Registration evidence
-- ---------------------------------------------------------

{- | The @Register@ redeemer evidence: the full keripy @icp@
serialization, per-field value offsets into it (the generator's
offset convention: first byte of the value content between the
quotes; a weighted @kt@\/@nt@ offset points at the opening @[@ of
the full compact-JSON array), and the controller signatures.

'reCtrlSigs' index into the datum's @cur_keys@ and sign the
__'InceptionMessage' canonical-CBOR preimage__ — NOT the KERI event
bytes ('reEventBytes'); the KEL's own indexed KERI signatures stay
off-chain audit material (spec QF).
-}
data RegistrationEvidence = RegistrationEvidence
    { reEventBytes :: !ByteString
    -- ^ the full keripy @icp@ serialization (@serder.raw@)
    , reOffT :: !Int
    -- ^ offset of the event-type value (@t@)
    , reOffI :: !Int
    -- ^ offset of the 44-char qb64 AID (@i@)
    , reOffS :: !Int
    -- ^ offset of the hex sequence-number value (@s@)
    , reOffK :: ![Int]
    -- ^ offsets of the 44-char qb64 @k@ entries
    , reOffKt :: !Int
    -- ^ offset of the @kt@ JSON value
    , reOffN :: ![Int]
    -- ^ offsets of the 44-char qb64 @n@ entries
    , reOffNt :: !Int
    -- ^ offset of the @nt@ JSON value
    , reOffB :: ![Int]
    -- ^ offsets of the 44-char qb64 @b@ entries
    , reOffBt :: !Int
    -- ^ offset of the @bt@ JSON value
    , reCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into cur_keys, sig over the message preimage)@
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- B-code qb64 and canonical keripy re-spelling
-- ---------------------------------------------------------

{- | The fully qualified Base64url form of a raw 32-byte
__non-transferable__ Ed25519 verkey: code @\'B\'@ followed by
@b64url(0x00 ‖ key)@ with the first (always @\'A\'@) character
replaced by the code — 44 ASCII characters. The witness (@b@ entry)
spelling; same body as 'qb64Verkey' under the @B@ code.
-}
qb64WitnessVerkey :: Verkey -> ByteString
qb64WitnessVerkey key =
    BS.cons 0x42 (BS.drop 1 b64) -- 'B' replaces the leading 'A'
  where
    b64 = convertToBase Base64URLUnpadded (BS.cons 0x00 key)

{- | The keripy @{:x}@ integer spelling: lowercase hex, no leading
zeros (@0 -> \"0\"@, @26 -> \"1a\"@) — the @kt@\/@nt@ unweighted and
@bt@ value bytes. Total: a negative input spells with a @-@ prefix,
which no keripy serialization contains, so its slice check fails.
-}
respellHex :: Integer -> ByteString
respellHex n
    | n < 0 = "-" <> respellHex (negate n)
    | n < 16 = BS.singleton (digit n)
    | otherwise =
        respellHex (n `div` 16) <> BS.singleton (digit (n `mod` 16))
  where
    digit d
        | d < 10 = fromIntegral (48 + d) -- '0'..'9'
        | otherwise = fromIntegral (87 + d) -- 'a'..'f'

{- | The exact compact-JSON value bytes keripy emits for a
threshold (E5\/E7 expected content — #106 O2's canonical
re-spelling, owned here for @icp@): an 'Unweighted' threshold as
its lowercase-hex string content ('respellHex'; the offset points
between the quotes), a single-clause 'Weighted' threshold as the
flat fraction-string array (@[\"1\/2\",\"1\/4\",\"1\/4\"]@ — the S1
fixture ground truth), and a multi-clause one as the nested array
of arrays (keripy's multi-clause convention). A unity\/zero weight
(@den == 1@) spells without a denominator, as keripy does.
-}
respellThreshold :: Threshold -> ByteString
respellThreshold (Unweighted m) = respellHex m
respellThreshold (Weighted [clause]) = respellClause clause
respellThreshold (Weighted clauses) =
    "[" <> BS.intercalate "," (map respellClause clauses) <> "]"

-- | One clause as a compact-JSON array of quoted fraction strings.
respellClause :: [Weight] -> ByteString
respellClause ws =
    "[" <> BS.intercalate "," (map quoted ws) <> "]"
  where
    quoted w = "\"" <> respellWeight w <> "\""

-- | @num\/den@ fraction-string content; @den == 1@ spells bare.
respellWeight :: Weight -> ByteString
respellWeight (Weight num 1) = BS8.pack (show num)
respellWeight (Weight num den) =
    BS8.pack (show num) <> "/" <> BS8.pack (show den)

-- ---------------------------------------------------------
-- Proof-token name (R5 derivation)
-- ---------------------------------------------------------

{- | The hash-proof token name:
@blake2b_256(event_bytes ‖ cesr_aid)@. The name binds the __pair__
(bytes, AID): a proof minted for one AID can never satisfy a
registration carrying different bytes or a different AID. The outer
hash is the cheap native blake2b — a Cardano-internal label, never
a KERI artifact (no blake3 on the registration path, R5).
-}
proofTokenName :: ByteString -> CesrAid -> ByteString
proofTokenName eventBytes cesrAid =
    blake2b_256 (eventBytes <> cesrAid)

-- ---------------------------------------------------------
-- Message reconstruction (R3)
-- ---------------------------------------------------------

{- | The __reconstructed__ 'InceptionMessage': deployment
parameters from the context, the asset name derived (never copied)
from the datum's AID, and the datum's own key-state fields. This is
the only message shape the predicate ever consults — nothing
message-shaped is caller-supplied (R3).
-}
registrationMessage ::
    DeploymentContext -> CheckpointDatumV1 -> InceptionMessage
registrationMessage ctx d =
    inceptionMessage
        (dcNetworkId ctx)
        (dcCheckpointPolicyId ctx)
        (deriveAidAssetName (cdCesrAid d))
        (cdCesrAid d)
        (cdCurKeys d)
        (cdCurThreshold d)
        (cdNextKeys d)
        (cdNextThreshold d)
        (cdWitnesses d)
        (cdToad d)
        (cdNativeSn d)

-- ---------------------------------------------------------
-- The registration predicate
-- ---------------------------------------------------------

-- | A registration rejection reason (one constructor per check).
data RegistrationError
    = {- | R3: @seq \/= 0@ or the datum is not the genesis datum of
      the reconstructed message.
      -}
      R3GenesisDatumMismatch
    | {- | R4: the frozen #68 'validateInception' rejected (domain,
      AID width, derived asset name, @native_sn@, F18 + rule 14).
      -}
      R4InceptionInvalid InceptionError
    | {- | E1: the @t@ slice is not @\"icp\"@ (@dip@\/@drt@\/@rot@
      all reject here; the verified slice feeds R4's event type).
      -}
      E1EventTypeMismatch
    | -- | E2: the @i@ slice is not the datum AID's E-code qb64.
      E2AidMismatch
    | -- | E3: the @s@ slice is not @\"0\"@ (an @icp@ has @s = 0@).
      E3SequenceMismatch
    | {- | E4: @k@ offset count or a slice differs from the datum's
      @cur_keys@ D-code qb64 — the keys-must-match gate.
      -}
      E4CurKeysMismatch
    | {- | E5: the @kt@ slice is not the canonical re-spelling of
      @cur_threshold@.
      -}
      E5CurThresholdMismatch
    | {- | E6: @n@ offset count or a slice differs from the datum's
      @next_keys@ E-code qb64.
      -}
      E6NextKeysMismatch
    | {- | E7: the @nt@ slice is not the canonical re-spelling of
      @next_threshold@.
      -}
      E7NextThresholdMismatch
    | {- | E8: @b@ offset count or a slice differs from the datum's
      witness B-code qb64.
      -}
      E8WitnessesMismatch
    | -- | E9: the @bt@ slice is not the hex re-spelling of @toad@.
      E9ToadMismatch
    | {- | R7: the distinct positions with a verifying signature
      over the message preimage do not satisfy @cur_threshold@.
      -}
      R7QuorumUnsatisfied
    | -- | R8: state-output lovelace below @min_ada + d_reg@.
      R8DepositBelowMinimum
    deriving stock (Show, Eq)

{- | R6 — the E1-E9 event-binding slice set. Every expected value
is computed from the datum (derivation-code-prefixed qb64 or exact
re-spelling); the prover's offsets only locate it. A slice is
checked bounds-first, so a truncated (tail) or negative offset
fails its field's check like any mismatch.
-}
eventBinding ::
    CheckpointDatumV1 ->
    RegistrationEvidence ->
    Either RegistrationError ()
eventBinding d e = do
    unless (slice (reOffT e) "icp") (Left E1EventTypeMismatch)
    unless
        (slice (reOffI e) (qb64Aid (cdCesrAid d)))
        (Left E2AidMismatch)
    unless (slice (reOffS e) "0") (Left E3SequenceMismatch)
    unless
        (slices (reOffK e) (map qb64Verkey (cdCurKeys d)))
        (Left E4CurKeysMismatch)
    unless
        (slice (reOffKt e) (respellThreshold (cdCurThreshold d)))
        (Left E5CurThresholdMismatch)
    unless
        (slices (reOffN e) (map qb64Aid (cdNextKeys d)))
        (Left E6NextKeysMismatch)
    unless
        (slice (reOffNt e) (respellThreshold (cdNextThreshold d)))
        (Left E7NextThresholdMismatch)
    unless
        (slices (reOffB e) (map qb64WitnessVerkey (cdWitnesses d)))
        (Left E8WitnessesMismatch)
    unless
        (slice (reOffBt e) (respellHex (cdToad d)))
        (Left E9ToadMismatch)
  where
    slice = sliceMatches (reEventBytes e)
    slices offs expected =
        length offs == length expected
            && and (zipWith slice offs expected)

{- | The pure registration predicate: R3, R6 (E1-E9), R4, R7, R8,
in order. R6 precedes R4 because E1's verified @t@ slice is what
derives R4's 'EventType' (after E1 only 'Icp' can reach it);
misdirected offsets that force a duplicate datum key slip past E4
only to fail R4's F18 (rule 2). The @lovelace@ argument is the
state output's value the R8 arithmetic runs over; transaction
shape itself (R1\/R2\/R5) is the S5 validator layer.
-}
registrationPredicate ::
    DeploymentContext ->
    -- | The inline datum @D@ of the genesis state output.
    CheckpointDatumV1 ->
    -- | The state output's lovelace (R8).
    Integer ->
    RegistrationEvidence ->
    Either RegistrationError ()
registrationPredicate ctx d lovelace e = do
    -- R3: genesis datum — reconstructed message, nothing supplied.
    let m = registrationMessage ctx d
    unless
        (cdSeq d == 0 && d == inceptionDatum m)
        (Left R3GenesisDatumMismatch)
    -- R6: the event-binding slice set (E1 derives R4's type).
    eventBinding d e
    -- R4: the frozen #68 schema predicate, reused.
    first R4InceptionInvalid (validateInception Icp m)
    -- R7: distinct verified positions over the message preimage.
    let preimage = canonicalCbor m
        signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- reCtrlSigs e
                , Just k <- [cdCurKeys d `atMay` idx]
                , verifyEd25519 k preimage sig
                ]
    unless
        (evaluate (cdCurThreshold d) (length (cdCurKeys d)) signed)
        (Left R7QuorumUnsatisfied)
    -- R8: deposit floor.
    unless
        (lovelace >= dcMinAda ctx + dcDReg ctx)
        (Left R8DepositBelowMinimum)

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

{- | Does the slice of @raw@ at @off@ equal @expected@?
Bounds-checked: an out-of-range span never matches.
-}
sliceMatches :: ByteString -> Int -> ByteString -> Bool
sliceMatches raw off expected =
    off >= 0
        && off + n <= BS.length raw
        && BS.take n (BS.drop off raw) == expected
  where
    n = BS.length expected

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing
