{- |
Module      : Cardano.KERI.AID.Checkpoint.Registration
Description : The registration predicate and the binding of an inception to the datum it books

Validator-free schema-support layer for the registration path, mirroring `checkpoint/registration.ak`: pure
predicates over an evidence record plus the genesis datum, returning @Either RegistrationError ()@.

The evidence carries the signed @icp@, the controller signatures and the witness receipts. Nothing in it is positioned
by the prover: the canonical inception is rebuilt from the datum's qualified spellings and compared with the signed
bytes whole ('eventBinding'). The datum keeps the qualified text of the identifier and of each current key; the raw
payloads are derived for the signature checks.

Checks composed here are the pure R3\/R4\/R6\/R7\/R8 subset: R3 genesis datum, R6 the binding, R4 the inception
schema predicate over the datum (with the inception's next declaration), R7 controller signatures and witness
receipts over the exact event bytes, R8 deposit arithmetic. Transaction-shape checks (R1\/R2\/R5) are the validator
layer; R5 appears here only as the proof-token name derivation 'proofTokenName'.
-}
module Cardano.KERI.AID.Checkpoint.Registration (
    -- * Deployment context
    DeploymentContext (..),

    -- * Registration evidence
    RegistrationEvidence (..),
    QualifiedSpelling (..),

    -- * B-code qb64 and canonical keripy re-spelling
    qb64WitnessVerkey,
    respellHex,
    respellThreshold,
    hex6,
    thresholdJson,
    listJson,

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
    registrationPredicate,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    DatumError,
    KeyStateView (..),
    QualifiedSpelling (..),
    Verkey,
    blake2b_256,
    keyStateInceptionWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.EventScan (anchorAfter)
import Cardano.KERI.AID.Checkpoint.Qualified (codeB, codeD, codeE, digestPayload)
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
import Data.Maybe (isNothing)

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

{- | The @Register@ redeemer evidence: the signed @icp@ as keripy serialized it, the controller signatures and the witness
receipts.

'reCtrlSigs' index into the datum's @cur_keys@ and 'reWitReceipts' index into its witnesses. Both authenticate exact
'reEventBytes'.
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
    first InceptionIllFormed (keyStateInceptionWellFormed d)

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
    | {- | R6: the signed bytes are not the canonical inception of the datum: rebuilt from the datum's spellings they differ
      anywhere before the anchor, the digest @d@ is not an @E@ digest, or the anchor is not one complete array that the
      closing brace follows.
      -}
      R6EventNotCanonical
    | {- | R6: the identifier does not fit its derivation code: a key must be the sole current key under threshold one (a
      @B@ key also with empty next keys, witnesses and anchor), a digest must be the event's own digest.
      -}
      R6PrefixMismatch
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

{- | R6 — the binding of the event to the datum, by reconstruction: the canonical inception is rebuilt from the datum's
own validated spellings, the digest @d@ read at its fixed place, and the whole event compared once up to the anchor,
which the one anchor scanner then reads and ends at the closing brace. No other field is scanned.
-}
eventBinding ::
    KeyStateView ->
    QualifiedSpelling ->
    RegistrationEvidence ->
    Either RegistrationError ()
eventBinding d q e
    | size < 1 || size > 1024 = Left R6EventNotCanonical
    | isNothing (digestPayload said) = Left R6EventNotCanonical
    | n >= size || BS.take n raw /= prefix = Left R6EventNotCanonical
    | otherwise = case anchorAfter raw n of
        Nothing -> Left R6EventNotCanonical
        Just (count, end)
            | end + 1 /= size || BS.index raw end /= 125 -> Left R6EventNotCanonical
            | prefixBinding d q said (count == 0) -> Right ()
            | otherwise -> Left R6PrefixMismatch
  where
    raw = reEventBytes e
    size = BS.length raw
    said = BS.take 44 (BS.drop 40 raw)
    prefix =
        BS.concat
            [ "{\"v\":\"KERI10JSON"
            , hex6 size
            , "_\",\"t\":\"icp\",\"d\":\""
            , said
            , "\",\"i\":\""
            , qsAid q
            , "\",\"s\":\"0\",\"kt\":"
            , thresholdJson (cdCurThreshold d)
            , ",\"k\":"
            , listJson (qsCurKeys q)
            , ",\"nt\":"
            , thresholdJson (cdNextThreshold d)
            , ",\"n\":"
            , listJson (map qb64Aid (cdNextKeys d))
            , ",\"bt\":\""
            , respellHex (cdToad d)
            , "\",\"b\":"
            , listJson (map qb64WitnessVerkey (cdWitnesses d))
            , ",\"c\":[],\"a\":"
            ]
    n = BS.length prefix

{- | The identifier fits its derivation code. A digest identifier is the event's own digest. A key identifier is the
sole current key, signing alone; a non-transferable one also leaves nothing to rotate to, witness or anchor.
-}
prefixBinding :: KeyStateView -> QualifiedSpelling -> ByteString -> Bool -> Bool
prefixBinding d q said anchorEmpty
    | code == codeE = said == qsAid q
    | code == codeD = soleKey
    | code == codeB = soleKey && null (cdNextKeys d) && null (cdWitnesses d) && anchorEmpty
    | otherwise = False
  where
    code = BS.head (qsAid q)
    soleKey = qsCurKeys q == [qsAid q] && cdCurThreshold d == Unweighted 1

-- | Six lowercase hexadecimal digits of a size.
hex6 :: Int -> ByteString
hex6 n = BS.replicate (6 - BS.length h) 48 <> h
  where
    h = respellHex (fromIntegral n)

-- | A threshold as its JSON value: the quoted hexadecimal string, or the array.
thresholdJson :: Threshold -> ByteString
thresholdJson t
    | BS.take 1 spelled == "[" = spelled
    | otherwise = "\"" <> spelled <> "\""
  where
    spelled = respellThreshold t

-- | A list of qualified texts as a JSON array of strings.
listJson :: [ByteString] -> ByteString
listJson [] = "[]"
listJson items = "[\"" <> BS.intercalate "\",\"" items <> "\"]"

{- | The pure registration predicate: R3, R6, R4, R7, R8, in order. The @lovelace@ argument is the state output's value
the R8 arithmetic runs over; transaction shape itself (R1\/R2\/R5) is the validator layer.
-}
registrationPredicate ::
    DeploymentContext ->
    -- | The inline datum @D@ of the genesis state output, as a raw view.
    KeyStateView ->
    -- | The qualified spellings of the identifier and the current keys.
    QualifiedSpelling ->
    -- | The state output's lovelace (R8).
    Integer ->
    RegistrationEvidence ->
    Either RegistrationError ()
registrationPredicate ctx d q lovelace e = do
    unless (validRegistrationDeposit (dcDReg ctx)) (Left DRegBelowMinimum)
    -- R3: genesis projection.
    unless (cdSeq d == 0) (Left R3GenesisDatumMismatch)
    -- R6: the binding of the event to the datum.
    eventBinding d q e
    -- R4: the schema predicate over the datum, with the inception's next declaration.
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
