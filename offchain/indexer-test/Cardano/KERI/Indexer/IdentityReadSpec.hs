{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.IdentityReadSpec
Description : The registry service's identity read over its real application (#353)

Drives the release-identity query application over a real in-memory store with
the registry's outputs seeded, and reads the HTTP answer of @GET /identity/{aid}@.
Every expected value is obtained from a producer, never typed here: the amounts
from 'heldValue', the registry and the release identities from the release
identity's own accessors, the key state from the service's own checkpoint
encoder, the failed clauses of the consumer result from 'consumableHolding' over
an observed output built from the seeded output, and the 503 body from the
service's own checkpoint route in the same state. Each refusal is reached by a
single change to a state that is otherwise answered, with two AIDs wherever a
count matters, at two chain points and with output indexes other than zero.
-}
module Cardano.KERI.Indexer.IdentityReadSpec (spec) where

import Cardano.KERI.AID.Application (
    Credential (..),
    OutputReference (..),
    RegistryIdentity (..),
 )
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..), KeyMaterial (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.AID.Checkpoint.Value (heldValue)
import Cardano.KERI.AID.Consumer (
    Clause,
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    consumableHolding,
 )
import Cardano.KERI.AID.Release (ReleaseIdentity (..), registryIdentityOf, releaseContext, releaseEnvironment)
import Cardano.KERI.Indexer.App (decodePolicyId)
import Cardano.KERI.Indexer.Codecs (checkpointAddressOf)
import Cardano.KERI.Indexer.Query.Server (
    ReleaseQueryHandle (..),
    mkQueryApplication,
    mkReleaseQueryApplication,
 )
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.KERI.Indexer.Query.Types (CheckpointData (..), hexBytes, qb64Witness)
import Cardano.KERI.Indexer.ReleaseFixtures
import Cardano.Node.Client.N2C.Reconnect (DisconnectInfo (..), UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (
    UtxoOp (..),
    applyAtSlot,
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Serialise (serialise)
import Control.Monad (unless, when)
import Data.Aeson (Object, Result (..), Value (..), decode, fromJSON, toJSON)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BSL
import Data.Char (isDigit, toLower)
import Data.Foldable (toList)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, sort)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word64)
import Database.KV.Transaction (RunTransaction (..))
import Network.HTTP.Types (statusCode)
import Network.Wai (Application, defaultRequest)
import Network.Wai.Test (SResponse (..), request, runSession, setPath)
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotSatisfy, shouldSatisfy)

poisoned :: CheckpointDatumV2 -> CheckpointDatumV2
poisoned l@Live{} = l{lvPoisoned = True}
poisoned other = other

toppedUp :: CheckpointDatumV2 -> CheckpointDatumV2
toppedUp l@Live{} = l{lvToppedUp = True}
toppedUp other = other

rawA, rawB :: ByteString
rawA = BS.replicate 32 0x31
rawB = BS.replicate 32 0x32

boardAddress :: Indexer.Address
boardAddress = Indexer.Address (BS.replicate 29 0x21)

-- | The point of the chain a store was committed at: its slot and its block hash.
data Chain = Chain {chainSlot :: Word64, chainHash :: ByteString}

chainOne, chainTwo :: Chain
chainOne = Chain 100 (BS.replicate 32 0x0c)
chainTwo = Chain 4_242 (BS.replicate 32 0xab)

-- | A readiness of a connected node whose tip is this many slots ahead of the chain's slot.
connectedAt :: Chain -> Word64 -> Readiness
connectedAt chain lag = tipAt chain (chainSlot chain + lag)

tipAt :: Chain -> Word64 -> Readiness
tipAt chain tip =
    Readiness
        { rProcessedSlot = Just (Indexer.SlotNo (chainSlot chain))
        , rTipSlot = Just (Indexer.SlotNo tip)
        , rUpstream = UpstreamConnected
        , rUpdatedAt = UTCTime (fromGregorian 2026 1 1) 0
        }

disconnected :: Chain -> Readiness
disconnected chain = (connectedAt chain 0){rUpstream = UpstreamDisconnected DisconnectInfo{diReason = "injected disconnect", diAttempt = 1, diSinceMs = 0}}

-- | A store operation creating an output of the release's validator at output index @ix@ of a transaction.
createAt :: Int -> Word64 -> ReleaseIdentity -> Indexer.TxOut -> UtxoOp
createAt n ix ri = UtxoCreate (Indexer.TxIn (BS.replicate 32 (fromIntegral n)) (fromIntegral ix)) (checkpointAddressOf ri)

data Mode = ReleaseMode | ManifestMode

-- | The answers (status code and body) of the application to these paths over a store holding these operations.
answers :: Mode -> Integer -> Chain -> ReleaseIdentity -> Readiness -> [UtxoOp] -> [String] -> IO [(Int, Value)]
answers mode maxLag chain ri readiness ops paths =
    withInMemoryIndexerRunner $ \handle runner -> do
        applyAtSlot handle (Indexer.SlotNo (chainSlot chain)) (Indexer.BlockHash (chainHash chain)) ops
        application <- applicationOver ri maxLag readiness mode runner
        mapM (answer application) paths

applicationOver :: ReleaseIdentity -> Integer -> Readiness -> Mode -> RunTransaction IO cf Cols op -> IO Application
applicationOver ri maxLag readiness mode runner = do
    policy <- either (fail . ("policy: " <>)) pure (decodePolicyId (hexBytes (rlStatePolicy (riRelease ri))))
    let query = QueryHandle runner (checkpointAddressOf ri) policy boardAddress (pure readiness)
    pure $ case mode of
        ReleaseMode -> mkReleaseQueryApplication (ReleaseQueryHandle ri query maxLag)
        ManifestMode -> mkQueryApplication query

answer :: Application -> String -> IO (Int, Value)
answer application path = do
    response <- runSession (request (setPath defaultRequest (BC.pack path))) application
    let body = BSL.toStrict (simpleBody response)
    pure (statusCode (simpleStatus response), fromMaybe (String (TE.decodeUtf8 body)) (decode (BSL.fromStrict body)))

-- | A ceiling no lag of this specification reaches: the rows that are not about the ceiling run under it.
farCeiling :: Integer
farCeiling = 1_000_000

