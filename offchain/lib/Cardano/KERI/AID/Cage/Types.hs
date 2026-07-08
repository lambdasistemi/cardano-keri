{- |
Module      : Cardano.KERI.AID.Cage.Types
Description : PlutusData types for the cardano-keri cage extension
License     : Apache-2.0

Haskell types matching the cardano-keri Aiken on-chain extensions.
'ProofStep' mirrors @Cardano.MPFS.Cage.Types.ProofStep@ byte-for-byte;
kept local to avoid pulling in the heavy cardano-mpfs-cage dep chain.

Hand-written 'ToData'\/'FromData' instances guarantee constructor
indices and field ordering match the Aiken source byte-for-byte.
-}
module Cardano.KERI.AID.Cage.Types (
    -- * MPF proof step (mirrors cardano-mpfs-cage)
    ProofStep (..),
    Neighbor (..),

    -- * AID-specific types
    AIDOwnerAuth (..),
    AIDRequestAction (..),
    AIDOnChainTokenState (..),
) where

import Data.ByteString (
    ByteString,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
    UnsafeFromData (..),
 )

-- ---------------------------------------------------------
-- MPF proof step types (mirrors Cardano.MPFS.Cage.Types)
-- ---------------------------------------------------------

{- | A single step in an MPF Merkle proof.
Encoding mirrors @cardano-mpfs-cage@'s 'ProofStep' byte-for-byte.
-}
data ProofStep
    = -- | Branch step (Constr 0)
      Branch
        { branchSkip :: !Integer
        , branchNeighbors :: !ByteString
        }
    | -- | Fork step (Constr 1)
      Fork
        { forkSkip :: !Integer
        , forkNeighbor :: !Neighbor
        }
    | -- | Leaf step (Constr 2)
      Leaf
        { leafSkip :: !Integer
        , leafKey :: !ByteString
        , leafValue :: !ByteString
        }
    deriving stock (Show, Eq)

-- | Neighbor node in a fork proof step.
data Neighbor = Neighbor
    { neighborNibble :: !Integer
    , neighborPrefix :: !ByteString
    , neighborRoot :: !ByteString
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- AID domain types
-- ---------------------------------------------------------

{- | Owner authorization for a value-write operation.
Matches Aiken @types\/OwnerAuth@.
-}
data AIDOwnerAuth = AIDOwnerAuth
    { ownerAid :: !ByteString
    -- ^ Key in identity_root MPF trie (AID identifier)
    , identityProof :: ![ProofStep]
    -- ^ MPF inclusion: identity_root[owner_aid] = blake2b_256(owner_key)
    , ownerKey :: !ByteString
    -- ^ Raw Ed25519 public key (32 bytes)
    , ownerSig :: !ByteString
    -- ^ Ed25519 signature (64 bytes) over the value-write message
    }
    deriving stock (Show, Eq)

{- | Per-request action in a @Modify@ redeemer.
Extends Aiken @types\/RequestAction@ with owner auth.
-}
data AIDRequestAction
    = -- | Apply the MPF op after verifying owner auth (Constr 0)
      AIDUpdateAction
        { valueProof :: ![ProofStep]
        -- ^ MPF proof for the value operation
        , auth :: !AIDOwnerAuth
        -- ^ Owner identity and signature
        }
    | -- | Reject an expired or dishonest request (Constr 1)
      AIDRejected
    deriving stock (Show, Eq)

{- | On-chain token state extended with identity_root.
Matches Aiken @types\/State@ (6 fields).
-}
data AIDOnChainTokenState = AIDOnChainTokenState
    { aidStateOwner :: !BuiltinByteString
    -- ^ Payment key hash of the token owner (28 bytes)
    , aidStateRoot :: !ByteString
    -- ^ Current MPF root of the token's trie
    , aidIdentityRoot :: !ByteString
    -- ^ AID identity registry MPF root snapshot
    , aidStateTip :: !Integer
    -- ^ Max fee (lovelace) charged per request
    , aidStateProcessTime :: !Integer
    -- ^ Oracle processing window duration (ms)
    , aidStateRetractTime :: !Integer
    -- ^ Requester retract window duration (ms)
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------

mkD :: Data -> BuiltinData
mkD = BuiltinData

unD :: BuiltinData -> Data
unD (BuiltinData d) = d

bsToD :: ByteString -> Data
bsToD = B

bsFromD :: Data -> Maybe ByteString
bsFromD (B bs) = Just bs
bsFromD _ = Nothing

bbsToD :: BuiltinByteString -> Data
bbsToD (BuiltinByteString bs) = B bs

bbsFromD :: Data -> Maybe BuiltinByteString
bbsFromD (B bs) = Just (BuiltinByteString bs)
bbsFromD _ = Nothing

-- ---------------------------------------------------------
-- ToData / FromData instances
-- ---------------------------------------------------------

instance ToData Neighbor where
    toBuiltinData Neighbor{..} =
        mkD $
            Constr
                0
                [ I neighborNibble
                , bsToD neighborPrefix
                , bsToD neighborRoot
                ]

instance FromData Neighbor where
    fromBuiltinData bd = case unD bd of
        Constr 0 [I nib, pfx, rt] ->
            Neighbor nib <$> bsFromD pfx <*> bsFromD rt
        _ -> Nothing

instance UnsafeFromData Neighbor where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [I nib, B pfx, B rt] -> Neighbor nib pfx rt
        _ -> error "unsafeFromBuiltinData: Neighbor"

instance ToData ProofStep where
    toBuiltinData Branch{..} =
        mkD $ Constr 0 [I branchSkip, bsToD branchNeighbors]
    toBuiltinData Fork{..} =
        mkD $ Constr 1 [I forkSkip, unD (toBuiltinData forkNeighbor)]
    toBuiltinData Leaf{..} =
        mkD $ Constr 2 [I leafSkip, bsToD leafKey, bsToD leafValue]

instance FromData ProofStep where
    fromBuiltinData bd = case unD bd of
        Constr 0 [I sk, nb] -> Branch sk <$> bsFromD nb
        Constr 1 [I sk, nd] -> Fork sk <$> fromBuiltinData (mkD nd)
        Constr 2 [I sk, k, v] -> Leaf sk <$> bsFromD k <*> bsFromD v
        _ -> Nothing

instance UnsafeFromData ProofStep where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [I sk, B nb] -> Branch sk nb
        Constr 1 [I sk, nd] -> Fork sk $ unsafeFromBuiltinData (mkD nd)
        Constr 2 [I sk, B k, B v] -> Leaf sk k v
        _ -> error "unsafeFromBuiltinData: ProofStep"

-- | Constr 0 [B owner_aid, List [proof_steps], B owner_key, B owner_sig]
instance ToData AIDOwnerAuth where
    toBuiltinData AIDOwnerAuth{..} =
        mkD $
            Constr
                0
                [ bsToD ownerAid
                , List $ map (unD . toBuiltinData) identityProof
                , bsToD ownerKey
                , bsToD ownerSig
                ]

instance FromData AIDOwnerAuth where
    fromBuiltinData bd = case unD bd of
        Constr 0 [aid, List steps, key, sig] -> do
            ownerAid <- bsFromD aid
            identityProof <- traverse (fromBuiltinData . mkD) steps
            ownerKey <- bsFromD key
            ownerSig <- bsFromD sig
            Just AIDOwnerAuth{..}
        _ -> Nothing

instance UnsafeFromData AIDOwnerAuth where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [B aid, List steps, B key, B sig] ->
            AIDOwnerAuth
                { ownerAid = aid
                , identityProof = map (unsafeFromBuiltinData . mkD) steps
                , ownerKey = key
                , ownerSig = sig
                }
        _ -> error "unsafeFromBuiltinData: AIDOwnerAuth"

-- | Constr 0 [List [value_proof_steps], auth] | Constr 1 []
instance ToData AIDRequestAction where
    toBuiltinData AIDUpdateAction{..} =
        mkD $
            Constr
                0
                [ List $ map (unD . toBuiltinData) valueProof
                , unD (toBuiltinData auth)
                ]
    toBuiltinData AIDRejected = mkD $ Constr 1 []

instance FromData AIDRequestAction where
    fromBuiltinData bd = case unD bd of
        Constr 0 [List steps, authD] -> do
            valueProof <- traverse (fromBuiltinData . mkD) steps
            auth <- fromBuiltinData (mkD authD)
            Just AIDUpdateAction{..}
        Constr 1 [] -> Just AIDRejected
        _ -> Nothing

instance UnsafeFromData AIDRequestAction where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [List steps, authD] ->
            AIDUpdateAction
                { valueProof = map (unsafeFromBuiltinData . mkD) steps
                , auth = unsafeFromBuiltinData (mkD authD)
                }
        Constr 1 [] -> AIDRejected
        _ -> error "unsafeFromBuiltinData: AIDRequestAction"

-- | Constr 0 [B owner, B root, B identity_root, I tip, I process_time, I retract_time]
instance ToData AIDOnChainTokenState where
    toBuiltinData AIDOnChainTokenState{..} =
        mkD $
            Constr
                0
                [ bbsToD aidStateOwner
                , bsToD aidStateRoot
                , bsToD aidIdentityRoot
                , I aidStateTip
                , I aidStateProcessTime
                , I aidStateRetractTime
                ]

instance FromData AIDOnChainTokenState where
    fromBuiltinData bd = case unD bd of
        Constr 0 [own, root, ir, I tip, I pt, I rt] -> do
            aidStateOwner <- bbsFromD own
            aidStateRoot <- bsFromD root
            aidIdentityRoot <- bsFromD ir
            let aidStateTip = tip
                aidStateProcessTime = pt
                aidStateRetractTime = rt
            Just AIDOnChainTokenState{..}
        _ -> Nothing

instance UnsafeFromData AIDOnChainTokenState where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [B own, B root, B ir, I tip, I pt, I rt] ->
            AIDOnChainTokenState
                { aidStateOwner = BuiltinByteString own
                , aidStateRoot = root
                , aidIdentityRoot = ir
                , aidStateTip = tip
                , aidStateProcessTime = pt
                , aidStateRetractTime = rt
                }
        _ ->
            error "unsafeFromBuiltinData: AIDOnChainTokenState"
