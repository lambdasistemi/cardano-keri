{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.CodecsSpec (spec) where

import Cardano.Crypto.Hash.Class (
    hashFromBytes,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.Indexer.Codecs (
    CheckpointDecodeError (..),
    CheckpointRecord (..),
    decodeCheckpointOutput,
 )
import Cardano.Ledger.Address (
    Addr (..),
    serialiseAddr,
 )
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    dataToBinaryData,
    hashData,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
 )
import Cardano.Ledger.Binary (
    serialize',
 )
import Cardano.Ledger.Coin (
    Coin (..),
 )
import Cardano.Ledger.Conway (
    ConwayEra,
 )
import Cardano.Ledger.Core (
    eraProtVerLow,
 )
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (
    ScriptHash (..),
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Serialise (
    deserialiseOrFail,
 )
import Data.Aeson (
    FromJSON (..),
    eitherDecodeFileStrict',
    withObject,
    (.:),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Function (
    (&),
 )
import Data.Map.Strict qualified as Map
import Data.Text (
    Text,
 )
import Data.Text.Encoding qualified as TE
import Lens.Micro (
    (.~),
 )
import Paths_cardano_keri (
    getDataFileName,
 )
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
 )
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "decodeCheckpointOutput" $ do
    it "round-trips the exact Conway TxOut serialisation used upstream" $ do
        decodeCase positiveCase
            `shouldBe` Right
                CheckpointRecord
                    { crAid = aidX
                    , crAssetName = assetX
                    , crTxIn = sampleTxIn
                    , crAddress = sampleIndexerAddress
                    , crDatum = sampleDatum
                    }

    it "rejects undecodable TxOut bytes with TxOutUndecodable" $
        decodeCheckpointOutput
            checkpointPolicy
            sampleTxIn
            sampleIndexerAddress
            (Indexer.TxOut "not a ledger TxOut")
            `shouldSatisfy` isTxOutUndecodable

    it "rejects absent and hash-only datums before inspecting assets" $ do
        decodeCase positiveCase{caseDatum = NoDatum}
            `shouldBe` Left NoInlineDatum
        decodeCase
            positiveCase
                { caseDatum =
                    DatumHash (hashData (Data wrongDatum :: Data ConwayEra))
                }
            `shouldBe` Left NoInlineDatum
        decodeCase
            positiveCase
                { caseDatum = NoDatum
                , caseAssets = mempty
                }
            `shouldBe` Left NoInlineDatum

    it "rejects a decodable non-checkpoint inline datum" $
        decodeCase positiveCase{caseDatum = inlineDatum wrongDatum}
            `shouldBe` Left DatumUndecodable

    it "rejects ADA-only and same-name assets under another policy" $ do
        decodeCase positiveCase{caseAssets = mempty}
            `shouldBe` Left NoCheckpointAsset
        decodeCase
            positiveCase
                { caseAssets =
                    Map.singleton
                        otherPolicy
                        (Map.singleton (assetName assetX) 1)
                }
            `shouldBe` Left NoCheckpointAsset

    it "rejects an asset genuinely derived for another AID" $ do
        -- This is a forgery attempt, not a formatting nicety: the output carries
        -- a well-formed datum for AID X but the authentic derived name for AID Y.
        decodeCase
            positiveCase
                { caseAssets =
                    Map.singleton
                        checkpointPolicy
                        (Map.singleton (assetName $ deriveAidAssetName aidY) 1)
                }
            `shouldBe` Left AssetNameMismatch

    it "rejects multiple policy assets even when one has the correct name" $
        decodeCase
            positiveCase
                { caseAssets =
                    Map.singleton
                        checkpointPolicy
                        ( Map.fromList
                            [ (assetName assetX, 1)
                            , (assetName $ deriveAidAssetName aidY, 1)
                            ]
                        )
                }
            `shouldBe` Left MultipleCheckpointAssets

    it "decodes real M1 chain components in a locally assembled TxOut envelope" $ do
        -- Koios captured the tx input, address, value, policy, asset name and
        -- inline datum. There was no preprod node socket, so only the Conway
        -- era-serialised TxOut envelope is assembled locally.
        fixture <- loadFixture
        let policy = policyFromBytes (hexText $ fixturePolicyId fixture)
            ledgerAddress = addressForPolicy policy
            rawAddress = hexText (fixtureAddressBytes fixture)
            capturedAsset = hexText (fixtureAssetName fixture)
            capturedDatum = decodePlutusData (hexText $ fixtureInlineDatum fixture)
            txIn =
                Indexer.TxIn
                    (hexText $ fixtureTxHash fixture)
                    (fromIntegral $ fixtureTxIndex fixture)
            indexerAddress = Indexer.Address rawAddress
            outputCase =
                OutputCase
                    { caseAddress = ledgerAddress
                    , caseCoin = fixtureLovelace fixture
                    , caseAssets =
                        Map.singleton
                            policy
                            ( Map.singleton
                                (assetName capturedAsset)
                                (fixtureAssetQuantity fixture)
                            )
                    , caseDatum = inlineDatum capturedDatum
                    }
        serialiseAddr ledgerAddress `shouldBe` rawAddress
        fixtureAddressBech32 fixture
            `shouldBe` "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
        case decodeCheckpointOutput policy txIn indexerAddress (encodeCase outputCase) of
            Left err -> expectationFailure ("golden decode failed: " <> show err)
            Right record -> do
                crAid record `shouldBe` goldenAid
                crAssetName record `shouldBe` capturedAsset
                crTxIn record `shouldBe` txIn
                crAddress record `shouldBe` indexerAddress
                crDatum record `shouldBe` goldenDatum

data OutputCase = OutputCase
    { caseAddress :: !Addr
    , caseCoin :: !Integer
    , caseAssets :: !(Map.Map PolicyID (Map.Map AssetName Integer))
    , caseDatum :: !(Datum ConwayEra)
    }

positiveCase :: OutputCase
positiveCase =
    OutputCase
        { caseAddress = sampleLedgerAddress
        , caseCoin = 5_000_000
        , caseAssets =
            Map.singleton
                checkpointPolicy
                (Map.singleton (assetName assetX) 1)
        , caseDatum = inlineDatum (plutusData $ V1 sampleDatum)
        }

decodeCase ::
    OutputCase ->
    Either CheckpointDecodeError CheckpointRecord
decodeCase =
    decodeCheckpointOutput
        checkpointPolicy
        sampleTxIn
        sampleIndexerAddress
        . encodeCase

encodeCase :: OutputCase -> Indexer.TxOut
encodeCase outputCase =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (ledgerOutput outputCase)

ledgerOutput :: OutputCase -> TxOut ConwayEra
ledgerOutput OutputCase{..} =
    mkBasicTxOut
        caseAddress
        (MaryValue (Coin caseCoin) (MultiAsset caseAssets))
        & datumTxOutL .~ caseDatum

inlineDatum :: PLC.Data -> Datum ConwayEra
inlineDatum datum =
    Datum (dataToBinaryData $ Data datum)

plutusData :: (ToData a) => a -> PLC.Data
plutusData value =
    let BuiltinData datum = toBuiltinData value
     in datum

wrongDatum :: PLC.Data
wrongDatum = PLC.Constr 1 []

sampleDatum :: CheckpointDatumV1
sampleDatum =
    CheckpointDatumV1
        { cdCesrAid = aidX
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

aidX, aidY, assetX :: ByteString
aidX = BS.replicate 32 0x31
aidY = BS.replicate 32 0x32
assetX = deriveAidAssetName aidX

checkpointPolicy, otherPolicy :: PolicyID
checkpointPolicy = policyFromBytes (BS.replicate 28 0x41)
otherPolicy = policyFromBytes (BS.replicate 28 0x42)

sampleLedgerAddress :: Addr
sampleLedgerAddress = addressForPolicy checkpointPolicy

sampleIndexerAddress :: Indexer.Address
sampleIndexerAddress = Indexer.Address (serialiseAddr sampleLedgerAddress)

sampleTxIn :: Indexer.TxIn
sampleTxIn = Indexer.TxIn (BS.replicate 32 0x51) 7

addressForPolicy :: PolicyID -> Addr
addressForPolicy (PolicyID scriptHash) =
    Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

policyFromBytes :: ByteString -> PolicyID
policyFromBytes bytes =
    PolicyID $
        ScriptHash $
            case hashFromBytes bytes of
                Just hash -> hash
                Nothing -> error "invalid policy id width"

assetName :: ByteString -> AssetName
assetName = AssetName . SBS.toShort

isTxOutUndecodable :: Either CheckpointDecodeError CheckpointRecord -> Bool
isTxOutUndecodable (Left (TxOutUndecodable _)) = True
isTxOutUndecodable _ = False

data LiveFixture = LiveFixture
    { fixtureTxHash :: !Text
    , fixtureTxIndex :: !Integer
    , fixtureAddressBech32 :: !Text
    , fixtureAddressBytes :: !Text
    , fixtureLovelace :: !Integer
    , fixturePolicyId :: !Text
    , fixtureAssetName :: !Text
    , fixtureAssetQuantity :: !Integer
    , fixtureInlineDatum :: !Text
    }

instance FromJSON LiveFixture where
    parseJSON = withObject "LiveFixture" $ \object ->
        LiveFixture
            <$> object .: "txHash"
            <*> object .: "txIndex"
            <*> object .: "addressBech32"
            <*> object .: "addressBytes"
            <*> object .: "lovelace"
            <*> object .: "policyId"
            <*> object .: "assetName"
            <*> object .: "assetQuantity"
            <*> object .: "inlineDatumCbor"

loadFixture :: IO LiveFixture
loadFixture = do
    path <- getDataFileName "indexer-test/fixtures/live-m1-checkpoint.json"
    eitherDecodeFileStrict' path >>= either fail pure

hexText :: Text -> ByteString
hexText text =
    case convertFromBase Base16 (TE.encodeUtf8 text) of
        Right bytes -> bytes
        Left err -> error ("invalid fixture hex: " <> err)

decodePlutusData :: ByteString -> PLC.Data
decodePlutusData bytes =
    case deserialiseOrFail (BSL.fromStrict bytes) of
        Right datum -> datum
        Left err -> error ("invalid fixture datum CBOR: " <> show err)

goldenAid :: ByteString
goldenAid =
    hexText "f72f797359b865886da85505520c58de5fc884133065ea6b469f5d3382b2ad46"

goldenDatum :: CheckpointDatumV1
goldenDatum =
    CheckpointDatumV1
        { cdCesrAid = goldenAid
        , cdCurKeys =
            [ hexText
                "2949f7b46498ab88fdedb1160f44723cd04cb1df8209974c57773a9c4ab60688"
            ]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys =
            [ hexText
                "b9e60ef4194482de6da2c79f40eca6f278eebfa65070010439dac3e769ab8937"
            ]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }
