{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.ChainQuery.Koios.DecodeSpec
Description : #257 RED — Koios self-resolves extended outputs, fail-closed (A-001)

Per A-001 (ruling on Q-001): the Koios interpreter is the sole resolver of a
Koios registration snapshot. It decodes every ledger-relevant address,
value, datum, reference-script byte, and output identity from Koios's own
extended UTxO response (verified against the real Koios OpenAPI @utxo_infos@
schema — @address@, @value@, @datum_hash@, @inline_datum@, @reference_script@
\{hash,size,type,bytes\}, @asset_list@ — captured in this file's fixtures) and
reconstructs the exact ledger 'TxOut' a transaction builder needs, with no
N2C fallback. Conversion is total and fail-closed: a missing field, a
script-hash mismatch, or an unrepresentable output returns
'ChainQueryError', never a partial or invented value.
-}
module Cardano.KERI.ChainQuery.Koios.DecodeSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes, hashToBytes)
import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    interpreterConsistency,
    interpreterSource,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.Koios (
    decodeExtendedUtxoJson,
    koiosBoardCatalog,
    koiosCurrentCheckpoint,
    koiosInterpreter,
    koiosLiveCheckpoints,
 )
import Cardano.KERI.ChainQuery.LedgerOutput (
    chainAssetUtxoToLedgerOutput,
    chainReferenceToLedgerOutput,
 )
