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

    -- * Continuity inputs
    CheckpointRoleState (..),
    PolicyReplacement (..),

    -- * Transaction mirror
    MigrationValue,
    MigrationInput (..),
    MigrationOutput (..),
    MigrationTx (..),
    lovelaceKey,
    lovelaceOf,
    tokenOf,
    sourceAddressIsRole,
    roleAddress,

    -- * Verdicts
    MigrationError (..),
    MigrationVerdict,

    -- * The modelled behaviour
    migrationMessage,
    encodeMigrationMessage,
    checkpointMigrationAuthorized,
    checkpointTransitionContinuous,
    validateCheckpointMigrateOut,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    DatumError,
    checkpointDatumFromData,
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Role (..),
    roleHash,
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
    AddressCredential (..),
    FullAddress (..),
    MigrationAuthorization (..),
    MigrationPredecessor (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
    canonicalCbor,
    migrationDomain,
    optionData,
 )
import Data.ByteString (
    ByteString,
 )
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
    , mmSourcePolicy :: !ByteString
    , mmSourceRef :: !OutputRef
    , mmSourceRole :: !MigrationRole
    , mmSourceState :: !Data
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
                , B mmSourcePolicy
                , dataOf mmSourceRef
                , dataOf mmSourceRole
                , mmSourceState
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

-- | A decoded lifecycle position with its checkpoint state.
data CheckpointRoleState = CheckpointRoleState
    { crRole :: !MigrationRole
    , crCheckpoint :: !CheckpointDatumV1
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
    | -- | the consumed source is not at the canonical role address of its policy
      MigrationForeignPredecessor
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
        , mmSourcePolicy = msSourcePolicy
        , mmSourceRef = msSourceRef
        , mmSourceRole = msSourceRole
        , mmSourceState = msSourceState
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

Inseparably composed with its successor: an authorized exit that burns the
source token and creates nothing destroys the identity under a package the
controllers genuinely signed, so the signed target must actually be built
here.
-}
validateCheckpointMigrateOut ::
    MigrationAuthorization ->
    OutputRef ->
    MigrationTx ->
    MigrationVerdict
validateCheckpointMigrateOut authorization ownRef tx = do
    input <- maybe (Left MigrationSourceMissing) Right (findInput ownRef tx)
    sourceState <- decodeCheckpoint (miDatum input)
    let source = sourceOf authorization (mtxNetworkId tx)
        target = maTarget authorization
        assetName = assetNameOf sourceState
        sourcePolicy = msSourcePolicy source
    -- The signed projection must be the consumed projection: the quorum signs
    -- `source_state`, while every continuity check reads the observed state.
    carried <-
        maybe
            (Left MigrationIdentityChanged)
            Right
            (checkpointFrom (msSourceState source))
    sourceAddressIsRole (msSourceRole source) sourcePolicy input
    if carried /= sourceState
        then Left MigrationIdentityChanged
        else
            if msSourceRef source /= ownRef
                then Left MigrationForeignPredecessor
                else do
                    checkpointMigrationAuthorized
                        sourceState
                        (migrationMessage source target)
                        (maControllerSignatures authorization)
                    successorOutput <-
                        soleSuccessor (mtTargetPolicy target) assetName tx
                    if moAddress successorOutput /= mtTargetAddress target
                        then Left MigrationValueChanged
                        else
                            if tokenOf sourcePolicy assetName (mtxMint tx) /= -1
                                || tokenOf (mtTargetPolicy target) assetName (mtxMint tx) /= 1
                                then Left MigrationTokenTransitionInvalid
                                else do
                                    successorState <-
                                        decodeCheckpoint (moDatum successorOutput)
                                    checkpointTransitionContinuous
                                        (roleStateOf (msSourceRole source) sourceState)
                                        (roleStateOf (mtTargetRole target) successorState)
                                        PolicyReplacement
                                            { prSourcePolicy = sourcePolicy
                                            , prTargetPolicy = mtTargetPolicy target
                                            , prAssetName = assetName
                                            , prSourceValue = miValue input
                                            , prSuccessorValue = moValue successorOutput
                                            }

-- | The source view an authorization proposes, bound to the observed network.
sourceOf :: MigrationAuthorization -> Integer -> MigrationSource
sourceOf MigrationAuthorization{..} networkId =
    MigrationSource
        { msNetworkId = networkId
        , msSourcePolicy = mpPredecessorPolicy maSource
        , msSourceRef = mpPredecessorRef maSource
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

-- | Read a v0-shaped @CheckpointDatum@ tree, unwrapping its version sum.
checkpointFrom :: Data -> Maybe CheckpointDatumV1
checkpointFrom d = (\(V1 inner) -> inner) <$> checkpointDatumFromData d

{- | The asset name of a checkpoint, mirroring the Aiken @deriveAidAssetName@
label of the AID.
-}
assetNameOf :: CheckpointDatumV1 -> ByteString
assetNameOf = deriveAidAssetName . cdCesrAid

-- | The lifecycle position a decoded row occupies, with its checkpoint state.
roleStateOf :: MigrationRole -> CheckpointDatumV1 -> CheckpointRoleState
roleStateOf role state =
    CheckpointRoleState
        { crRole = role
        , crCheckpoint = state
        }

{- | The canonical role address a policy's lifecycle position occupies, built
the way the on-chain path builds it rather than described field by field:
ACTIVE is the bare script address, and every tagged role delegates to its
deterministic role script.  The role derivation is reused from
"Cardano.KERI.AID.Checkpoint.FreezeBond" so there is exactly one mirror of it.
-}
roleAddress :: ByteString -> Role -> FullAddress
roleAddress policy role =
    FullAddress
        (ScriptCredential policy)
        (fmap (InlineStakeCredential . ScriptCredential) (roleHash policy role))

-- | The checkpoint lifecycle position a migration role names, if it names one.
lifecycleRole :: MigrationRole -> Maybe Role
lifecycleRole = \case
    CheckpointActive -> Just Active
    CheckpointFrozen -> Nothing
    CheckpointArmed -> Nothing
    Board -> Nothing

{- | The predecessor must be sitting at the canonical role address of the
policy it claims — compared as one whole value.

This is deliberately a __total structural equality__, not a projection.  The
previous method projected the address down to its payment script hash and
checked that, which silently ignored every other part of the address: a
correct payment hash carrying a spurious stake credential passed here while
the live Aiken path, which classifies the entire address, refused it.

Comparing the complete decoded value against an address built by construction
cannot have that failure mode.  A field added to 'FullAddress' participates in
'==' automatically, and a new 'StakeCredential' variant is compared by the
same derived equality; neither can be missed by a hand-written list of fields,
because there is no such list.
-}
sourceAddressIsRole ::
    MigrationRole ->
    ByteString ->
    MigrationInput ->
    Either MigrationError ()
sourceAddressIsRole role policy input = do
    lifecycle <-
        maybe (Left MigrationForeignPredecessor) Right (lifecycleRole role)
    if miAddress input == roleAddress policy lifecycle
        then Right ()
        else Left MigrationForeignPredecessor