releaseAnswers :: Chain -> ReleaseIdentity -> Readiness -> [UtxoOp] -> [String] -> IO [(Int, Value)]
releaseAnswers = answers ReleaseMode farCeiling

-- | The answers of a service started with this ceiling.
releaseAnswersAt :: Integer -> Chain -> ReleaseIdentity -> Readiness -> [UtxoOp] -> [String] -> IO [(Int, Value)]
releaseAnswersAt = answers ReleaseMode

at :: [Text] -> Value -> Maybe Value
at [] v = Just v
at (k : ks) (Object o) = KeyMap.lookup (Key.fromText k) o >>= at ks
at _ _ = Nothing

must :: [Text] -> Value -> IO Value
must path v = maybe (expectationFailure ("missing " <> T.unpack (T.intercalate "." path) <> " in " <> show v) >> fail "missing") pure (at path v)

number :: Value -> Maybe Integer
number v = case fromJSON v of
    Success n -> Just n
    Error _ -> Nothing

hexText :: ByteString -> Value
hexText = String . hexBytes

num :: [Text] -> Value -> Maybe Integer
num path v = at path v >>= number

-- | The sorted field names of the object at a path.
fields :: [Text] -> Value -> Maybe [Text]
fields path v = case at path v of
    Just (Object o) -> Just (sort (map Key.toText (KeyMap.keys o)))
    _ -> Nothing

reasonOf :: Value -> Text
reasonOf body = case at ["reason"] body of
    Just (String reason) -> reason
    _ -> ""

identityPath :: ByteString -> String
identityPath raw = "/identity/" <> BC.unpack (aidText raw)

-- | The consumer result the library gives the output the seeded fixture stands for.
expectedClauses :: ReleaseIdentity -> CheckpointDatumV2 -> ByteString -> Integer -> Integer -> [Clause]
expectedClauses ri facts raw window now =
    consumableHolding
        window
        now
        (releaseEnvironment ri)
        (releaseContext ri (aidText raw))
        ObservedOutput
            { ooCredential = ScriptCredential (riCheckpointValidator ri)
            , ooAssets = [asset ri raw]
            , ooDatum = DatumInline (BSL.toStrict (serialise (datumOf facts)))
            }

-- | The registry a release names, as the identity answers render it.
registryJson :: ReleaseIdentity -> Value
registryJson ri =
    let registry = registryIdentityOf ri
        OutputReference seedTx seedIx = riSeed ri
     in toJSON
            ( KeyMap.fromList
                [ ("state_policy" :: Key.Key, hexText (registryStatePolicy registry))
                , ("state_token_name", hexText (registryName registry))
                , ("seed", toJSON (KeyMap.fromList [("tx_id" :: Key.Key, hexText seedTx), ("output_index", toJSON seedIx)]))
                ]
            )

-- | The four identities of a release, as the identity answers render them.
releaseJson :: ReleaseIdentity -> Value
releaseJson ri =
    let release = riRelease ri
     in toJSON
            ( KeyMap.fromList
                [ ("application_policy" :: Key.Key, hexText (rlApplicationPolicy release))
                , ("application_credential", hexText (rlApplicationCredential release))
                , ("state_program", hexText (rlStateProgram release))
                , ("state_policy", hexText (rlStatePolicy release))
                ]
            )

-- | Key material with three current keys, two next keys under a weighted threshold and three witnesses.
richKeys :: KeyMaterial
richKeys =
    KeyMaterial
        { kmCurKeys = [BS.replicate 32 0x11, BS.replicate 32 0x12, BS.replicate 32 0x13]
        , kmCurThreshold = Unweighted 2
        , kmNextKeys = [BS.replicate 32 0x21, BS.replicate 32 0x22]
        , kmNextThreshold = Weighted [[Weight 1 2, Weight 1 2], [Weight 1 3]]
        , kmWitnesses = [BS.replicate 32 0x91, BS.replicate 32 0x92, BS.replicate 32 0x93]
        , kmToad = 2
        }

{- | The key state the service's own checkpoint encoder gives this key material:
the six key fields, as the identity read must render them.
-}
expectedKeyState :: KeyMaterial -> Value
expectedKeyState KeyMaterial{..} =
    case toJSON
        CheckpointData
            { chkTxId = BS.empty
            , chkOutputIndex = 0
            , chkSequence = 0
            , chkNativeSequence = 0
            , chkCurrentKeys = kmCurKeys
            , chkCurrentThreshold = kmCurThreshold
            , chkNextKeyDigests = kmNextKeys
            , chkNextThreshold = kmNextThreshold
            , chkWitnesses = kmWitnesses
            , chkWitnessThreshold = kmToad
            } of
        Object o -> Object (KeyMap.filterWithKey (\k _ -> Key.toText k `elem` keyFields) o)
        other -> other
  where
    keyFields = ["current_keys", "current_threshold", "next_key_digests", "next_threshold", "witnesses", "witness_threshold"]

spec :: Spec
spec = do
    identitySpec
    registryRoutesSpec

identitySpec :: Spec
identitySpec = describe "GET /identity/{aid} in the registry service" $ do
    describe "a live holding" $ do
        it "is answered with every fact, amount, identity, the output reference, the chain point and the freshness, one AID at a time" $
            mapM_
                ( \(ri, chain) -> do
                    let factsA = toppedUp (liveShaped richKeys (5, 2, 1_700_000_000_000) rawA)
                        factsB = poisoned (liveShaped (lvKeys (liveFacts rawB)) (9, 4, 1_650_000_000_000) rawB)
                    results <-
                        releaseAnswersAt
                            11
                            chain
                            ri
                            (connectedAt chain 7)
                            [createAt 1 3 ri (liveOutputWith ri factsA rawA 3), createAt 2 7 ri (liveOutputWith ri factsB rawB 5_000_000)]
                            [identityPath rawA, identityPath rawB]
                    mapM_
                        ( \((code, body), (n, ix, raw, facts, pool)) -> do
                            code `shouldBe` 200
                            fields [] body
                                `shouldBe` Just (sort ["status", "aid", "as_of_slot", "tip_lag_slots", "max_tip_lag_slots", "block_hash", "registry", "release", "holding", "consumer"])
                            num ["max_tip_lag_slots"] body `shouldBe` Just 11
                            at ["status"] body `shouldBe` Just (String "live")
                            at ["aid"] body `shouldBe` Just (String (TE.decodeUtf8 (aidText raw)))
                            num ["as_of_slot"] body `shouldBe` Just (fromIntegral (chainSlot chain))
                            num ["tip_lag_slots"] body `shouldBe` Just 7
                            at ["block_hash"] body `shouldBe` Just (hexText (chainHash chain))
                            let registry = registryIdentityOf ri
                                OutputReference seedTx seedIx = riSeed ri
                            fields ["registry"] body `shouldBe` Just (sort ["state_policy", "state_token_name", "seed"])
                            at ["registry", "state_policy"] body `shouldBe` Just (hexText (registryStatePolicy registry))
                            at ["registry", "state_token_name"] body `shouldBe` Just (hexText (registryName registry))
                            at ["registry", "seed", "tx_id"] body `shouldBe` Just (hexText seedTx)
                            num ["registry", "seed", "output_index"] body `shouldBe` Just seedIx
                            let release = riRelease ri
                            fields ["release"] body `shouldBe` Just (sort ["application_policy", "application_credential", "state_program", "state_policy"])
                            at ["release", "application_policy"] body `shouldBe` Just (hexText (rlApplicationPolicy release))
                            at ["release", "application_credential"] body `shouldBe` Just (hexText (rlApplicationCredential release))
                            at ["release", "state_program"] body `shouldBe` Just (hexText (rlStateProgram release))
                            at ["release", "state_policy"] body `shouldBe` Just (hexText (rlStatePolicy release))
                            fields ["holding"] body
                                `shouldBe` Just (sort ["tx_id", "output_index", "sn", "epoch", "poisoned", "frozen", "topped_up", "born_at", "refund_address", "deposit", "freeze_bond", "pool", "lovelace", "key_state"])
                            at ["holding", "tx_id"] body `shouldBe` Just (hexText (BS.replicate 32 (fromIntegral n)))
                            num ["holding", "output_index"] body `shouldBe` Just (fromIntegral ix)
                            num ["holding", "sn"] body `shouldBe` Just (lvSn facts)
                            num ["holding", "epoch"] body `shouldBe` Just (lvEpoch facts)
                            at ["holding", "poisoned"] body `shouldBe` Just (Bool (lvPoisoned facts))
                            at ["holding", "frozen"] body `shouldBe` Just (Bool (lvFrozen facts))
                            at ["holding", "topped_up"] body `shouldBe` Just (Bool (lvToppedUp facts))
                            num ["holding", "born_at"] body `shouldBe` Just (lvBornAt facts)
                            at ["holding", "refund_address"] body `shouldBe` Just (hexText (lvRefundTo facts))
                            num ["holding", "deposit"] body `shouldBe` Just (riDeposit ri)
                            num ["holding", "freeze_bond"] body `shouldBe` Just (if lvFrozen facts then 0 else riFreezeBond ri)
                            num ["holding", "pool"] body `shouldBe` Just pool
                            num ["holding", "lovelace"] body
                                `shouldBe` Just (heldValue (riMinimumAda ri) (riDeposit ri) (riFreezeBond ri) facts pool)
                            at ["holding", "key_state"] body `shouldBe` Just (expectedKeyState (lvKeys facts))
                        )
                        (zip results [(1 :: Int, 3 :: Word64, rawA, factsA, 3), (2, 7, rawB, factsB, 5_000_000)])
                )
                [(ri, chain) | ri <- [testRelease, otherRegistry], chain <- [chainOne, chainTwo]]
        it "is answered exactly while the tip lag is within the ceiling the service was started with: at each of three ceilings, a lag equal to it is live and one more is unavailable, at both chain points" $
            mapM_
                ( \(maxLag, chain) -> do
                    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
                    [(cWithin, bWithin)] <- releaseAnswersAt maxLag chain testRelease (connectedAt chain (fromIntegral maxLag)) ops [identityPath rawA]
                    (maxLag, cWithin) `shouldBe` (maxLag, 200)
                    at ["status"] bWithin `shouldBe` Just (String "live")
                    num ["tip_lag_slots"] bWithin `shouldBe` Just maxLag
                    num ["max_tip_lag_slots"] bWithin `shouldBe` Just maxLag
                    [(cBeyond, bBeyond)] <- releaseAnswersAt maxLag chain testRelease (connectedAt chain (fromIntegral maxLag + 1)) ops [identityPath rawA]
                    (maxLag, cBeyond) `shouldBe` (maxLag, 503)
                    at ["status"] bBeyond `shouldBe` Just (String "unavailable")
                    at ["ready"] bBeyond `shouldBe` Just (Bool False)
                    at ["error"] bBeyond `shouldBe` Just (String "service_unavailable")
                    num ["tip_lag_slots"] bBeyond `shouldBe` Just (maxLag + 1)
                    num ["max_tip_lag_slots"] bBeyond `shouldBe` Just maxLag
                    at ["holding"] bBeyond `shouldBe` Nothing
                    -- the reason names the lag and the ceiling, and no number of its own
                    let reason = T.unpack (reasonOf bBeyond)
                    reason `shouldSatisfy` isInfixOf (show (maxLag + 1))
                    reason `shouldSatisfy` isInfixOf (show maxLag)
                    reason `shouldNotSatisfy` isInfixOf "60"
                )
                [(maxLag, chain) | maxLag <- [0, 17, 400], chain <- [chainOne, chainTwo]]
    describe "unavailable is not absence" $ do
        it "is a 503 whose body says it is unavailable, with the reason and the readiness fields, when the node is disconnected, the tip is far behind or the store is ahead of the tip" $
            mapM_
                ( \chain -> do
                    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
                        maxLag = 17
                        -- name, readiness, lag, fragments of the reason, upstream, the code the other data routes answer and whether their body is the same one
                        cases =
                            [ ("disconnected", disconnected chain, Just 0, ["disconnected"], "disconnected", (503, True))
                            , ("lag beyond the ceiling", connectedAt chain 18, Just 18, ["18", "17"], "connected", (503, True))
                            , ("lag far beyond the ceiling", connectedAt chain 1_000, Just 1_000, ["1000", "17"], "connected", (503, True))
                            , ("store ahead of the tip", tipAt chain (chainSlot chain - 60), Nothing, ["ahead"], "connected", (503, True))
                            , ("no tip observed yet", (connectedAt chain 0){rTipSlot = Nothing}, Nothing, ["tip"], "connected", (503, True))
                            ]
                    mapM_
                        ( \(name, readiness, lag, fragments, upstream, (otherCode, sameBody)) -> do
                            [(code, body), (cCode, cBody)] <-
                                releaseAnswersAt maxLag chain testRelease readiness ops [identityPath rawA, "/checkpoint/" <> BC.unpack (aidText rawA)]
                            (name :: String, code) `shouldBe` (name, 503)
                            (name, at ["status"] body) `shouldBe` (name, Just (String "unavailable"))
                            (name, at ["ready"] body) `shouldBe` (name, Just (Bool False))
                            (name, at ["error"] body) `shouldBe` (name, Just (String "service_unavailable"))
                            (name, at ["upstream"] body) `shouldBe` (name, Just (String upstream))
                            (name, num ["as_of_slot"] body) `shouldBe` (name, Just (fromIntegral (chainSlot chain)))
                            (name, num ["tip_lag_slots"] body) `shouldBe` (name, lag)
                            (name, num ["max_tip_lag_slots"] body) `shouldBe` (name, Just maxLag)
                            mapM_ (\fragment -> (name, T.unpack (reasonOf body)) `shouldSatisfy` (\(_, r) -> fragment `isInfixOf` r)) fragments
                            (name, at ["holding"] body) `shouldBe` (name, Nothing)
                            -- the body of the other data routes in the same state, and besides the status
                            -- and the registry and the release the service follows and the ceiling in force
                            at ["status"] cBody `shouldBe` Nothing
                            at ["max_tip_lag_slots"] cBody `shouldBe` Nothing
                            (name, cCode) `shouldBe` (name, otherCode)
                            when sameBody (Just body `shouldBe` (withIdentity testRelease maxLag <$> Just cBody))
                        )
                        cases
                )
                [chainOne, chainTwo]
        it "is a 503 over a store that has recorded nothing yet, with no slot" $
            withInMemoryIndexerRunner $ \_ runner -> do
                application <- applicationOver testRelease farCeiling (connectedAt chainOne 0) ReleaseMode runner
                (code, body) <- answer application (identityPath rawA)
                code `shouldBe` 503
                at ["status"] body `shouldBe` Just (String "unavailable")
                at ["as_of_slot"] body `shouldBe` Just Null
        it "is a 200 unavailable, never a 404 or an empty success, when no live checkpoint of the registry is held for the AID" $ do
            let ops =
                    [ createAt 1 3 testRelease (liveOutput testRelease rawB False 0)
                    , createAt 2 4 testRelease (pendingOutput testRelease rawA (riMinimumAda testRelease))
                    , createAt 3 5 testRelease (liveOutput otherRegistry rawA False 0)
                    ]
            results <- releaseAnswers chainTwo testRelease (connectedAt chainTwo 0) ops [identityPath rawA, identityPath (BS.replicate 32 0x77)]
            mapM_
                ( \(code, body) -> do
                    code `shouldBe` 200
                    fields [] body `shouldBe` Just (sort ["status", "aid", "as_of_slot", "tip_lag_slots", "max_tip_lag_slots", "block_hash", "registry", "release", "reason"])
                    at ["block_hash"] body `shouldBe` Just (hexText (chainHash chainTwo))
                    at ["registry"] body `shouldBe` Just (registryJson testRelease)
                    at ["release"] body `shouldBe` Just (releaseJson testRelease)
                    at ["status"] body `shouldBe` Just (String "unavailable")
                    num ["as_of_slot"] body `shouldBe` Just 4_242
                    T.null (reasonOf body) `shouldBe` False
                    mapM_
                        (\word -> map toLower (T.unpack (reasonOf body)) `shouldNotSatisfy` isInfixOf word)
                        ["terminat", "convict", "never", "pending", "closed", "parked"]
                )
                results
        it "is a 200 unavailable, with a reason of its own, when more than one live checkpoint is held for the AID" $ do
            let ops =
                    [ createAt 1 3 testRelease (liveOutput testRelease rawA False 0)
                    , createAt 2 4 testRelease (liveOutput testRelease rawA False 2)
                    , createAt 3 5 testRelease (liveOutput testRelease rawB False 0)
                    ]
            [(codeA, bodyA), (codeB, bodyB)] <- releaseAnswers chainOne testRelease (connectedAt chainOne 0) ops [identityPath rawA, identityPath rawB]
            codeA `shouldBe` 200
            at ["status"] bodyA `shouldBe` Just (String "unavailable")
            at ["holding"] bodyA `shouldBe` Nothing
            T.null (reasonOf bodyA) `shouldBe` False
            codeB `shouldBe` 200
            at ["status"] bodyB `shouldBe` Just (String "live")
            [(_, bodyNone)] <- releaseAnswers chainOne testRelease (connectedAt chainOne 0) [] [identityPath rawA]
            reasonOf bodyA `shouldNotSatisfy` (== reasonOf bodyNone)
        it "is a 400 for an identifier that is no self-addressing identifier, with or without a holding" $ do
            let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
            results <-
                releaseAnswers
                    chainOne
                    testRelease
                    (connectedAt chainOne 0)
                    ops
                    ["/identity/notanaid", "/identity/" <> BC.unpack (aidText rawA) <> "x", "/identity/B" <> drop 1 (BC.unpack (aidText rawA))]
            map fst results `shouldBe` [400, 400, 400]
        it "reads the holdings and the chain point in exactly one store transaction, live, unavailable or not ready" $
            mapM_
                ( \(readiness, ops) -> do
                    count <- newIORef (0 :: Int)
                    withInMemoryIndexerRunner $ \handle runner -> do
                        applyAtSlot handle (Indexer.SlotNo 100) (Indexer.BlockHash (chainHash chainOne)) ops
                        let counting =
                                RunTransaction
                                    { runTransaction = \tx -> atomicModifyIORef' count (\n -> (n + 1, ())) >> runTransaction runner tx
                                    }
                        application <- applicationOver testRelease 17 readiness ReleaseMode counting
                        _ <- answer application (identityPath rawA)
                        pure ()
                    readIORef count >>= (`shouldBe` 1)
                )
                [ (connectedAt chainOne 0, [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)])
                , (connectedAt chainOne 0, [])
                , (connectedAt chainOne 18, [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)])
                ]
    describe "the ceiling in force" $ do
        it "is carried by every identity body: a live holding, the unavailable answer for an AID with no checkpoint or with two, and the not-ready answer, at three ceilings and both chain points" $
            mapM_
                ( \(maxLag, chain) -> do
                    let ops =
                            [ createAt 1 3 testRelease (liveOutput testRelease rawA False 0)
                            , createAt 2 4 testRelease (liveOutput testRelease rawB False 0)
                            , createAt 3 5 testRelease (liveOutput testRelease rawB False 2)
                            ]
                        paths = [identityPath rawA, identityPath rawB, identityPath (BS.replicate 32 0x77)]
                    ready <- releaseAnswersAt maxLag chain testRelease (connectedAt chain (fromIntegral maxLag)) ops paths
                    map fst ready `shouldBe` [200, 200, 200]
                    map (at ["status"] . snd) ready `shouldBe` map (Just . String) ["live", "unavailable", "unavailable"]
                    map (num ["max_tip_lag_slots"] . snd) ready `shouldBe` replicate 3 (Just maxLag)
                    map (num ["tip_lag_slots"] . snd) ready `shouldBe` replicate 3 (Just maxLag)
                    notReady <- releaseAnswersAt maxLag chain testRelease (connectedAt chain (fromIntegral maxLag + 1)) ops paths
                    map fst notReady `shouldBe` [503, 503, 503]
                    map (num ["max_tip_lag_slots"] . snd) notReady `shouldBe` replicate 3 (Just maxLag)
                    -- not even a disconnected node hides the ceiling in force
                    [(cDown, bDown)] <- releaseAnswersAt maxLag chain testRelease (disconnected chain) ops [identityPath rawA]
                    cDown `shouldBe` 503
                    num ["max_tip_lag_slots"] bDown `shouldBe` Just maxLag
                )
                [(maxLag, chain) | maxLag <- [0, 17, 400], chain <- [chainOne, chainTwo]]
        it "is unavailable, not live, when the upstream is connected and the store holds the AID but no tip was observed, whatever the ceiling, and a ceiling does not make an unknown tip known" $
            mapM_
                ( \(maxLag, chain) -> do
                    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
                        noTip = (connectedAt chain 0){rTipSlot = Nothing}
                    -- the control: the same store, a tip observed, is live under the same ceiling
                    [(cKnown, bKnown)] <- releaseAnswersAt maxLag chain testRelease (connectedAt chain 0) ops [identityPath rawA]
                    (maxLag, cKnown, at ["status"] bKnown) `shouldBe` (maxLag, 200, Just (String "live"))
                    [(code, body)] <- releaseAnswersAt maxLag chain testRelease noTip ops [identityPath rawA]
                    (maxLag, code) `shouldBe` (maxLag, 503)
                    at ["status"] body `shouldBe` Just (String "unavailable")
                    at ["holding"] body `shouldBe` Nothing
                    at ["tip_lag_slots"] body `shouldBe` Just Null
                    num ["as_of_slot"] body `shouldBe` Just (fromIntegral (chainSlot chain))
                    num ["max_tip_lag_slots"] body `shouldBe` Just maxLag
                    T.unpack (reasonOf body) `shouldSatisfy` isInfixOf "tip"
                )
                [(maxLag, chain) | maxLag <- [0, 400, 1_000_000], chain <- [chainOne, chainTwo]]
    describe "the consumer result" $ do
        it "is the library's verdict over the same holding, with the failed clauses, and never changes the status" $
            mapM_
                ( \(flags, window, now) -> do
                    let facts = liveWith flags rawA
                        ops = [createAt 1 3 testRelease (liveOutputWith testRelease facts rawA 0), createAt 2 4 testRelease (liveOutput testRelease rawB False 0)]
                        expected = expectedClauses testRelease facts rawA window now
                    [(code, body)] <-
                        releaseAnswers
                            chainOne
                            testRelease
                            (connectedAt chainOne 0)
                            ops
                            [identityPath rawA <> "?window_ms=" <> show window <> "&now_ms=" <> show now]
                    code `shouldBe` 200
                    at ["status"] body `shouldBe` Just (String "live")
                    at ["consumer", "evaluated"] body `shouldBe` Just (Bool True)
                    at ["consumer", "consumable"] body `shouldBe` Just (Bool (null expected))
                    at ["consumer", "failed_clauses"] body
                        `shouldBe` Just (toJSON [T.pack (show c) | c <- expected])
                )
                [ (flags, window, now)
                | flags <- [(f, p, t) | f <- [False, True], p <- [False, True], t <- [False, True]]
                , (window, now) <- [(60_000, 1_700_000_000_000 + 59_999), (60_000, 1_700_000_000_000 + 60_000), (0, 1_700_000_000_000)]
                ]
        it "is reported as not evaluated, with a reason, unless both window_ms and now_ms are given" $
            mapM_
                ( \suffix -> do
                    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
                    [(code, body)] <- releaseAnswers chainOne testRelease (connectedAt chainOne 0) ops [identityPath rawA <> suffix]
                    code `shouldBe` 200
                    at ["status"] body `shouldBe` Just (String "live")
                    at ["consumer", "evaluated"] body `shouldBe` Just (Bool False)
                    at ["consumer", "reason"] body `shouldSatisfy` (/= Nothing)
                    at ["consumer", "consumable"] body `shouldBe` Nothing
                )
                ["", "?window_ms=60000", "?now_ms=1700000000000"]
        it "is a 400 for a window or a time that is not a non-negative integer" $
            mapM_
                ( \suffix -> do
                    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
                    [(code, _)] <- releaseAnswers chainOne testRelease (connectedAt chainOne 0) ops [identityPath rawA <> suffix]
                    code `shouldBe` 400
                )
                ["?window_ms=abc&now_ms=1", "?window_ms=1&now_ms=-1", "?window_ms=1.5&now_ms=1"]
    describe "the manifest mode" $
        it "does not serve the identity route and says it is the manifest mode" $ do
            [(code, body)] <- answers ManifestMode farCeiling chainOne testRelease (connectedAt chainOne 0) [] [identityPath rawA]
            code `shouldBe` 404
            case at ["error"] body of
                Just (String message) -> T.unpack message `shouldSatisfy` isInfixOf "manifest mode"
                other -> expectationFailure ("no error message: " <> show other)
    describe "the published description" $
        it "describes the identity route: its parameters, and which body each of its 200, 400, 404 and 503 answers has" $ do
            description <- readSwagger
            path <- must ["paths", "/identity/{aid}", "get"] description
            names <- must ["parameters"] path
            case fromJSON names of
                Success parameters ->
                    [n | p <- parameters :: [Object], Just (String n) <- [KeyMap.lookup "name" p]]
                        `shouldBe` ["aid", "window_ms", "now_ms"]
                Error message -> expectationFailure ("parameters: " <> message)
            mapM_ (\code -> at ["responses", code] path `shouldSatisfy` (/= Nothing)) ["200", "400", "404", "503"]
            let ref name = Just (String ("#/components/schemas/" <> name))
                content code = ["responses", code, "content", "application/json", "schema"]
            at (content "200" <> ["oneOf"]) path
                `shouldBe` Just (toJSON [refTo name | name <- ["IdentityLiveResponse", "IdentityUnavailableResponse"]])
            at (content "503" <> ["$ref"]) path `shouldBe` ref "IdentityNotReadyResponse"
            mapM_
                (\(schema, status) -> at ["components", "schemas", schema, "properties", "status", "enum"] description `shouldBe` Just (toJSON [status :: Text]))
                [("IdentityLiveResponse", "live"), ("IdentityUnavailableResponse", "unavailable"), ("IdentityNotReadyResponse", "unavailable")]
            mapM_
                ( \(schema, property, target) ->
                    at ["components", "schemas", schema, "properties", property, "$ref"] description `shouldBe` ref target
                )
                [ ("IdentityLiveResponse", "registry", "IdentityRegistry")
                , ("IdentityLiveResponse", "release", "IdentityRelease")
                , ("IdentityLiveResponse", "holding", "IdentityHolding")
                , ("IdentityHolding", "key_state", "IdentityKeyState")
                ]
            -- the ceiling in force is a property of each of the three bodies, a whole number
            mapM_
                ( \schema -> do
                    at ["components", "schemas", schema, "properties", "max_tip_lag_slots", "type"] description `shouldBe` Just (String "integer")
                    at ["components", "schemas", schema, "required"] description
                        `shouldSatisfy` maybe False (\required -> toJSON ("max_tip_lag_slots" :: Text) `elem` arrayOf required)
                )
                ["IdentityLiveResponse", "IdentityUnavailableResponse", "IdentityNotReadyResponse"]
            -- and no number of its own is written in any text of the identity route or its bodies
            identitySchemas <- must ["components", "schemas"] description
            let identityTexts =
                    textsOf path
                        <> concat [textsOf schema | (name, schema) <- objectEntries identitySchemas, "Identity" `T.isPrefixOf` name]
            identityTexts `shouldSatisfy` (not . null)
            mapM_ (\text -> (text, T.unpack text) `shouldSatisfy` (\(_, t) -> not ("60" `isInfixOf` t))) identityTexts
  where
    refTo name = toJSON (KeyMap.fromList [("$ref" :: Key.Key, String ("#/components/schemas/" <> name))])
    arrayOf v = case v of
        Array items -> toList items
        _ -> []
    objectEntries v = case v of
        Object o -> [(Key.toText k, x) | (k, x) <- KeyMap.toList o]
        _ -> []
    readSwagger = do
        path <- getDataFileName "docs/assets/swagger/query-api.json"
        bytes <- BS.readFile path
        maybe (expectationFailure "query-api.json does not parse" >> fail "parse") pure (decode (BSL.fromStrict bytes))
    withIdentity ri maxLag v = case v of
        Object o ->
            Object
                ( KeyMap.insert "status" (String "unavailable") $
                    KeyMap.insert "max_tip_lag_slots" (toJSON maxLag) $
                        KeyMap.insert "registry" (registryJson ri) $
                            KeyMap.insert "release" (releaseJson ri) o
                )
        other -> other

