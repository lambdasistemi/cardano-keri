{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

{- |
Module      : Cardano.KERI.Deployment.TestNetworkTime
Description : A network time of a test network, in the form Singular reads a pinned one

Singular's windows are computed from a pinned network time: a manifest, a genesis
and an era history, all bound by their hashes. A test of the windows needs
networks whose slots and horizons it chooses, so this builds the three from the
numbers that matter: the slot length, the epoch's length, the security
parameter, the active slots coefficient and the instant of slot zero, and
optionally a later era with another slot length. The network time is of magic 42,
open at its end, as Singular's own devnet time is.
-}
module Cardano.KERI.Deployment.TestNetworkTime (
    TestNetwork (..),
    testTimeSource,
    testNetworkTime,
    writeTimeSource,
) where

import Cardano.Slotting.Slot (EpochNo (..), EpochSize (..))
import Cardano.Slotting.Time (mkSlotLength)
import Codec.Serialise (serialise)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (encode, object, (.=))
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text.Encoding (decodeUtf8)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Word (Word64)
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
import Singular.Registry.TimeSource (TimeSource (..))
import System.FilePath ((</>))

-- | The numbers of a test network.
data TestNetwork = TestNetwork
    { slotSeconds :: Rational
    , epochLength :: Word64
    , securityParam :: Integer
    , activeSlotsCoeff :: Double
    , zeroMs :: Integer
    -- ^ the instant of slot zero, in POSIX milliseconds
    , laterEra :: Maybe (Word64, Rational)
    {- ^ a second era from the end of the epoch given, with its own slot length in seconds: the first era's epochs
    are the genesis's, the second era's are of the same length
    -}
    }

-- | The time source of the network.
testTimeSource :: TestNetwork -> TimeSource
testTimeSource network = TimeSource (manifest network) (genesis network) (history network)

-- | The validated network time of the network.
testNetworkTime :: TestNetwork -> IO NetworkTime
testNetworkTime network = case testTimeSource network of
    TimeSource manifest' genesis' history' ->
        either (fail . ("the test network time does not validate: " <>) . show) pure (validateNetworkTime 42 manifest' genesis' history')

-- | The files of a time source, as public Singular reads a directory of them.
writeTimeSource :: FilePath -> TestNetwork -> IO ()
writeTimeSource directory network = do
    BS.writeFile (directory </> "shelley-genesis.json") (genesis network)
    BS.writeFile (directory </> "era-history.cbor") (history network)
    let m = manifest network
    LBS.writeFile (directory </> "time-manifest.json") . encode $
        object
            [ "networkMagic" .= timeNetworkMagic m
            , "systemStartMs" .= timeSystemStartMs m
            , "genesisSha256" .= hex (timeGenesisSha256 m)
            , "eraHistorySha256" .= hex (timeEraHistorySha256 m)
            , "horizonSlot" .= timeHorizonSlot m
            , "protocolMajor" .= timeProtocolMajor m
            , "sourceIdentity" .= timeSourceIdentity m
            ]
  where
    hex bytes = decodeUtf8 (convertToBase Base16 bytes)

genesis :: TestNetwork -> ByteString
genesis network =
    LBS.toStrict . encode $
        object
            [ "networkMagic" .= (42 :: Int)
            , "systemStart" .= posixSecondsToUTCTime (fromInteger (zeroMs network) / 1000)
            , "securityParam" .= securityParam network
            , "activeSlotsCoeff" .= activeSlotsCoeff network
            , "epochLength" .= epochLength network
            ]

params :: Rational -> TestNetwork -> EraParams
params seconds network =
    EraParams
        { eraEpochSize = EpochSize (epochLength network)
        , eraSlotLength = mkSlotLength (fromRational seconds)
        , eraSafeZone = StandardSafeZone (epochLength network)
        , eraGenesisWin = GenesisWindow (epochLength network)
        , eraPerasRoundLength = NoPerasEnabled
        }

-- | The eras: one from slot zero, or two, the second beginning where the first ends.
summaries :: TestNetwork -> [EraSummary]
summaries network = case laterEra network of
    Nothing -> [EraSummary initBound (EraEnd (mkUpperBound first initBound (EpochNo 1_000_000))) first]
    Just (epoch, seconds) ->
        let changed = mkUpperBound first initBound (EpochNo epoch)
            second = params seconds network
         in [ EraSummary initBound (EraEnd changed) first
            , EraSummary changed (EraEnd (mkUpperBound second changed (EpochNo 1_000_000))) second
            ]
  where
    first = params (slotSeconds network) network

end :: TestNetwork -> Bound
end network = case reverse (summaries network) of
    EraSummary _ (EraEnd bound) _ : _ -> bound
    _ -> initBound

history :: TestNetwork -> ByteString
history network = LBS.toStrict (serialise (summaries network))

manifest :: TestNetwork -> NetworkTimeManifest
manifest network =
    NetworkTimeManifest
        42
        (zeroMs network)
        (digest (genesis network))
        (digest (history network))
        (boundSlot (end network))
        11
        "a test network"
  where
    digest :: ByteString -> ByteString
    digest bytes = convert (hash bytes :: Digest SHA256)
