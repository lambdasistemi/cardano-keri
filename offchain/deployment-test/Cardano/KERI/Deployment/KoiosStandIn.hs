{- |
Module      : Cardano.KERI.Deployment.KoiosStandIn
Description : A loopback stand-in for the Koios service, scripted per request

A small HTTP server on the loopback interface. Every request it receives is
logged (method, path, headers, body, arrival time) and answered by a script
that is given how many requests came to the same path before it. A reply may be
held back for a while, which is how a service that does not answer in time is
played. Nothing here reaches a network beyond the machine.
-}
module Cardano.KERI.Deployment.KoiosStandIn (
    Seen (..),
    Reply (..),
    Script,
    answering,
    cutOff,
    silent,
    withStandIn,
    withStandInAt,
    withStandInClosed,
) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (ErrorCall (..), bracket, throwIO)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (byteString)
import Data.ByteString.Lazy qualified as BSL
import Data.CaseInsensitive qualified as CI
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, getCurrentTime)
import Data.Word (Word8)
import Network.HTTP.Types (mkStatus)
import Network.Socket (
    Family (AF_INET),
    SockAddr (SockAddrInet),
    SocketOption (ReuseAddr),
    SocketType (Stream),
    bind,
    close,
    defaultProtocol,
    listen,
    setSocketOption,
    socket,
    socketPort,
    tupleToHostAddress,
 )
import Network.Wai (
    Application,
    rawPathInfo,
    requestHeaders,
    requestMethod,
    responseLBS,
    responseStream,
    strictRequestBody,
 )
import Network.Wai.Handler.Warp (defaultSettings, runSettingsSocket, withApplication)

-- | One request the stand-in received.
data Seen = Seen
    { seenMethod :: !Text
    , seenPath :: !Text
    -- ^ the path below @/api/v1@
    , seenHeaders :: ![(Text, Text)]
    -- ^ header names in lower case
    , seenBody :: !ByteString
    , seenAt :: !UTCTime
    }
    deriving stock (Show)

-- | An answer: how long it is held back, its status, its headers, its body.
data Reply = Reply
    { replyAfter :: !Double
    -- ^ seconds before the answer is sent
    , replyStatus :: !Int
    , replyHeaders :: ![(Text, Text)]
    , replyBody :: !ByteString
    , replyCuts :: !Bool
    -- ^ the connection is dropped after the body, which is shorter than announced
    }

{- | The answer to a request, given the request and how many requests came to
its path before it.
-}
type Script = Seen -> Int -> Reply

-- | An answer sent at once.
answering :: Int -> ByteString -> Reply
answering status body = Reply 0 status [] body False

{- | An answer that announces more bytes than it sends and then drops the
connection: the body arrives cut off.
-}
cutOff :: ByteString -> Reply
cutOff body =
    Reply 0 200 [("Content-Length", T.pack (show (BS.length body + 100)))] body True

-- | A service that takes the request and does not answer in any useful time.
silent :: Reply
silent = Reply 30 200 [] "" False

{- | Run the stand-in on a free loopback port and hand the action the base URL
(ending in @/api/v1@) and a reading of the request log.
-}
withStandIn :: Script -> (Text -> IO [Seen] -> IO a) -> IO a
withStandIn script action = do
    logRef <- newIORef []
    withApplication (pure (application logRef script)) $ \port ->
        action (baseUrl port) (readIORef logRef)

{- | The same stand-in, bound to one loopback address of the machine (on
Linux the whole @127.0.0.0/8@ answers locally), so that a redirect to it names
another host string than the one it came from.
-}
withStandInAt ::
    (Word8, Word8, Word8, Word8) ->
    Script ->
    (Text -> IO [Seen] -> IO a) ->
    IO a
withStandInAt address script action = do
    logRef <- newIORef []
    bracket opened close $ \sock -> do
        port <- socketPort sock
        bracket
            (forkIO (runSettingsSocket defaultSettings sock (application logRef script)))
            killThread
            $ \_ -> action (baseUrlAt address (fromIntegral port)) (readIORef logRef)
  where
    opened = do
        sock <- socket AF_INET Stream defaultProtocol
        setSocketOption sock ReuseAddr 1
        bind sock (SockAddrInet 0 (tupleToHostAddress address))
        listen sock 128
        pure sock

{- | The base URL of a port nothing listens on any more: the port was free, the
stand-in ran on it and has stopped.
-}
withStandInClosed :: (Text -> IO a) -> IO a
withStandInClosed action = do
    url <- withStandIn (\_ _ -> answering 200 "") (\base _ -> pure base)
    action url

baseUrl :: Int -> Text
baseUrl = baseUrlAt (127, 0, 0, 1)

baseUrlAt :: (Word8, Word8, Word8, Word8) -> Int -> Text
baseUrlAt (a, b, c, d) port =
    "http://"
        <> T.intercalate "." (map (T.pack . show) [a, b, c, d])
        <> ":"
        <> T.pack (show port)
        <> "/api/v1"

application :: IORef [Seen] -> Script -> Application
application logRef script request reply = do
    body <- BSL.toStrict <$> strictRequestBody request
    now <- getCurrentTime
    let path = TE.decodeUtf8 (rawPathInfo request)
        seen =
            Seen
                { seenMethod = TE.decodeUtf8 (requestMethod request)
                , seenPath = fromMaybe path (T.stripPrefix "/api/v1" path)
                , seenHeaders =
                    [ (T.toLower (TE.decodeUtf8 (CI.original name)), TE.decodeUtf8 value)
                    | (name, value) <- requestHeaders request
                    ]
                , seenBody = body
                , seenAt = now
                }
    before <-
        atomicModifyIORef' logRef $ \earlier ->
            (earlier <> [seen], length (filter ((== seenPath seen) . seenPath) earlier))
    let Reply{..} = script seen before
    threadDelay (round (replyAfter * 1_000_000))
    let status = mkStatus replyStatus ""
        headers = [(CI.mk (TE.encodeUtf8 name), TE.encodeUtf8 value) | (name, value) <- replyHeaders]
    reply $
        if replyCuts
            then responseStream status headers $ \write flush -> do
                write (byteString replyBody)
                flush
                throwIO (ErrorCall "the stand-in drops the connection")
            else responseLBS status headers (BSL.fromStrict replyBody)
