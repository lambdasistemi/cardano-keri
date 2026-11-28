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

* __R3__ — genesis datum: @seq == 0@.
* __R6__ — the E1-E9 event-binding slice set ('eventBinding'). E1
  runs before R4 because the verified @t@ slice is what derives
  R4's 'EventType' (spec E1 "feeds R4's event_type"): a @dip@\/
  @drt@\/@rot@ event rejects at E1.
* __R4__ — the frozen #68 inception schema predicate over the datum.
* __R7__ — controller signatures and witness receipts over exact KERI
  event bytes; distinct verified controller positions satisfy @kt@ and
  distinct witness positions satisfy @toad@.
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

    -- * Deployment-fixed registration bond
    registrationDepositFloor,
    validRegistrationDeposit,

    -- * Inception schema validation (R4)
    EventType (..),
    InceptionError (..),
    validateInceptionDatum,

    -- * The registration predicate
    RegistrationError (..),
    eventBinding,
    eventBindingOver,
    futureThresholdMatches,
    registrationPredicate,
    registrationPredicateOver,
    qualifiedOfView,
) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    DatumError,
    KeyStateView (..),
    QualifiedIdentity (..),
    Verkey,
    blake2b_256,
    inceptionKeyStateWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventVariant (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.InceptionPrefix (verifyPrefixBinding)
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
    evaluate,
    normaliseWeights,
    parseThresholdSpelling,
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

{- | The deployment values registration validation enforces: the
deployment-fixed @d_reg@ plus the ledger @min_ada@ floor the R8
arithmetic runs over.
-}
data DeploymentContext = DeploymentContext
    { dcMinAda :: !Integer
    -- ^ ledger min-ADA floor of the state output
    , dcDReg :: !Integer
    {- ^ deployment-fixed registration bond whose operator magnitude is
    selected pre-mainnet; #117 owns migration/consumer lookup,
    not this security parameter
    -}
    }
    deriving stock (Show, Eq)

-- | Mechanical lower bound for the deployment-fixed registration bond.
registrationDepositFloor :: Integer
registrationDepositFloor = 5_000_000

-- | Whether an applied registration-bond parameter is deployable.
validRegistrationDeposit :: Integer -> Bool
validRegistrationDeposit dReg = dReg >= registrationDepositFloor

-- ---------------------------------------------------------
-- Registration evidence
-- ---------------------------------------------------------

{- | The @Register@ redeemer evidence: the exact signed keripy @icp@
serialization and the attachments over it. No position is carried: the
fields of the event are read from the bytes by the structural decoder
("Cardano.KERI.AID.Checkpoint.EventDecoder"), so a submitter cannot choose
where a validator reads.

'reCtrlSigs' index into the datum's @cur_keys@ and 'reWitReceipts'
index into its witnesses. Both authenticate exact 'reEventBytes'.
-}
data RegistrationEvidence = RegistrationEvidence
    { reEventBytes :: !ByteString
    -- ^ the full keripy @icp@ serialization (@serder.raw@)
    , reCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into cur_keys, signature over event_bytes)@
    , reWitReceipts :: ![(Int, ByteString)]
    -- ^ @(index into witnesses, receipt signature over event_bytes)@
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
-- Inception schema validation (R4)
-- ---------------------------------------------------------

-- | The attested KERI inception event type. V1 accepts only 'Icp'.
data EventType = Icp | Dip | Drt
    deriving stock (Show, Eq)

-- | An inception datum rejection reason, with no authorization message.
data InceptionError
    = DelegatedInceptionRejected
    | InceptionAidWidth
    | InceptionNativeSnNonZero
    | InceptionIllFormed DatumError
    deriving stock (Show, Eq)

-- | Validate the structural inception projection carried by a datum.
validateInceptionDatum ::
    EventType -> KeyStateView -> Either InceptionError ()
validateInceptionDatum et d = do
    unless (et == Icp) (Left DelegatedInceptionRejected)
    unless (BS.length (cdCesrAid d) == 32) (Left InceptionAidWidth)
    unless (cdNativeSn d == 0) (Left InceptionNativeSnNonZero)
    first InceptionIllFormed (inceptionKeyStateWellFormed d)

-- ---------------------------------------------------------
-- The registration predicate
-- ---------------------------------------------------------

-- | A registration rejection reason (one constructor per check).
data RegistrationError
    = -- | Applied @d_reg@ is below 'registrationDepositFloor'.
      DRegBelowMinimum
    | {- | R3: @seq \/= 0@ or the datum is not the genesis checkpoint
      state.
      -}
      R3GenesisDatumMismatch
    | {- | R4: inception datum validation rejected (AID width,
      @native_sn@, F18 + rule 14).
      -}
      R4InceptionInvalid InceptionError
    | {- | E1: the bytes are not one complete @icp@ event: the structural
      decoder refuses them, or the decoded type is not @icp@ (@dip@\/@drt@\/
      @rot@ all reject here; the decoded type feeds R4's event type).
      -}
      E1EventTypeMismatch
    | {- | E2: the signed @i@ is not bound to its prefix kind (a basic prefix is
      the sole signing key; a self-addressing prefix is the digest of the signed
      body), or its raw 32 bytes are not the datum's identifier.
      -}
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
    | {- | R7: the distinct positions with a verifying signature over
      the exact @event_bytes@ do not satisfy @cur_threshold@.
      -}
      R7QuorumUnsatisfied
    | {- | R7: distinct valid witness receipt positions did not meet @toad@,
      or a zero-toad datum carried a non-empty receipt list.
      -}
      R7WitnessQuorumUnsatisfied
    | -- | R8: state-output lovelace below @min_ada + d_reg@.
      R8DepositBelowMinimum
    deriving stock (Show, Eq)

{- | The signed @i@ is bound to its prefix kind and carries exactly the datum's
32 identifier bytes: the key of a basic prefix (codes B and D), the digest of a
self-addressing one (code E).
-}
identifierBound :: DecodedEstablishmentEvent -> QualifiedIdentity -> CesrAid -> Bool
identifierBound ev q aid =
    either (const False) (const True) (verifyPrefixBinding ev)
        && deeAid ev == qiAid q
        && case parsePrimitive (qiAid q) of
            Right (Ed25519PublicKey raw, rest) -> BS.null rest && raw == aid
            Right (SelfAddressing raw, rest) -> BS.null rest && raw == aid
            _ -> False

-- | The 32 raw bytes of one complete qualified Ed25519 public key (code B or D).
rawKey :: ByteString -> Maybe ByteString
rawKey text = case parsePrimitive text of
    Right (Ed25519PublicKey raw, rest) | BS.null rest -> Just raw
    _ -> Nothing

{- | The signed future threshold against the datum's. A numeric threshold is compared by its exact
spelling, as the current threshold is. A weighted one is compared by the rational value of its
weights: the signed bytes keep the spelling they were signed with (an unreduced @2/4@ stays @2/4@
in the event, in its identity and its signatures), the datum stores the weights in lowest terms.
-}
futureThresholdMatches :: ByteString -> Threshold -> Bool
futureThresholdMatches signed = \case
    declared@(Unweighted _) -> signed == respellThreshold declared
    declared@(Weighted _) ->
        either (const False) ((== normaliseWeights declared) . normaliseWeights) (parseThresholdSpelling signed)

{- | R6 — the E1-E9 event binding. The event is decoded from its bytes
alone (E1 refuses what does not decode); every expected value is computed from the datum
(derivation-code-prefixed qb64 or an exact keripy re-spelling) and compared
with the decoder's projection of the same field. There is no position to
point at another field: field identity comes from the parse.
-}
eventBindingOver ::
    QualifiedIdentity ->
    KeyStateView ->
    RegistrationEvidence ->
    Either RegistrationError ()
eventBindingOver q d e = do
    ev <-
        either
            (const (Left E1EventTypeMismatch))
            Right
            (decodeEstablishmentEvent (reEventBytes e))
    unless (deeVariant ev == VariantIcp) (Left E1EventTypeMismatch)
    unless (identifierBound ev q (cdCesrAid d)) (Left E2AidMismatch)
    unless (deeSeq ev == "0") (Left E3SequenceMismatch)
    unless
        (deeK ev == qiCurKeys q && map rawKey (qiCurKeys q) == map Just (cdCurKeys d))
        (Left E4CurKeysMismatch)
    unless
        (deeKt ev == respellThreshold (cdCurThreshold d))
        (Left E5CurThresholdMismatch)
    unless
        (deeN ev == map qb64Aid (cdNextKeys d))
        (Left E6NextKeysMismatch)
    unless
        (futureThresholdMatches (deeNt ev) (cdNextThreshold d))
        (Left E7NextThresholdMismatch)
    unless
        (deeB ev == map qb64WitnessVerkey (cdWitnesses d))
        (Left E8WitnessesMismatch)
    unless
        (deeBt ev == respellHex (cdToad d))
        (Left E9ToadMismatch)

{- | The qualified spelling of a datum whose identifier carries the E code and
whose current keys carry the D code: the datum of a self-addressing, transferable
inception. A basic prefix whose signing key has the B code is read with
'registrationPredicateOver' and its own qualified identity.
-}
qualifiedOfView :: KeyStateView -> QualifiedIdentity
qualifiedOfView d =
    QualifiedIdentity
        { qiAid = qb64Aid (cdCesrAid d)
        , qiCurKeys = map qb64Verkey (cdCurKeys d)
        }

-- | R6 over the E and D spelling of the datum ('qualifiedOfView').
eventBinding :: KeyStateView -> RegistrationEvidence -> Either RegistrationError ()
eventBinding d = eventBindingOver (qualifiedOfView d) d

-- | The registration predicate over the E and D spelling of the datum.
registrationPredicate ::
    DeploymentContext ->
    KeyStateView ->
    Integer ->
    RegistrationEvidence ->
    Either RegistrationError ()
registrationPredicate ctx d = registrationPredicateOver ctx (qualifiedOfView d) d

{- | The pure registration predicate: R3, R6 (E1-E9), R4, R7, R8,
in order. R6 precedes R4 because E1's verified @t@ slice is what
derives R4's 'EventType' (after E1 only 'Icp' can reach it);
misdirected offsets that force a duplicate datum key slip past E4
only to fail R4's F18 (rule 2). The @lovelace@ argument is the
state output's value the R8 arithmetic runs over; transaction
shape itself (R1\/R2\/R5) is the S5 validator layer.
-}
registrationPredicateOver ::
    DeploymentContext ->
    -- | The qualified identifier and current keys the committed datum carries.
    QualifiedIdentity ->
    -- | The inline datum @D@ of the genesis state output.
    KeyStateView ->
    -- | The state output's lovelace (R8).
    Integer ->
    RegistrationEvidence ->
    Either RegistrationError ()
registrationPredicateOver ctx q d lovelace e = do
    unless (validRegistrationDeposit (dcDReg ctx)) (Left DRegBelowMinimum)
    -- R3: genesis projection.
    unless (cdSeq d == 0) (Left R3GenesisDatumMismatch)
    -- R6: the event-binding slice set (E1 derives R4's type).
    eventBindingOver q d e
    -- R4: the frozen #68 schema predicate, reused.
    first R4InceptionInvalid (validateInceptionDatum Icp d)
    -- R7: distinct controller positions over exact event bytes.
    let signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- reCtrlSigs e
                , Just k <- [cdCurKeys d `atMay` idx]
                , verifyEd25519 k (reEventBytes e) sig
                ]
    unless
        (evaluate (cdCurThreshold d) (length (cdCurKeys d)) signed)
        (Left R7QuorumUnsatisfied)
    -- R7: distinct witness receipt positions over those same bytes. A
    -- zero-toad event accepts only a literally empty evidence list.
    let witnessed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- reWitReceipts e
                , Just k <- [cdWitnesses d `atMay` idx]
                , verifyEd25519 k (reEventBytes e) sig
                ]
        receiptsSatisfied
            | cdToad d == 0 = null (reWitReceipts e)
            | otherwise =
                toInteger (IntSet.size witnessed) >= cdToad d
    unless receiptsSatisfied (Left R7WitnessQuorumUnsatisfied)
    -- R8: deposit floor.
    unless
        (lovelace >= dcMinAda ctx + dcDReg ctx)
        (Left R8DepositBelowMinimum)

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
