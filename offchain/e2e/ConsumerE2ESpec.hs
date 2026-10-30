{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : ConsumerE2ESpec
Description : Connected boundary for the consumer predicate (#343 slice 2)

Starts a protocol devnet and exercises the example relying contract
(@consumer_example@) that reads a candidate holding as a reference input and
spends only if the Lean's @consumableHoldingB@ holds for it.

Two labels bound what this proves:

* test interpretation, not the registry byte layout: the hash, codec,
  AID-to-key map and datum decoder are the declared test functions of
  @consumer_test_interpretation@; the token names below are recomputed here
  from that definition, not read back from the validator;
* seeded holding, not a registration journey: the holdings are minted by the
  test-only policy @consumer_seed_policy@ at a test application credential. The
  genuine registration journey belongs to #324.

One accepting transaction settles. Every refusal is a Phase-2 failure of the
consumer script: its transaction passes every ledger rule, carries no other
script, and is rejected by the node when that script evaluates false. The
refusals differ from the accepting transaction only in the holding they
reference.

The same journey runs a second time with the concrete identity bytes of the
Lean model (@consumer_identity_example@, @consumer_identity_bytes@): the
registry name, the key and the representative name are recomputed here from
the Lean layout, and checked against the vectors of
@lean/consumer-identity-vectors.json@ before they name anything on chain. The
datum decoder is still the declared test choice, and the holdings are still
seeded.
-}
module ConsumerE2ESpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, unless, when)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Short qualified as SBS
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word32, Word8)
import Lens.Micro ((&), (.~), (^.))
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import System.Timeout (timeout)
import Test.Hspec

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    vldtTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    coinTxOutL,
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Inject (..),
    Network (..),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..), unCoin)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId, TxIn (..))

import Cardano.Node.Client.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
    withDevnet,
 )
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))

import PlutusCore.Data qualified as PLC

import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.E2E.Mpf (blake2b256)
import Cardano.KERI.AID.E2E.Script (
    applyDataArgs,
    cageScriptAddr,
    computeScriptHash,
    extractCompiledCodeExact,
    loadBlueprint,
    mkCageScript,
 )

type Utxo = (TxIn, TxOut ConwayEra)

-- ---------------------------------------------------------------------------
-- The consumer's fixed context (declared test values)
-- ---------------------------------------------------------------------------

-- | Network discriminator carried by the context (devnet is a testnet).
contextNetwork :: Integer
contextNetwork = 0

-- | The intended AID.
intendedAid :: Integer
intendedAid = 42

-- | Checkpoint parameters: only @w@ is read; maturity is one time unit.
paramsData :: PLC.Data
paramsData = PLC.Constr 0 [PLC.I 3, PLC.I 2, PLC.I 1, PLC.I 1]

-- | The test application credential holdings are seeded at (28 bytes).
applicationCredential :: ByteString
applicationCredential = BS.replicate 28 0xaa

applicationPolicy :: ByteString
applicationPolicy = BS.replicate 28 0xcc

stateProgram :: ByteString
stateProgram = BS.replicate 28 0xbb

-- | The intended registry seed, and a rival registry's seed.
seedTx, rivalSeedTx :: ByteString
seedTx = BS.replicate 32 0xee
rivalSeedTx = BS.replicate 32 0xdd

-- ---------------------------------------------------------------------------
-- The declared test interpretation, written out for the off-chain side
-- ---------------------------------------------------------------------------

be8 :: Integer -> ByteString
be8 n = BS.pack [fromIntegral (n `shiftR` (8 * k)) | k <- [7, 6 .. 0]]

-- | @code(State seed)@ then @hash@: the registry asset name.
registryName :: ByteString -> ByteString
registryName tx = blake2b256 (BS.concat [BS.singleton 0, tx, be8 0])

-- | @hash(code(Active registry key))@: the representative asset name.
representativeName :: ByteString -> ByteString -> ByteString
representativeName statePolicy tx =
    blake2b256
        ( BS.concat
            [BS.singleton 1, statePolicy, registryName tx, be8 intendedAid]
        )

-- ---------------------------------------------------------------------------
-- Datum builders (Plutus data of the Aiken types)
-- ---------------------------------------------------------------------------

boolData :: Bool -> PLC.Data
boolData b = PLC.Constr (if b then 1 else 0) []

