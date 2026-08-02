{- |
Module      : Cardano.KERI.CLI.Backend.KoiosSpec
Description : #177 Slice 1 T177-S1-5 Koios provenance (RED)

The RULING-001 regression proof lives here: 'advancedFixture' constructs an
'ActiveCheckpoint' whose live UTxO's own creating tx differs from the
registration/minting tx, and asserts 'resolveKoiosFreshness' reflects the
UTxO's own creating tx's slot — never a stale mint event (which is not even
a parameter this function can consult).

The DIRECTION-001 regression proof lives here too: 'closedButLiveLookingUtxo'
is a fixture where @queryAssetUtxos@ would resolve a live-looking ACTIVE
checkpoint, but @queryAssetHistory@ shows the latest recorded event for that
asset is a burn. 'resolveKoiosActive' must prefer the proven-or-unprovable
burn over the utxo snapshot (mirrors the retired
@queryCheckpointStatusUsing@'s precedence) — ported from the deleted
@deployment-test/.../CloseSpec.hs@ "prefers a proved latest Close over a
stale ACTIVE index row" scenario.
-}
module Cardano.KERI.CLI.Backend.KoiosSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.CLI.Backend (BackendError (..), Freshness (..))
import Cardano.KERI.CLI.Backend.Koios (resolveKoiosActive, resolveKoiosFreshness)
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetHistory (..),
    ChainAssetUtxo (..),
    ChainMintingTransaction (..),
    ChainTip (..),
    ChainTransactionInfo (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    checkpointAssetName,
 )
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
    freshnessSpec
    activePrecedenceSpec

freshnessSpec :: Spec
freshnessSpec = describe "resolveKoiosFreshness (T177-S1-5)" $ do
    it "derives as_of_slot from the live UTxO's own creating tx, with a coherent tip" $
        resolveKoiosFreshness registrationFixture (Just registrationTxInfo) (Just (ChainTip 129_600_050))
            `shouldBe` Right (Freshness (Just 129_600_000) (Just 50))

    it "RULING-001 regression: an advanced checkpoint's as_of_slot is the UTxO's own creating tx, not the stale mint" $
        resolveKoiosFreshness advancedFixture (Just advancedTxInfo) (Just (ChainTip 129_700_010))
            `shouldBe` Right (Freshness (Just 129_700_000) (Just 10))

    it "missing tx_info for the checkpoint's own creating tx fails closed" $
        resolveKoiosFreshness registrationFixture Nothing (Just (ChainTip 129_600_050))
            `shouldSatisfy` isMalformed

    it "missing tip fails closed" $
        resolveKoiosFreshness registrationFixture (Just registrationTxInfo) Nothing
            `shouldSatisfy` isMalformed

    it "a tx_info answer for a different tx hash fails closed (ambiguous provenance)" $
        resolveKoiosFreshness
            registrationFixture
            (Just (ChainTransactionInfo "unrelated-tx-hash" 1))
            (Just (ChainTip 129_600_050))
            `shouldSatisfy` isMalformed

    it "a tip behind the checkpoint's own slot is an incoherent bound and fails closed" $
        resolveKoiosFreshness registrationFixture (Just registrationTxInfo) (Just (ChainTip 100))
            `shouldSatisfy` isMalformed

activePrecedenceSpec :: Spec
activePrecedenceSpec = describe "resolveKoiosActive (DIRECTION-001)" $ do
    it "resolves the live utxo as active when history shows no burn" $
        resolveKoiosActive sampleManifest aidText assetName [] [liveLookingUtxo]
            `shouldSatisfy` either (const False) activeIsJust

    it "DIRECTION-001 regression: a burn in asset_history wins over a live-looking utxo" $
        resolveKoiosActive sampleManifest aidText assetName [burnHistory] [liveLookingUtxo]
            `shouldBe` Right Nothing

    it "no utxo and no burn history is genuinely not registered" $
        resolveKoiosActive sampleManifest aidText assetName [] []
            `shouldBe` Right Nothing

activeIsJust :: Maybe ActiveCheckpoint -> Bool
activeIsJust (Just _) = True
activeIsJust Nothing = False

isMalformed :: Either BackendError a -> Bool
isMalformed (Left (MalformedResponse _)) = True
isMalformed _ = False

-- ---------------------------------------------------------------------------
-- DIRECTION-001 fixtures

policy :: Text
policy = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

checkpointAddress :: Text
checkpointAddress = "addr_test1checkpointdirection001"

assetName :: Text
assetName = either (error "KoiosSpec: invalid fixture aid") id (checkpointAssetName aidText)

sampleManifest :: Manifest
sampleManifest =
    Manifest
        { manifestSchemaVersion = "cardano-keri/m1-deployment-manifest/v1"
        , manifestNetwork = NetworkInfo "preprod" 1
        , manifestSource = SourceInfo "repository" "commit"
        , manifestBlueprint = BlueprintInfo "digest"
        , manifestParameters = DeploymentParameters 0 0 0 0 0
        , manifestCheckpoint = CheckpointInfo checkpointAddress policy
        , manifestPublishedAt = "2026-01-01T00:00:00Z"
        , manifestScripts = []
        }

liveLookingUtxo :: ChainAssetUtxo
liveLookingUtxo =
    ChainAssetUtxo
        { chainAssetTxId = T.replicate 64 "1" -- lookalike hex; length unchecked here
        , chainAssetIndex = 0
        , chainAssetAddress = checkpointAddress
        , chainAssetLovelace = 5_000_000
        , chainAssetList = [ChainAsset policy assetName 1]
        , chainAssetInlineDatum = Just (toDatumValue closedDatum)
        }
  where
    closedDatum =
        CheckpointDatumV1
            { cdCesrAid = BS.replicate 32 0x00
            , cdCurKeys = [BS.replicate 32 0x11]
            , cdCurThreshold = Unweighted 1
            , cdNextKeys = [BS.replicate 32 0x22]
            , cdNextThreshold = Unweighted 1
            , cdWitnesses = []
            , cdToad = 0
            , cdSeq = 0
            , cdNativeSn = 0
            }

burnHistory :: ChainAssetHistory
burnHistory =
    ChainAssetHistory
        { chainHistoryPolicy = policy
        , chainHistoryAssetName = assetName
        , chainMintingTransactions =
            [ChainMintingTransaction "burntx0000000000000000000000000000000000000000000000000000" (-1) 100]
        }

toDatumValue :: CheckpointDatumV1 -> Value
toDatumValue datum =
    let BuiltinData plc = toBuiltinData (V1 datum)
     in plutusDataJson plc

registrationTxId :: ByteString
registrationTxId = BS.replicate 32 0x10

registrationFixture :: ActiveCheckpoint
registrationFixture =
    ActiveCheckpoint
        { activeCheckpointAid = aidText
        , activeCheckpointAssetName = "assetname"
        , activeCheckpointTxId = "1010101010101010101010101010101010101010101010101010101010101010"
        , activeCheckpointIndex = 0
        , activeCheckpointAddress = "addr_test1checkpoint"
        , activeCheckpointLovelace = 5_000_000
        , activeCheckpointAssets = []
        , activeCheckpointDatum = datumX0
        }

registrationTxInfo :: ChainTransactionInfo
registrationTxInfo = ChainTransactionInfo "1010101010101010101010101010101010101010101010101010101010101010" 129_600_000

advancedFixture :: ActiveCheckpoint
advancedFixture =
    registrationFixture
        { activeCheckpointTxId = "2020202020202020202020202020202020202020202020202020202020202020"
        , activeCheckpointDatum = datumX0{cdSeq = 1, cdNativeSn = 1}
        }

advancedTxInfo :: ChainTransactionInfo
advancedTxInfo = ChainTransactionInfo "2020202020202020202020202020202020202020202020202020202020202020" 129_700_000

aidText :: Text
aidText = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

datumX0 :: CheckpointDatumV1
datumX0 =
    CheckpointDatumV1
        { cdCesrAid = registrationTxId
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }
