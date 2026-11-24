{- |
Module      : Cardano.KERI.AID.Consumer
Description : The consumer predicate of the Lean model, in the library (#353)

A program that holds an authenticated relying context and an observed output
gets here the verdict of the Lean @CardanoKeri.ConsumerIdentity.consumableHoldingB@
and, when it is refused, which of its clauses failed. The words are the Lean's:

* 'Release' is @PublishedRelease@, 'Context' and 'Environment' are the Lean
  structures of those names;
* 'representativeAsset' is @representativeAsset@: the state policy of the release
  and the active token name of the registry identity and the AID's key;
* 'decodeCheckpoint' is the consumer's decoder
  (@CardanoKeri.CheckpointDatum.decode@): version 2 only, every shape checked,
  the read fields validated, nothing about the key material but its shape;
* 'consumableHolding' lists the failed clauses, in the order of
  @consumableHoldingB@; 'consumableHoldingB' is true exactly when none failed.

The library is pure: the network, the release and the checkpoint credential
are resolved by the caller, who supplies them as the 'Environment'; nothing
here discovers them or talks to a node.
-}
module Cardano.KERI.AID.Consumer (
    -- * The relying contract
    Release (..),
    Context (..),
    Environment (..),

    -- * The observed output
    ObservedOutput (..),
    OutputDatum (..),
    inlineDatumBytes,

    -- * The representative asset
    representativeAsset,
    representativeQuantity,

    -- * The consumer's reading of a checkpoint datum
    DecodedCheckpoint (..),
    decodeCheckpoint,

    -- * The authentication
    authenticated,

    -- * The verdict
    Clause (..),
    consumableHolding,
    consumableHoldingB,
) where

import Cardano.KERI.AID.Application (
    Credential,
    OutputReference,
    RegistryIdentity (..),
    activeTokenName,
    stateTokenName,
 )
import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.Serialise (decode)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import PlutusCore.Data (Data (..))

-- | The published release of the application: the Lean @PublishedRelease@.
data Release = Release
    { rlApplicationPolicy :: !ByteString
    , rlApplicationCredential :: !ByteString
    , rlStateProgram :: !ByteString
    , rlStatePolicy :: !ByteString
    }
    deriving stock (Eq, Show)

{- | What the relying contract establishes, independently of the output: the
network, the release, the seed that created the registry, the AID in question
and the payment credential of the checkpoint validator (not the release's
application credential).
-}
data Context = Context
    { cxNetwork :: !Integer
    , cxRelease :: !Release
    , cxSeed :: !OutputReference
    , cxAid :: !ByteString
    , cxCheckpointCredential :: !Credential
    }
    deriving stock (Eq, Show)

{- | The actual network, release and checkpoint credential, resolved by the
trusted integration; never a field read from a candidate datum. 'Nothing' is
unresolved and fails closed.
-}
data Environment = Environment
    { envNetwork :: !Integer
    , envRelease :: !(Maybe Release)
    , envCheckpointCredential :: !(Maybe Credential)
    }
    deriving stock (Eq, Show)

{- | An observed output: its payment credential, the quantity of every asset
(policy, name, quantity; an asset may be listed more than once) and the form
of its datum.
-}
data ObservedOutput = ObservedOutput
    { ooCredential :: !Credential
    , ooAssets :: ![(ByteString, ByteString, Integer)]
    , ooDatum :: !OutputDatum
    }
    deriving stock (Eq, Show)

{- | The form of the datum of an output as the ledger carries it: none (the
Lean @empty@), the hash of a datum held elsewhere, or inline datum bytes. The
three are different ledger forms and stay different here.
-}
data OutputDatum
    = DatumAbsent
    | DatumByHash !ByteString
    | DatumInline !ByteString
    deriving stock (Eq, Show)

-- | The bytes of an inline datum, the only form a datum is decoded from.
inlineDatumBytes :: OutputDatum -> Maybe ByteString
inlineDatumBytes = \case
    DatumInline bytes -> Just bytes
    _ -> Nothing

{- | The representative asset of an identity: (policy, name). The policy is the
release's state policy; the name is the active token name of the registry
identity (the state policy and the name of the state token the seed names) and
the AID's qualified CESR text.
-}
representativeAsset :: Context -> (ByteString, ByteString)
representativeAsset Context{cxRelease, cxSeed, cxAid} =
    ( policy
    , activeTokenName (RegistryIdentity policy (stateTokenName cxSeed)) cxAid
    )
  where
    policy = rlStatePolicy cxRelease

-- | The facts the consumer reads from a checkpoint datum.
data DecodedCheckpoint
    = DecodedLive
        { dcAid :: !ByteString
        , dcSn :: !Integer
        , dcEpoch :: !Integer
        , dcPoisoned :: !Bool
        , dcFrozen :: !Bool
        , dcBornAt :: !Integer
        }
    | DecodedPending
        { dcAid :: !ByteString
        , dcSn :: !Integer
        , dcEpoch :: !Integer
        }
    deriving stock (Eq, Show)

{- | The consumer's decoder on the bytes of an inline datum: exactly one Plutus
Data item with nothing left over, then version 2 only, the shape of every
field checked, including inside the key material, @sn@, @epoch@ and @born_at@
non-negative. The key material's own validity is not read.
-}
decodeCheckpoint :: ByteString -> Maybe DecodedCheckpoint
decodeCheckpoint bytes =
    case deserialiseFromBytes decode (BL.fromStrict bytes) of
        Right (rest, datum) | BL.null rest -> decodeData datum
        _ -> Nothing

decodeData :: Data -> Maybe DecodedCheckpoint
decodeData = \case
    Constr
        1
        [ Constr
                0
                [aid, sn, epoch, poisoned, frozen, bornAt, refundTo, toppedUp, keys]
            ] -> do
            dcAid <- bytesOf aid
            dcSn <- natOf sn
            dcEpoch <- natOf epoch
            dcPoisoned <- boolOf poisoned
            dcFrozen <- boolOf frozen
            dcBornAt <- natOf bornAt
            _ <- bytesOf refundTo
            _ <- boolOf toppedUp
            keyMaterialShape keys
            pure DecodedLive{..}
    Constr 1 [Constr 1 [aid, sn, epoch]] -> do
        dcAid <- bytesOf aid
        dcSn <- natOf sn
        dcEpoch <- natOf epoch
        pure DecodedPending{..}
    _ -> Nothing

bytesOf :: Data -> Maybe ByteString
bytesOf (B b) = Just b
bytesOf _ = Nothing

natOf :: Data -> Maybe Integer
natOf (I n) | n >= 0 = Just n
natOf _ = Nothing

boolOf :: Data -> Maybe Bool
boolOf (Constr 0 []) = Just False
boolOf (Constr 1 []) = Just True
boolOf _ = Nothing

-- | The six fields of the key material, each of its shape.
keyMaterialShape :: Data -> Maybe ()
keyMaterialShape = \case
    Constr 0 [curKeys, curThreshold, nextKeys, nextThreshold, witnesses, I _] -> do
        bytesList curKeys
        thresholdShape curThreshold
        bytesList nextKeys
        thresholdShape nextThreshold
        bytesList witnesses
    _ -> Nothing
  where
    bytesList (List items) = mapM_ bytesOf items
    bytesList _ = Nothing

thresholdShape :: Data -> Maybe ()
thresholdShape = \case
    Constr 0 [I _] -> Just ()
    Constr 1 [List clauses] -> mapM_ clauseShape clauses
    _ -> Nothing
  where
    clauseShape (List weights) = mapM_ weightShape weights
    clauseShape _ = Nothing
    weightShape (Constr 0 [I _, I _]) = Just ()
    weightShape _ = Nothing

{- | The clauses of the Lean @consumableHoldingB@ an observed output can fail.
A holding fails every clause that does not hold of it.
-}
data Clause
    = {- | The network, the release or the checkpoint credential the environment
      resolved is not the context's, or is unresolved.
      -}
      ContextNotAuthenticated
    | -- | The output is not at the checkpoint credential.
      OutputNotAtCheckpointCredential
    | -- | The quantity of the representative asset is other than one.
      RepresentativeQuantityNotOne
    | {- | The datum is no version 2 checkpoint datum, or is for another AID.
      The state clauses of a datum that decodes for another AID are
      reported as well.
      -}
      DatumNotDecodedForAid
    | CheckpointFrozen
    | CheckpointPoisoned
    | -- | @born_at + W > now@.
      CheckpointJuvenile
    | CheckpointTerminationPending
    deriving stock (Eq, Show, Enum, Bounded)

{- | The quantity of the representative asset an output holds: the sum of
every entry of that asset (Lean @quantity@).
-}
representativeQuantity :: Context -> ObservedOutput -> Integer
representativeQuantity cx out =
    sum [q | (p, n, q) <- ooAssets out, (p, n) == representativeAsset cx]

{- | The failed clauses of a holding, in the order of the Lean
@consumableHoldingB@. The arguments are the maturity window @W@ and the time
@now@, in the unit of the datum's @born_at@.
-}
consumableHolding ::
    Integer -> Integer -> Environment -> Context -> ObservedOutput -> [Clause]
consumableHolding window now env cx out =
    [ContextNotAuthenticated | not (authenticated env cx)]
        <> [ OutputNotAtCheckpointCredential
           | ooCredential out /= cxCheckpointCredential cx
           ]
        <> [RepresentativeQuantityNotOne | representativeQuantity cx out /= 1]
        <> case inlineDatumBytes (ooDatum out) >>= decodeCheckpoint of
            Nothing -> [DatumNotDecodedForAid]
            Just decoded ->
                [DatumNotDecodedForAid | dcAid decoded /= cxAid cx]
                    <> stateClauses window now decoded

{- | The clauses of the Lean @consumableStateB@ a decoded datum fails: frozen,
poisoned and juvenile (@born_at + W > now@) for a live checkpoint, pending
termination for the other form. They are evaluated whatever AID the datum
names, as the Lean conjunction is.
-}
stateClauses :: Integer -> Integer -> DecodedCheckpoint -> [Clause]
stateClauses window now = \case
    DecodedLive{..} ->
        [CheckpointFrozen | dcFrozen]
            <> [CheckpointPoisoned | dcPoisoned]
            <> [CheckpointJuvenile | dcBornAt + window > now]
    DecodedPending{} -> [CheckpointTerminationPending]

{- | The Lean @authenticatedContextB@: the environment resolves the context's
network, its release and its checkpoint credential, each as a whole. An
unresolved release or checkpoint credential never authenticates. The consumer
predicate and the reader's status share this one definition.
-}
authenticated :: Environment -> Context -> Bool
authenticated env cx =
    envNetwork env == cxNetwork cx
        && envRelease env == Just (cxRelease cx)
        && envCheckpointCredential env == Just (cxCheckpointCredential cx)

-- | The verdict of the Lean @consumableHoldingB@: true when no clause failed.
consumableHoldingB ::
    Integer -> Integer -> Environment -> Context -> ObservedOutput -> Bool
consumableHoldingB window now env cx out =
    null (consumableHolding window now env cx out)
