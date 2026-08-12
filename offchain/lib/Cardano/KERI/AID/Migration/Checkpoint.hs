{- |
Module      : Cardano.KERI.AID.Migration.Checkpoint
Description : Checkpoint-family migration parity oracle, #254 (MOD-254-PARITY)

The offchain mirror of @onchain\/lib\/cardano_keri\/migration\/checkpoint.ak@.
It owns two things and deliberately not a third:

* the canonical migration message bytes controllers actually sign, which must
  be byte-identical to what the Aiken encoder reconstructs; and
* the structured verdict every migration rule returns, whose error classes map
  one-for-one onto the generated Aiken vectors.

It does __not__ own a second copy of the business rules for their own sake.
The transaction-shaped arms below observe exactly the facts the Aiken arms
observe — consumed source, mint map, outputs, network — through a small
'MigrationTx' mirror rather than a full ledger transaction, because a parity
oracle must be able to state a verdict about a transition without linking a
ledger.

Authorization is data, never caller identity: the sole thing that can move a
checkpoint is a quorum of its own current controller keys over
'migrationMessage'. There is no governance key, payment credential,
transaction-signatory or relayer fallback anywhere in this module, which is
what makes a valid package permissionlessly relayable.
-}
module Cardano.KERI.AID.Migration.Checkpoint (
    -- * Message inputs
    MigrationSource (..),
    MigrationMessage (..),

    -- * Edge and continuity inputs
    Predecessor (..),
    MigrationSuccessor (..),
    CheckpointRoleState (..),
    PolicyReplacement (..),
    VersionedCheckpoint (..),

    -- * Legacy bridge inputs
    LegacyCheckpointIdentity (..),
    LegacyCloseEvidence (..),
    preprodV0,

    -- * Transaction mirror
    MigrationValue,
    MigrationInput (..),
    MigrationOutput (..),
    MigrationTx (..),
    lovelaceKey,
    lovelaceOf,
    tokenOf,

    -- * Verdicts
    MigrationError (..),
    MigrationVerdict,

    -- * The modelled behaviour
    migrationMessage,
    encodeMigrationMessage,
    checkpointMigrationAuthorized,
    validMigrationEdge,
    checkpointTransitionContinuous,
    validateCheckpointMigrateOut,
    validateCheckpointMigrateIn,
    validateLegacyCheckpointMigrateIn,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    DatumError,
    checkpointDatumFromData,
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    evaluate,
 )
import Cardano.KERI.AID.Ed25519 (
    verifyEd25519,
 )
