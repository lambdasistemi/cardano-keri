{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

{- |
Module      : Cardano.KERI.AID.E2E.EvaluationParity
Description : One transaction, evaluated by the node and by the local evaluation the Koios commands use

The local evaluation needs the network's time. A devnet has no published
material, so its time is built from the genesis the node runs on and the
instant the node started: one era from slot zero, the genesis's slot length and
epoch size, ending far beyond anything a journey reaches. The two results are
given as they are; the caller compares them.
-}
module Cardano.KERI.AID.E2E.EvaluationParity (evaluationsOf, writeDevnetTimeSource) where

import Cardano.KERI.Deployment.KoiosRuntime (evaluateLocally)
import Cardano.Ledger.Api.PParams (ppProtocolVersionL)
import Cardano.Ledger.BaseTypes (ProtVer (..))
import Cardano.Ledger.Binary (getVersion)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult, Provider (..))
import Cardano.Slotting.Slot (EpochNo (..), EpochSize (..))
import Cardano.Slotting.Time (mkSlotLength)
import Codec.Serialise (serialise)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (Value (..), eitherDecodeFileStrict', encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text.Encoding (decodeUtf8)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Word (Word64)
import Lens.Micro ((^.))
import Ouroboros.Consensus.Block (GenesisWindow (..))
import Ouroboros.Consensus.HardFork.History.EraParams (EraParams (..), SafeZone (..), pattern NoPerasEnabled)
import Ouroboros.Consensus.HardFork.History.Summary (
    Bound (..),
    EraEnd (..),
    EraSummary (..),
    initBound,
    mkUpperBound,
 )
import Singular.Registry.NetworkTime (NetworkTime, NetworkTimeManifest (..), validateNetworkTime)
import System.FilePath ((</>))

{- | What the node says of the transaction, and what the local evaluation says of it, over the
protocol parameters and the outputs the node holds.
-}
evaluationsOf ::
    Provider IO ->
    -- | the directory of the genesis the node was started from
    FilePath ->
    -- | the instant the node started, in POSIX milliseconds
    Integer ->
    ConwayTx ->
    IO (EvaluateTxResult ConwayEra, EvaluateTxResult ConwayEra)
evaluationsOf provider genesisDirectory startMs signed = do
    parameters <- queryProtocolParams provider
    time <- devnetTime genesisDirectory startMs (getVersion (pvMajor (parameters ^. ppProtocolVersionL)))
    nodeSays <- evaluateTx provider signed
    localSays <- evaluateLocally time (pure parameters) (queryUTxOByTxIn provider) signed
    pure (nodeSays, localSays)

devnetTime :: FilePath -> Integer -> Word64 -> IO NetworkTime
devnetTime genesisDirectory startMs major = do
    (manifest, genesis, history) <- devnetSource genesisDirectory startMs major
    either (fail . ("the devnet time does not validate: " <>) . show) pure (validateNetworkTime 42 manifest genesis history)

{- | The files of the devnet's time source, as public Singular reads a directory of them: the manifest, the genesis
and the era history, built from the genesis the node runs on.
-}
writeDevnetTimeSource :: FilePath -> Integer -> Word64 -> FilePath -> IO ()
writeDevnetTimeSource genesisDirectory startMs major target = do
    (manifest, genesis, history) <- devnetSource genesisDirectory startMs major
    BS.writeFile (target </> "shelley-genesis.json") genesis
    BS.writeFile (target </> "era-history.cbor") history
    LBS.writeFile (target </> "time-manifest.json") . encode $
        object
            [ "networkMagic" .= timeNetworkMagic manifest
            , "systemStartMs" .= timeSystemStartMs manifest
            , "genesisSha256" .= hex (timeGenesisSha256 manifest)
            , "eraHistorySha256" .= hex (timeEraHistorySha256 manifest)
            , "horizonSlot" .= timeHorizonSlot manifest
            , "protocolMajor" .= timeProtocolMajor manifest
            , "sourceIdentity" .= timeSourceIdentity manifest
            ]
  where
    hex bytes = decodeUtf8 (convertToBase Base16 bytes)

devnetSource :: FilePath -> Integer -> Word64 -> IO (NetworkTimeManifest, ByteString, ByteString)
devnetSource genesisDirectory startMs major = do
    shelley <-
        eitherDecodeFileStrict' (genesisDirectory </> "shelley-genesis.json")
            >>= either (fail . ("the genesis does not read: " <>)) pure
    slotSeconds <- number "slotLength" shelley
    epochLength <- floor <$> number "epochLength" shelley
    security <- number "securityParam" shelley
    coefficient <- number "activeSlotsCoeff" shelley
    let genesis =
            LBS.toStrict . encode $
                object
                    [ "networkMagic" .= (42 :: Int)
                    , "systemStart" .= posixSecondsToUTCTime (fromInteger startMs / 1000)
                    , "securityParam" .= (floor security :: Integer)
                    , "activeSlotsCoeff" .= (fromRational coefficient :: Double)
                    , "epochLength" .= (epochLength :: Word64)
                    ]
        params =
            EraParams
                { eraEpochSize = EpochSize epochLength
                , eraSlotLength = mkSlotLength (fromRational slotSeconds)
                , eraSafeZone = StandardSafeZone epochLength
                , eraGenesisWin = GenesisWindow epochLength
                , eraPerasRoundLength = NoPerasEnabled
                }
        end = mkUpperBound params initBound (EpochNo 1_000_000)
        history = LBS.toStrict (serialise [EraSummary initBound (EraEnd end) params])
        manifest =
            NetworkTimeManifest
                42
                startMs
                (digest genesis)
                (digest history)
                (boundSlot end)
                major
                "the devnet's own genesis and start, one era from slot zero"
    pure (manifest, genesis, history)
  where
    digest :: ByteString -> ByteString
    digest bytes = convert (hash bytes :: Digest SHA256)
    number key shelley = case shelley of
        Object fields -> case KeyMap.lookup (Key.fromString key) fields of
            Just (Number n) -> pure (toRational n)
            _ -> fail ("the genesis has no number " <> key)
        _ -> fail "the genesis is not an object"
