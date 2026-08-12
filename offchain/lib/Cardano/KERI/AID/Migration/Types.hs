{- |
Module      : Cardano.KERI.AID.Migration.Types
Description : Shared validator-migration wire contract, #254 (MOD-254-PROTOCOL)

Protocol data only: the program generation, the immediate predecessor origin,
the migration target, the migration role vocabulary, and every input the later
canonical authorization message is built from.  No migrate-in\/out behaviour,
no deployment identity, no registry, and no consumer resolution live here.

Checkpoint, board, deployment, and the #253 endpoints all read these types, so
the module depends on nothing but ledger references, policies, addresses, and
network identity.  Constructor indices and field order are protocol surface;
they change only by a new applied program hash.  The Aiken mirror is
@onchain\/lib\/cardano_keri\/migration\/types.ak@ and
@offchain\/app\/GenMigrationTypesVectors.hs@ is the sole source of the byte
fixtures both suites assert against.

'FullAddress' and friends re-declare the Aiken @cardano\/address.Address@
Plutus-Data mirror rather than importing the identical one from
"Cardano.KERI.AID.Checkpoint.Close": that module carries the Close predicate,
which this landing excludes, and MOD-254-PROTOCOL may not depend on checkpoint
validator behaviour.
-}
module Cardano.KERI.AID.Migration.Types (
    -- * Ledger mirrors
    AddressCredential (..),
    StakeCredential (..),
    FullAddress (..),
    OutputRef (..),

    -- * Shared migration contract
    migrationDomain,
    MigrationRole (..),
    MigrationPredecessor (..),
    MigrationTarget (..),
    MigrationAuthorization (..),

    -- * Canonical serialization
    canonicalCbor,
    canonicalCborData,
    optionData,
) where

import Data.ByteString (
    ByteString,
 )
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins (
    serialiseData,
 )
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- ---------------------------------------------------------
-- Serialization helpers
-- ---------------------------------------------------------

-- | Strip the 'BuiltinData' wrapper of a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- | Decode a public 'Data' tree through a frozen wire codec.
fromData :: (FromData a) => Data -> Maybe a
fromData = fromBuiltinData . BuiltinData

{- | Canonical Plutus 'Data' CBOR bytes of a value — the cross-language,
byte-for-byte contract (the same bytes Aiken @cbor.serialise@ emits).
-}
canonicalCbor :: (ToData a) => a -> ByteString
canonicalCbor = canonicalCborData . asData

-- | Canonical Plutus-Data CBOR bytes of an already-built 'Data' tree.
canonicalCborData :: Data -> ByteString
canonicalCborData d =
    let BuiltinByteString bs = serialiseData (BuiltinData d) in bs

{- | Aiken @Option@: @Some@ is constructor 0, @None@ is constructor 1.  Spelled
out rather than inherited so the optional-field wire shape stays visible.
-}
optionData :: (ToData a) => Maybe a -> Data
optionData = maybe (Constr 1 []) (\x -> Constr 0 [asData x])

-- | Inverse of 'optionData'.
optionFrom :: (FromData a) => Data -> Maybe (Maybe a)
optionFrom = \case
    Constr 0 [d] -> Just <$> fromData d
    Constr 1 [] -> Just Nothing
    _ -> Nothing

-- ---------------------------------------------------------
-- Ledger mirrors
-- ---------------------------------------------------------

-- | Aiken @Credential@: verification key is constructor 0, script is 1.
data AddressCredential
    = VerificationKeyCredential !ByteString
    | ScriptCredential !ByteString
    deriving stock (Show, Eq)

-- | Aiken @Referenced\<Credential\>@: inline is constructor 0, pointer is 1.
data StakeCredential
    = InlineStakeCredential !AddressCredential
    | PointerStakeCredential !Integer !Integer !Integer
    deriving stock (Show, Eq)

-- | Byte-identical Haskell mirror of Aiken @Address@ (constructor 0).
data FullAddress = FullAddress
    { faPaymentCredential :: !AddressCredential
    -- ^ the spending condition
    , faStakeCredential :: !(Maybe StakeCredential)
    -- ^ the delegation part, absent for an undelegated address
    }
    deriving stock (Show, Eq)

