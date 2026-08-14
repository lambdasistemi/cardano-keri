{- |
Module      : Cardano.KERI.Deployment.EndpointBoard
Description : Verify KERI endpoint records and resolve the on-chain board

The catalog is deliberately fail-closed: every current output at the frozen
marker address must be an authentic board marker, otherwise no partial view is
returned. Current means the exact unspent set; valid duplicates stay visible.
-}
module Cardano.KERI.Deployment.EndpointBoard (
    EndpointRecord (..),
    BoardEntry (..),
    parseEndpointRecord,
    parseWitnessKey,
    resolveBoardCatalog,
    renderBoardCatalog,
    watchabilityGrade,
    missingBoardWitnesses,
    reconcileBoardMigration,
    renderWatchability,

    -- * Board datum protocol (#253 DAT-253-LEGACY-DATUM/DAT-253-AUTHORIZED-DATUM)
    LegacyBoardDatum (..),
    AuthorizedBoardDatum (..),
    BoardNonce (..),
    BoardDecodeError (..),
    decodeLegacyBoardDatum,
    decodeAuthorizedBoardDatum,
    renderBoardDecodeError,
    legacyBoardDatumData,
    legacyBoardDatumBytes,
    authorizedBoardDatumData,
    authorizedBoardDatumBytes,

    -- * Canonical authorization (#253 DAT-253-AUTHORIZATION)
    BoardAuthorization (..),
    boardAuthorizationDomain,
    reconstructBoardAuthorization,
    boardAuthorizationBytes,
    verifyBoardAuthorization,
    verifyBoardEndpointSignature,
    boardDatumIsAuthentic,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (canonicalCbor)
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Cardano.KERI.ChainQuery (
    BoardEntry (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataFromJson)
import Control.Monad (unless, when)
import Data.Aeson (
    FromJSON (..),
    eitherDecodeStrict',
    withObject,
    (.:),
    (.:?),
 )
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (digitToInt, isHexDigit)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

data EndpointRecord = EndpointRecord
    { endpointEventBytes :: !ByteString
    , endpointSignature :: !ByteString
    , endpointWitnessKey :: !ByteString
    , endpointAid :: !Text
    , endpointScheme :: !Text
    , endpointUrl :: !Text
    }
    deriving stock (Show, Eq)

{- | The one-use ledger output reference bound into an authorization.

Wire shape: @Constr 0 [B nonce_tx_id, I nonce_output_index]@.
-}
data BoardNonce = BoardNonce
    { boardNonceTxId :: !ByteString
    , boardNonceOutputIndex :: !Integer
    }
    deriving stock (Show, Eq)

{- | The frozen #165 board datum: @Constr 0@ with exactly four fields.

Accepted only as historical data or a migration source. It is never emitted,
and never promoted as though it carried an authorization.
-}
data LegacyBoardDatum = LegacyBoardDatum
    { legacyWitnessKey :: !ByteString
    , legacyEndpointRecord :: !ByteString
    , legacyEndpointSignature :: !ByteString
    , legacyOwnerKeyHash :: !ByteString
    }
    deriving stock (Show, Eq)

{- | The authorized target datum: @Constr 0@ with exactly six fields.

The shape is released protocol data shared byte-for-byte with the Aiken
surface. It carries no sequence, no version tag and no stored origin: it is
told apart from the frozen legacy shape by field count alone, and the release
it belongs to is identified by the applied policy hash.
-}
data AuthorizedBoardDatum = AuthorizedBoardDatum
    { authorizedWitnessKey :: !ByteString
    , authorizedEndpointRecord :: !ByteString
    , authorizedEndpointSignature :: !ByteString
    , authorizedOwnerKeyHash :: !ByteString
    , authorizedNonce :: !BoardNonce
    , authorizedSignature :: !ByteString
    }
    deriving stock (Show, Eq)

-- | Why a candidate inline datum is not the board datum it was read as.
data BoardDecodeError
    = -- | The constructor index is not 0.
      BoardUnknownConstructor !Integer
    | -- | Constructor 0 with a field count belonging to no board shape.
      BoardWrongFieldCount !Int
    | -- | A field is present but not of its protocol type.
      BoardFieldNotWellTyped !Int
    | -- | The datum is not a constructor at all.
      BoardNotAConstructor
    | {- | Well-shaped six-field data whose authorization does not verify
      under the applied policy it was read against.
      -}
      BoardAuthorizationRejected
    deriving stock (Show, Eq)

{- | The canonical signed authorization message (@Constr 0@, six fields).

Every field here is covered by the authorization signature; anything absent
from this record is not something the witness agreed to.
-}
data BoardAuthorization = BoardAuthorization
    { boardAuthDomain :: !ByteString
    , boardAuthPolicyId :: !ByteString
    , boardAuthWitnessKey :: !ByteString
    , boardAuthEndpointRecord :: !ByteString
    , boardAuthOwnerKeyHash :: !ByteString
    , boardAuthNonce :: !BoardNonce
    }
    deriving stock (Show, Eq)

instance ToData BoardNonce where
    toBuiltinData nonce =
        BuiltinData $
            Constr
                0
                [ B (boardNonceTxId nonce)
                , I (boardNonceOutputIndex nonce)
                ]

instance ToData LegacyBoardDatum where
    toBuiltinData datum =
        BuiltinData $
            Constr
                0
                [ B (legacyWitnessKey datum)
                , B (legacyEndpointRecord datum)
                , B (legacyEndpointSignature datum)
                , B (legacyOwnerKeyHash datum)
                ]

instance ToData AuthorizedBoardDatum where
    toBuiltinData datum =
        BuiltinData $
            Constr
                0
                [ B (authorizedWitnessKey datum)
                , B (authorizedEndpointRecord datum)
                , B (authorizedEndpointSignature datum)
                , B (authorizedOwnerKeyHash datum)
                , rawData (authorizedNonce datum)
                , B (authorizedSignature datum)
                ]

instance ToData BoardAuthorization where
    toBuiltinData authorization =
        BuiltinData $
            Constr
                0
                [ B (boardAuthDomain authorization)
                , B (boardAuthPolicyId authorization)
                , B (boardAuthWitnessKey authorization)
                , B (boardAuthEndpointRecord authorization)
                , B (boardAuthOwnerKeyHash authorization)
                , rawData (boardAuthNonce authorization)
                ]

rawData :: (ToData a) => a -> Data
rawData value = let BuiltinData raw = toBuiltinData value in raw

{- | Domain separator for the board authorization message.

It is stable and unversioned: releases are told apart by applied policy hash
and exact structural shape, never by a string inside the signed message. No
other cardano-keri message can be replayed as a board authorization.
-}
boardAuthorizationDomain :: ByteString
boardAuthorizationDomain =
    TE.encodeUtf8 "cardano-keri/endpoint-board/authorization"

-- | The exact wire 'Data' of a frozen legacy board datum.
legacyBoardDatumData :: LegacyBoardDatum -> Data
legacyBoardDatumData = rawData

-- | Canonical Plutus Data CBOR of a frozen legacy board datum.
legacyBoardDatumBytes :: LegacyBoardDatum -> ByteString
legacyBoardDatumBytes = canonicalCbor

-- | The exact wire 'Data' of an authorized board datum.
authorizedBoardDatumData :: AuthorizedBoardDatum -> Data
authorizedBoardDatumData = rawData

-- | Canonical Plutus Data CBOR of an authorized board datum.
authorizedBoardDatumBytes :: AuthorizedBoardDatum -> ByteString
authorizedBoardDatumBytes = canonicalCbor

{- | FUN-253-DECODE-LEGACY: read the frozen four-field shape.

Six-field data is not silently truncated into a legacy record: the field
count is exact.
-}
decodeLegacyBoardDatum :: Data -> Either BoardDecodeError LegacyBoardDatum
decodeLegacyBoardDatum = \case
    Constr 0 [f0, f1, f2, f3] ->
        LegacyBoardDatum
            <$> bytesAt 0 f0
            <*> bytesAt 1 f1
            <*> bytesAt 2 f2
            <*> bytesAt 3 f3
    Constr 0 fields -> Left (BoardWrongFieldCount (length fields))
    Constr other _ -> Left (BoardUnknownConstructor other)
    _ -> Left BoardNotAConstructor

{- | FUN-253-DECODE-AUTHORIZED: read the six-field shape under one applied
policy, and refuse it unless the witness authorization verifies under exactly
that policy.

The policy id is the caller's own applied identity, so the same bytes that
authenticate under their own release do not authenticate under another.
-}
decodeAuthorizedBoardDatum ::
    ByteString ->
    Data ->
    Either BoardDecodeError AuthorizedBoardDatum
decodeAuthorizedBoardDatum policyId = \case
    Constr 0 [f0, f1, f2, f3, f4, f5] -> do
        datum <-
            AuthorizedBoardDatum
                <$> bytesAt 0 f0
                <*> bytesAt 1 f1
                <*> bytesAt 2 f2
                <*> bytesAt 3 f3
                <*> nonceAt 4 f4
                <*> bytesAt 5 f5
        unless (verifyBoardAuthorization policyId datum) $
            Left BoardAuthorizationRejected
        pure datum
    Constr 0 fields -> Left (BoardWrongFieldCount (length fields))
    Constr other _ -> Left (BoardUnknownConstructor other)
    _ -> Left BoardNotAConstructor

bytesAt :: Int -> Data -> Either BoardDecodeError ByteString
bytesAt index = \case
    B bytes -> Right bytes
    _ -> Left (BoardFieldNotWellTyped index)

nonceAt :: Int -> Data -> Either BoardDecodeError BoardNonce
nonceAt index = \case
    Constr 0 [B txId, I outputIndex] -> Right (BoardNonce txId outputIndex)
    _ -> Left (BoardFieldNotWellTyped index)

-- | A human-readable rendering of a decode rejection.
renderBoardDecodeError :: BoardDecodeError -> String
renderBoardDecodeError = \case
    BoardUnknownConstructor index ->
        "board datum constructor "
            <> show index
            <> " is not a supported board shape"
    BoardWrongFieldCount count ->
        "board datum constructor 0 has "
            <> show count
            <> " fields, which is neither the frozen legacy shape nor the \
               \authorized shape"
    BoardFieldNotWellTyped index ->
        "board datum field "
            <> show index
            <> " is not of its protocol type"
    BoardNotAConstructor -> "inline datum is not a board datum constructor"
    BoardAuthorizationRejected ->
        "authorized board datum is not signed by its witness under this \
        \applied policy"

{- | FUN-253-AUTH-RECONSTRUCT: rebuild the signed message from a trusted
policy id and a typed authorized datum, never from a caller-supplied preimage.
-}
reconstructBoardAuthorization ::
    ByteString ->
    AuthorizedBoardDatum ->
    BoardAuthorization
reconstructBoardAuthorization policyId datum =
    BoardAuthorization
        { boardAuthDomain = boardAuthorizationDomain
        , boardAuthPolicyId = policyId
        , boardAuthWitnessKey = authorizedWitnessKey datum
        , boardAuthEndpointRecord = authorizedEndpointRecord datum
        , boardAuthOwnerKeyHash = authorizedOwnerKeyHash datum
        , boardAuthNonce = authorizedNonce datum
        }

{- | FUN-253-AUTH-BYTES: canonical Plutus Data CBOR of the authorization —
the same bytes Aiken @cbor.serialise@ emits for the same value.
-}
boardAuthorizationBytes :: BoardAuthorization -> ByteString
boardAuthorizationBytes = canonicalCbor

-- | FUN-253-AUTH-VERIFY: the witness authorized exactly this bound record.
verifyBoardAuthorization :: ByteString -> AuthorizedBoardDatum -> Bool
verifyBoardAuthorization policyId datum =
    BS.length (authorizedWitnessKey datum) == witnessKeyWidth
        && BS.length (authorizedSignature datum) == signatureWidth
        && verifyEd25519
            (authorizedWitnessKey datum)
            ( boardAuthorizationBytes $
                reconstructBoardAuthorization policyId datum
            )
            (authorizedSignature datum)

{- | The independent #165 endpoint signature over the raw KERI record bytes.

Neither signature replaces the other: one proves the endpoint bytes are the
witness's, the other proves the witness accepted this Cardano binding.
-}
verifyBoardEndpointSignature :: AuthorizedBoardDatum -> Bool
verifyBoardEndpointSignature datum =
    BS.length (authorizedWitnessKey datum) == witnessKeyWidth
        && BS.length (authorizedEndpointSignature datum) == signatureWidth
        && verifyEd25519
            (authorizedWitnessKey datum)
            (authorizedEndpointRecord datum)
            (authorizedEndpointSignature datum)

{- | Every byte-level rule for an authorized datum: widths, a non-negative
nonce index, the expected witness key, and BOTH witness signatures.
-}
boardDatumIsAuthentic ::
    ByteString -> ByteString -> AuthorizedBoardDatum -> Bool
boardDatumIsAuthentic expectedKey policyId datum =
    and
        [ BS.length expectedKey == witnessKeyWidth
        , authorizedWitnessKey datum == expectedKey
        , not (BS.null $ authorizedEndpointRecord datum)
        , BS.length (authorizedEndpointSignature datum) == signatureWidth
        , BS.length (authorizedOwnerKeyHash datum) == ownerKeyHashWidth
        , BS.length (boardNonceTxId $ authorizedNonce datum) == nonceTxIdWidth
        , boardNonceOutputIndex (authorizedNonce datum) >= 0
        , -- Both, independently: neither signature stands in for the other.
          verifyBoardEndpointSignature datum
        , verifyBoardAuthorization policyId datum
        ]

witnessKeyWidth, signatureWidth, ownerKeyHashWidth, nonceTxIdWidth :: Int
witnessKeyWidth = 32
signatureWidth = 64
ownerKeyHashWidth = 28
nonceTxIdWidth = 32

{- | The two field counts that select a board shape.

They are exported nowhere and used in exactly one place each, but they are
named because the whole release discrimination rests on them being different.
-}
legacyFieldCount, authorizedFieldCount :: Int
legacyFieldCount = 4
authorizedFieldCount = 6

-- | Why some inline datum is not a board datum of either shape.
boardShapeError :: Data -> BoardDecodeError
boardShapeError = \case
    Constr 0 fields -> BoardWrongFieldCount (length fields)
    Constr other _ -> BoardUnknownConstructor other
    _ -> BoardNotAConstructor

data ReplyEvent = ReplyEvent
    { replyVersion :: !Text
    , replyType :: !Text
    , replyDigest :: !Text
    , replyDate :: !Text
    , replyRoute :: !Text
    , replyAttributes :: !ReplyAttributes
    }

data ReplyAttributes = ReplyAttributes
    { replyEndpointAid :: !Text
    , replyScheme :: !Text
    , replyUrl :: !Text
    }

newtype RoutedEvent = RoutedEvent
    { routedRoute :: Maybe Text
    }

instance FromJSON ReplyEvent where
    parseJSON = withObject "KERI reply event" $ \object ->
        ReplyEvent
            <$> object .: "v"
            <*> object .: "t"
            <*> object .: "d"
            <*> object .: "dt"
            <*> object .: "r"
            <*> object .: "a"

instance FromJSON ReplyAttributes where
    parseJSON = withObject "KERI endpoint attributes" $ \object ->
        ReplyAttributes
            <$> object .: "eid"
            <*> object .: "scheme"
            <*> object .: "url"

instance FromJSON RoutedEvent where
    parseJSON = withObject "KERI routed event" $ \object ->
        RoutedEvent <$> object .:? "r"

-- | Extract exactly one authentic @/loc/scheme@ reply from an OOBI stream.
parseEndpointRecord :: ByteString -> Either String EndpointRecord
parseEndpointRecord stream = do
    messages <- splitMessages stream
    records <- traverse endpointCandidate messages
    case catMaybes records of
        [record] -> pure record
        [] -> Left "OOBI has no /loc/scheme reply"
        _ -> Left "OOBI has more than one /loc/scheme reply"
  where
    endpointCandidate (raw, attachments) = do
        routed <-
            either
                (Left . ("invalid KERI event JSON: " <>))
                pure
                (eitherDecodeStrict' raw)
        if routedRoute routed /= Just "/loc/scheme"
            then pure Nothing
            else do
                event <- decodeReply raw
                Just <$> recordFromAttachedEvent raw attachments event

-- | Decode one witness's KERI B-code to its raw 32-byte Ed25519 key.
parseWitnessKey :: Text -> Either String ByteString
parseWitnessKey = decodeWitnessKey "witness identifier" . TE.encodeUtf8

resolveBoardCatalog ::
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    Either String [BoardEntry]
resolveBoardCatalog policy markerAddress =
    traverse resolveOne . sortOn outputKey
  where
    outputKey output =
        (chainAssetTxId output, chainAssetIndex output)
    resolveOne output =
        prefixOutput output $ do
            unless (chainAssetAddress output == markerAddress) $
                Left "output address is not the board marker address"
            marker <-
                case chainAssetList output of
                    [asset] -> pure asset
                    _ -> Left "output must carry exactly one native asset"
            unless
                ( chainAssetPolicy marker == policy
                    && chainAssetQuantity marker == 1
                )
                $ Left "output does not carry exactly one board marker"
            markerKey <-
                decodeMarkerName (chainAssetName marker)
            datumValue <-
                maybe
                    (Left "output has no inline datum")
                    plutusDataFromJson
                    (chainAssetInlineDatum output)
            -- Both releases are constructor 0, so the decoder is selected by
            -- exact field count. Registry-backed selection by applied policy
            -- hash is T253-S3-03 and is deliberately not done here; see
            -- INV-253-R05 for the honest limit of the structural choice.
            (datumKey, eventBytes, signature, owner) <-
                case datumValue of
                    Constr 0 fields
                        | length fields == legacyFieldCount -> do
                            legacy <-
                                first
                                    renderBoardDecodeError
                                    (decodeLegacyBoardDatum datumValue)
                            pure
                                ( legacyWitnessKey legacy
                                , legacyEndpointRecord legacy
                                , legacyEndpointSignature legacy
                                , legacyOwnerKeyHash legacy
                                )
                        | length fields == authorizedFieldCount -> do
                            -- An authorized record is promoted only when the
                            -- witness signed both the endpoint bytes and this
                            -- exact Cardano binding of them under this policy.
                            policyId <- decodeBoardPolicyId policy
                            current <-
                                first
                                    renderBoardDecodeError
                                    ( decodeAuthorizedBoardDatum
                                        policyId
                                        datumValue
                                    )
                            unless
                                ( boardDatumIsAuthentic
                                    markerKey
                                    policyId
                                    current
                                )
                                $ Left
                                    "authorized datum is not authenticated by \
                                    \both witness signatures"
                            pure
                                ( authorizedWitnessKey current
                                , authorizedEndpointRecord current
                                , authorizedEndpointSignature current
                                , authorizedOwnerKeyHash current
                                )
                    _ ->
                        Left
                            . renderBoardDecodeError
                            $ boardShapeError datumValue
            unless (BS.length datumKey == 32 && datumKey == markerKey) $
                Left "datum witness key does not match the marker asset name"
            unless (BS.length owner == 28) $
                Left "datum owner key hash is not 28 bytes"
            record <-
                validateEndpointEvent datumKey eventBytes signature
            pure
                BoardEntry
                    { boardWitnessKey = endpointWitnessKey record
                    , boardAid = endpointAid record
                    , boardScheme = endpointScheme record
                    , boardUrl = endpointUrl record
                    , boardTxId = chainAssetTxId output
                    , boardIndex = chainAssetIndex output
                    , boardLovelace = chainAssetLovelace output
                    , boardOwnerKeyHash = owner
                    }

renderBoardCatalog :: [BoardEntry] -> Text
renderBoardCatalog =
    T.unlines . map renderEntry
  where
    renderEntry entry =
        T.unwords
            [ boardAid entry
            , "verified"
            , boardScheme entry
            , boardUrl entry
            , "tx"
            , boardTxId entry
                <> "#"
                <> T.pack (show $ boardIndex entry)
            , "deposit"
            , T.pack (show $ boardLovelace entry)
            ]

{- | Count declared witness keys with at least one current verified record.
Duplicate board records never increase the numerator.
-}
watchabilityGrade :: [ByteString] -> [BoardEntry] -> (Int, Int)
watchabilityGrade witnesses entries =
    ( length
        [ ()
        | witness <- witnesses
        , witness `Set.member` catalogKeys
        ]
    , length witnesses
    )
  where
    catalogKeys = Set.fromList (map boardWitnessKey entries)

-- | Declared witness keys that have no current verified board record.
missingBoardWitnesses :: [ByteString] -> [BoardEntry] -> [ByteString]
missingBoardWitnesses witnesses entries =
    [ witness
    | witness <- witnesses
    , witness `Set.notMember` catalogKeys
    ]
  where
    catalogKeys = Set.fromList (map boardWitnessKey entries)

{- | Reconcile one complete source board inventory with its successors.

Both inventories must contain exactly the expected witness identities, once
each, and every protected field must survive the migration unchanged.  The
transaction out-ref is deliberately allowed to change: it identifies the new
successor UTxO rather than board content or custody.
-}
reconcileBoardMigration ::
    [Text] ->
    [BoardEntry] ->
    [BoardEntry] ->
    Either String [(BoardEntry, BoardEntry)]
reconcileBoardMigration expected sources successors = do
    ensureUnique "expected witness identity" expected
    sourceByAid <- inventoryByAid "source" sources
    successorByAid <- inventoryByAid "successor" successors
    unless (Set.fromList expected == Map.keysSet sourceByAid) $
        Left "source board inventory does not match the expected witnesses"
    unless (Set.fromList expected == Map.keysSet successorByAid) $
        Left "successor board inventory does not match the expected witnesses"
    traverse
        reconcileOne
        (Map.elems $ Map.intersectionWith (,) sourceByAid successorByAid)
  where
    reconcileOne (source, successor) = do
        unless (boardRowContinuous source successor) $
            Left
                ( "successor board row changed protected fields for "
                    <> T.unpack (boardAid source)
                )
        pure (source, successor)

inventoryByAid :: String -> [BoardEntry] -> Either String (Map.Map Text BoardEntry)
inventoryByAid label entries = do
    ensureUnique (label <> " board witness identity") (map boardAid entries)
    pure (Map.fromList [(boardAid entry, entry) | entry <- entries])

ensureUnique :: (Ord a) => String -> [a] -> Either String ()
ensureUnique label values =
    unless (Set.size (Set.fromList values) == length values) $
        Left (label <> " appears more than once")

boardRowContinuous :: BoardEntry -> BoardEntry -> Bool
boardRowContinuous source successor =
    -- The AID is deliberately absent: reconciliation has already selected
    -- both rows from maps keyed by this exact expected AID, so comparing it
    -- here would be the tautology @aid == aid@ rather than a continuity check.
    and
        [ boardWitnessKey successor == boardWitnessKey source
        , boardScheme successor == boardScheme source
        , boardUrl successor == boardUrl source
        , boardLovelace successor == boardLovelace source
        , boardOwnerKeyHash successor == boardOwnerKeyHash source
        ]

renderWatchability :: [ByteString] -> [BoardEntry] -> Text
renderWatchability witnesses entries =
    let (watchable, declared) = watchabilityGrade witnesses entries
     in "watchable "
            <> T.pack (show watchable)
            <> "/"
            <> T.pack (show declared)

recordFromAttachedEvent ::
    ByteString ->
    ByteString ->
    ReplyEvent ->
    Either String EndpointRecord
recordFromAttachedEvent raw attachments _event = do
    unless (BS.length attachments == 136) $
        Left "endpoint attachment is not one signer and signature"
    unless ("-CAB" `BS.isPrefixOf` attachments) $
        Left "endpoint attachment signer counter is malformed"
    let signerToken = BS.take 44 (BS.drop 4 attachments)
        signatureToken = BS.drop 48 attachments
    signerKey <- decodeWitnessKey "endpoint attachment signer" signerToken
    signature <-
        case parsePrimitive signatureToken of
            Right (Ed25519Signature rawSignature, trailing)
                | BS.null trailing -> pure rawSignature
            _ -> Left "endpoint attachment signature is malformed"
    record <- validateEndpointEvent signerKey raw signature
    unless (TE.encodeUtf8 (endpointAid record) == signerToken) $
        Left "endpoint attachment signer does not match event eid"
    pure record

validateEndpointEvent ::
    ByteString ->
    ByteString ->
    ByteString ->
    Either String EndpointRecord
validateEndpointEvent expectedKey raw signature = do
    event <- decodeReply raw
    validateEventVersion raw (replyVersion event)
    unless (replyType event == "rpy") $
        Left "endpoint event type is not rpy"
    unless
        ( not (T.null $ replyDate event)
            && T.all (not . isUrlWhitespace) (replyDate event)
        )
        $ Left "endpoint event datetime is empty or contains whitespace"
    unless (replyRoute event == "/loc/scheme") $
        Left "endpoint event route is not /loc/scheme"
    let attributes = replyAttributes event
        aid = replyEndpointAid attributes
        scheme = replyScheme attributes
        url = replyUrl attributes
    witnessKey <-
        decodeWitnessKey "endpoint eid" (TE.encodeUtf8 aid)
    unless (witnessKey == expectedKey) $
        Left "endpoint eid does not match the marker witness key"
    digest <-
        decodeDigest (TE.encodeUtf8 $ replyDigest event)
    digestOffset <- scalarOffset raw "d" (replyDigest event)
    unless (blake3Hash (blankDigest raw digestOffset) == digest) $
        Left "endpoint SAID does not bind the exact event bytes"
    unless (scheme == "http" || scheme == "https") $
        Left "endpoint scheme is not http or https"
    unless
        ( (scheme <> "://") `T.isPrefixOf` url
            && T.length url > T.length scheme + 3
            && T.all (not . isUrlWhitespace) url
        )
        $ Left "endpoint URL does not match its scheme"
    unless (BS.length signature == 64) $
        Left "endpoint signature is not 64 bytes"
    unless (verifyEd25519 witnessKey raw signature) $
        Left "endpoint signature does not verify"
    pure
        EndpointRecord
            { endpointEventBytes = raw
            , endpointSignature = signature
            , endpointWitnessKey = witnessKey
            , endpointAid = aid
            , endpointScheme = scheme
            , endpointUrl = url
            }

decodeReply :: ByteString -> Either String ReplyEvent
decodeReply raw =
    either
        (Left . ("invalid KERI reply JSON: " <>))
        pure
        (eitherDecodeStrict' raw)

validateEventVersion :: ByteString -> Text -> Either String ()
validateEventVersion raw version = do
    let encoded = TE.encodeUtf8 version
        prefix = "{\"v\":\"" <> encoded <> "\","
    unless
        ( BS.length encoded == 17
            && BS.take 10 encoded == "KERI10JSON"
            && BS.drop 16 encoded == "_"
            && prefix `BS.isPrefixOf` raw
        )
        $ Left "endpoint version is not canonical KERI 1.0 JSON"
    embeddedSize <-
        parseHexBytes
            "endpoint version size"
            (BS.take 6 $ BS.drop 10 encoded)
    unless (embeddedSize == BS.length raw) $
        Left "endpoint version size does not match event bytes"

splitMessages ::
    ByteString ->
    Either String [(ByteString, ByteString)]
splitMessages bytes
    | BS.null (BS.dropWhile isAsciiWhitespace bytes) = pure []
    | otherwise = do
        (raw, attachments, trailing) <-
            splitMessage (BS.dropWhile isAsciiWhitespace bytes)
        ((raw, attachments) :) <$> splitMessages trailing

splitMessage ::
    ByteString ->
    Either String (ByteString, ByteString, ByteString)
splitMessage stream = do
    let prefix = "{\"v\":\"KERI10JSON"
    unless (prefix `BS.isPrefixOf` stream) $
        Left "OOBI does not contain a KERI 1.0 JSON message"
    eventSize <-
        parseHexBytes
            "KERI message size"
            (BS.take 6 $ BS.drop (BS.length prefix) stream)
    when (eventSize <= 0 || eventSize > BS.length stream) $
        Left "OOBI embedded event size is out of bounds"
    let (raw, afterEvent) = BS.splitAt eventSize stream
    (attachmentQuadlets, afterCounter) <-
        parseCounter "-V" afterEvent
    let attachmentBytes = attachmentQuadlets * 4
    when (BS.length afterCounter < attachmentBytes) $
        Left "OOBI attachment group is truncated"
    let (attachments, trailing) =
            BS.splitAt attachmentBytes afterCounter
    pure (raw, attachments, trailing)

parseCounter ::
    ByteString ->
    ByteString ->
    Either String (Int, ByteString)
parseCounter code bytes = do
    when (BS.length bytes < 4) $
        Left ("truncated CESR counter " <> B8.unpack code)
    unless (BS.take 2 bytes == code) $
        Left ("expected CESR counter " <> B8.unpack code)
    high <- decodeBase64Digit (BS.index bytes 2)
    low <- decodeBase64Digit (BS.index bytes 3)
    pure (high * 64 + low, BS.drop 4 bytes)

decodeBase64Digit :: Word8 -> Either String Int
decodeBase64Digit byte
    | byte >= 0x41 && byte <= 0x5a =
        pure (fromIntegral byte - 0x41)
    | byte >= 0x61 && byte <= 0x7a =
        pure (fromIntegral byte - 0x61 + 26)
    | byte >= 0x30 && byte <= 0x39 =
        pure (fromIntegral byte - 0x30 + 52)
    | byte == 0x2d = pure 62
    | byte == 0x5f = pure 63
    | otherwise = Left "invalid CESR base64 counter digit"

decodeWitnessKey :: String -> ByteString -> Either String ByteString
decodeWitnessKey label token = do
    unless (BS.take 1 token == "B") $
        Left (label <> " is not a non-transferable B-code witness key")
    case parsePrimitive token of
        Right (Ed25519PublicKey key, trailing)
            | BS.null trailing -> pure key
        _ -> Left (label <> " is not one complete Ed25519 key")

decodeDigest :: ByteString -> Either String ByteString
decodeDigest token =
    case parsePrimitive token of
        Right (SelfAddressing digest, trailing)
            | BS.null trailing -> pure digest
        _ -> Left "endpoint d is not one complete E-code digest"

-- | The board policy id a locator names, as raw ledger hash bytes.
decodeBoardPolicyId :: Text -> Either String ByteString
decodeBoardPolicyId encoded = do
    bytes <-
        either
            (const $ Left "board policy id is not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == ownerKeyHashWidth) $
        Left "board policy id is not a 28-byte script hash"
    pure bytes

decodeMarkerName :: Text -> Either String ByteString
decodeMarkerName assetName = do
    bytes <-
        either
            (const $ Left "marker asset name is not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 assetName)
    unless
        ( BS.length bytes == 32
            && TE.decodeUtf8 (convertToBase Base16 bytes) == assetName
        )
        $ Left "marker asset name is not canonical raw 32-byte key hex"
    pure bytes

scalarOffset ::
    ByteString ->
    Text ->
    Text ->
    Either String Int
scalarOffset raw field value = do
    let prefix = TE.encodeUtf8 ("\"" <> field <> "\":\"")
        needle = TE.encodeUtf8 value
        (before, match) = BS.breakSubstring prefix raw
    when (BS.null match) $
        Left (T.unpack field <> " field not found")
    let offset = BS.length before + BS.length prefix
    unless (needle `BS.isPrefixOf` BS.drop offset raw) $
        Left (T.unpack field <> " value does not match event bytes")
    pure offset

blankDigest :: ByteString -> Int -> ByteString
blankDigest raw digestOffset =
    BS.take digestOffset raw
        <> B8.replicate 44 '#'
        <> BS.drop (digestOffset + 44) raw

prefixOutput ::
    ChainAssetUtxo ->
    Either String a ->
    Either String a
prefixOutput output = \case
    Left err ->
        Left $
            T.unpack (chainAssetTxId output)
                <> "#"
                <> show (chainAssetIndex output)
                <> ": "
                <> err
    Right value -> Right value

parseHexBytes :: String -> ByteString -> Either String Int
parseHexBytes label bytes
    | BS.null bytes || not (all isHexDigit $ B8.unpack bytes) =
        Left (label <> " is not hexadecimal")
    | otherwise =
        pure $
            foldl
                (\acc digit -> acc * 16 + digitToInt digit)
                0
                (B8.unpack bytes)

isAsciiWhitespace :: Word8 -> Bool
isAsciiWhitespace byte =
    byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20

isUrlWhitespace :: Char -> Bool
isUrlWhitespace char =
    char == ' ' || char == '\t' || char == '\r' || char == '\n'
