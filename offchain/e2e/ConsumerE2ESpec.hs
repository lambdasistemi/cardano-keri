{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : ConsumerE2ESpec
Description : Connected boundary for the consumer predicate (#343)

Starts a protocol devnet and exercises the example relying contract
(@consumer_identity_example@) that reads a candidate holding as a reference
input and spends only if the Lean's @consumableHoldingB@ holds for it, on the
concrete identity bytes and the datum decoder of the Lean model
(@consumer_identity_bytes@, @consumer_checkpoint_datum@).

The registry name, the key and the representative name are recomputed here from
the Lean layout, and checked against the vectors of
@lean/consumer-identity-vectors.json@ before they name anything on chain.

__The genuine journeys.__ The consumer reads checkpoints that the production
validators produced: a registration booked through the application and folded
by another party into the checkpoint validator's address, the same identity
frozen by its controller's honest freeze rotation and restored by its deposit
rotation, and the same identity convicted, its pending termination left at the
checkpoint validator's address. The consumer's context (network, application
policy and credential, state program and policy, seed, the AID as its qualified
CESR text, the checkpoint credential) is taken from the devnet's registry
environment, never declared here. The maturity window @W@ is the relying
contract's choice (Lean @T9_juvenility_is_consumer_only@): no transition of the
registry reads it, and 'maturityWindowMs' is a parameter of the consumer's
program only.

Each reading differs from the accepting one in one aspect. A refusal is a
Phase-2 failure of the consumer script: its transaction passes every ledger
rule, carries the consumer script as its only script, and the node rejects it
when that script evaluates false. Every verdict is also checked against
'failedClauses', the Lean predicate evaluated over what the chain holds.

__Seeded fixture cases.__ Three cases are not reachable by any honest arm of
the registry and stay seeded: a poisoned checkpoint (no arm writes the poison
flag), a holding carrying a version 1 datum (the checkpoint datum type has no
such constructor), and a holding with the representative token twice (the
registry mints the active token once). They are minted by the test-only policy
@consumer_seed_policy@ at a test checkpoint credential, and prove only the
consumer's decoder and quantity clauses over those bytes; they say nothing of a
registration journey. The pool and the bond amounts are held in the output's
value and are not read from it (#339).
-}
module ConsumerE2ESpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, catch)
import Control.Monad (forM_, unless, when)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Short qualified as SBS
import Data.Char (digitToInt, isDigit)
import Data.IORef (IORef, modifyIORef, newIORef, readIORef, writeIORef)
import Data.List (isInfixOf, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
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

import Cardano.Crypto.DSIGN (SignKeyDSIGN)
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx, witsTxL)
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
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    mkBasicTxOut,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Inject (..),
    Network (..),
    SlotNo,
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

import Cardano.KERI.AID.Application (OutputReference (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
 )
import Cardano.KERI.AID.E2E.Datum (extractDatum, mkInlineDatum)
import Cardano.KERI.AID.E2E.Mpf (blake2b256)
import Cardano.KERI.AID.E2E.Script (
    applyDataArgs,
    cageScriptAddr,
    computeScriptHash,
    extractCompiledCodeExact,
    loadBlueprint,
    mkCageScript,
 )

import CheckpointTxBuilder (
    CheckpointEnv (..),
    CheckpointInput (..),
    Observer,
    Party (..),
    Stage (..),
    awaitChainTime,
    consumerParty,
    freezeThenDepositJourney,
    productionRegisterScenario,
    registrySeed,
    resolveBlueprintPath,
    stagedCheckpointDevnet,
    terminationJourney,
 )

type Utxo = (TxIn, TxOut ConwayEra)

-- ---------------------------------------------------------------------------
-- The consumer's context and parameters
-- ---------------------------------------------------------------------------

{- | The relying contract's fixed context, the Lean @Context@: network, the
published release (application policy and credential, state program and
policy), the registry seed, the AID as its qualified CESR text and the
checkpoint credential. Credentials are script hashes.
-}
data Context = Context
    { cxNetwork :: Integer
    , cxApplicationPolicy :: ByteString
    , cxApplicationCredential :: ByteString
    , cxStateProgram :: ByteString
    , cxStatePolicy :: ByteString
    , cxSeedTx :: ByteString
    , cxSeedIndex :: Integer
    , cxAid :: ByteString
    , cxCheckpointCredential :: ByteString
    }

contextData :: Context -> PLC.Data
contextData cx =
    PLC.Constr
        0
        [ PLC.I (cxNetwork cx)
        , PLC.Constr
            0
            [ PLC.B (cxApplicationPolicy cx)
            , PLC.Constr 1 [PLC.B (cxApplicationCredential cx)]
            , PLC.B (cxStateProgram cx)
            , PLC.B (cxStatePolicy cx)
            ]
        , PLC.Constr 0 [PLC.B (cxSeedTx cx), PLC.I (cxSeedIndex cx)]
        , PLC.I (packBytes (cxAid cx))
        , PLC.Constr 1 [PLC.B (cxCheckpointCredential cx)]
        ]

-- | The representative asset name the Lean layout gives the context.
representativeNameOf :: Context -> ByteString
representativeNameOf cx =
    concreteRepresentativeName
        (cxStatePolicy cx)
        (cxSeedTx cx)
        (cxSeedIndex cx)
        (cxAid cx)

{- | Checkpoint parameters of a consumer: only @w@ is read, the maturity window
in the unit of the delivered datum's birth, POSIX milliseconds. The release's
terms carry none (Lean @T9_juvenility_is_consumer_only@).
-}
paramsDataFor :: Integer -> PLC.Data
paramsDataFor w = PLC.Constr 0 [PLC.I 3, PLC.I 2, PLC.I 1, PLC.I w]

-- ---------------------------------------------------------------------------
-- Seeded fixture: declared test values
-- ---------------------------------------------------------------------------

-- | The window of the seeded consumer: one millisecond over a birth of 0.
seededWindowMs :: Integer
seededWindowMs = 1

-- | The seeded consumer's context over the test-only policy's hash.
seededContext :: ByteString -> Context
seededContext statePolicyBytes =
    Context
        { cxNetwork = 0
        , cxApplicationPolicy = BS.replicate 28 0xcc
        , cxApplicationCredential = BS.replicate 28 0xaa
        , cxStateProgram = BS.replicate 28 0xbb
        , cxStatePolicy = statePolicyBytes
        , cxSeedTx = BS.replicate 32 0xee
        , cxSeedIndex = 0
        , cxAid = concreteAidText
        , cxCheckpointCredential = BS.replicate 28 0xdd
        }

-- ---------------------------------------------------------------------------
-- Datum builders: the Lean version 2 layout, field by field
-- ---------------------------------------------------------------------------

boolData :: Bool -> PLC.Data
boolData b = PLC.Constr (if b then 1 else 0) []

{- | The key material the Lean vectors use: one current key, one next key, both
unweighted thresholds of 1, no witnesses, @toad@ 0.
-}
keyMaterialData :: PLC.Data
keyMaterialData =
    PLC.Constr
        0
        [ PLC.List [PLC.B (unhex "1f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8")]
        , PLC.Constr 0 [PLC.I 1]
        , PLC.List [PLC.B (unhex "3e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017")]
        , PLC.Constr 0 [PLC.I 1]
        , PLC.List []
        , PLC.I 0
        ]

{- | Version 2, live: the AID's CESR text, sequence number, epoch, poisoned,
frozen, birth slot, refund address, top-up mark, key material.
-}
liveDatumWith :: Bool -> PLC.Data
liveDatumWith poisoned =
    PLC.Constr
        1
        [ PLC.Constr
            0
            [ PLC.B concreteAidText
            , PLC.I 0
            , PLC.I 0
            , boolData poisoned
            , boolData False
            , PLC.I 0
            , PLC.B (BS.pack [1, 2, 3, 4])
            , boolData False
            , keyMaterialData
            ]
        ]

{- | The version 1 layout (constructor 0, no consumer facts), as the Lean vector
@version-1@.
-}
versionOneDatum :: PLC.Data
versionOneDatum =
    PLC.Constr
        0
        [ PLC.Constr
            0
            [ PLC.B (unhex "00070e151c232a31383f464d545b626970777e858c939aa1a8afb6bdc4cbd2d9")
            , PLC.List [PLC.B (unhex "1f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8")]
            , PLC.Constr 0 [PLC.I 1]
            , PLC.List [PLC.B (unhex "3e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017")]
            , PLC.Constr 0 [PLC.I 1]
            , PLC.List []
            , PLC.I 0
            , PLC.I 3
            , PLC.I 4
            ]
        ]

-- ---------------------------------------------------------------------------
-- Seeded scenarios
-- ---------------------------------------------------------------------------

data DatumKind = LiveDatum | PoisonedDatum | VersionOneDatum

-- | A seeded holding: how many of the token it carries and what datum.
data Scenario = Scenario
    { scName :: String
    , scQuantity :: Integer
    , scDatum :: DatumKind
    }

accepting :: Scenario
accepting = Scenario "the eligible seeded holding" 1 LiveDatum

refusals :: [Scenario]
refusals =
    [ Scenario "a seeded poisoned holding" 1 PoisonedDatum
    , Scenario "a seeded holding with the token twice" 2 LiveDatum
    , Scenario "a seeded holding carrying a version 1 datum" 1 VersionOneDatum
    ]

scenarios :: [Scenario]
scenarios = accepting : refusals

datumData :: DatumKind -> PLC.Data
datumData LiveDatum = liveDatumWith False
datumData PoisonedDatum = liveDatumWith True
datumData VersionOneDatum = versionOneDatum

-- | Blueprint title of the consumer validator.
consumerValidator :: Text
consumerValidator =
    "consumer_identity_example.consumer_identity_example.spend"

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

-- | The qualified CESR text of the seeded fixture's AID (vector @transferable-aid@).
concreteAidText :: ByteString
concreteAidText = B8.pack "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"

-- | Bytes from hexadecimal text (the vectors' notation).
unhex :: String -> ByteString
unhex [] = BS.empty
unhex (a : b : rest) = BS.cons (digit a * 16 + digit b) (unhex rest)
  where
    digit c
        | isDigit c = fromIntegral (digitToInt c)
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
    describe "#343 consumer predicate on the local chain, Lean datum decoder" $ do
        namesMatchTheLeanVectors
        around stagedCheckpointDevnet $ do
            it
                "reads the checkpoint a genuine registration delivered: refused one slot before the maturity boundary, settled at it, refused by a consumer fixing another checkpoint credential or another seed"
                registeredHoldingJourney
            it
                "#345 restores the bond of a frozen checkpoint with the controller's deposit rotation, refuses a deposit whose intent names another amount, and the checkpoint is consumable again; the consumer reads the genuine frozen checkpoint, refused, and the checkpoint the deposit restored, settled"
                ( \env -> do
                    (observer, settle) <- frozenThenRestored env
                    freezeThenDepositJourney env observer
                    settle
                )
            it
                "#350 books the termination of a convicted identity with a third party's fee, folds it with another party, reads the terminal key back, and refuses each clause's violation, a second booking and a registration of the terminal key; the consumer reads the standing checkpoint, settled, the pending output its conviction left, refused, and no checkpoint after the terminating fold"
                ( \env -> do
                    (observer, settle) <- convictedReading env
                    terminationJourney env observer
                    settle
                )
        aroundAll withSeededWorld $ do
            it "seeded fixture: settles a spend that references the eligible holding" $
                \w -> acceptingSettles w
            forM_ (zip [1 ..] refusals) $ \(ix, sc) ->
                it ("seeded fixture: refuses, in the consumer script, " <> scName sc) $
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

withSeededWorld :: (World -> IO ()) -> IO ()
withSeededWorld action = do
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
        maybe (fail (T.unpack consumerValidator <> " not in the blueprint")) pure $
            extractCompiledCodeExact consumerValidator bp
    let seedHash = computeScriptHash seedProgram
        statePolicyBytes = scriptHashBytes seedHash
        consumerProgram =
            applyDataArgs
                [ contextData (seededContext statePolicyBytes)
                , paramsDataFor seededWindowMs
                ]
                consumerCode
        consumerHash = computeScriptHash consumerProgram
    withDevnet $ \lsq ltxs -> do
        let prov = mkN2CProvider lsq
            sub = mkN2CSubmitter ltxs
        dbg ("seed policy " <> show seedHash <> "; consumer " <> show consumerHash)
        world <-
            seedWorld
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

submitOk :: Submitter IO -> SignKeyDSIGN Ed25519DSIGN -> String -> ConwayTx -> IO TxId
submitOk sub key label tx = do
    r <-
        withinSecs 60 ("submit " <> label) $
            submitTx sub (addKeyWitness key tx)
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
holding per scenario to the test checkpoint credential, each with a
datum of its kind; lock one consumer output per scenario.
-}
buildSeedTx ::
    Provider IO ->
    SBS.ShortByteString ->
    ScriptHash ->
    ByteString ->
    SBS.ShortByteString ->
    Utxo ->
    Utxo ->
    IO ConwayTx
buildSeedTx prov seedProgram seedHash statePolicyBytes consumerProgram feeUtxo collUtxo = do
    pp <- queryProtocolParams prov
    let policyId = PolicyID seedHash
        seeded = seededContext statePolicyBytes
        name = representativeNameOf seeded
        minted =
            Map.fromListWith
                (+)
                [(name, scQuantity sc) | sc <- scenarios]
        mintMA =
            MultiAsset . Map.singleton policyId $
                Map.fromList
                    [(assetNameOf n, q) | (n, q) <- Map.toList minted]
        holding sc =
            mkBasicTxOut
                (scriptAddr (scriptHashOf (cxCheckpointCredential seeded)))
                ( MaryValue
                    (Coin seededAda)
                    ( MultiAsset . Map.singleton policyId $
                        Map.singleton
                            (assetNameOf name)
                            (scQuantity sc)
                    )
                )
                & datumTxOutL .~ mkInlineDatum (datumData (scDatum sc))
        locked =
            mkBasicTxOut
                (cageScriptAddr consumerProgram Testnet)
                (inject (Coin lockedAda))
        outs =
            StrictSeq.fromList
                ( map holding scenarios
                    <> map (const locked) scenarios
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
    Provider IO ->
    Submitter IO ->
    SBS.ShortByteString ->
    ScriptHash ->
    ByteString ->
    SBS.ShortByteString ->
    ScriptHash ->
    IO World
seedWorld prov sub seedProgram seedHash statePolicyBytes consumerProgram consumerHash = do
    splitTx <- withinSecs 60 "split" (buildSplitTx prov)
    splitId <- submitOk sub genesisSignKey "wallet split" splitTx
    wallet <- awaitOutputs prov (outputsOf splitId [0 .. 5])
    (mintFee, mintColl, wallet') <- case wallet of
        (a : b : rest) -> pure (a, b, rest)
        _ -> fail "wallet split gave fewer outputs than planned"
    dbg "wallet split settled"
    seedTx' <-
        withinSecs 90 "seed" $
            buildSeedTx
                prov
                seedProgram
                seedHash
                statePolicyBytes
                consumerProgram
                mintFee
                mintColl
    seedId <- submitOk sub genesisSignKey "seeded holdings" seedTx'
    let n = fromIntegral (length scenarios)
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

{- | The transaction that spends a consumer-locked output and references a
holding, valid from a lower-bound slot with no upper bound. Everything else is
the same across the readings of one consumer.
-}
spendTx ::
    Provider IO ->
    SBS.ShortByteString ->
    ScriptHash ->
    Addr ->
    Utxo ->
    Utxo ->
    Utxo ->
    TxIn ->
    SlotNo ->
    IO ConwayTx
spendTx prov program programHash changeTo locked feeUtxo collUtxo holding lowerSlot = do
    pp <- queryProtocolParams prov
    let ins = Set.fromList [fst locked, fst feeUtxo]
        change = adaOf (snd locked) + adaOf (snd feeUtxo) - consumerFee
        outs =
            StrictSeq.singleton
                (mkBasicTxOut changeTo (inject (Coin change)))
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwaySpending (AsIx (spendingIndex (fst locked) ins)))
                    (Data (PLC.Constr 0 []), spendExUnits)
        integrity = computeScriptIntegrity PlutusV3 pp redeemers
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ ins
                & referenceInputsTxBodyL .~ Set.singleton holding
                & outputsTxBodyL .~ outs
                & feeTxBodyL .~ Coin consumerFee
                & collateralInputsTxBodyL .~ Set.singleton (fst collUtxo)
                & vldtTxBodyL .~ ValidityInterval (SJust lowerSlot) SNothing
                & scriptIntegrityHashTxBodyL .~ integrity
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ Map.singleton programHash (mkCageScript program)
            & witsTxL . rdmrsTxWitsL .~ redeemers

{- | Spend the consumer-locked output of a seeded scenario, referencing that
scenario's holding, ten seconds into the past of the chain's clock.
-}
buildConsumerTx :: World -> Int -> Utxo -> Utxo -> IO ConwayTx
buildConsumerTx w ix feeUtxo collUtxo = do
    nowMs <- currentPosixMs
    lowerSlot <-
        withinSecs 30 "slot of the validity lower bound" $
            posixMsCeilSlot (wProvider w) (nowMs - 10_000)
    spendTx
        (wProvider w)
        (wConsumerProgram w)
        (wConsumerHash w)
        genesisAddr
        (wLocked w !! ix)
        feeUtxo
        collUtxo
        (fst (wHoldings w !! ix))
        lowerSlot

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
    txId <- submitOk (wSubmitter w) genesisSignKey "accepting spend" tx
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
    refusedInScript
        (wSubmitter w)
        genesisSignKey
        (wConsumerHash w)
        (scName sc)
        tx

-- | The node rejects the transaction in Phase 2 of its only script, and not otherwise.
refusedInScript ::
    Submitter IO ->
    SignKeyDSIGN Ed25519DSIGN ->
    ScriptHash ->
    String ->
    ConwayTx ->
    IO ()
refusedInScript sub key consumerHash label tx = do
    Map.keys (tx ^. witsTxL . scriptTxWitsL)
        `shouldBe` [consumerHash]
    r <-
        withinSecs 60 ("submit spend for " <> label) $
            submitTx sub (addKeyWitness key tx)
    case r of
        Submitted txId ->
            expectationFailure
                ( label
                    <> " was accepted as "
                    <> show txId
                    <> " but must be refused"
                )
        Rejected raw -> do
            let diagnostic = B8.unpack raw
            when (any (`isInfixOf` diagnostic) phase1Markers) $
                expectationFailure
                    ( label
                        <> " failed a ledger rule, not the script: "
                        <> diagnostic
                    )
            unless (any (`isInfixOf` diagnostic) phase2Markers) $
                expectationFailure
                    ( label
                        <> " was rejected, but not by script evaluation: "
                        <> diagnostic
                    )
            dbg
                ( label
                    <> " refused in the script: "
                    <> take 200 diagnostic
                )

-- ---------------------------------------------------------------------------
-- The genuine readings
-- ---------------------------------------------------------------------------

{- | The maturity window the relying contract chooses, in POSIX milliseconds.

The delivered datum's birth is the upper bound of the booking's validity, and
the consumer's present is the lower bound of its own transaction's validity:
both are slot starts, and the node's slots last a tenth of a second. 30 seconds
is a multiple of the slot length, so the boundary @born_at + W@ is a slot
start and one slot before it is exactly 100 ms younger. No reading depends on
how long a fold takes: each is placed relative to the boundary, and the chain
is awaited past it before the transaction is built.
-}
maturityWindowMs :: Integer
maturityWindowMs = 30_000

-- | A consumer: a context and the example contract applied to it.
data Consumer = Consumer
    { cnContext :: Context
    , cnProgram :: SBS.ShortByteString
    , cnHash :: ScriptHash
    }

-- | The environment of the genuine readings: the devnet's registry and the consumer's code.
data Reader = Reader
    { rdEnv :: CheckpointEnv
    , rdCode :: SBS.ShortByteString
    }

reader :: CheckpointEnv -> IO Reader
reader env = do
    bp <- resolveBlueprintPath >>= loadBlueprint >>= either fail pure
    code <-
        maybe (fail (T.unpack consumerValidator <> " not in the blueprint")) pure $
            extractCompiledCodeExact consumerValidator bp
    pure (Reader env code)

consumerOf :: Reader -> Context -> Consumer
consumerOf rd cx =
    let program =
            applyDataArgs
                [contextData cx, paramsDataFor maturityWindowMs]
                (rdCode rd)
     in Consumer cx program (computeScriptHash program)

{- | The context of the devnet's registry for an identity. Nothing in it is a
declared value: the release, the seed and the checkpoint credential are what
the registry environment holds, the AID is the one the delivered datum names.
-}
genuineContext :: CheckpointEnv -> ByteString -> Context
genuineContext env aid =
    Context
        { cxNetwork = 0
        , cxApplicationPolicy = scriptHashBytes (envApplicationHash env)
        , cxApplicationCredential = scriptHashBytes (envApplicationHash env)
        , cxStateProgram = scriptHashBytes (envStateHash env)
        , cxStatePolicy = scriptHashBytes (envStateHash env)
        , cxSeedTx = outputTransactionId (registrySeed env)
        , cxSeedIndex = outputIndex (registrySeed env)
        , cxAid = aid
        , cxCheckpointCredential = scriptHashBytes (envCheckpointHash env)
        }

-- | The clauses of the Lean @consumableHoldingB@ a holding can fail.
data Clause
    = AddressClause
    | QuantityClause
    | DatumClause
    | FrozenClause
    | PoisonedClause
    | JuvenileClause
    | PendingClause
    deriving stock (Show, Eq)

{- | The Lean @consumableHoldingB@ over what the chain holds, clause by clause:
the whole address of the checkpoint credential, the representative token
exactly once, a decoded datum for the AID, and a consumable state (present,
unfrozen, unpoisoned, @born_at + W <= now@). The authenticated-context clause
holds of the example by construction. @now@ is a value on the same side of
every threshold as the time the script reads.
-}
failedClauses :: Context -> Integer -> TxOut ConwayEra -> [Clause]
failedClauses cx now out =
    [AddressClause | out ^. addrTxOutL /= checkpointAddress]
        <> [QuantityClause | representativeQuantity cx out /= 1]
        <> case extractDatum out of
            Just (V2 facts@Live{})
                | lvAid facts == cxAid cx ->
                    [FrozenClause | lvFrozen facts]
                        <> [PoisonedClause | lvPoisoned facts]
                        <> [JuvenileClause | lvBornAt facts + maturityWindowMs > now]
            Just (V2 facts@TerminationPending{})
                | tpAid facts == cxAid cx -> [PendingClause]
            _ -> [DatumClause]
  where
    checkpointAddress =
        scriptAddr (scriptHashOf (cxCheckpointCredential cx))

-- | The quantity of the context's representative asset in an output.
representativeQuantity :: Context -> TxOut ConwayEra -> Integer
representativeQuantity cx out =
    case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            fromMaybe 0 $
                Map.lookup (PolicyID (scriptHashOf (cxStatePolicy cx))) assets
                    >>= Map.lookup (assetNameOf (representativeNameOf cx))

-- | The identifier and the birth of a checkpoint the chain holds, live.
liveFactsOf :: CheckpointInput -> IO (ByteString, Integer)
liveFactsOf input = case checkpointFacts input of
    facts@Live{} -> pure (lvAid facts, lvBornAt facts)
    _ -> fail "the checkpoint is not live"

{- | The time the consumer script is to read: at or after an instant, or at or
before it. The transaction's validity lower bound is the ceiling slot of the
first and the floor slot of the second.
-}
data Clock = NotBefore Integer | NotAfter Integer

clockMs :: Clock -> Integer
clockMs (NotBefore ms) = ms
clockMs (NotAfter ms) = ms

-- | Lock one output at the consumer's address and set a collateral aside.
lockOutput :: CheckpointEnv -> Consumer -> IO (Utxo, Utxo)
lockOutput env consumer = do
    let prov = envProvider env
        wallet = partyAddr consumerParty
    pp <- withinSecs 30 "query parameters" (queryProtocolParams prov)
    funding <-
        withinSecs 30 "query the consumer wallet" (queryUTxOs prov wallet)
            >>= \utxos -> case sortOn (Down . adaOf . snd) utxos of
                [] -> fail "the consumer wallet holds nothing"
                (largest : _) -> pure largest
    let locked =
            mkBasicTxOut
                (cageScriptAddr (cnProgram consumer) Testnet)
                (inject (Coin lockedAda))
        collateral = mkBasicTxOut wallet (inject (Coin 10_000_000))
        skeleton =
            mkBasicTx
                ( mkBasicTxBody
                    & outputsTxBodyL .~ StrictSeq.fromList [locked, collateral]
                )
    tx <- case balanceTx pp [funding] [] wallet skeleton of
        Left err -> fail ("lockOutput: " <> show err)
        Right r -> pure (balancedTx r)
    txId <- submitOk (envSubmitter env) (partyKey consumerParty) "lock" tx
    awaitOutputs prov (outputsOf txId [0, 1]) >>= \case
        [l, c] -> pure (l, c)
        _ -> fail "the lock transaction's outputs did not settle"

{- | Read a holding with a consumer at a time, and assert three things agree:
the story (exactly the clauses named fail), the Lean predicate over what the
chain holds, and the node. The node settles a spend when no clause fails and
refuses it, in Phase 2 of the consumer script alone, otherwise. The refusal's
transaction is built exactly as the accepting one: a fresh locked output at the
consumer's address, the same fee and collateral kinds, the same reference-input
shape.
-}
readHolding ::
    Reader ->
    Consumer ->
    Utxo ->
    Clock ->
    [Clause] ->
    String ->
    IO ()
readHolding rd consumer holding clock failing label = do
    let env = rdEnv rd
        prov = envProvider env
        key = partyKey consumerParty
        predicateFailing =
            failedClauses (cnContext consumer) (clockMs clock) (snd holding)
    -- a validity lower bound later than the chain's tip is a ledger refusal
    awaitChainTime env label (clockMs clock + 3_000)
    lowerSlot <-
        withinSecs 30 (label <> ": slot of the lower bound") $ case clock of
            NotBefore ms -> posixMsCeilSlot prov ms
            NotAfter ms -> posixMsToSlot prov ms
    (locked, collateral) <- lockOutput env consumer
    fee <-
        withinSecs 30 (label <> ": query the consumer wallet") (queryUTxOs prov (partyAddr consumerParty))
            >>= \wallet -> case sortOn (Down . adaOf . snd) (filter ((/= fst collateral) . fst) wallet) of
                [] -> fail (label <> ": no fee output")
                (u : _) -> pure u
    tx <-
        withinSecs 60 (label <> ": build the spend") $
            spendTx
                prov
                (cnProgram consumer)
                (cnHash consumer)
                (partyAddr consumerParty)
                locked
                fee
                collateral
                (fst holding)
                lowerSlot
    let spendPurpose =
            ConwaySpending
                (AsIx (spendingIndex (fst locked) (tx ^. bodyTxL . inputsTxBodyL)))
    observed <-
        withinSecs 120 (label <> ": evaluate") $
            evaluateTx prov (addKeyWitness key tx)
    nodeSettles <- case Map.toList observed of
        [(purpose, outcome)]
            | purpose == spendPurpose -> pure (either (const False) (const True) outcome)
        _ ->
            fail
                ( label
                    <> ": the node's evaluation is not the consumer's alone: "
                    <> take 400 (show (Map.toList observed))
                )
    unless (predicateFailing == failing && nodeSettles == null failing) $
        fail
            ( label
                <> ": the story names "
                <> show failing
                <> "; the predicate over the chain's output fails "
                <> show predicateFailing
                <> "; the node "
                <> if nodeSettles then "settles it" else "refuses it"
            )
    if nodeSettles
        then do
            txId <- submitOk (envSubmitter env) key label tx
            _ <- awaitOutputs prov (outputsOf txId [0])
            spent <-
                withinSecs 30 (label <> ": query the locked output") $
                    queryUTxOByTxIn prov (Set.singleton (fst locked))
            unless (Map.null spent) $
                fail (label <> ": the locked output was not spent")
            dbg (label <> ": settled as " <> show txId)
        else refusedInScript (envSubmitter env) key (cnHash consumer) label tx

-- | A consumer for the identity a checkpoint names, in the devnet's registry.
genuineConsumer :: Reader -> CheckpointInput -> IO (Consumer, Integer)
genuineConsumer rd input = do
    (aid, bornAt) <- liveFactsOf input
    pure (consumerOf rd (genuineContext (rdEnv rd) aid), bornAt)

{- | The readings of one journey that failed, each with its reason. A reading
that fails is recorded and the journey goes on to the next one, so that every
reading is judged on its own; the journey fails at its end if any did.
-}
type Findings = IORef [String]

reading :: Findings -> String -> IO () -> IO ()
reading findings label act =
    act `catch` \(e :: IOException) ->
        modifyIORef findings (<> [label <> ": " <> show e])

settleFindings :: Findings -> IO ()
settleFindings findings =
    readIORef findings >>= \case
        [] -> pure ()
        failures -> fail (unlines failures)

{- | A journey must hand the observer every stage its readings expect: a dropped
hand-over fails the journey, it does not skip the reading.
-}
expectStages :: IORef [Stage] -> [Stage] -> IO ()
expectStages stages expected = do
    seen <- readIORef stages
    let missing = filter (`notElem` seen) expected
    unless (null missing) $
        fail ("the journey never handed the observer " <> show missing)

{- | A registration booked through the application and folded by another party:
the checkpoint it delivered, read at the maturity boundary of its own datum.
One slot before the boundary the holding is juvenile and refused; at it, it is
settled. A consumer fixing another checkpoint credential refuses the same
holding for its address alone, and one fixing another seed for the missing
token alone.
-}
registeredHoldingJourney :: CheckpointEnv -> IO ()
registeredHoldingJourney env = do
    rd <- reader env
    findings <- newIORef []
    registered <- productionRegisterScenario env
    (genuine, bornAt) <- genuineConsumer rd registered
    let holding = checkpointUtxo registered
        cx = cnContext genuine
        boundary = bornAt + maturityWindowMs
        elsewhere =
            consumerOf
                rd
                cx{cxCheckpointCredential = scriptHashBytes (envApplicationHash env)}
        rivalSeed =
            consumerOf rd cx{cxSeedIndex = cxSeedIndex cx + 1}
    reading findings "context-is-the-genuine-release" $
        unless (representativeQuantity cx (snd holding) == 1) $
            fail "the context the registry environment gives does not name the token the genuine holding carries"
    reading findings "juvenile-holding-refused" $
        readHolding rd genuine holding (NotAfter (boundary - 1)) [JuvenileClause] "juvenile-holding-refused: one slot before born_at + W"
    reading findings "other-credential-refused" $
        readHolding rd elsewhere holding (NotBefore boundary) [AddressClause] "other-credential-refused"
    reading findings "other-registry-refused" $
        readHolding rd rivalSeed holding (NotBefore boundary) [QuantityClause] "other-registry-refused: a consumer fixing another seed"
    reading findings "genuine-holding-accepted-after-window" $
        readHolding rd genuine holding (NotBefore boundary) [] "genuine-holding-accepted-after-window: at born_at + W"
    settleFindings findings

{- | The frozen checkpoint a controller's honest freeze rotation left is refused
for its frozen mark alone, long after its maturity; the checkpoint the deposit
rotation restored, the same identity and the same birth, is settled.
-}
frozenThenRestored :: CheckpointEnv -> IO (Observer, IO ())
frozenThenRestored env = do
    rd <- reader env
    findings <- newIORef []
    stages <- newIORef []
    let observer stage checkpoint =
            modifyIORef stages (stage :) >> case (stage, checkpoint) of
                (Frozen, Just frozen) -> reading findings "frozen-holding-refused" $ do
                    (consumer, bornAt) <- genuineConsumer rd frozen
                    readHolding rd consumer (checkpointUtxo frozen) (NotBefore (bornAt + maturityWindowMs)) [FrozenClause] "frozen-holding-refused"
                (Restored, Just restored) -> reading findings "restored-holding-accepted" $ do
                    (consumer, bornAt) <- genuineConsumer rd restored
                    readHolding rd consumer (checkpointUtxo restored) (NotBefore (bornAt + maturityWindowMs)) [] "restored-holding-accepted"
                _ -> pure ()
    pure (observer, expectStages stages [Frozen, Restored] >> settleFindings findings)

{- | The standing checkpoint of an identity is settled; once convicted, the
pending output its conviction left is refused for its pending state alone; after
the terminating fold no output at the checkpoint validator holds the token. The
same count over the validator's outputs finds the token once while the pending
output stands, so an empty count after the fold is not an empty query.
-}
convictedReading :: CheckpointEnv -> IO (Observer, IO ())
convictedReading env = do
    rd <- reader env
    findings <- newIORef []
    stages <- newIORef []
    seen <- newIORef Nothing
    let known = readIORef seen >>= maybe (fail "no standing checkpoint was read") pure
        holders consumer =
            fmap
                (length . filter ((> 0) . representativeQuantity (cnContext consumer) . snd))
                . withinSecs 30 "query the checkpoint validator"
                $ queryUTxOs (envProvider env) (scriptAddr (envCheckpointHash env))
        observer stage checkpoint =
            modifyIORef stages (stage :) >> case (stage, checkpoint) of
                (Standing, Just standing) -> reading findings "standing-holding-accepted" $ do
                    (consumer, bornAt) <- genuineConsumer rd standing
                    writeIORef seen (Just (consumer, bornAt))
                    readHolding rd consumer (checkpointUtxo standing) (NotBefore (bornAt + maturityWindowMs)) [] "standing-holding-accepted"
                (Pending, Just left) -> do
                    reading findings "pending-termination-refused" $ do
                        (consumer, bornAt) <- known
                        readHolding rd consumer (checkpointUtxo left) (NotBefore (bornAt + maturityWindowMs)) [PendingClause] "pending-termination-refused"
                    reading findings "pending-output-holds-the-token" $ do
                        (consumer, _) <- known
                        count <- holders consumer
                        unless (count == 1) $
                            fail ("the pending output does not hold the representative token once: " <> show count)
                (Terminated, Nothing) -> reading findings "terminated-key-has-no-holding" $ do
                    (consumer, _) <- known
                    count <- holders consumer
                    unless (count == 0) $
                        fail ("an output at the checkpoint validator still holds the representative token after the terminating fold: " <> show count)
                _ -> pure ()
    pure
        ( observer
        , expectStages stages [Standing, Pending, Terminated] >> settleFindings findings
        )