-- | Byte-identical Haskell mirror of Aiken @OutputReference@.
data OutputRef = OutputRef
    { orTransactionId :: !ByteString
    -- ^ the 32-byte transaction id
    , orOutputIndex :: !Integer
    -- ^ the output position within that transaction
    }
    deriving stock (Show, Eq)

instance ToData AddressCredential where
    toBuiltinData = \case
        VerificationKeyCredential h -> BuiltinData (Constr 0 [B h])
        ScriptCredential h -> BuiltinData (Constr 1 [B h])

instance FromData AddressCredential where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B h] -> Just (VerificationKeyCredential h)
        Constr 1 [B h] -> Just (ScriptCredential h)
        _ -> Nothing

instance ToData StakeCredential where
    toBuiltinData = \case
        InlineStakeCredential c -> BuiltinData (Constr 0 [asData c])
        PointerStakeCredential slot txIx certIx ->
            BuiltinData (Constr 1 [I slot, I txIx, I certIx])

instance FromData StakeCredential where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [c] -> InlineStakeCredential <$> fromData c
        Constr 1 [I slot, I txIx, I certIx] ->
            Just (PointerStakeCredential slot txIx certIx)
        _ -> Nothing

instance ToData FullAddress where
    toBuiltinData FullAddress{..} =
        BuiltinData $
            Constr 0 [asData faPaymentCredential, optionData faStakeCredential]

instance FromData FullAddress where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [c, stake] ->
            FullAddress <$> fromData c <*> optionFrom stake
        _ -> Nothing

instance ToData OutputRef where
    toBuiltinData OutputRef{..} =
        BuiltinData (Constr 0 [B orTransactionId, I orOutputIndex])

instance FromData OutputRef where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B txid, I index] -> Just (OutputRef txid index)
        _ -> Nothing

-- ---------------------------------------------------------
-- The shared migration contract
-- ---------------------------------------------------------

{- | @MIGRATION_DOMAIN = UTF8("cardano-keri\/migration\/v1")@ — the frozen
25-byte domain separator every authorization carries, so it can never be
replayed as another protocol's message.
-}
migrationDomain :: ByteString
migrationDomain = TE.encodeUtf8 "cardano-keri/migration/v1"

{- | Which live lifecycle position a migration moves.  The terminal burn state
is deliberately absent: it is an end state, not something that can be
migrated, so it is unrepresentable rather than merely unused.  @Board@ is the
board-side position; its state and inventory rules belong to S254-2.
-}
data MigrationRole
    = CheckpointActive
    | CheckpointFrozen
    | CheckpointArmed
    | Board
    deriving stock (Show, Eq)

{- | The exact predecessor a migration consumes (DAT-254-PREDECESSOR): the
minting policy that holds it and the output being spent.

There is no program generation here and no stored back-pointer.  The successor
program is applied with the one predecessor policy it accepts, so its own hash
is its release identity, and the atomic transaction -- spend this output, burn
its token, mint and confine the same-name successor -- is the lineage edge.
-}
data MigrationPredecessor = MigrationPredecessor
    { mpPredecessorPolicy :: !ByteString
    -- ^ the minting policy holding the predecessor
    , mpPredecessorRef :: !OutputRef
    -- ^ the exact output being spent
    }
    deriving stock (Show, Eq)

{- | Where a migration lands (DAT-254-TARGET).  The refund address is optional
and legacy-only: it names where value from a retired generation is returned,
and is absent for every target with no legacy remainder.
-}
data MigrationTarget = MigrationTarget
    { mtTargetPolicy :: !ByteString
    -- ^ the successor minting policy
    , mtTargetRole :: !MigrationRole
    -- ^ the lifecycle position the successor occupies
    , mtTargetAddress :: !FullAddress
    -- ^ the successor's full address, staking part included
    , mtLegacyRefundAddress :: !(Maybe FullAddress)
    -- ^ legacy-only remainder refund destination
    }
    deriving stock (Show, Eq)

