{- |
Module      : Cardano.KERI.Deployment.RegistryWindow
Description : The validity end of a deployment's transactions, from public Singular's window

Every transaction of @ckeri registry deploy@ carries a finite, exclusive upper slot,
on the node socket and on Koios alike, and it is public Singular's: its window from
the tip over its usual span, with its pinned network time converting the instant an
hour after the tip's slot start to a slot and its horizon cutting it short. Nothing
here is a window rule of its own. What differs is only where the tip is read, and
the one session Singular's window is asked of holds that tip and the network time
and nothing else.
-}
module Cardano.KERI.Deployment.RegistryWindow (
    resolveTimeSource,
    singularWindow,
    koiosValidityEnd,
    installNodeWindow,
    installNodeWindowWith,
) where

import Cardano.KERI.Deployment.KoiosRuntime (wholeAnswers)
import Cardano.KERI.Deployment.RegistryChain (Observation (..), RegistryRuntime (..), ValidityEnd (..))
import Cardano.Node.Client.Provider (SlotNo)
import Control.Exception (Exception, throwIO)
import Control.Tracer (nullTracer)
import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Singular.Provider.Koios.Client (Koios)
import Singular.Provider.Koios.Client qualified as Client
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.Evidence (Evidenced (..), NoWitness, SessionBinding (..), SessionId (..))
import Singular.Registry.LedgerProvider (
    HistoryFailure (..),
    Network (..),
    ReadFailure (..),
    Session (..),
    TipObservation (..),
 )
import Singular.Registry.NetworkTime (validateNetworkTime)
import Singular.Registry.TimeSource (TimeSource (..), loadPinnedSource)
import Singular.State.Assemble (usualSpan, windowFromTip)

{- | The network time of a network: the directory given, as public Singular reads it, and without one the pinned
package of preprod. The command line gives the directory (its option, else the variable), and nothing here reads the
environment.
-}
resolveTimeSource :: Word32 -> Maybe FilePath -> IO (Either ReadFailure TimeSource)
resolveTimeSource = loadPinnedSource

{- | The end of a transaction built now: Singular's @windowFromTip session usualSpan@ over the network time given
and the tip slot as the caller reads it. No usable window is the answer of the window, not a failure; what cannot
be read (the time source, the tip) is a failure, before anything is built.
-}
singularWindow :: IO (Either ReadFailure TimeSource) -> Network -> IO SlotNo -> IO ValidityEnd
singularWindow loadSource network readTip = do
    window <- windowFromTip (session loadSource network readTip) usualSpan
    pure $ case window of
        Just (_, upper) -> EndAt upper
        Nothing -> NoUsableWindow

{- | The same, over the tip of a Koios provider. The tip is read under the same whole-or-named rule as every other read
of the deployment: an answer that signals it is partial is refused, and no window is made of it.
-}
koiosValidityEnd :: Koios IO -> IO (Either ReadFailure TimeSource) -> Network -> IO ValidityEnd
koiosValidityEnd client loadSource network =
    singularWindow loadSource network $
        Client.tip whole >>= either (throwIO . Unreadable . T.pack . show) (pure . Wire.tipSlot)
  where
    whole = client{Client.koiosTransport = wholeAnswers (Client.koiosTransport client)}

{- | A runtime of the node socket with its end from the same window over the node's own tip, over the network time
of the network its command was given.
-}
installNodeWindow :: Int -> Maybe FilePath -> RegistryRuntime -> RegistryRuntime
installNodeWindow magic time = installNodeWindowWith (resolveTimeSource (fromIntegral magic) time) (Network (fromIntegral magic))

-- | The same over the time source given.
installNodeWindowWith :: IO (Either ReadFailure TimeSource) -> Network -> RegistryRuntime -> RegistryRuntime
installNodeWindowWith loadSource network runtime =
    runtime{rtValidityEnd = singularWindow loadSource network (obsTipSlot <$> rtObserve runtime)}

-- | A tip that cannot be read.
newtype Unreadable = Unreadable Text
    deriving stock (Show)

instance Exception Unreadable

{- | The one session the window is asked of: the tip the caller reads and the network time of the source, and
no other read.
-}
session :: IO (Either ReadFailure TimeSource) -> Network -> IO SlotNo -> Session NoWitness IO
session loadSource network readTip =
    Session
        { sessionNetwork = network
        , sessionId = SessionId "deployment-window"
        , sessionBinding = Unbound
        , sessionTracer = nullTracer
        , sessionEvaluated = \_ -> pure ()
        , servedNetwork = unavailable
        , outputs = const unavailable
        , protocolParameters = unavailable
        , tipObservation = do
            slot <- readTip
            pure (Right (Evidenced (TipObservation slot mempty 0 0) Nothing))
        , networkTime = do
            source <- loadSource
            pure $ do
                TimeSource manifest genesis eras <- source
                let Network magic = network
                first NetworkTimeRefusal (fmap (`Evidenced` Nothing) (validateNetworkTime magic manifest genesis eras))
        , scriptRegistered = const unavailable
        , mintRecord = const unavailable
        , history = \_ _ -> pure (Left (HistoryReadFailure (BackendReadFailure "the window reads no history")))
        , inclusion = const unavailable
        }
  where
    unavailable = pure (Left (BackendReadFailure "the window reads nothing but the tip and the network time"))