import Cardano.KERI.ChainQuery.Program (boardCatalog, payerUtxos, referenceScripts, storeWatermark)
import Cardano.KERI.ChainQuery.Types (
    BoardEntry,
    BoardLocator (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainReferenceScript (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySource (SourceKoios),
    SnapshotConsistency (AtomicLocal, LegacySequential),
 )
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Alonzo.Scripts (AlonzoEraScript (..))
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (Testnet), StrictMaybe (SJust, SNothing))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, hashScript)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3), Plutus (..), PlutusBinary (..))
import Codec.Binary.Bech32 qualified as Bech32
import Control.Monad (forM_, join, (>=>))
import Data.Aeson (decode)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Lens.Micro ((^.))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
    shouldReturn,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Koios (extended decode, A-001)" $ do
    describe "decodeExtendedUtxoJson" $ do
        it "decodes a complete extended payer output (verified Koios utxo_infos shape)" $ do
            case decode payerJson of
                Nothing -> fail "extended UTxO JSON literal failed to parse as JSON at all"
                Just value ->
                    case decodeExtendedUtxoJson value of
                        Left err -> fail ("expected a decode, got " <> show err)
                        Right utxo -> do
                            chainAssetTxId utxo `shouldBe` "f144a8264acf4bdfe2e1241170969c930d64ab6b0996a4a45237b623f1dd670e"
                            chainAssetIndex utxo `shouldBe` 0
                            chainAssetLovelace utxo `shouldBe` 5000000
                            chainAssetReferenceScript utxo `shouldBe` Nothing

        it "decodes a complete extended reference-script output" $ do
            case decode referenceJson of
                Nothing -> fail "extended UTxO JSON literal failed to parse as JSON at all"
                Just value ->
                    case decodeExtendedUtxoJson value of
                        Left err -> fail ("expected a decode, got " <> show err)
                        Right utxo ->
                            chainAssetReferenceScript utxo
                                `shouldBe` Just
                                    ChainReferenceScript
                                        { chainReferenceScriptHashField = "67f33146617a5e61936081db3b2117cbf59bd2123748f58ac9678656"
                                        , chainReferenceScriptType = "plutusV3"
                                        , chainReferenceScriptBytes = testScriptHex
                                        }

    describe "chainAssetUtxoToLedgerOutput (payer rows, DAT-257-ASSET-OUTPUT)" $ do
        it "reconstructs the exact address and lovelace value" $ do
            case chainAssetUtxoToLedgerOutput testPayerUtxo of
                Left err -> fail ("expected a resolved output, got " <> show err)
                Right (_txIn, txOut) -> do
                    txOut ^. valueTxOutL `shouldBe` MaryValue (Coin 5000000) mempty
                    txOut ^. referenceScriptTxOutL `shouldBe` SNothing

        it "fails closed on an unparseable address rather than inventing one" $ do
            let malformed = testPayerUtxo{chainAssetAddress = "not-a-bech32-address"}
                assertion :: IO ()
                assertion = case chainAssetUtxoToLedgerOutput malformed of
                    Left (DecodingFailure _) -> pure ()
                    other -> fail ("expected DecodingFailure, got " <> show other)
            assertion

    describe "chainReferenceToLedgerOutput (reference rows, DAT-257-REFERENCE)" $ do
        it "reconstructs a reference output whose script hash matches the request" $ do
            case chainReferenceToLedgerOutput testReference of
                Left err -> fail ("expected a resolved reference, got " <> show err)
                Right (_txIn, txOut) ->
                    case txOut ^. referenceScriptTxOutL of
                        SJust script -> hashScript script `shouldBe` hashScript testScript
                        SNothing -> fail "reconstructed reference output carries no reference script"

        it "fails closed when the decoded script bytes do not hash to the requested script hash" $ do
            let poisoned =
                    testReference
                        { chainReferenceScriptHash = "0000000000000000000000000000000000000000000000000000"
                        }
                assertion :: IO ()
                assertion = case chainReferenceToLedgerOutput poisoned of
                    Left (DecodingFailure _) -> pure ()
                    other -> fail ("expected a hash-mismatch DecodingFailure, got " <> show other)
            assertion

        it "fails closed when the output has no reference script at all" $ do
            let bare =
                    testReference
                        { chainReferenceOutput =
                            (chainReferenceOutput testReference){chainAssetReferenceScript = Nothing}
                        }
                assertion :: IO ()
                assertion = case chainReferenceToLedgerOutput bare of
                    Left (DecodingFailure _) -> pure ()
                    other -> fail ("expected DecodingFailure for a missing reference script, got " <> show other)
            assertion

    describe "Koios locator validation fails closed before any HTTP effect (DATA-INV-257-01)" $ do
        it "rejects every malformed checkpoint locator in the family"
            $ forM_
                [ CheckpointLocator "" "addr_test1checkpoint"
                , CheckpointLocator "policy-hex" ""
                , CheckpointLocator "" ""
                ]
            $ \locator ->
                koiosCurrentCheckpoint unreachableUrl Nothing locator "aid"
                    >>= (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects every malformed checkpoint locator for live-checkpoint enumeration"
            $ forM_
                [ CheckpointLocator "" "addr_test1checkpoint"
                , CheckpointLocator "policy-hex" ""
                ]
            $ koiosLiveCheckpoints unreachableUrl Nothing
                >=> (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects every malformed board locator in the family"
            $ forM_
                [ BoardLocator "" "addr_test1board"
                , BoardLocator "board-policy-hex" ""
                , BoardLocator "" ""
                ]
            $ koiosBoardCatalog unreachableUrl Nothing
                >=> (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects an empty payer address through the Koios interpreter, never issuing a request" $
            runChainQuery (koiosInterpreter unreachableUrl Nothing) (payerUtxos [""])
                >>= (`shouldSatisfy` isLeftInvalidLocator) . join

        it "rejects a non-empty checkpoint locator whose policy id is not canonical 28-byte hex, never issuing a request"
            $ forM_
                [ CheckpointLocator "not-hex-at-all" "addr_test1checkpoint"
                , -- valid hex, but the wrong decoded length (14 bytes, not 28)
                  CheckpointLocator "aabbccddeeff00112233445566" "addr_test1checkpoint"
                ]
            $ \locator ->
                koiosCurrentCheckpoint unreachableUrl Nothing locator "aid"
                    >>= (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects a non-empty checkpoint locator whose address is not canonical bech32, never issuing a request" $
            koiosCurrentCheckpoint unreachableUrl Nothing (CheckpointLocator canonicalPolicyHex "not-a-bech32-address") "aid"
                >>= (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects a non-empty board locator whose policy id is not canonical 28-byte hex, never issuing a request" $
            koiosBoardCatalog unreachableUrl Nothing (BoardLocator "not-hex-at-all" "addr_test1board")
                >>= (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects a non-empty board locator whose address is not canonical bech32, never issuing a request" $
            koiosBoardCatalog unreachableUrl Nothing (BoardLocator canonicalPolicyHex "not-a-bech32-address")
                >>= (`shouldSatisfy` isLeftInvalidLocator)

        it "rejects an empty payer-address set through the Koios interpreter, rather than answering it vacuously (NOTE-019)" $
            runChainQuery (koiosInterpreter unreachableUrl Nothing) (payerUtxos [])
                >>= (`shouldSatisfy` isLeftInvalidLocator) . join

        it "rejects a non-empty, non-canonical reference hash before any HTTP effect (NOTE-019)" $
            runChainQuery (koiosInterpreter unreachableUrl Nothing) (referenceScripts ["not-canonical-hex"])
                >>= (`shouldSatisfy` isLeftInvalidLocator) . join

        it "returns an empty result for an empty reference-hash list, a legal no-op shape, without any HTTP effect (NOTE-020 mandate ruling)" $
            join
                <$> runChainQuery (koiosInterpreter unreachableUrl Nothing) (referenceScripts [])
                `shouldReturn` Right []

        it "structurally rejects a buried invalid board locator reachable only via a real earlier operation's result, without ever invoking any interpreter field for it (NOTE-020)" $ do
            result <-
                runChainQuery
                    (poisonExceptWatermark (Populated testWatermark))
                    ( do
                        watermark <- storeWatermark
                        case watermark of
                            Cold -> pure (Right [])
                            Populated _ -> boardCatalog (BoardLocator "buried-bad-policy" "buried-bad-address")
                    )
            case result of
                Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

        it "structurally rejects a buried invalid reference-hash list reachable only via a real earlier operation's result, without ever invoking any interpreter field for it (NOTE-020)" $ do
            result <-
                runChainQuery
                    (poisonExceptWatermark (Populated testWatermark))
                    ( do
                        watermark <- storeWatermark
                        case watermark of
                            Cold -> pure (Right [])
                            Populated _ -> referenceScripts ["not-canonical-hex"]
                    )
            case result of
                Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

    describe "the actual production koiosInterpreter reports its own real provenance (not a fake stand-in), DATA-INV-257-03" $ do
        it "reports SourceKoios as its interpreter source" $
            interpreterSource (koiosInterpreter unreachableUrl Nothing) `shouldBe` SourceKoios

        it "reports LegacySequential as its interpreter consistency (INV-257-CONSISTENCY)" $
            interpreterConsistency (koiosInterpreter unreachableUrl Nothing) `shouldBe` LegacySequential

        it "never reports AtomicLocal, since Koios issues several independent calls rather than one shared-snapshot read" $
            interpreterConsistency (koiosInterpreter unreachableUrl Nothing) `shouldNotBe` AtomicLocal

    describe
        "#262 RQ-262-06 -- the Koios interpreter accounts EXPLICITLY for both \
        \new operation families, RED against the closed test-local stand-in"
        $ do
            it "answers the exact-output operation with a named UnsupportedOperation rather than a partial value, a fallback, or an HTTP attempt" $ do
                result <- capKoiosExactOutput redKoiosCapabilities koiosTxIdHex 0
                case result of
                    Left (UnsupportedOperation _) -> pure ()
                    other ->
                        fail
                            ( "expected Koios to account for the exact-output operation with a \
                              \named UnsupportedOperation, got "
                                <> show other
                            )

            it "answers the board/output operation with a named UnsupportedOperation, never falling through to the local interpreter" $ do
                result <-
                    capKoiosBoardOutputs
                        redKoiosCapabilities
                        canonicalPolicyHex
                        testAddressBech32
                case result of
                    Left (UnsupportedOperation _) -> pure ()
                    other ->
                        fail
                            ( "expected Koios to account for the board/output operation with a \
                              \named UnsupportedOperation, got "
                                <> show other
                            )

{- | The two \#262 operations as answered by the REAL production
'koiosInterpreter', behind a test-local adapter whose field types take the
locators' own pieces and are therefore identical before and after
implementation. RED closes both with a stand-in that reports the wrong
failure, so each example fails for exactly the missing accounting rather
than for a compilation reason.

'unreachableUrl' is the point: an interpreter that answered either operation
by dialing Koios would fail with a transport error instead of a named
'UnsupportedOperation', so these examples also witness that no HTTP call is
attempted.
-}
data KoiosCapabilities = KoiosCapabilities
    { capKoiosExactOutput ::
        Text -> Int -> IO (Either ChainQueryError ChainAssetUtxo)
    , capKoiosBoardOutputs ::
        Text -> Text -> IO (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
    }

redKoiosCapabilities :: KoiosCapabilities
redKoiosCapabilities =
    KoiosCapabilities
        { capKoiosExactOutput = \_txIdHex _index -> pure (Left notAccountedForYet)
        , capKoiosBoardOutputs = \_policyId _address -> pure (Left notAccountedForYet)
        }

notAccountedForYet :: ChainQueryError
notAccountedForYet =
    ProviderFailure
        "the Koios interpreter does not account for this operation family yet"

-- | A canonical lower-case 32-byte transaction id.
koiosTxIdHex :: Text
koiosTxIdHex = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 32 0x91))

{- | A genuine, checksum-valid testnet address: real ledger bytes
(mirroring 'Cardano.KERI.Indexer.ReadsSpec.checkpointLedgerAddress')
rendered through the real 'Bech32.encodeLenient' encoder, so decode
fidelity is proven against an address that actually round-trips rather
than a hand-typed literal whose checksum could not be verified by hand.
-}
testLedgerAddress :: Addr
testLedgerAddress =
    let scriptHash =
            ScriptHash $ case hashFromBytes (BS.replicate 28 0x41) of
                Just hash -> hash
                Nothing -> error "invalid script hash width"
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

testAddressBech32 :: Text
testAddressBech32 =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes (serialiseAddr testLedgerAddress))

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

testPayerUtxo :: ChainAssetUtxo
testPayerUtxo =
    ChainAssetUtxo
        { chainAssetTxId = "f144a8264acf4bdfe2e1241170969c930d64ab6b0996a4a45237b623f1dd670e"
        , chainAssetIndex = 0
        , chainAssetAddress = testAddressBech32
        , chainAssetLovelace = 5000000
        , chainAssetList = []
        , chainAssetInlineDatum = Nothing
        , chainAssetReferenceScript = Nothing
        }

{- | The requested script hash is computed from the SAME decoded script the
extended response carries (not an independently hand-typed hash whose
Blake2b-224 digest could not be verified by hand) — self-consistent by
construction, so this fixture cannot spuriously mismatch whatever
'chainReferenceToLedgerOutput' honestly recomputes.
-}
testReference :: ChainReference
testReference =
    ChainReference
        { chainReferenceScriptHash = testScriptHashHex
        , chainReferenceOutput =
            testPayerUtxo
                { chainAssetReferenceScript =
                    Just
                        ChainReferenceScript
                            { chainReferenceScriptHashField = testScriptHashHex
                            , chainReferenceScriptType = "plutusV3"
                            , chainReferenceScriptBytes = testScriptHex
                            }
                }
        }

{- | A minimal, syntactically valid PlutusV3 script body (the compiled form
of @\\_ -> ()@-shaped constant unit script), hex-encoded.
-}
testScriptHex :: Text
testScriptHex = "4e4d01000033222220051200120011"

testScript :: Script ConwayEra
testScript =
    case convertFromBase Base16 (TE.encodeUtf8 testScriptHex) of
        Left err -> error ("test fixture: invalid script hex: " <> err)
        Right bytes ->
            case mkPlutusScript (Plutus @PlutusV3 (PlutusBinary (SBS.toShort bytes))) of
                Just script -> fromPlutusScript script
                Nothing -> error "test fixture: invalid PlutusV3 script bytes"

testScriptHashHex :: Text
testScriptHashHex =
    let ScriptHash digest = hashScript testScript
     in TE.decodeUtf8 (convertToBase Base16 (hashToBytes digest))

payerJson :: ByteString
payerJson =
    "{\"tx_hash\":\"f144a8264acf4bdfe2e1241170969c930d64ab6b0996a4a45237b623f1dd670e\",\"tx_index\":0,\"address\":\"addr_test1vpu5vlrf4xkxv2qpwngf6cjhtw542ayty80v8dyr49rf5eg0yu80w\",\"value\":\"5000000\",\"datum_hash\":null,\"inline_datum\":null,\"reference_script\":null,\"asset_list\":[]}"

referenceJson :: ByteString
referenceJson =
    "{\"tx_hash\":\"f144a8264acf4bdfe2e1241170969c930d64ab6b0996a4a45237b623f1dd670e\",\"tx_index\":0,\"address\":\"addr_test1vpu5vlrf4xkxv2qpwngf6cjhtw542ayty80v8dyr49rf5eg0yu80w\",\"value\":\"5000000\",\"datum_hash\":null,\"inline_datum\":null,\"reference_script\":{\"hash\":\"67f33146617a5e61936081db3b2117cbf59bd2123748f58ac9678656\",\"size\":15,\"type\":\"plutusV3\",\"bytes\":\"4e4d01000033222220051200120011\",\"value\":null},\"asset_list\":[]}"

{- | Never actually dialed: every locator this file feeds it is malformed,
so the validation guard must short-circuit before any HTTP attempt.
-}
unreachableUrl :: Text
unreachableUrl = "https://unreachable.invalid"

{- | Every field except the watermark crashes if ever invoked (NOTE-020:
proving DATA-INV-257-01 structurally, not by enumeration). A program that
reads a genuine watermark result and branches to a buried invalid operation
must never reach that operation's interpreter field, however the buried
argument was derived -- if a deliberate boundary bypass ever let it through,
this interpreter observably crashes rather than silently answering.
-}
poisonExceptWatermark :: ColdOr ChainWatermark -> ChainQueryInterpreter IO
poisonExceptWatermark watermark =
    chainQueryInterpreter
        (\_ _ -> error "poison: current-checkpoint must never be reached")
        (\_ -> error "poison: live-checkpoints must never be reached")
        (\_ -> error "poison: reference-scripts must never be reached")
        (\_ -> error "poison: board-catalog must never be reached")
        (\_ -> error "poison: payer-utxos must never be reached")
        (pure (Right watermark))
        SourceKoios
        LegacySequential

{- | A non-degenerate, distinguishable watermark -- so the "populated" branch
of the buried-operation tests is genuinely reachable via a real interpreter
result, not a placeholder.
-}
testWatermark :: ChainWatermark
testWatermark = ChainWatermark 42 "aabbccdd"

{- | Canonical 28-byte hex script hash policy id (this file's canonical-shape
negative tests need the OTHER field to be genuinely canonical, so the
rejection is provably about the field under test).
-}
canonicalPolicyHex :: Text
canonicalPolicyHex = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x41))

isLeftInvalidLocator :: Either ChainQueryError a -> Bool
isLeftInvalidLocator (Left (InvalidLocator _)) = True
isLeftInvalidLocator _ = False