liveData :: Integer -> PLC.Data
liveData bornAt =
    PLC.Constr
        0
        [ PLC.I 0
        , PLC.I 0
        , boolData False
        , boolData False
        , PLC.I bornAt
        , PLC.I 7
        , PLC.I 5
        ]

data StateKind = Absent | Present | Parked | Pending | Convicted

stateData :: StateKind -> PLC.Data
stateData Absent = PLC.Constr 0 []
stateData Present = PLC.Constr 1 [liveData 0]
stateData Parked = PLC.Constr 2 [PLC.Constr 0 [PLC.I 0, PLC.I 0]]
stateData Pending = PLC.Constr 3 [PLC.Constr 0 [PLC.I 0, PLC.I 0]]
stateData Convicted = PLC.Constr 4 []

decodedDatum :: Integer -> StateKind -> PLC.Data
decodedDatum aid s = PLC.Constr 0 [PLC.I aid, stateData s]

-- ---------------------------------------------------------------------------
-- Scenarios
-- ---------------------------------------------------------------------------

data Scenario = Scenario
    { scName :: String
    , scRivalRegistry :: Bool
    , scQuantity :: Integer
    , scState :: StateKind
    }

accepting :: Scenario
accepting = Scenario "the eligible holding" False 1 Present

refusals :: [Scenario]
refusals =
    [ Scenario "a rival registry's token" True 1 Present
    , Scenario "quantity two" False 2 Present
    , Scenario "a parked holding" False 1 Parked
    , Scenario "a holding with termination pending" False 1 Pending
    , Scenario "a retired holding (convicted)" False 1 Convicted
    , Scenario "a retired holding (absent)" False 1 Absent
    ]

scenarios :: [Scenario]
scenarios = accepting : refusals

{- | What differs between the two connected runs: the consumer validator, the
AID the consumer fixes, how a representative asset is named from the state
policy and the seed transaction, and the scenarios.
-}
data Variant = Variant
    { vValidator :: Text
    -- ^ blueprint title of the consumer validator
    , vAid :: Integer
    , vRepresentativeName :: ByteString -> ByteString -> ByteString
    -- ^ state policy, seed transaction id
    , vScenarios :: [Scenario]
    }

-- | The declared test interpretation (not the registry byte layout).
testVariant :: Variant
testVariant =
    Variant
        { vValidator = "consumer_example.consumer_example.spend"
        , vAid = intendedAid
        , vRepresentativeName = representativeName
        , vScenarios = scenarios
        }

-- | The concrete identity bytes of the Lean model.
concreteVariant :: Variant
concreteVariant =
    Variant
        { vValidator =
            "consumer_identity_example.consumer_identity_example.spend"
        , vAid = concreteAid
        , vRepresentativeName = \statePolicy tx ->
            concreteRepresentativeName statePolicy tx 0 concreteAidText
        , vScenarios =
            [ accepting
            , Scenario "a rival seed's token" True 1 Present
            ]
        }

-- ---------------------------------------------------------------------------
-- The concrete identity bytes, written out from the Lean layout
-- ---------------------------------------------------------------------------

-- | Lean @pack@: the bijective base-256 numeral of a byte string.
packBytes :: ByteString -> Integer
packBytes = BS.foldr (\b acc -> toInteger b + 1 + 256 * acc) 0

-- | CBOR head of a major type and an argument below 2^64, shortest form.
cborHead :: Word8 -> Integer -> ByteString
cborHead major n
    | n < 24 = BS.pack [major * 32 + fromInteger n]
    | n < 256 = BS.cons (major * 32 + 24) (be 1)
    | n < 65_536 = BS.cons (major * 32 + 25) (be 2)
    | n < 4_294_967_296 = BS.cons (major * 32 + 26) (be 4)
    | otherwise = BS.cons (major * 32 + 27) (be 8)
  where
    be k = BS.pack [fromIntegral (n `shiftR` (8 * i)) | i <- [k - 1, k - 2 .. 0]]

-- | A byte string of at most 64 bytes, definite.
cborBytes :: ByteString -> ByteString
cborBytes b
    | BS.length b <= 64 = cborHead 2 (toInteger (BS.length b)) <> b
    | otherwise = error "cborBytes: the identity fields are at most 64 bytes"

-- | Lean @code (State seed)@: constructor 0 holding the output reference.
concreteStatePreimage :: ByteString -> Integer -> ByteString
concreteStatePreimage tx index =
    BS.concat
        [ BS.pack [0xd8, 0x79, 0x9f, 0xd8, 0x79, 0x9f]
        , cborBytes tx
        , cborHead 0 index
        , BS.pack [0xff, 0xff]
        ]

-- | Lean @code (Active registry key)@: constructor 1 holding the registry.
concreteActivePreimage :: ByteString -> ByteString -> ByteString -> ByteString
concreteActivePreimage policy registry key =
    BS.concat
        [ BS.pack [0xd8, 0x7a, 0x9f, 0xd8, 0x79, 0x9f]
        , cborBytes policy
        , cborBytes registry
        , BS.pack [0xff]
        , cborBytes key
        , BS.pack [0xff]
        ]

-- | The registry asset name: the hash of the state preimage.
concreteRegistryName :: ByteString -> Integer -> ByteString
concreteRegistryName tx index = blake2b256 (concreteStatePreimage tx index)

{- | The representative asset name: the hash of the active preimage, over the
state policy, the registry name and the AID's CESR text.
-}
concreteRepresentativeName ::
    ByteString -> ByteString -> Integer -> ByteString -> ByteString
concreteRepresentativeName policy tx index key =
    blake2b256
        (concreteActivePreimage policy (concreteRegistryName tx index) key)

-- | The qualified CESR text of the intended AID (vector @transferable-aid@).
concreteAidText :: ByteString
concreteAidText = B8.pack "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"

-- | Lean @aidOfCesr@ of that text: the AID the consumer fixes.
concreteAid :: Integer
concreteAid = packBytes concreteAidText

-- | Bytes from hexadecimal text (the vectors' notation).
unhex :: String -> ByteString
unhex [] = BS.empty
unhex (a : b : rest) = BS.cons (digit a * 16 + digit b) (unhex rest)
  where
    digit c
        | c >= '0' && c <= '9' = fromIntegral (fromEnum c - fromEnum '0')
        | c >= 'a' && c <= 'f' = fromIntegral (fromEnum c - fromEnum 'a' + 10)
        | otherwise = error "unhex: not a lowercase hexadecimal digit"
unhex _ = error "unhex: odd length"

{- | The vectors of @lean/consumer-identity-vectors.json@: id, state policy,
seed transaction id, seed output index, CESR text, expected registry name and
expected representative name. Copied from the file, not computed here.
-}
leanVectors :: [(String, String, String, Integer, String, String, String)]
leanVectors =
    [
        ( "transferable-aid"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 0
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , "866d8e0d3205af393ae4f5e03038e60e6206b1efbfd88ab34d13b6c9cb9cfde8"
        )
    ,
        ( "other-aid-same-registry"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 0
        , "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        , "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , "07758b6c783532bf93bb2dbeeef28a8287716447662dd60a13b3357799e53110"
        )
    ,
        ( "non-transferable-aid"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 0
        , "BPbeCTEUzPz5UEX4J9Mk8JST2bZV3phvCQ8hWs0diM14"
        , "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , "fda241c4049323fa652a76f3d500e7828b49acdd1eca2a112adfa5265653fc80"
        )
    ,
        ( "rival-seed-output-index"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 1
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "137d838233aa11f5c452b27faba772d541440f2a8aabb0357f565d5fe182002c"
        , "2f55cee243abd69ae7276f2478fffb5dbac67bd0146e90bfa8432b59cc04be15"
        )
    ,
        ( "rival-seed-transaction"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1e"
        , 0
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "187d076638ea18d91c192c59092396bb7bf9c0f302ead97cf65751af0e878bcc"
        , "d934a32be44496f7452cbae58775ce251138a942e121dbcc80e1f2883a9969a9"
        )
    ,
        ( "other-state-policy"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f6"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 0
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , "66b57382eb1f585288faa37a7a7ee4591ede1f8a2cc0d289be96140e19e73ce9"
        )
    ,
        ( "seed-output-index-24"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 24
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "9d417daf68fb27a72855350afe1b3720d6f1fe33a72f470a3c6d422e84d2230d"
        , "5f5c9b01bac42f5f47a57e27f2d3b11bde6e741926d034b8b380cbcf35f6bbc5"
        )
    ,
        ( "seed-output-index-256"
        , "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , 256
        , "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , "dc4d6b04df49082c68c31bee1f1c79f1d50bd845678b3db5c311da83a45a38f0"
        , "1917168024281cff5941cd308be5d1b9b2bd35c54937153fe3dbc884759270b2"
        )
    ]

-- | The off-chain naming reproduces every vector of the Lean model.
namesMatchTheLeanVectors :: Spec
namesMatchTheLeanVectors =
    forM_ leanVectors $ \(vid, policy, tx, index, cesr, registry, active) ->
        it ("names " <> vid <> " as the Lean vector does") $ do
            let txBytes = unhex tx
                key = B8.pack cesr
            concreteRegistryName txBytes index `shouldBe` unhex registry
            concreteRepresentativeName (unhex policy) txBytes index key
                `shouldBe` unhex active

-- ---------------------------------------------------------------------------
-- World
-- ---------------------------------------------------------------------------

data World = World
    { wProvider :: Provider IO
    , wSubmitter :: Submitter IO
    , wConsumerProgram :: SBS.ShortByteString
    , wConsumerHash :: ScriptHash
    , wHoldings :: [Utxo]
    -- ^ one per scenario, in 'scenarios' order
    , wLocked :: [Utxo]
    -- ^ one consumer-locked output per scenario, in 'scenarios' order
    , wWallet :: [Utxo]
    -- ^ fee and collateral outputs for the consumer transactions
    }

spec :: Spec
spec =
    describe "#343 consumer predicate on the local chain" $ do
        aroundAll (withSeededWorld testVariant) $ do
            it "settles a spend that references the eligible holding" $
                \w -> acceptingSettles w
            forM_ (zip [1 ..] refusals) $ \(ix, sc) ->
                it ("refuses, in the consumer script, " <> scName sc) $
                    \w -> refusalIsScriptFailure w ix sc
        describe "concrete identity bytes, test datum decoder" $ do
            namesMatchTheLeanVectors
            aroundAll (withSeededWorld concreteVariant) $ do
                it "settles a spend that references the holding named by the concrete identity bytes" $
                    \w -> acceptingSettles w
                forM_ (zip [1 ..] (drop 1 (vScenarios concreteVariant))) $
                    \(ix, sc) ->
                        it ("refuses, in the consumer script, " <> scName sc) $
                            \w -> refusalIsScriptFailure w ix sc

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

dbg :: String -> IO ()
dbg = hPutStrLn stderr . ("[consumer-e2e] " <>)

withinSecs :: Int -> String -> IO a -> IO a
withinSecs secs label act =
    timeout (secs * 1_000_000) act
        >>= maybe (fail (label <> ": timed out after " <> show secs <> "s")) pure

scriptHashOf :: ByteString -> ScriptHash
scriptHashOf bytes =
    maybe (error "scriptHashOf: bad length") ScriptHash (hashFromBytes bytes)

scriptAddr :: ScriptHash -> Addr
scriptAddr h = Addr Testnet (ScriptHashObj h) StakeRefNull

withSeededWorld :: Variant -> (World -> IO ()) -> IO ()
withSeededWorld variant action = do
    bpPath <-
        lookupEnv "KERI_CAGE_BLUEPRINT"
            >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
    bp <- loadBlueprint bpPath >>= either fail pure
    seedProgram <-
        maybe (fail "consumer_seed_policy not in the blueprint") pure $
            extractCompiledCodeExact
                "consumer_seed_policy.consumer_seed_policy.mint"
                bp
    consumerCode <-
        maybe (fail (T.unpack (vValidator variant) <> " not in the blueprint")) pure $
            extractCompiledCodeExact (vValidator variant) bp
    let seedHash = computeScriptHash seedProgram
        statePolicyBytes = scriptHashBytes seedHash
        contextData =
            PLC.Constr
                0
                [ PLC.I contextNetwork
                , PLC.Constr
                    0
                    [ PLC.B applicationPolicy
                    , PLC.Constr 1 [PLC.B applicationCredential]
                    , PLC.B stateProgram
                    , PLC.B statePolicyBytes
                    ]
                , PLC.Constr 0 [PLC.B seedTx, PLC.I 0]
                , PLC.I (vAid variant)
                ]
        consumerProgram = applyDataArgs [contextData, paramsData] consumerCode
        consumerHash = computeScriptHash consumerProgram
    withDevnet $ \lsq ltxs -> do
        let prov = mkN2CProvider lsq
            sub = mkN2CSubmitter ltxs
        dbg ("seed policy " <> show seedHash <> "; consumer " <> show consumerHash)
        world <-
            seedWorld
                variant
                prov
                sub
                seedProgram
                seedHash
                statePolicyBytes
                consumerProgram
                consumerHash
        action world

scriptHashBytes :: ScriptHash -> ByteString
scriptHashBytes (ScriptHash h) = hashToBytes h

-- | POSIX milliseconds now; the devnet clock tracks the wall clock.
currentPosixMs :: IO Integer
currentPosixMs = round . (* 1000) <$> getPOSIXTime

adaOf :: TxOut ConwayEra -> Integer
adaOf o = unCoin (o ^. coinTxOutL)

-- | Position of a spent input among the sorted inputs of a transaction.
spendingIndex :: TxIn -> Set.Set TxIn -> Word32
spendingIndex needle ins = go 0 (Set.toAscList ins)
  where
    go _ [] = error "spendingIndex: input not in the transaction"
    go n (x : xs)
        | x == needle = n
        | otherwise = go (n + 1) xs

-- | Wait until every listed output exists, then return them.
awaitOutputs :: Provider IO -> [TxIn] -> IO [Utxo]
awaitOutputs prov ins = go (40 :: Int)
  where
    go n
        | n <= 0 = fail ("outputs never appeared: " <> show ins)
        | otherwise = do
            found <-
                withinSecs 30 "query outputs" $
                    queryUTxOByTxIn prov (Set.fromList ins)
            if Map.size found == length ins
                then pure [(i, o) | i <- ins, Just o <- [Map.lookup i found]]
                else threadDelay 1_000_000 >> go (n - 1)

outputsOf :: TxId -> [Integer] -> [TxIn]
outputsOf txId ixs = [TxIn txId (TxIx (fromInteger i)) | i <- ixs]

submitOk :: Submitter IO -> String -> ConwayTx -> IO TxId
submitOk sub label tx = do
    r <-
        withinSecs 60 ("submit " <> label) $
            submitTx sub (addKeyWitness genesisSignKey tx)
    case r of
        Submitted txId -> pure txId
        Rejected reason ->
            fail (label <> " rejected: " <> B8.unpack reason)

-- ---------------------------------------------------------------------------
-- Wallet split, then the seeding transaction
-- ---------------------------------------------------------------------------

{- | Fan the single genesis output out into disjoint wallet outputs: one to
fund the seeding transaction, its collateral, and a fee and collateral
output for the accepting transaction and for the refusals.
-}
buildSplitTx :: Provider IO -> IO ConwayTx
buildSplitTx prov = do
    pp <- queryProtocolParams prov
    wallet <- queryUTxOs prov genesisAddr
    feeUtxo <- case wallet of
        (u : _) -> pure u
        [] -> fail "buildSplitTx: no genesis output"
    let out n = mkBasicTxOut genesisAddr (inject (Coin n))
        outs =
            StrictSeq.fromList
                [ out 100_000_000
                , out 10_000_000
                , out 30_000_000
                , out 10_000_000
                , out 30_000_000
                , out 10_000_000
                ]
        tx = mkBasicTx (mkBasicTxBody & outputsTxBodyL .~ outs)
    case balanceTx pp [feeUtxo] [] genesisAddr tx of
        Left err -> fail ("buildSplitTx: " <> show err)
        Right r -> pure (balancedTx r)

-- | Lovelace on every seeded holding and on every consumer-locked output.
seededAda, lockedAda :: Integer
seededAda = 3_000_000
lockedAda = 4_000_000

mintExUnits, spendExUnits :: ExUnits
mintExUnits = ExUnits 2_000_000 1_000_000_000
spendExUnits = ExUnits 4_000_000 2_000_000_000

-- | Fixed fee of a consumer transaction (an overestimate the ledger accepts).
consumerFee :: Integer
consumerFee = 1_500_000

assetNameOf :: ByteString -> AssetName
assetNameOf = AssetName . SBS.toShort

{- | Mint the representative tokens with the test-only policy and pay one
holding per scenario to the test application credential, each with a
decoded datum of its state; lock one consumer output per scenario.
-}
buildSeedTx ::
    Variant ->
    Provider IO ->
    SBS.ShortByteString ->
    ScriptHash ->
    ByteString ->
    SBS.ShortByteString ->
    Utxo ->
    Utxo ->
    IO ConwayTx
buildSeedTx variant prov seedProgram seedHash statePolicyBytes consumerProgram feeUtxo collUtxo = do
    pp <- queryProtocolParams prov
    let policyId = PolicyID seedHash
        intendedName = vRepresentativeName variant statePolicyBytes seedTx
        rivalName = vRepresentativeName variant statePolicyBytes rivalSeedTx
        nameOf sc
            | scRivalRegistry sc = rivalName
            | otherwise = intendedName
        total pick =
            sum [scQuantity sc | sc <- vScenarios variant, pick sc]
        mintMA =
            MultiAsset . Map.singleton policyId $
                Map.fromList
                    [ (assetNameOf intendedName, total (not . scRivalRegistry))
                    , (assetNameOf rivalName, total scRivalRegistry)
                    ]
        holding sc =
            mkBasicTxOut
                (scriptAddr (scriptHashOf applicationCredential))
                ( MaryValue
                    (Coin seededAda)
                    ( MultiAsset . Map.singleton policyId $
                        Map.singleton
                            (assetNameOf (nameOf sc))
                            (scQuantity sc)
                    )
                )
                & datumTxOutL .~ mkInlineDatum (decodedDatum (vAid variant) (scState sc))
        locked =
            mkBasicTxOut
                (cageScriptAddr consumerProgram Testnet)
                (inject (Coin lockedAda))
        outs =
            StrictSeq.fromList
                ( map holding (vScenarios variant)
                    <> map (const locked) (vScenarios variant)
                )
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwayMinting (AsIx 0))
                    (Data (PLC.Constr 0 []), mintExUnits)
        integrity = computeScriptIntegrity PlutusV3 pp redeemers
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton (fst feeUtxo)
                & outputsTxBodyL .~ outs
                & mintTxBodyL .~ mintMA
                & collateralInputsTxBodyL .~ Set.singleton (fst collUtxo)
                & scriptIntegrityHashTxBodyL .~ integrity
        tx =
            mkBasicTx body
                & witsTxL . scriptTxWitsL
                    .~ Map.singleton seedHash (mkCageScript seedProgram)
                & witsTxL . rdmrsTxWitsL .~ redeemers
    case balanceTxWith
        pp
        [feeUtxo]
        (CollateralUtxos [collUtxo])
        []
        genesisAddr
        Nothing
        tx of
        Left err -> fail ("buildSeedTx: " <> show err)
        Right r -> pure (balancedTx r)

