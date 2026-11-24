{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.ReleaseFixtures
Description : Outputs of a registry release for the reader's tests (#353)

A release identity, the outputs its checkpoint validator would hold and the
store operations that put them in an index. The expected asset of an AID is
always the library's own 'representativeAsset' of the identity's context,
never a name typed here.
-}
module Cardano.KERI.Indexer.ReleaseFixtures (
    testRelease,
    otherRegistry,
    releaseAddr,
    keyStateOf,
    aidText,
    assetOf,
    liveFacts,
    pendingFacts,
    datumOf,
    outputAt,
    outputWithDatum,
    txInAt,
    frozenLive,
    liveWith,
    liveShaped,
    liveOutputWith,
    scriptHashOf,
    asset,
    liveOutput,
    validManifest,
    manifestAddress,
    writeManifest,
    pendingOutput,
) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..))
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (V2),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    convictedOf,
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Value (heldValue)
import Cardano.KERI.AID.Consumer (Release (..), representativeAsset)
import Cardano.KERI.AID.Release (ReleaseIdentity (..), releaseContext)
import Cardano.KERI.Deployment.Manifest (CheckpointInfo (..), Manifest (..), writeManifestAtomic)
import Cardano.KERI.Indexer.Config (decodeAddress)
import Cardano.KERI.Indexer.FollowerSpec (m1Manifest)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData)
import Cardano.Ledger.Api.Tx.Out (TxOut, datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Lens.Micro ((.~))
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import System.FilePath ((</>))

-- | A release whose amounts leave room for a deposit, a bond and a pool.
testRelease :: ReleaseIdentity
testRelease =
    ReleaseIdentity
        { riNetwork = 0
        , riRelease =
            Release
                { rlApplicationPolicy = BS.replicate 28 0x61
                , rlApplicationCredential = BS.replicate 28 0x62
                , rlStateProgram = BS.replicate 28 0x63
                , rlStatePolicy = BS.replicate 28 0x64
                }
        , riSeed = OutputReference (BS.replicate 32 0x65) 3
        , riCheckpointValidator = BS.replicate 28 0x66
        , riDeposit = 8_000_000
        , riFreezeBond = 2_000_000
        , riPremium = 500_000
        , riMinimumAda = 2_000_000
        , riTerminationCarrier = 1_500_000
        , riApplicationParameters =
            ApplicationParameters 1_000_000 500_000 90_000 5_000
        }

-- | The same release of another registry: its seed and its amounts differ.
otherRegistry :: ReleaseIdentity
otherRegistry =
    testRelease
        { riSeed = OutputReference (BS.replicate 32 0x65) 4
        , riDeposit = 7_000_000
        , riFreezeBond = 3_000_000
        , riMinimumAda = 2_500_000
        , riPremium = 400_000
        , riTerminationCarrier = 1_200_000
        }

releaseAddr :: ReleaseIdentity -> Addr
releaseAddr ri =
    Addr
        (if riNetwork ri == 0 then Testnet else Mainnet)
        (ScriptHashObj (scriptHashOf (riCheckpointValidator ri)))
        StakeRefNull

scriptHashOf :: ByteString -> ScriptHash
scriptHashOf bytes = maybe (error "ReleaseFixtures: hash width") ScriptHash (hashFromBytes bytes)

keyStateOf :: ByteString -> KeyStateView
keyStateOf rawAid =
    KeyStateView
        { cdCesrAid = rawAid
        , cdCurKeys = [BS.replicate 32 0x11, BS.replicate 32 0x12]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 2
        , cdNativeSn = 5
        }

-- | The qualified text of the AID of a raw 32-byte digest.
aidText :: ByteString -> ByteString
aidText = qb64Aid

-- | The asset the identity's context gives an AID: policy and name.
assetOf :: ReleaseIdentity -> ByteString -> (ByteString, ByteString)
assetOf ri raw = representativeAsset (releaseContext ri (qb64Aid raw))

liveFacts :: ByteString -> CheckpointDatumV2
liveFacts raw = liveOfKeyState (BS.replicate 29 0x70) 1_700_000_000_000 (keyStateOf raw)

pendingFacts :: ByteString -> CheckpointDatumV2
pendingFacts raw = fromMaybe (error "ReleaseFixtures: not live") (convictedOf (liveFacts raw))

-- | The live facts of a raw AID, frozen or not.
frozenLive :: Bool -> ByteString -> CheckpointDatumV2
frozenLive frozen = liveWith (frozen, False, False)

-- | The live facts of a raw AID with these flags: frozen, poisoned, topped up.
liveWith :: (Bool, Bool, Bool) -> ByteString -> CheckpointDatumV2
liveWith (frozen, poisoned, toppedUp) raw = case liveFacts raw of
    l@Live{} -> l{lvFrozen = frozen, lvPoisoned = poisoned, lvToppedUp = toppedUp}
    other -> other

datumOf :: CheckpointDatumV2 -> PLC.Data
datumOf facts = let BuiltinData d = toBuiltinData (V2 facts) in d

{- | An output at an address with this lovelace, these assets (policy, name,
quantity) and this inline datum, as the store holds it.
-}
outputAt :: Addr -> Integer -> [(ByteString, ByteString, Integer)] -> Maybe PLC.Data -> Indexer.TxOut
outputAt addr lovelace assets datum =
    outputWithDatum addr lovelace assets (maybe NoDatum (Datum . dataToBinaryData . Data) datum)

{- | An output at an address with this lovelace, these assets and this datum in
any form the ledger carries: none, a hash or inline.
-}
outputWithDatum ::
    Addr -> Integer -> [(ByteString, ByteString, Integer)] -> Datum ConwayEra -> Indexer.TxOut
outputWithDatum addr lovelace assets datum =
    Indexer.TxOut $
        serialize' (eraProtVerLow @ConwayEra) $
            base & datumTxOutL .~ datum
  where
    base :: TxOut ConwayEra
    base = mkBasicTxOut addr (MaryValue (Coin lovelace) (MultiAsset policies))
    policies =
        Map.fromListWith
            Map.union
            [ (PolicyID (scriptHashOf p), Map.singleton (AssetName (SBS.toShort n)) q)
            | (p, n, q) <- assets
            ]

txInAt :: Int -> Indexer.TxIn
txInAt n = Indexer.TxIn (BS.replicate 32 (fromIntegral n)) 0

asset :: ReleaseIdentity -> ByteString -> (ByteString, ByteString, Integer)
asset ri raw = let (p, n) = assetOf ri raw in (p, n, 1)

-- | An accepted live output of the release for a raw AID, holding this pool.
liveOutput :: ReleaseIdentity -> ByteString -> Bool -> Integer -> Indexer.TxOut
liveOutput ri raw frozen = liveOutputWith ri (frozenLive frozen raw) raw

-- | An output of the release for a raw AID holding these facts and this pool.
liveOutputWith :: ReleaseIdentity -> CheckpointDatumV2 -> ByteString -> Integer -> Indexer.TxOut
liveOutputWith ri facts raw pool =
    outputAt
        (releaseAddr ri)
        (heldValue (riMinimumAda ri) (riDeposit ri) (riFreezeBond ri) facts pool)
        [asset ri raw]
        (Just (datumOf facts))

-- | An output of the release for a raw AID in pending termination, holding this lovelace.
pendingOutput :: ReleaseIdentity -> ByteString -> Integer -> Indexer.TxOut
pendingOutput ri raw lovelace =
    outputAt (releaseAddr ri) lovelace [asset ri raw] (Just (datumOf (pendingFacts raw)))

-- | The version 1 manifest of the tests, with a checkpoint policy that is valid hexadecimal.
validManifest :: Manifest
validManifest =
    m1Manifest
        { manifestCheckpoint =
            (manifestCheckpoint m1Manifest)
                { checkpointPolicyId = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
                }
        }

-- | The checkpoint address the manifest names.
manifestAddress :: Indexer.Address
manifestAddress =
    either
        (error . ("manifest address: " <>))
        id
        (decodeAddress (checkpointAddressBech32 (manifestCheckpoint validManifest)))

-- | Write 'validManifest' in a directory and return its path.
writeManifest :: FilePath -> IO FilePath
writeManifest dir = do
    let path = dir </> "manifest.json"
    writeManifestAtomic path validManifest
    pure path

-- | The live facts of a raw AID with this key material and this sequence number, epoch and birth time.
liveShaped :: KeyMaterial -> (Integer, Integer, Integer) -> ByteString -> CheckpointDatumV2
liveShaped keys (sn, epoch, bornAt) raw = case liveFacts raw of
    l@Live{} -> l{lvKeys = keys, lvSn = sn, lvEpoch = epoch, lvBornAt = bornAt}
    other -> other
