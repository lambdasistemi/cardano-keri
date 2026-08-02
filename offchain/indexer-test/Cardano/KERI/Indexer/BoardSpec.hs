{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.BoardSpec
Description : #176 PROVE-LIST item 6 — board authenticity through the real adapter

Seeds real indexed ledger 'TxOut's (never hand-built Koios JSON) carrying the
genuine committed preprod witness OOBI fixtures already used by
"Cardano.KERI.Deployment.EndpointBoardSpec", and proves 'indexedBoardCatalog'
resolves them end to end through the frozen 'resolveBoardCatalog' oracle: a
valid signed record round-trips to its 'BoardEntry', a forged signature and a
malformed datum each invalidate the whole catalog, and a duplicate
witness-key row does not inflate a watchability count.
-}
module Cardano.KERI.Indexer.BoardSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
    missingBoardWitnesses,
    parseEndpointRecord,
    watchabilityGrade,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    frozenEndpointBoardPolicyId,
 )
import Cardano.KERI.Indexer.Board (indexedBoardCatalog)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    dataToBinaryData,
 )
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Lens.Micro ((.~))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.KERI.Indexer.Board (#176 PROVE-LIST 6)" $ do
    it "resolves a real authenticated record by B-code witness key" $ do
        record <- loadRecord "witness-1-oobi.cesr"
        let txIn = sampleTxIn 0x01
        indexedBoardCatalog boardAddress [(txIn, boardOutput record)]
            `shouldBe` Right [expectedEntry record 0x01]

    it "fails the whole catalog closed on a forged signature" $ do
        record <- loadRecord "witness-1-oobi.cesr"
        let forged =
                record
                    { endpointEventBytes =
                        replaceOnce
                            "witness-1"
                            "witness-X"
                            (endpointEventBytes record)
                    }
            txIn = sampleTxIn 0x02
        indexedBoardCatalog boardAddress [(txIn, boardOutput forged)]
            `shouldSatisfy` isLeft

    it "fails the whole catalog closed on a malformed inline datum" $ do
        record <- loadRecord "witness-1-oobi.cesr"
        let txIn = sampleTxIn 0x03
        indexedBoardCatalog boardAddress [(txIn, malformedDatumOutput record)]
            `shouldSatisfy` isLeft

    it "does not inflate witnesses_listed for a duplicate witness-key row" $ do
        record <- loadRecord "witness-1-oobi.cesr"
        let txInA = sampleTxIn 0x04
            txInB = sampleTxIn 0x05
        catalog <-
            expectRight $
                indexedBoardCatalog
                    boardAddress
                    [ (txInA, boardOutput record)
                    , (txInB, boardOutput record)
                    ]
        length catalog `shouldBe` 2
        watchabilityGrade [endpointWitnessKey record] catalog `shouldBe` (1, 1)

    it "reports a witness missing from the catalog in canonical B-code form" $ do
        record <- loadRecord "witness-1-oobi.cesr"
        other <- loadRecord "witness-2-oobi.cesr"
        let txIn = sampleTxIn 0x06
        catalog <-
            expectRight $
                indexedBoardCatalog boardAddress [(txIn, boardOutput record)]
        missingBoardWitnesses
            [endpointWitnessKey record, endpointWitnessKey other]
            catalog
            `shouldBe` [endpointWitnessKey other]

-- ---------------------------------------------------------------------------
-- Fixtures

boardAddress :: Indexer.Address
boardAddress = Indexer.Address (serialiseAddr ledgerAddress)

ledgerAddress :: Addr
ledgerAddress =
    let PolicyID scriptHash = boardPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

boardPolicy :: PolicyID
boardPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (hexBytesOrError frozenEndpointBoardPolicyId) of
                Just h -> h
                Nothing -> error "BoardSpec: invalid frozen policy id width"

expectedEntry :: EndpointRecord -> Word8 -> BoardEntry
expectedEntry record txByte =
    BoardEntry
        { boardWitnessKey = endpointWitnessKey record
        , boardAid = endpointAid record
        , boardScheme = endpointScheme record
        , boardUrl = endpointUrl record
        , boardTxId = hexText (txIdBytes txByte)
        , boardIndex = 0
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = owner
        }

owner :: ByteString
owner = BS.replicate 28 0x33

boardOutput :: EndpointRecord -> Indexer.TxOut
boardOutput record =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (boardDatum record))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut = mkBasicTxOut ledgerAddress (boardValue record)

malformedDatumOutput :: EndpointRecord -> Indexer.TxOut
malformedDatumOutput record =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (PLC.Constr 0 [PLC.B "short"]))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut = mkBasicTxOut ledgerAddress (boardValue record)

boardValue :: EndpointRecord -> MaryValue
boardValue record =
    MaryValue
        (Coin 2_000_000)
        ( MultiAsset $
            Map.singleton
                boardPolicy
                ( Map.singleton
                    (AssetName . SBS.toShort $ endpointWitnessKey record)
                    1
                )
        )

boardDatum :: EndpointRecord -> PLC.Data
boardDatum record =
    PLC.Constr
        0
        [ PLC.B (endpointWitnessKey record)
        , PLC.B (endpointEventBytes record)
        , PLC.B (endpointSignature record)
        , PLC.B owner
        ]

inlineDatum :: PLC.Data -> Datum ConwayEra
inlineDatum datum = Datum (dataToBinaryData (Data datum))

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (txIdBytes byte) 0

txIdBytes :: Word8 -> ByteString
txIdBytes = BS.replicate 32

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

replaceOnce :: ByteString -> ByteString -> ByteString -> ByteString
replaceOnce needle replacement haystack =
    let (before, match) = BS.breakSubstring needle haystack
     in if BS.null match
            then haystack
            else before <> replacement <> BS.drop (BS.length needle) match

loadRecord :: FilePath -> IO EndpointRecord
loadRecord name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    bytes <- BS.readFile path
    case parseEndpointRecord bytes of
        Left err -> expectationFailure err >> fail err
        Right record -> pure record

expectRight :: (Show err) => Either err a -> IO a
expectRight = \case
    Left err -> expectationFailure (show err) >> fail (show err)
    Right value -> pure value

hexText :: ByteString -> Text
hexText bytes = TE.decodeUtf8 (convertToBase Base16 bytes)

hexBytesOrError :: Text -> ByteString
hexBytesOrError hexInput =
    case convertFromBase Base16 (TE.encodeUtf8 hexInput) of
        Right bytes -> bytes
        Left err -> error ("BoardSpec: invalid hex fixture: " <> err)