seedWorld ::
    Variant ->
    Provider IO ->
    Submitter IO ->
    SBS.ShortByteString ->
    ScriptHash ->
    ByteString ->
    SBS.ShortByteString ->
    ScriptHash ->
    IO World
seedWorld variant prov sub seedProgram seedHash statePolicyBytes consumerProgram consumerHash = do
    splitTx <- withinSecs 60 "split" (buildSplitTx prov)
    splitId <- submitOk sub "wallet split" splitTx
    wallet <- awaitOutputs prov (outputsOf splitId [0 .. 5])
    (mintFee, mintColl, wallet') <- case wallet of
        (a : b : rest) -> pure (a, b, rest)
        _ -> fail "wallet split gave fewer outputs than planned"
    dbg "wallet split settled"
    seedTx' <-
        withinSecs 90 "seed" $
            buildSeedTx
                variant
                prov
                seedProgram
                seedHash
                statePolicyBytes
                consumerProgram
                mintFee
                mintColl
    seedId <- submitOk sub "seeded holdings" seedTx'
    let n = fromIntegral (length (vScenarios variant))
    holdings <- awaitOutputs prov (outputsOf seedId [0 .. n - 1])
    locked <- awaitOutputs prov (outputsOf seedId [n .. 2 * n - 1])
    dbg "seeded holdings and consumer outputs settled"
    pure
        World
            { wProvider = prov
            , wSubmitter = sub
            , wConsumerProgram = consumerProgram
            , wConsumerHash = consumerHash
            , wHoldings = holdings
            , wLocked = locked
            , wWallet = wallet'
            }

-- ---------------------------------------------------------------------------
-- The consumer transaction
-- ---------------------------------------------------------------------------

{- | Spend the consumer-locked output of a scenario, referencing that
scenario's holding. Everything else is the same across scenarios.
-}
buildConsumerTx :: World -> Int -> Utxo -> Utxo -> IO ConwayTx
buildConsumerTx w ix feeUtxo collUtxo = do
    let prov = wProvider w
        locked = wLocked w !! ix
        holding = wHoldings w !! ix
    pp <- queryProtocolParams prov
    nowMs <- currentPosixMs
    lowerSlot <-
        withinSecs 30 "slot of the validity lower bound" $
            posixMsCeilSlot prov (nowMs - 10_000)
    let ins = Set.fromList [fst locked, fst feeUtxo]
        change = adaOf (snd locked) + adaOf (snd feeUtxo) - consumerFee
        outs =
            StrictSeq.singleton
                (mkBasicTxOut genesisAddr (inject (Coin change)))
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwaySpending (AsIx (spendingIndex (fst locked) ins)))
                    (Data (PLC.Constr 0 []), spendExUnits)
        integrity = computeScriptIntegrity PlutusV3 pp redeemers
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ ins
                & referenceInputsTxBodyL .~ Set.singleton (fst holding)
                & outputsTxBodyL .~ outs
                & feeTxBodyL .~ Coin consumerFee
                & collateralInputsTxBodyL .~ Set.singleton (fst collUtxo)
                & vldtTxBodyL .~ ValidityInterval (SJust lowerSlot) SNothing
                & scriptIntegrityHashTxBodyL .~ integrity
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ Map.singleton
                    (wConsumerHash w)
                    (mkCageScript (wConsumerProgram w))
            & witsTxL . rdmrsTxWitsL .~ redeemers

acceptingSettles :: World -> IO ()
acceptingSettles w = do
    (acceptFee, acceptColl) <- case wWallet w of
        (a : b : _) -> pure (a, b)
        _ -> fail "no wallet outputs for the accepting spend"
    lockedIn <- case wLocked w of
        (l : _) -> pure (fst l)
        [] -> fail "no consumer output was seeded"
    tx <-
        withinSecs 60 "build accepting spend" $
            buildConsumerTx w 0 acceptFee acceptColl
    txId <- submitOk (wSubmitter w) "accepting spend" tx
    _ <- awaitOutputs (wProvider w) (outputsOf txId [0])
    stillLocked <-
        withinSecs 30 "query the consumer output" $
            queryUTxOByTxIn (wProvider w) (Set.singleton lockedIn)
    unless (Map.null stillLocked) $
        expectationFailure "the consumer output was not spent"
    dbg ("accepting spend settled as " <> show txId)

phase1Markers, phase2Markers :: [String]
phase1Markers =
    [ "BadInputsUTxO"
    , "FeeTooSmallUTxO"
    , "InsufficientCollateral"
    , "OutsideValidityIntervalUTxO"
    , "PPViewHashesDontMatch"
    , "MissingRedeemers"
    , "ValueNotConservedUTxO"
    , "OutputTooSmallUTxO"
    , "ExUnitsTooBigUTxO"
    , "MaxTxSizeUTxO"
    ]
phase2Markers =
    [ "FailedUnexpectedly"
    , "PlutusFailure"
    , "ValidationTagMismatch"
    , "ScriptWitnessNotValidatingUTXOW"
    ]

{- | The refusal is the consumer script's own verdict: the transaction has
the consumer as its only script, and the node rejects it in Phase 2.
-}
refusalIsScriptFailure :: World -> Int -> Scenario -> IO ()
refusalIsScriptFailure w ix sc = do
    (refuseFee, refuseColl) <- case drop 2 (wWallet w) of
        (a : b : _) -> pure (a, b)
        _ -> fail "no wallet outputs for the refusals"
    tx <-
        withinSecs 60 ("build spend for " <> scName sc) $
            buildConsumerTx w ix refuseFee refuseColl
    Map.keys (tx ^. witsTxL . scriptTxWitsL)
        `shouldBe` [wConsumerHash w]
    r <-
        withinSecs 60 ("submit spend for " <> scName sc) $
            submitTx
                (wSubmitter w)
                (addKeyWitness genesisSignKey tx)
    case r of
        Submitted txId ->
            expectationFailure
                ( scName sc
                    <> " was accepted as "
                    <> show txId
                    <> " but must be refused"
                )
        Rejected raw -> do
            let diagnostic = B8.unpack raw
            when (any (`isInfixOf` diagnostic) phase1Markers) $
                expectationFailure
                    ( scName sc
                        <> " failed a ledger rule, not the script: "
                        <> diagnostic
                    )
            unless (any (`isInfixOf` diagnostic) phase2Markers) $
                expectationFailure
                    ( scName sc
                        <> " was rejected, but not by script evaluation: "
                        <> diagnostic
                    )
            dbg
                ( scName sc
                    <> " refused in the script: "
                    <> take 200 diagnostic
                )