-- ---------------------------------------------------------------------------
-- The ceiling governs every route of the registry mode

-- | The data routes a service in registry mode answers from the store, and /ready.
registryRoutes :: [(String, String)]
registryRoutes =
    [ ("ready", "/ready")
    , ("checkpoint", "/checkpoint/" <> BC.unpack (aidText rawA))
    , ("watchability", "/watchability/" <> BC.unpack (aidText rawA))
    , ("board list", "/board")
    , ("board entry", "/board/" <> BC.unpack (qb64Witness (BS.replicate 32 0x91)))
    ]

{- | What an answer says about readiness, exactly as its route builds it. @Just True@:
/ready answers 200 with @ready@ the Boolean true, any other route its ready answer, 200
with no error. @Just False@: /ready answers 200 with @ready@ the Boolean false and a reason;
every other route answers its typed 503, with exactly the fields of the not-ready body, @ready@
the Boolean false, the error tag, an upstream text and a reason text. @Nothing@: anything
else, such as a 500, a null, or a body of another shape.
-}
isReadyAnswer :: String -> (Int, Value) -> Maybe Bool
isReadyAnswer "ready" (200, body) = case (at ["ready"] body, at ["reason"] body) of
    (Just (Bool True), _) -> Just True
    (Just (Bool False), Just (String _)) -> Just False
    _ -> Nothing