import Cardano.KERI.AID.Migration.Types (
    FullAddress (..),
    MigrationAuthorization (..),
    MigrationOrigin (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    ValidatorVersion (..),
    canonicalCbor,
    migrationDomain,
    optionData,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet
import Data.Map.Strict (
    Map,
 )
import Data.Map.Strict qualified as Map
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- ---------------------------------------------------------
-- Message inputs
-- ---------------------------------------------------------

{- | Everything about the generation being left, as the transaction observes
it — never as the caller asserts it.  @msSourceState@ is the source's own
projected state carried verbatim.
-}
data MigrationSource = MigrationSource
    { msNetworkId :: !Integer
    -- ^ the chain this move is valid on
    , msSourceVersion :: !ValidatorVersion
    -- ^ the generation being left
    , msSourcePolicy :: !ByteString
    -- ^ the source minting policy
    , msSourceRef :: !OutputRef
    -- ^ the exact consumed source output
    , msSourceRole :: !MigrationRole
    -- ^ the source's live lifecycle position
    , msSourceState :: !Data
    -- ^ the source's complete projected state, carried verbatim
    }
    deriving stock (Show, Eq)

{- | The canonical, versioned, domain-separated migration preimage.

Field order is protocol surface.  Every caller-controlled field that could
redirect identity, value or successor selection appears here — that is exactly
what makes a signature over it unreplayable onto a different move, and it is
why the negative vectors mutate one field each.
-}
data MigrationMessage = MigrationMessage
    { mmDomain :: !ByteString
    , mmNetworkId :: !Integer
    , mmSourceVersion :: !ValidatorVersion
    , mmSourcePolicy :: !ByteString
    , mmSourceRef :: !OutputRef
    , mmSourceRole :: !MigrationRole
    , mmSourceState :: !Data
    , mmTargetVersion :: !ValidatorVersion
    , mmTargetPolicy :: !ByteString
    , mmTargetRole :: !MigrationRole
    , mmTargetAddress :: !FullAddress
    , mmLegacyRefundAddress :: !(Maybe FullAddress)
    }
    deriving stock (Show, Eq)

instance ToData MigrationMessage where
    toBuiltinData MigrationMessage{..} =
        BuiltinData $
            Constr
                0
                [ B mmDomain
                , I mmNetworkId
                , dataOf mmSourceVersion
                , B mmSourcePolicy
                , dataOf mmSourceRef
                , dataOf mmSourceRole
                , mmSourceState
                , dataOf mmTargetVersion
                , B mmTargetPolicy
                , dataOf mmTargetRole
                , dataOf mmTargetAddress
                , optionData mmLegacyRefundAddress
                ]

-- | Strip the 'BuiltinData' wrapper of a value's 'Data' tree.
dataOf :: (ToData a) => a -> Data
dataOf x = let BuiltinData d = toBuiltinData x in d

-- ---------------------------------------------------------
-- Edge and continuity inputs
-- ---------------------------------------------------------

{- | The applied predecessor a target program pins.  Both fields are compiled
into the successor program as parameters, so no datum or redeemer value can
substitute either identity.
-}
data Predecessor = Predecessor
    { pdPredecessorVersion :: !ValidatorVersion
    , pdPredecessorPolicy :: !ByteString
    }
    deriving stock (Show, Eq)

-- | The successor a transaction actually proposes, read from its output.
data MigrationSuccessor = MigrationSuccessor
    { suVersion :: !ValidatorVersion
    , suPolicy :: !ByteString
    , suOrigin :: !(Maybe MigrationOrigin)
    , suRole :: !MigrationRole
    }
    deriving stock (Show, Eq)

{- | The frozen KEL projection wrapped with deployment metadata
(DAT-254-CHECKPOINT).  @vcState@ is referenced, never restated field by field.
-}
data VersionedCheckpoint = VersionedCheckpoint
    { vcValidatorVersion :: !ValidatorVersion
    , vcMigrationOrigin :: !(Maybe MigrationOrigin)
    , vcState :: !CheckpointDatumV1
    }
    deriving stock (Show, Eq)

instance ToData VersionedCheckpoint where
    toBuiltinData VersionedCheckpoint{..} =
        BuiltinData $
            Constr
                0
                [ dataOf vcValidatorVersion
                , optionData vcMigrationOrigin
                , dataOf vcState
                ]

{- | A decoded lifecycle position plus its complete role payload.  ARMED
carries its hunter and deadline; ACTIVE and FROZEN carry neither, and a role
that invents either is not the role it claims to be.
-}
data CheckpointRoleState = CheckpointRoleState
    { crRole :: !MigrationRole
    , crCheckpoint :: !CheckpointDatumV1
    , crHunterPkh :: !(Maybe ByteString)
    , crDeadline :: !(Maybe Integer)
    }
    deriving stock (Show, Eq)

{- | The single admitted value difference across a migration: one named token
moves from the source policy to the target policy and nothing else changes.
-}
data PolicyReplacement = PolicyReplacement
    { prSourcePolicy :: !ByteString
    , prTargetPolicy :: !ByteString
    , prAssetName :: !ByteString
    , prSourceValue :: !MigrationValue
    , prSuccessorValue :: !MigrationValue
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Legacy bridge inputs
-- ---------------------------------------------------------

{- | The immutable identity of the deployed preprod v0 checkpoint program.  It
is data, pinned by the target program — never derived by recompiling current
source, which would produce different bytes and prove nothing about what is
actually on preprod.
-}
data LegacyCheckpointIdentity = LegacyCheckpointIdentity
    { lcNetworkName :: !ByteString
    , lcNetworkMagic :: !Integer
    , lcNetworkId :: !Integer
    , lcVersion :: !ValidatorVersion
    , lcPolicy :: !ByteString
    , lcSourceCommit :: !ByteString
    }
    deriving stock (Show, Eq)

{- | The exact committed preprod v0 checkpoint family (T254-004).  These are
release facts recorded in @deploy\/preprod\/m1-manifest.json@, restated here as
the only legacy source the bridge admits.
-}
preprodV0 :: LegacyCheckpointIdentity
preprodV0 =
    LegacyCheckpointIdentity
        { lcNetworkName = "preprod"
        , lcNetworkMagic = 1
        , lcNetworkId = 0
        , lcVersion = ValidatorVersion 0
        , lcPolicy = policy
        , lcSourceCommit = "50a582064ddfde15ebfa3649c6b6fea8d39fc697"
        }
  where
    -- Raw 28 bytes, never the 56-character hex text: a policy id compared
    -- against its own ASCII spelling can never match anything on chain.
    policy = case convertFromBase Base16 hex of
        Right bytes | BS.length bytes == 28 -> bytes
        _ -> error "preprod v0 policy is not 28 bytes of hex"
    hex :: ByteString
    hex = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"

{- | The v0 exit the same transaction must have performed: the immutable v0
program's own controller-authorized @Close@ refund plus its exact @CloseBurn@.
-}
data LegacyCloseEvidence = LegacyCloseEvidence
    { lceRefundAddress :: !FullAddress
    , lceRefundLovelace :: !Integer
    , lceBurnedAssetName :: !ByteString
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Transaction mirror
-- ---------------------------------------------------------

{- | A multi-asset value: @(policy, asset name) -> quantity@.  Lovelace is the
empty-policy, empty-name entry, exactly as the ledger represents ada.
-}
type MigrationValue = Map (ByteString, ByteString) Integer

-- | The ada key of a 'MigrationValue'.
lovelaceKey :: (ByteString, ByteString)
lovelaceKey = ("", "")

-- | The ada quantity of a value.
lovelaceOf :: MigrationValue -> Integer
lovelaceOf = Map.findWithDefault 0 lovelaceKey

-- | The quantity of one named token.
tokenOf :: ByteString -> ByteString -> MigrationValue -> Integer
tokenOf policy name = Map.findWithDefault 0 (policy, name)

-- | One consumed output, as the migration arms observe it.
data MigrationInput = MigrationInput
    { miRef :: !OutputRef
    , miAddress :: !FullAddress
    , miValue :: !MigrationValue
    , miDatum :: !(Maybe Data)
    }
    deriving stock (Show, Eq)

-- | One created output, as the migration arms observe it.
data MigrationOutput = MigrationOutput
    { moAddress :: !FullAddress
    , moValue :: !MigrationValue
    , moDatum :: !(Maybe Data)
    }
    deriving stock (Show, Eq)

{- | The transaction facts a migration arm reads.  Deliberately the smallest
mirror that can express every rule: anything absent here is a fact no rule in
this family is allowed to depend on — notably there is no signatory list, so
no rule can accidentally acquire a transaction-signer fallback.
-}
data MigrationTx = MigrationTx
    { mtxNetworkId :: !Integer
    , mtxInputs :: ![MigrationInput]
    , mtxOutputs :: ![MigrationOutput]
    , mtxMint :: !MigrationValue
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Verdicts
-- ---------------------------------------------------------

{- | Why a migration was refused.  Each class maps one-for-one onto a generated
Aiken vector and onto an Aiken @MigrationError@ constructor, so a parity
disagreement is observable as a class change and not only as a byte change.
-}
data MigrationError
    = -- | the carried source projection is not a well-formed checkpoint datum
      MigrationDatumIllFormed !DatumError
    | -- | the current controller threshold is not met by valid distinct indices
      MigrationQuorumUnsatisfied
    | -- | the target is not exactly the source generation plus one
      MigrationVersionNotSuccessor
    | -- | the consumed source is not the successor's pinned predecessor
      MigrationForeignPredecessor
    | -- | the recorded origin is not the actual consumed source output
      MigrationOriginMismatch
    | -- | the successor's applied version marker disagrees with its datum
      MigrationAppliedVersionMismatch
    | -- | a KEL projection field changed across the move
      MigrationIdentityChanged
    | -- | the lifecycle position or its role payload changed across the move
      MigrationRoleChanged
    | -- | value moved by more than the one admitted policy replacement
      MigrationValueChanged
    | -- | the source named by the authorization is not in the transaction
      MigrationSourceMissing
    | -- | more than one candidate successor output was offered
      MigrationAmbiguousSuccessor
    | -- | the burn\/mint pair is not the exact one-for-one replacement
      MigrationTokenTransitionInvalid
    | -- | the legacy source is not the exact committed preprod v0 family
      MigrationLegacyIdentityMismatch
    | -- | the legacy source is not ACTIVE, and has no authorized exit
      MigrationLegacyRoleUnsupported
    | -- | the legacy close refund is not exact
      MigrationLegacyRefundMismatch
    deriving stock (Show, Eq)

-- | @Right ()@ is acceptance; @Left e@ names the class that refused.
type MigrationVerdict = Either MigrationError ()

-- ---------------------------------------------------------
-- The modelled behaviour
-- ---------------------------------------------------------

-- | Build the sole canonical signed migration preimage.
migrationMessage :: MigrationSource -> MigrationTarget -> MigrationMessage
migrationMessage MigrationSource{..} MigrationTarget{..} =
    MigrationMessage
        { mmDomain = migrationDomain
        , mmNetworkId = msNetworkId
        , mmSourceVersion = msSourceVersion
        , mmSourcePolicy = msSourcePolicy
        , mmSourceRef = msSourceRef
        , mmSourceRole = msSourceRole
        , mmSourceState = msSourceState
        , mmTargetVersion = mtTargetVersion
        , mmTargetPolicy = mtTargetPolicy
        , mmTargetRole = mtTargetRole
        , mmTargetAddress = mtTargetAddress
        , mmLegacyRefundAddress = mtLegacyRefundAddress
        }

{- | The canonical bytes checkpoint controllers sign — the same bytes the Aiken
encoder reconstructs from the transaction.
-}
encodeMigrationMessage :: MigrationSource -> MigrationTarget -> ByteString
encodeMigrationMessage source target =
    canonicalCbor (migrationMessage source target)

{- | Evaluate the source checkpoint's __own__ current controller quorum over
the canonical message.

Three properties this must have, each of which has a named control: an index
outside @[0, n)@ never counts, a repeated index never counts twice, and a
signature that does not verify never counts.  The first two are established
here by deduplicating verified positions into an 'IntSet.IntSet' before
'evaluate' sees them, which also filters the range.
-}
checkpointMigrationAuthorized ::
    CheckpointDatumV1 ->
    MigrationMessage ->
    [(Integer, ByteString)] ->
    MigrationVerdict
checkpointMigrationAuthorized sourceState message signatures =
    case datumWellFormed sourceState of
        Left e -> Left (MigrationDatumIllFormed e)
        Right () ->
            let preimage = canonicalCbor message
                keys = cdCurKeys sourceState
                n = length keys
                verified =
                    IntSet.fromList
                        [ fromIntegral index
                        | (index, signature) <- signatures
                        , index >= 0
                        , index < fromIntegral n
                        , verifyEd25519
                            (keys !! fromIntegral index)
                            preimage
                            signature
                        ]
             in if evaluate (cdCurThreshold sourceState) n verified
                    then Right ()
                    else Left MigrationQuorumUnsatisfied

{- | Check the permanent @N -> N+1@ edge, the pinned predecessor identity, and
the successor's recorded origin against the actually consumed source.
-}
validMigrationEdge ::
    MigrationSource ->
    MigrationSuccessor ->
    Predecessor ->
    MigrationVerdict
validMigrationEdge source successor expected
    | msSourceVersion source /= pdPredecessorVersion expected =
        Left MigrationForeignPredecessor
    | msSourcePolicy source /= pdPredecessorPolicy expected =
        Left MigrationForeignPredecessor
    | vvValue (suVersion successor)
        /= vvValue (msSourceVersion source) + 1 =
        Left MigrationVersionNotSuccessor
    | suOrigin successor /= Just actualOrigin =
        Left MigrationOriginMismatch
    | otherwise = Right ()
  where
    actualOrigin =
        MigrationOrigin
            { moSourceVersion = msSourceVersion source
            , moSourcePolicy = msSourcePolicy source
            , moSourceRef = msSourceRef source
            }

{- | Check that identity, lifecycle position, role payload and protected value
all survive the move, admitting only the one policy-token replacement.

The value rule is stated as an equality between the successor value and the
source value with exactly one token swapped, rather than as a list of things
that must not change: an inequality catches every redirection, including ones
nobody enumerated.
-}
checkpointTransitionContinuous ::
    CheckpointRoleState ->
    CheckpointRoleState ->
    PolicyReplacement ->
    MigrationVerdict
checkpointTransitionContinuous source successor replacement
    | crCheckpoint source /= crCheckpoint successor =
        Left MigrationIdentityChanged
    | crRole source /= crRole successor =
        Left MigrationRoleChanged
    | crHunterPkh source /= crHunterPkh successor =
        Left MigrationRoleChanged
    | crDeadline source /= crDeadline successor =
        Left MigrationRoleChanged
    | prSuccessorValue /= expected =
        Left MigrationValueChanged
    | otherwise = Right ()
  where
    PolicyReplacement{..} = replacement
    expected =
        Map.filter (/= 0) $
            Map.insertWith
                (+)
                (prTargetPolicy, prAssetName)
                1
                (Map.insertWith (+) (prSourcePolicy, prAssetName) (-1) prSourceValue)

{- | The source generation's exit arm.

It proves the named source is genuinely consumed, that the source's own
controllers authorized this exact move, and that the transaction burns exactly
the source token — leaving where the successor lands to the entry arm, which
is the program that owns the target address.
-}
validateCheckpointMigrateOut ::
    Integer ->
    MigrationAuthorization ->
    OutputRef ->
    MigrationTx ->
    MigrationVerdict
validateCheckpointMigrateOut version authorization ownRef tx = do
    input <- maybe (Left MigrationSourceMissing) Right (findInput ownRef tx)
    -- A permanent-family source is itself a versioned row, so its own applied
    -- marker is available and must agree with the program's generation.
    sourceVersioned <- decodeVersioned (miDatum input)
    let sourceState = vcState sourceVersioned
        origin = maSourceOrigin authorization
    if vvValue (vcValidatorVersion sourceVersioned) /= version
        || vvValue (moSourceVersion origin) /= version
        then Left MigrationAppliedVersionMismatch
        else do
            let source = sourceOf authorization (mtxNetworkId tx)
                message = migrationMessage source (maTarget authorization)
                assetName = assetNameOf sourceState
                sourcePolicy = moSourcePolicy origin
            if miRef input /= moSourceRef origin
                then Left MigrationOriginMismatch
                else do
                    checkpointMigrationAuthorized
                        sourceState
                        message
                        (maControllerSignatures authorization)
                    if tokenOf sourcePolicy assetName (mtxMint tx) /= -1
                        then Left MigrationTokenTransitionInvalid
                        else Right ()

{- | The successor generation's entry arm, pinned to its exact predecessor.

The pinned 'Predecessor' arrives as a program parameter, never from the datum
or redeemer, which is what makes "unknown version", "skipped version" and
"foreign family" all unrepresentable rather than merely rejected.
-}
validateCheckpointMigrateIn ::
    Integer ->
    Predecessor ->
    OutputRef ->
    MigrationAuthorization ->
    ByteString ->
    MigrationTx ->
    MigrationVerdict
validateCheckpointMigrateIn version predecessor sourceRef authorization policy tx = do
    input <- maybe (Left MigrationSourceMissing) Right (findInput sourceRef tx)
    sourceVersioned <- decodeVersioned (miDatum input)
    let sourceState = vcState sourceVersioned
        source = sourceOf authorization (mtxNetworkId tx)
        target = maTarget authorization
        message = migrationMessage source target
        assetName = assetNameOf sourceState
        sourcePolicy = msSourcePolicy source
    successorOutput <- soleSuccessor policy assetName tx
    successorState <- decodeVersioned (moDatum successorOutput)
    if vvValue (vcValidatorVersion successorState) /= version
        then Left MigrationAppliedVersionMismatch
        else do
            checkpointMigrationAuthorized
                sourceState
                message
                (maControllerSignatures authorization)
            validMigrationEdge
                source
                MigrationSuccessor
                    { suVersion = vcValidatorVersion successorState
                    , suPolicy = policy
                    , suOrigin = vcMigrationOrigin successorState
                    , suRole = mtTargetRole target
                    }
                predecessor
            if tokenOf sourcePolicy assetName (mtxMint tx) /= -1
                || tokenOf policy assetName (mtxMint tx) /= 1
                then Left MigrationTokenTransitionInvalid
                else
                    checkpointTransitionContinuous
                        CheckpointRoleState
                            { crRole = msSourceRole source
                            , crCheckpoint = sourceState
                            , crHunterPkh = Nothing
                            , crDeadline = Nothing
                            }
                        CheckpointRoleState
                            { crRole = mtTargetRole target
                            , crCheckpoint = vcState successorState
                            , crHunterPkh = Nothing
                            , crDeadline = Nothing
                            }
                        PolicyReplacement
                            { prSourcePolicy = sourcePolicy
                            , prTargetPolicy = policy
                            , prAssetName = assetName
                            , prSourceValue = miValue input
                            , prSuccessorValue = moValue successorOutput
                            }

{- | The one-off bridge out of the immutable deployed preprod v0 program.

Two things make this different from an ordinary migrate-in and both are
load-bearing.  First, v0 has no migrate-out arm, so the transaction must show
the v0 program's own authorized @Close@ and exact @CloseBurn@ instead — and
because @Close@ is the only authorized v0 exit, ARMED and FROZEN v0 rows have
none and are refused here rather than rewritten.  Second, the refunded value
leaves to the refund address, so the successor is capitalized independently
with __equal__ protected lovelace.  That is a recapitalization, not a transfer
of the refunded ada, and the verdict must not pretend otherwise.
-}
validateLegacyCheckpointMigrateIn ::
    LegacyCheckpointIdentity ->
    OutputRef ->
    LegacyCloseEvidence ->
    MigrationAuthorization ->
    ByteString ->
    MigrationTx ->
    MigrationVerdict
validateLegacyCheckpointMigrateIn v0 sourceRef close authorization policy tx = do
    input <- maybe (Left MigrationSourceMissing) Right (findInput sourceRef tx)
    sourceState <- decodeCheckpoint (miDatum input)
    let source = sourceOf authorization (mtxNetworkId tx)
        target = maTarget authorization
        message = migrationMessage source target
        assetName = assetNameOf sourceState
    if msSourcePolicy source /= lcPolicy v0
        || msSourceVersion source /= lcVersion v0
        || mtxNetworkId tx /= lcNetworkId v0
        then Left MigrationLegacyIdentityMismatch
        else
            if msSourceRole source /= CheckpointActive
                then Left MigrationLegacyRoleUnsupported
                else do
                    successorOutput <- soleSuccessor policy assetName tx
                    successorState <- decodeVersioned (moDatum successorOutput)
                    checkpointMigrationAuthorized
                        sourceState
                        message
                        (maControllerSignatures authorization)
                    if lceBurnedAssetName close /= assetName
                        || tokenOf (lcPolicy v0) assetName (mtxMint tx) /= -1
                        || tokenOf policy assetName (mtxMint tx) /= 1
                        then Left MigrationTokenTransitionInvalid
                        else
                            if not (exactRefund close tx)
                                then Left MigrationLegacyRefundMismatch
                                else
                                    if vcMigrationOrigin successorState
                                        /= Just (maSourceOrigin authorization)
                                        then Left MigrationOriginMismatch
                                        else
                                            if lovelaceOf (moValue successorOutput)
                                                /= lovelaceOf (miValue input)
                                                then Left MigrationValueChanged
                                                else
                                                    if vcState successorState /= sourceState
                                                        then Left MigrationIdentityChanged
                                                        else Right ()

-- ---------------------------------------------------------
-- Shared observation helpers
-- ---------------------------------------------------------

-- | The source view an authorization proposes, bound to the observed network.
sourceOf :: MigrationAuthorization -> Integer -> MigrationSource
sourceOf MigrationAuthorization{..} networkId =
    MigrationSource
        { msNetworkId = networkId
        , msSourceVersion = moSourceVersion maSourceOrigin
        , msSourcePolicy = moSourcePolicy maSourceOrigin
        , msSourceRef = moSourceRef maSourceOrigin
        , msSourceRole = maSourceRole
        , msSourceState = maSourceState
        }

-- | The consumed output a reference names, if the transaction has it.
findInput :: OutputRef -> MigrationTx -> Maybe MigrationInput
findInput ref tx =
    case filter ((== ref) . miRef) (mtxInputs tx) of
        [input] -> Just input
        _ -> Nothing

{- | The single output holding the target token.  Ambiguity is its own error
class: two candidate successors is a different defect from none, and collapsing
them would let a duplicated successor read as a missing one.
-}
soleSuccessor ::
    ByteString ->
    ByteString ->
    MigrationTx ->
    Either MigrationError MigrationOutput
soleSuccessor policy assetName tx =
    case filter holdsTarget (mtxOutputs tx) of
        [output] -> Right output
        [] -> Left MigrationSourceMissing
        _ -> Left MigrationAmbiguousSuccessor
  where
    holdsTarget output = tokenOf policy assetName (moValue output) > 0

-- | Decode a carried v0-shaped checkpoint projection.
decodeCheckpoint :: Maybe Data -> Either MigrationError CheckpointDatumV1
decodeCheckpoint = \case
    Just d
        | Just state <- checkpointFrom d -> Right state
    _ -> Left MigrationIdentityChanged

-- | Decode a versioned successor record.
decodeVersioned :: Maybe Data -> Either MigrationError VersionedCheckpoint
decodeVersioned = \case
    Just d
        | Just state <- versionedFrom d -> Right state
    _ -> Left MigrationIdentityChanged

-- | Read a v0-shaped @CheckpointDatum@ tree, unwrapping its version sum.
checkpointFrom :: Data -> Maybe CheckpointDatumV1
checkpointFrom d = (\(V1 inner) -> inner) <$> checkpointDatumFromData d

-- | Read a versioned successor record.
versionedFrom :: Data -> Maybe VersionedCheckpoint
versionedFrom = \case
    Constr 0 [version, origin, state] ->
        VersionedCheckpoint
            <$> fromData version
            <*> optionFrom origin
            <*> fromData state
    _ -> Nothing

-- | Decode a public 'Data' tree through a frozen wire codec.
fromData :: (FromData a) => Data -> Maybe a
fromData = fromBuiltinData . BuiltinData

-- | Inverse of 'optionData', spelled out so the wire shape stays visible.
optionFrom :: (FromData a) => Data -> Maybe (Maybe a)
optionFrom = \case
    Constr 0 [d] -> Just <$> fromData d
    Constr 1 [] -> Just Nothing
    _ -> Nothing

{- | The asset name of a checkpoint, mirroring the Aiken @deriveAidAssetName@
label of the AID.
-}
assetNameOf :: CheckpointDatumV1 -> ByteString
assetNameOf = deriveAidAssetName . cdCesrAid

-- | Whether the legacy close refund is exactly what the evidence claims.
exactRefund :: LegacyCloseEvidence -> MigrationTx -> Bool
exactRefund LegacyCloseEvidence{..} tx =
    case filter ((== lceRefundAddress) . moAddress) (mtxOutputs tx) of
        [refund] -> lovelaceOf (moValue refund) == lceRefundLovelace
        _ -> False