{- | Every input the later canonical authorization message is built from
(DAT-254-AUTHORIZATION).  No redirectable caller field is omitted: the domain
and network pin the protocol and chain, the origin pins the exact spent
predecessor, the role and state pin what is being moved, the target pins where
it lands including any refund, and the indexed signatures carry the controller
evidence.

@maSourceState@ is the source generation's own projected state, carried
verbatim as its canonical Plutus-Data serialization.  This layer never
interprets, copies, or summarises it — a field-by-field restatement would be
exactly the lossy alternate representation INV-254-IDENTITY forbids, and would
bind this module to checkpoint or board content.  A later version-specific
validator decodes it with its own frozen codec.

@maControllerSignatures@ are @(index, signature)@ pairs over the current
controller key set.  Representing them is all this landing does: quorum
evaluation and signature verification are later behaviour.

The index is 'Integer' because the Aiken @Int@ it mirrors is unbounded: a machine
word aliases @2^63@ to @-2^63@, losing what the authorization carries.  No wire
integer in this module narrows.
-}
data MigrationAuthorization = MigrationAuthorization
    { maDomain :: !ByteString
    -- ^ the frozen protocol domain separator
    , maNetworkId :: !Integer
    -- ^ the chain this authorization is valid on
    , maSource :: !MigrationPredecessor
    -- ^ the exact predecessor output being spent
    , maSourceRole :: !MigrationRole
    -- ^ the predecessor's live lifecycle position
    , maSourceState :: !Data
    -- ^ the predecessor's complete projected state, carried verbatim
    , maTarget :: !MigrationTarget
    -- ^ the complete migration target
    , maControllerSignatures :: ![(Integer, ByteString)]
    -- ^ indexed current-controller signature evidence, never narrowed
    }
    deriving stock (Show, Eq)

instance ToData MigrationRole where
    toBuiltinData = \case
        CheckpointActive -> BuiltinData (Constr 0 [])
        CheckpointFrozen -> BuiltinData (Constr 1 [])
        CheckpointArmed -> BuiltinData (Constr 2 [])
        Board -> BuiltinData (Constr 3 [])

instance FromData MigrationRole where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [] -> Just CheckpointActive
        Constr 1 [] -> Just CheckpointFrozen
        Constr 2 [] -> Just CheckpointArmed
        Constr 3 [] -> Just Board
        _ -> Nothing

instance ToData MigrationPredecessor where
    toBuiltinData MigrationPredecessor{..} =
        BuiltinData $
            Constr 0 [B mpPredecessorPolicy, asData mpPredecessorRef]

instance FromData MigrationPredecessor where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B policy, ref] ->
            MigrationPredecessor policy <$> fromData ref
        _ -> Nothing

instance ToData MigrationTarget where
    toBuiltinData MigrationTarget{..} =
        BuiltinData $
            Constr
                0
                [ B mtTargetPolicy
                , asData mtTargetRole
                , asData mtTargetAddress
                , optionData mtLegacyRefundAddress
                ]

instance FromData MigrationTarget where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B policy, role, address, refund] ->
            MigrationTarget policy
                <$> fromData role
                <*> fromData address
                <*> optionFrom refund
        _ -> Nothing

instance ToData MigrationAuthorization where
    toBuiltinData MigrationAuthorization{..} =
        BuiltinData $
            Constr
                0
                [ B maDomain
                , I maNetworkId
                , asData maSource
                , asData maSourceRole
                , maSourceState
                , asData maTarget
                , List
                    [ List [I index, B signature]
                    | (index, signature) <- maControllerSignatures
                    ]
                ]

instance FromData MigrationAuthorization where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [B domain, I network, source, role, state, target, List sigs] ->
            MigrationAuthorization domain network
                <$> fromData source
                <*> fromData role
                <*> pure state
                <*> fromData target
                <*> traverse indexedSignature sigs
        _ -> Nothing
      where
        indexedSignature = \case
            List [I index, B signature] -> Just (index, signature)
            _ -> Nothing