isReadyAnswer "ready" _ = Nothing
isReadyAnswer _ (200, body) = if isJust (at ["error"] body) || isJust (at ["ready"] body) then Nothing else Just True
isReadyAnswer _ (503, body)
    | fields [] body == Just (sort ["ready", "as_of_slot", "tip_lag_slots", "upstream", "reason", "error"])
    , at ["ready"] body == Just (Bool False)
    , at ["error"] body == Just (String "service_unavailable")
    , Just (String _) <- at ["upstream"] body
    , Just (String _) <- at ["reason"] body =
        Just False
isReadyAnswer _ _ = Nothing

-- | The names of the fields of an answer that is a JSON object.
keysOf :: Value -> [Text]
keysOf body = fromMaybe [] (fields [] body)

-- | The texts of the descriptions and summaries of a part of the published description.
textsOf :: Value -> [Text]
textsOf v = case v of
    Object o -> concat [(if Key.toText k `elem` ["description", "summary"] then [t | String t <- [x]] else []) <> textsOf x | (k, x) <- KeyMap.toList o]
    Array items -> concatMap textsOf items
    _ -> []

-- | The sentences of a text.
sentencesOf :: Text -> [Text]
sentencesOf = filter (not . T.null) . map (T.dropWhileEnd (== '.') . T.strip) . T.splitOn ". "

{- | The sentences of these texts that give a figure (any run of digits) and do not
keep it to the manifest mode: a sentence that gives a figure must name the manifest
mode and must name neither the registry mode nor the ceiling.
-}
figureViolations :: [Text] -> [Text]
figureViolations texts =
    [ sentence
    | text <- texts
    , sentence <- sentencesOf text
    , T.any isDigit sentence
    , not (names "manifest" sentence) || names "registry" sentence || names "ceiling" sentence
    ]
  where
    names word sentence = word `T.isInfixOf` T.toLower sentence

{- | The texts of the parts of the published description that say when a service is
ready or what a readiness-bearing answer carries: the 200 answer of /ready, the 503
answer of each data route, the identity route and its bodies, and the ready response.
-}
readinessTexts :: Value -> [Text]
readinessTexts description =
    concat
        ( [textsOf v | Just v <- [at ["paths", "/ready", "get", "responses", "200"] description]]
            <> [ textsOf v
               | path <- ["/checkpoint/{aid}", "/watchability/{aid}", "/board", "/board/{witness_key}"]
               , Just v <- [at ["paths", path, "get", "responses", "503"] description]
               ]
            <> [textsOf v | Just v <- [at ["paths", "/identity/{aid}"] description]]
            <> [textsOf v | Just v <- [at ["components", "schemas", "ReadyResponse"] description]]
            <> [ textsOf v
               | Just (Object schemas) <- [at ["components", "schemas"] description]
               , (name, v) <- KeyMap.toList schemas
               , "Identity" `T.isPrefixOf` Key.toText name
               ]
        )

registryRoutesSpec :: Spec
registryRoutesSpec = describe "the ceiling of the registry service governs every route" $ do
    let ops = [createAt 1 3 testRelease (liveOutput testRelease rawA False 0)]
        routePaths = map snd registryRoutes
        answerAll mode maxLag chain readiness = answers mode maxLag chain testRelease readiness ops routePaths
    it "applies the ceiling, and nothing else, to /ready, the checkpoint, watchability and both board routes: ready at a lag equal to it, not ready at one more, at three ceilings and both chain points, with the reason naming the lag and the ceiling" $
        mapM_
            ( \(maxLag, chain) -> do
                within <- answerAll ReleaseMode maxLag chain (connectedAt chain (fromIntegral maxLag))
                beyond <- answerAll ReleaseMode maxLag chain (connectedAt chain (fromIntegral maxLag + 1))
                mapM_
                    ( \((name, _), inside, outside) -> do
                        ((name, maxLag), isReadyAnswer name inside) `shouldBe` ((name, maxLag), Just True)
                        ((name, maxLag), isReadyAnswer name outside) `shouldBe` ((name, maxLag), Just False)
                        num ["tip_lag_slots"] (snd outside) `shouldBe` Just (maxLag + 1)
                        num ["as_of_slot"] (snd outside) `shouldBe` Just (fromIntegral (chainSlot chain))
                        let reason = T.unpack (reasonOf (snd outside))
                        (name, reason) `shouldSatisfy` (\(_, r) -> show (maxLag + 1) `isInfixOf` r && show maxLag `isInfixOf` r)
                        (name, reason) `shouldSatisfy` (\(_, r) -> not ("60" `isInfixOf` r))
                        -- only /ready and the identity bodies carry the ceiling; the other routes keep their shapes:
                        -- the key is absent from the object, not null, on both sides of the boundary
                        mapM_
                            ( \answered ->
                                if name == "ready"
                                    then num ["max_tip_lag_slots"] (snd answered) `shouldBe` Just maxLag
                                    else do
                                        (name, fields [] (snd answered)) `shouldSatisfy` (isJust . snd)
                                        (name, keysOf (snd answered)) `shouldSatisfy` (\(_, keys) -> "max_tip_lag_slots" `notElem` keys)
                            )
                            [inside, outside]
                        unless (name == "ready") $ do
                            fst outside `shouldBe` 503
                            at ["error"] (snd outside) `shouldBe` Just (String "service_unavailable")
                    )
                    (zip3 registryRoutes within beyond)
            )
            [(maxLag, chain) | maxLag <- [0, 17, 400], chain <- [chainOne, chainTwo]]
    it "is not ready, on every route, when the standing is unknown whatever the ceiling: the node disconnected, no tip observed, or nothing recorded by the store" $
        mapM_
            ( \maxLag -> do
                let chain = chainOne
                    noTip = (connectedAt chain 0){rTipSlot = Nothing}
                mapM_
                    ( \(label, readiness, fragment) -> do
                        results <- answerAll ReleaseMode maxLag chain readiness
                        mapM_
                            ( \((name, _), result) -> do
                                ((label, name, maxLag), isReadyAnswer name result) `shouldBe` ((label, name, maxLag), Just False)
                                (label, name, T.unpack (reasonOf (snd result))) `shouldSatisfy` (\(_, _, r) -> fragment `isInfixOf` r)
                            )
                            (zip registryRoutes results)
                    )
                    [("disconnected" :: String, disconnected chain, "disconnected"), ("no tip", noTip, "tip")]
                -- a store that has recorded nothing yet
                withInMemoryIndexerRunner $ \_ runner -> do
                    application <- applicationOver testRelease maxLag (connectedAt chain 0) ReleaseMode runner
                    mapM_
                        ( \(name, path) -> do
                            result <- answer application path
                            ((name, maxLag), isReadyAnswer name result) `shouldBe` ((name, maxLag), Just False)
                            (name, at ["as_of_slot"] (snd result)) `shouldBe` (name, Just Null)
                        )
                        registryRoutes
            )
            [0, 400, 1_000_000]
    it "gives the same request a different answer in the two modes when the ceiling is not the manifest service's figure, in both directions: a ceiling below it makes a lag ready for the manifest service not ready, a ceiling above it the reverse" $
        mapM_
            ( \(maxLag, lag, registryReady, manifestReady) ->
                mapM_
                    ( \chain -> do
                        registry <- answerAll ReleaseMode maxLag chain (connectedAt chain lag)
                        manifest <- answerAll ManifestMode maxLag chain (connectedAt chain lag)
                        mapM_
                            ( \((name, _), r, m) -> do
                                ((name, maxLag, lag, "registry" :: String), isReadyAnswer name r) `shouldBe` ((name, maxLag, lag, "registry"), Just registryReady)
                                ((name, maxLag, lag, "manifest" :: String), isReadyAnswer name m) `shouldBe` ((name, maxLag, lag, "manifest"), Just manifestReady)
                            )
                            (zip3 registryRoutes registry manifest)
                    )
                    [chainOne, chainTwo]
            )
            [(17, 30, False, True), (400, 100, True, False)]
    it "leaves /ready of the manifest service as it is, with no ceiling field, and gives /ready of the registry service exactly one field more, the ceiling in force" $ do
        [(_, manifest)] <- answers ManifestMode farCeiling chainOne testRelease (connectedAt chainOne 3) ops ["/ready"]
        [(_, registry)] <- answers ReleaseMode 17 chainOne testRelease (connectedAt chainOne 3) ops ["/ready"]
        fields [] manifest `shouldBe` Just (sort ["ready", "as_of_slot", "tip_lag_slots", "upstream", "reason"])
        fields [] registry `shouldBe` Just (sort ["ready", "as_of_slot", "tip_lag_slots", "upstream", "reason", "max_tip_lag_slots"])
        num ["max_tip_lag_slots"] registry `shouldBe` Just 17
    it "describes the not-ready answers of every route per mode: a fixed figure is given for the manifest service only, and the registry service's limit is its ceiling" $ do
        description <- readSwagger
        let figures = concatMap (filter (T.any isDigit) . sentencesOf) (textsOf description)
            borne = readinessTexts description
        -- the control: the description does give a figure, the manifest service's
        figures `shouldSatisfy` (not . null)
        -- a figure is given in a sentence of the manifest mode that names neither the registry mode nor the ceiling
        figureViolations borne `shouldBe` []
        -- the rule can fail: a registry sentence with the figure of the other mode, or with another figure
        figureViolations ["Manifest mode uses its fixed limit. Registry mode uses a fixed ceiling of 60 slots."]
            `shouldBe` ["Registry mode uses a fixed ceiling of 60 slots"]
        figureViolations ["Manifest mode uses its fixed limit. Registry mode uses a fixed ceiling of 25 slots."]
            `shouldBe` ["Registry mode uses a fixed ceiling of 25 slots"]
        figureViolations ["In manifest mode the limit is a fixed 60 slots, in registry mode the ceiling."]
            `shouldBe` ["In manifest mode the limit is a fixed 60 slots, in registry mode the ceiling"]
        figureViolations ["A fixed limit of 60 slots."] `shouldBe` ["A fixed limit of 60 slots"]
        -- and it lets the right wording through
        figureViolations ["In manifest mode the limit is a fixed 60 slots. In registry mode it is the configured ceiling."] `shouldBe` []
        -- the same rule over the texts of the published file itself, with one registry sentence mutated
        figureViolations (map (<> " Registry mode uses a fixed ceiling of 60 slots.") (take 1 borne)) `shouldSatisfy` (not . null)
        -- every route that can be not ready says, besides, that the registry service's limit is its ceiling
        mapM_
            ( \(path, texts) -> do
                (path, texts) `shouldSatisfy` (\(_, ts) -> not (null ts))
                mapM_ (\text -> (path, text, "ceiling" `T.isInfixOf` T.toLower text) `shouldBe` (path, text, True)) texts
            )
            [ (path, notReadyTexts path description)
            | path <- ["/ready", "/checkpoint/{aid}", "/watchability/{aid}", "/board", "/board/{witness_key}"]
            ]
    it "describes the ceiling of /ready in the published description as a property of the registry service's answer only, optional, with no number of its own" $ do
        description <- readSwagger
        property <- must ["components", "schemas", "ReadyResponse", "properties", "max_tip_lag_slots"] description
        at ["type"] property `shouldBe` Just (String "integer")
        case at ["description"] property of
            Just (String text) -> do
                T.unpack text `shouldSatisfy` isInfixOf "registry"
                T.unpack text `shouldSatisfy` (not . isInfixOf "60")
            other -> expectationFailure ("no description: " <> show other)
        required <- must ["components", "schemas", "ReadyResponse", "required"] description
        elem (String "max_tip_lag_slots") (arrayOf required) `shouldBe` False
  where
    -- the texts that say when a route is not ready: the description of the 200 answer of /ready and the one of the 503 answer of the others
    notReadyTexts path description =
        [ t
        | Just (String t) <-
            [ at
                ( if path == "/ready"
                    then ["paths", T.pack path, "get", "responses", "200", "description"]
                    else ["paths", T.pack path, "get", "responses", "503", "description"]
                )
                description
            ]
        ]
    arrayOf v = case v of
        Array items -> toList items
        _ -> []
    readSwagger = do
        path <- getDataFileName "docs/assets/swagger/query-api.json"
        bytes <- BS.readFile path
        maybe (expectationFailure "query-api.json does not parse" >> fail "parse") pure (decode (BSL.fromStrict bytes))
