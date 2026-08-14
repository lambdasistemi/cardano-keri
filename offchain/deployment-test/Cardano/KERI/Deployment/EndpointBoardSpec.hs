{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardSpec
Description : Genuine witness OOBI parsing and fail-closed board catalog tests
-}
module Cardano.KERI.Deployment.EndpointBoardSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.ChainQuery (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataJson)
import Cardano.KERI.Deployment.CLI (registerPreflight)
import Cardano.KERI.Deployment.EndpointBoard (
    AuthorizedBoardDatum (..),
    BoardAuthorization (..),
    BoardEntry (..),
    BoardNonce (..),
    EndpointRecord (..),
    LegacyBoardDatum (..),
    authorizedBoardDatumBytes,
    authorizedBoardDatumData,
    boardAuthorizationBytes,
    boardAuthorizationDomain,
    boardDatumIsAuthentic,
    decodeAuthorizedBoardDatum,
    decodeLegacyBoardDatum,
    legacyBoardDatumBytes,
    legacyBoardDatumData,
    parseEndpointRecord,
    reconstructBoardAuthorization,
    renderBoardCatalog,
    renderWatchability,
    resolveBoardCatalog,
    verifyBoardAuthorization,
    verifyBoardEndpointSignature,
    watchabilityGrade,
 )
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    parseInceptionExport,
 )
import Control.Monad (forM_)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )
import Text.Printf (printf)

spec :: Spec
spec = do
    describe "signed KERI endpoint record" $ do
        it "extracts and verifies the genuine witness-1 /loc/scheme reply" $ do
            record <- loadRecord
            endpointAid record
                `shouldBe` "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
            endpointScheme record `shouldBe` "https"
            endpointUrl record
                `shouldBe` "https://witness-1.preprod.plutimus.com/"
            BS.length (endpointWitnessKey record) `shouldBe` 32
            BS.length (endpointSignature record) `shouldBe` 64
            BS.take 1 (endpointEventBytes record) `shouldBe` "{"

        it "verifies every genuine preprod witness OOBI"
            $ forM_
                [
                    ( "witness-1-oobi.cesr"
                    , "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
                    , "https://witness-1.preprod.plutimus.com/"
                    )
                ,
                    ( "witness-2-oobi.cesr"
                    , "BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B"
                    , "https://witness-2.preprod.plutimus.com/"
                    )
                ,
                    ( "witness-3-oobi.cesr"
                    , "BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4"
                    , "https://witness-3.preprod.plutimus.com/"
                    )
                ]
            $ \(name, aid, url) -> do
                record <-
                    loadFixtureNamed name
                        >>= expectRight . parseEndpointRecord
                endpointAid record `shouldBe` aid
                endpointUrl record `shouldBe` url

        it "rejects a changed endpoint when the CESR signature is retained" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "witness-1" "witness-X" bytes)
                `shouldSatisfy` isLeftContaining "SAID"

        it "rejects an unsupported route instead of accepting another reply" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "/loc/scheme" "/bad/scheme" bytes)
                `shouldSatisfy` isLeftContaining "/loc/scheme"

        it "rejects malformed endpoint attachment material" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "-CABBCZT" "-CABCCZT" bytes)
                `shouldSatisfy` isLeftContaining "signer"

    describe "fail-closed endpoint board catalog" $ do
        it "decodes an authentic marker and renders its source output" $ do
            record <- loadRecord
            entries <-
                expectRight $
                    resolveBoardCatalog policy markerAddress [validUtxo record]
            entries `shouldBe` [expectedEntry record 0]
            T.unpack (renderBoardCatalog entries)
                `shouldContain` T.unpack (endpointAid record)
            T.unpack (renderBoardCatalog entries)
                `shouldContain` "verified"
            T.unpack (renderBoardCatalog entries)
                `shouldContain` (T.unpack txId <> "#0")

        it "surfaces every valid unspent duplicate in output-reference order" $ do
            record <- loadRecord
            let second =
                    (validUtxo record)
                        { chainAssetTxId = T.replicate 64 "2"
                        , chainAssetIndex = 3
                        }
            resolveBoardCatalog policy markerAddress [second, validUtxo record]
                `shouldBe` Right
                    [ expectedEntry record 0
                    , (expectedEntry record 3)
                        { boardTxId = T.replicate 64 "2"
                        }
                    ]

        it "rejects the whole catalog and names a wrong-address output" $ do
            record <- loadRecord
            resolveBoardCatalog
                policy
                markerAddress
                [(validUtxo record){chainAssetAddress = "addr_test1wrong"}]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")

        it "rejects wrong marker quantity, policy, and asset-name binding" $ do
            record <- loadRecord
            let marker = onlyMarker record
                cases =
                    [ [marker{chainAssetQuantity = 2}]
                    , [marker{chainAssetPolicy = "wrong"}]
                    , [marker{chainAssetName = T.replicate 64 "0"}]
                    ]
                resolve assets =
                    resolveBoardCatalog
                        policy
                        markerAddress
                        [(validUtxo record){chainAssetList = assets}]
            map resolve cases
                `shouldSatisfy` all
                    (isLeftContaining $ T.unpack txId <> "#0")

        it "rejects malformed datum and retained-signature event tampering" $ do
            record <- loadRecord
            let malformed =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just (plutusDataJson $ Constr 0 [B "short"])
                        }
                forged =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just $
                                plutusDataJson $
                                    Constr
                                        0
                                        [ B (endpointWitnessKey record)
                                        , B $
                                            replaceOnce
                                                "witness-1"
                                                "witness-X"
                                                (endpointEventBytes record)
                                        , B (endpointSignature record)
                                        , B owner
                                        ]
                        }
            resolveBoardCatalog policy markerAddress [malformed]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")
            resolveBoardCatalog policy markerAddress [forged]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")

        it "rejects a witness-supplied non-KERI version before trusting it" $ do
            record <- loadRecord
            let versionDrift =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just $
                                plutusDataJson $
                                    Constr
                                        0
                                        [ B (endpointWitnessKey record)
                                        , B $
                                            replaceOnce
                                                "KERI10JSON"
                                                "KERI11JSON"
                                                (endpointEventBytes record)
                                        , B (endpointSignature record)
                                        , B owner
                                        ]
                        }
            resolveBoardCatalog policy markerAddress [versionDrift]
                `shouldSatisfy` isLeftContaining "version"

    boardAuthorizationSpec

    describe "checkpoint witness watchability" $ do
        it "grades 0/0, absent, partial, complete, and duplicate records" $ do
            inception <- loadWitnessedInception
            pool <- loadPoolEntries
            let witnesses = cdWitnesses (inceptionDatum inception)
            watchabilityGrade [] [] `shouldBe` (0, 0)
            watchabilityGrade witnesses [] `shouldBe` (0, 3)
            watchabilityGrade witnesses (take 2 pool) `shouldBe` (2, 3)
            watchabilityGrade witnesses pool `shouldBe` (3, 3)
            watchabilityGrade witnesses (take 1 pool <> pool)
                `shouldBe` (3, 3)
            renderWatchability witnesses (take 2 pool)
                `shouldBe` "watchable 2/3"

        it "refuses missing witnesses and accepts complete or explicit override" $ do
            inception <- loadWitnessedInception
            pool <- loadPoolEntries
            registerPreflight "preprod" 1 False False 0 [] inception
                `shouldSatisfy` isLeftContaining "3/3"
            registerPreflight
                "preprod"
                1
                False
                False
                0
                (take 2 pool)
                inception
                `shouldSatisfy` isLeftContaining "1/3"
            registerPreflight "preprod" 1 False False 0 pool inception
                `shouldBe` Right ()
            registerPreflight "preprod" 1 True False 0 [] inception
                `shouldBe` Right ()

{- | #253 S253-2. The golden constants below come from an oracle that shares
no code with this implementation (independent CBOR encoder written from
RFC 8949 plus the canonical Plutus @serialiseData@ rules, and Ed25519 from
OpenSSL via Node). The identical constants are asserted from Aiken in
@endpoint_board_authorization_tests.ak@, so agreement on both sides is byte
parity between the two languages rather than either one describing itself.

The S253-2 protocol carries no sequence, no datum version, no version-only
constructor and no stored origin. Both shapes are constructor 0 and are told
apart by field count alone, which is why the field-count cases below are
load-bearing rather than decorative.
-}
boardAuthorizationSpec :: Spec
boardAuthorizationSpec = describe "board authorization" $ do
    describe "canonical signed bytes" $ do
        it "freezes the stable, unversioned domain separator" $
            boardAuthorizationDomain
                `shouldBe` "cardano-keri/endpoint-board/authorization"

        it "matches the independent oracle" $
            boardAuthorizationBytes
                (reconstructBoardAuthorization policyIdBytes smallDatum)
                `shouldBe` smallGoldenAuthorization

        it "matches the oracle for a chunked record" $
            -- 65 record bytes force indefinite-length chunked CBOR. With the
            -- sequence field cut, the record is the only remaining forcing
            -- case, so a naive encoder passes every short vector and fails
            -- exactly here.
            boardAuthorizationBytes
                (reconstructBoardAuthorization policyIdBytes chunkedDatum)
                `shouldBe` chunkedGoldenAuthorization

        it "takes its policy id from the verifier, not the datum" $
            boardAuthPolicyId
                (reconstructBoardAuthorization otherPolicyBytes smallDatum)
                `shouldBe` otherPolicyBytes

        it "reproduces the oracle's signature from the frozen seed" $ do
            -- Binds our Ed25519 (cardano-crypto-class) to the oracle's
            -- (OpenSSL): same seed, same key, same signature bytes.
            testWitnessKey `shouldBe` frozenWitnessKey
            signTest smallGoldenAuthorization
                `shouldBe` smallGoldenSignature

    describe "frozen structural wire" $ do
        it "keeps the legacy shape at constructor 0 with four fields" $
            legacyBoardDatumBytes smallLegacyDatum
                `shouldBe` smallGoldenLegacyDatum

        it "puts the authorized shape at constructor 0 with six fields" $ do
            authorizedBoardDatumBytes smallDatum
                `shouldBe` smallGoldenAuthorizedDatum
            authorizedBoardDatumBytes chunkedDatum
                `shouldBe` chunkedGoldenAuthorizedDatum

        it "distinguishes the two shapes by field count, not constructor" $ do
            constructorIndexOf (legacyBoardDatumData smallLegacyDatum)
                `shouldBe` Just 0
            constructorIndexOf (authorizedBoardDatumData smallDatum)
                `shouldBe` Just 0
            fieldCountOf (legacyBoardDatumData smallLegacyDatum)
                `shouldBe` Just 4
            fieldCountOf (authorizedBoardDatumData smallDatum)
                `shouldBe` Just 6

        it "round trips both shapes exactly" $ do
            decodeLegacyBoardDatum (legacyBoardDatumData smallLegacyDatum)
                `shouldBe` Right smallLegacyDatum
            decodeAuthorizedBoardDatum
                policyIdBytes
                (authorizedBoardDatumData smallDatum)
                `shouldBe` Right smallDatum
            decodeAuthorizedBoardDatum
                policyIdBytes
                (authorizedBoardDatumData chunkedDatum)
                `shouldBe` Right chunkedDatum

        it "still decodes a frozen four-field legacy datum" $
            decodeLegacyBoardDatum
                ( Constr
                    0
                    [ B frozenWitnessKey
                    , B smallRecord
                    , B smallEndpointSignature
                    , B owner
                    ]
                )
                `shouldBe` Right smallLegacyDatum

        it "refuses each shape in the other's decoder" $ do
            -- Six-field data is not a legacy record, and four-field data is
            -- not an authorized one. Neither is silently truncated or padded.
            decodeLegacyBoardDatum (authorizedBoardDatumData smallDatum)
                `shouldSatisfy` isLeft
            decodeAuthorizedBoardDatum
                policyIdBytes
                (legacyBoardDatumData smallLegacyDatum)
                `shouldSatisfy` isLeft

        it "rejects unknown constructors and neighbouring field counts" $ do
            let authorizedFields = fieldsOf (authorizedBoardDatumData smallDatum)
                cases =
                    [ Constr 1 authorizedFields
                    , Constr 2 []
                    , Constr 3 [B frozenWitnessKey]
                    , Constr 0 [B frozenWitnessKey]
                    , -- one short and one long of the authorized shape
                      Constr 0 (take 5 authorizedFields)
                    , Constr 0 (authorizedFields <> [I 0])
                    , I 1
                    , B "not a datum"
                    , List []
                    ]
            map decodeLegacyBoardDatum cases `shouldSatisfy` all isLeft
            map (decodeAuthorizedBoardDatum policyIdBytes) cases
                `shouldSatisfy` all isLeft

        it "rejects a well-shaped datum with a mistyped field" $ do
            let authorizedFields = fieldsOf (authorizedBoardDatumData smallDatum)
                mistyped =
                    [ -- witness key as an integer
                      Constr 0 (I 0 : drop 1 authorizedFields)
                    , -- nonce as a flat bytestring instead of Constr 0
                      Constr
                        0
                        ( take 4 authorizedFields
                            <> [B ""]
                            <> drop 5 authorizedFields
                        )
                    , -- nonce index as bytes
                      Constr
                        0
                        ( take 4 authorizedFields
                            <> [Constr 0 [B (BS.replicate 32 0x11), B "0"]]
                            <> drop 5 authorizedFields
                        )
                    , -- authorization signature as an integer
                      Constr 0 (take 5 authorizedFields <> [I 0])
                    ]
            map (decodeAuthorizedBoardDatum policyIdBytes) mistyped
                `shouldSatisfy` all isLeft

        it "refuses to decode an authorized datum under a foreign policy" $
            -- The decoder is handed the applied policy, so the same bytes
            -- that authenticate under their own release do not authenticate
            -- under another one.
            decodeAuthorizedBoardDatum
                otherPolicyBytes
                (authorizedBoardDatumData smallDatum)
                `shouldSatisfy` isLeft

    describe "witness authorization" $ do
        it "accepts a genuine authorization for both vectors" $ do
            verifyBoardAuthorization policyIdBytes smallDatum
                `shouldBe` True
            verifyBoardAuthorization policyIdBytes chunkedDatum
                `shouldBe` True

        it "accepts a fully authentic authorized datum" $
            boardDatumIsAuthentic frozenWitnessKey policyIdBytes smallDatum
                `shouldBe` True

        -- INV-253-SIGNED-FIELDS: each mutant changes exactly one ordered
        -- signed component and leaves every other field, and both
        -- signatures, individually valid.
        it "rejects a mutation of every ordered signed field" $ do
            let mutants :: [(String, ByteString, AuthorizedBoardDatum)]
                mutants =
                    [ ("policy id", policyIdBytes', smallDatum)
                    ,
                        ( "witness key"
                        , policyIdBytes
                        , smallDatum
                            { authorizedWitnessKey = foreignWitnessKey
                            , authorizedSignature =
                                foreignSignature
                            }
                        )
                    ,
                        ( "endpoint record"
                        , policyIdBytes
                        , smallDatum
                            { authorizedEndpointRecord = "loc/scheme-vector-2"
                            }
                        )
                    ,
                        ( "owner key hash"
                        , policyIdBytes
                        , smallDatum
                            { authorizedOwnerKeyHash = BS.replicate 28 0x44
                            }
                        )
                    ,
                        ( "nonce tx id"
                        , policyIdBytes
                        , smallDatum
                            { authorizedNonce =
                                BoardNonce (BS.replicate 32 0x31) 0
                            }
                        )
                    ,
                        ( "nonce output index"
                        , policyIdBytes
                        , smallDatum
                            { authorizedNonce =
                                BoardNonce (BS.replicate 32 0x11) 1
                            }
                        )
                    ]
                verdicts =
                    [ (label, verifyBoardAuthorization policyId' datum)
                    | (label, policyId', datum) <- mutants
                    ]
            verdicts `shouldBe` [(label, False) | (label, _, _) <- mutants]

        it "keeps the domain inside the signed bytes" $ do
            -- The domain is a constant, so it is mutated where it is used. A
            -- sibling cardano-keri domain is the control: the retired
            -- versioned spelling cannot appear in a protocol file.
            let otherDomain =
                    (reconstructBoardAuthorization policyIdBytes smallDatum)
                        { boardAuthDomain =
                            "cardano-keri/endpoint-board/attestation"
                        }
            boardAuthorizationBytes otherDomain
                `shouldBe` wrongDomainGoldenAuthorization
            boardAuthorizationBytes otherDomain
                `shouldSatisfy` (/= smallGoldenAuthorization)

        it "rejects a genuine signature by a foreign signer" $
            verifyBoardAuthorization
                policyIdBytes
                smallDatum{authorizedSignature = foreignSignature}
                `shouldBe` False

        -- INV-253-WITNESS-AUTH: neither signature stands in for the other.
        it "refuses to promote on the endpoint signature alone" $ do
            let datum =
                    smallDatum
                        { authorizedSignature =
                            chunkedGoldenSignature
                        }
            verifyBoardEndpointSignature datum `shouldBe` True
            verifyBoardAuthorization policyIdBytes datum `shouldBe` False
            boardDatumIsAuthentic frozenWitnessKey policyIdBytes datum
                `shouldBe` False

        it "refuses to promote on the authorization alone" $ do
            let datum =
                    smallDatum
                        { authorizedEndpointSignature = chunkedEndpointSignature
                        }
            verifyBoardAuthorization policyIdBytes datum `shouldBe` True
            verifyBoardEndpointSignature datum `shouldBe` False
            boardDatumIsAuthentic frozenWitnessKey policyIdBytes datum
                `shouldBe` False

        it "rejects wrong widths, wrong key, and a negative index" $ do
            let cases :: [(String, ByteString, AuthorizedBoardDatum)]
                cases =
                    [ ("expected key", foreignWitnessKey, smallDatum)
                    ,
                        ( "short witness key"
                        , BS.take 31 frozenWitnessKey
                        , smallDatum
                            { authorizedWitnessKey =
                                BS.take 31 frozenWitnessKey
                            }
                        )
                    ,
                        ( "empty record"
                        , frozenWitnessKey
                        , smallDatum{authorizedEndpointRecord = ""}
                        )
                    ,
                        ( "short endpoint signature"
                        , frozenWitnessKey
                        , smallDatum
                            { authorizedEndpointSignature =
                                BS.take 63 smallEndpointSignature
                            }
                        )
                    ,
                        ( "short authorization signature"
                        , frozenWitnessKey
                        , smallDatum
                            { authorizedSignature =
                                BS.take 63 smallGoldenSignature
                            }
                        )
                    ,
                        ( "short owner hash"
                        , frozenWitnessKey
                        , smallDatum
                            { authorizedOwnerKeyHash = BS.replicate 27 0x33
                            }
                        )
                    ,
                        ( "negative nonce index"
                        , frozenWitnessKey
                        , smallDatum
                            { authorizedNonce =
                                BoardNonce (BS.replicate 32 0x11) (-1)
                            }
                        )
                    ,
                        ( "short nonce tx id"
                        , frozenWitnessKey
                        , smallDatum
                            { authorizedNonce =
                                BoardNonce (BS.replicate 31 0x11) 0
                            }
                        )
                    ]
                verdicts =
                    [ ( label
                      , boardDatumIsAuthentic key policyIdBytes datum
                      )
                    | (label, key, datum) <- cases
                    ]
            verdicts `shouldBe` [(label, False) | (label, _, _) <- cases]

    describe "authorized catalog promotion" $ do
        it "promotes a record only when both signatures verify" $
            resolveBoardCatalog policy markerAddress [syntheticAuthorizedUtxo]
                `shouldBe` Right [syntheticEntry]

        it "refuses every single-signature and post-signature mutation" $ do
            let variants :: [(String, ByteString)]
                variants =
                    [ ("no authorization", chunkedGoldenSignature)
                    , ("foreign authorization", foreignSignature)
                    ]
                bound :: [(String, AuthorizedBoardDatum)]
                bound =
                    [ ("owner", syntheticDatum{authorizedOwnerKeyHash = other28})
                    ,
                        ( "nonce"
                        , syntheticDatum
                            { authorizedNonce =
                                BoardNonce (BS.replicate 32 0x77) 2
                            }
                        )
                    ]
                resolve datum =
                    resolveBoardCatalog
                        policy
                        markerAddress
                        [utxoWithDatum (authorizedBoardDatumData datum)]
            map
                ( \(_, signature) ->
                    resolve
                        syntheticDatum
                            { authorizedSignature = signature
                            }
                )
                variants
                `shouldSatisfy` all isLeft
            map (resolve . snd) bound `shouldSatisfy` all isLeft

        it "refuses an authorized datum whose endpoint signature is broken" $
            resolveBoardCatalog
                policy
                markerAddress
                [ utxoWithDatum . authorizedBoardDatumData $
                    syntheticDatum
                        { authorizedEndpointSignature = chunkedEndpointSignature
                        }
                ]
                `shouldSatisfy` isLeft

        it "refuses to lift a genuine legacy record by copying it" $ do
            -- The real preprod witness signed its endpoint bytes and nothing
            -- else, so no authorization over them can exist.
            record <- loadRecord
            let lifted =
                    AuthorizedBoardDatum
                        { authorizedWitnessKey = endpointWitnessKey record
                        , authorizedEndpointRecord = endpointEventBytes record
                        , authorizedEndpointSignature = endpointSignature record
                        , authorizedOwnerKeyHash = owner
                        , authorizedNonce = BoardNonce (BS.replicate 32 0x11) 0
                        , authorizedSignature = smallGoldenSignature
                        }
            resolveBoardCatalog
                policy
                markerAddress
                [ (utxoWithDatum $ authorizedBoardDatumData lifted)
                    { chainAssetList = [onlyMarker record]
                    }
                ]
                `shouldSatisfy` isLeft

        it "still promotes a frozen legacy record unchanged" $ do
            record <- loadRecord
            resolveBoardCatalog policy markerAddress [validUtxo record]
                `shouldBe` Right [expectedEntry record 0]

constructorIndexOf :: Data -> Maybe Integer
constructorIndexOf = \case
    Constr index _ -> Just index
    _ -> Nothing

fieldCountOf :: Data -> Maybe Int
fieldCountOf = fmap length . fieldsOfMaybe

fieldsOf :: Data -> [Data]
fieldsOf datum =
    case fieldsOfMaybe datum of
        Just fields -> fields
        Nothing -> error "EndpointBoardSpec: board datum is not a constructor"

fieldsOfMaybe :: Data -> Maybe [Data]
fieldsOfMaybe = \case
    Constr _ fields -> Just fields
    _ -> Nothing

policy, markerAddress, txId :: Text
policy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
markerAddress = "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"
txId = T.replicate 64 "1"

owner :: ByteString
owner = BS.replicate 28 0x33

validUtxo :: EndpointRecord -> ChainAssetUtxo
validUtxo record =
    ChainAssetUtxo
        { chainAssetTxId = txId
        , chainAssetIndex = 0
        , chainAssetAddress = markerAddress
        , chainAssetLovelace = 2_000_000
        , chainAssetList = [onlyMarker record]
        , chainAssetInlineDatum =
            Just $
                plutusDataJson $
                    Constr
                        0
                        [ B (endpointWitnessKey record)
                        , B (endpointEventBytes record)
                        , B (endpointSignature record)
                        , B owner
                        ]
        , chainAssetReferenceScript = Nothing
        }

onlyMarker :: EndpointRecord -> ChainAsset
onlyMarker record =
    ChainAsset
        { chainAssetPolicy = policy
        , chainAssetName =
            TE.decodeUtf8 (convertToBase Base16 $ endpointWitnessKey record)
        , chainAssetQuantity = 1
        }

expectedEntry :: EndpointRecord -> Int -> BoardEntry
expectedEntry record index =
    BoardEntry
        { boardWitnessKey = endpointWitnessKey record
        , boardAid = endpointAid record
        , boardScheme = endpointScheme record
        , boardUrl = endpointUrl record
        , boardTxId = txId
        , boardIndex = index
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = owner
        }

loadRecord :: IO EndpointRecord
loadRecord = loadFixture >>= expectRight . parseEndpointRecord

loadFixture :: IO ByteString
loadFixture = loadFixtureNamed "witness-1-oobi.cesr"

loadFixtureNamed :: FilePath -> IO ByteString
loadFixtureNamed name = do
    path <-
        getDataFileName
            ("deployment-test/fixtures/" <> name)
    BS.readFile path

loadWitnessedInception :: IO InceptionExport
loadWitnessedInception = do
    path <-
        getDataFileName
            "deployment-test/fixtures/kli-export-2-of-5.cesr"
    BS.readFile path >>= expectRight . parseInceptionExport

loadPoolEntries :: IO [BoardEntry]
loadPoolEntries =
    sequence
        [ loadFixtureNamed ("witness-" <> show index <> "-oobi.cesr")
            >>= expectRight . parseEndpointRecord
            >>= \record ->
                pure
                    ( (expectedEntry record index)
                        { boardTxId = T.replicate 63 "0" <> T.pack (show index)
                        }
                    )
        | index <- [1 .. 3]
        ]

expectRight :: Either String a -> IO a
expectRight = \case
    Left err -> expectationFailure err >> fail err
    Right value -> pure value

replaceOnce :: ByteString -> ByteString -> ByteString -> ByteString
replaceOnce needle replacement haystack =
    case BS.breakSubstring needle haystack of
        (before, after)
            | BS.null after -> haystack
            | otherwise ->
                before
                    <> replacement
                    <> BS.drop (BS.length needle) after

isLeftContaining :: String -> Either String a -> Bool
isLeftContaining needle = \case
    Left err -> T.pack needle `T.isInfixOf` T.pack err
    Right _ -> False

-- ---------------------------------------------------------------
-- #253 S253-1 frozen vectors, shared byte-for-byte with Aiken
-- ---------------------------------------------------------------

hex :: ByteString -> ByteString
hex encoded =
    case convertFromBase Base16 encoded of
        Right bytes -> bytes
        Left err -> error ("EndpointBoardSpec: bad vector hex: " <> err)

{- | The frozen test witness seed. Test material only: it exists so both
languages can verify the same signature, and no production path reads it.
-}
testSeed :: ByteString
testSeed =
    hex "5323531f0000000000000000000000000000000000000000000000000000abcd"

testSignKey :: SignKeyDSIGN Ed25519DSIGN
testSignKey = genKeyDSIGN (mkSeedFromBytes testSeed)

testWitnessKey :: ByteString
testWitnessKey = rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN testSignKey)

signTest :: ByteString -> ByteString
signTest message =
    rawSerialiseSigDSIGN (signDSIGN () message testSignKey)

frozenWitnessKey :: ByteString
frozenWitnessKey =
    hex "d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

foreignWitnessKey :: ByteString
foreignWitnessKey =
    hex "332ebe8d27cb7323b3a401c1c13b5dd64bccc0e10ecda1c2b5d11a03779a85e5"

foreignSignature :: ByteString
foreignSignature =
    hex
        "8eeaee81b6110a87c0737157c8ba317947b7aa1d4b23ec340ab679456f9f9716\
        \08488ead6d22d4dd1b0bf4a52081e1aa6913f0bba5e02c0c8718404ffd9b6b07"

policyIdBytes, policyIdBytes', otherPolicyBytes :: ByteString
policyIdBytes = hex "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
policyIdBytes' = hex "00494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
otherPolicyBytes = BS.replicate 28 0x5a

other28 :: ByteString
other28 = BS.replicate 28 0x44

smallRecord :: ByteString
smallRecord = "loc/scheme-vector-1"

smallEndpointSignature :: ByteString
smallEndpointSignature =
    hex
        "1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6\
        \989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

smallGoldenSignature :: ByteString
smallGoldenSignature =
    hex
        "61c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77b021\
        \3b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba8006"

chunkedRecord :: ByteString
chunkedRecord = BS.replicate 64 0xaa <> BS.singleton 0xbb

chunkedEndpointSignature :: ByteString
chunkedEndpointSignature =
    hex
        "7ad2ae84bf3feb749b85d8110cd9e03f6006eb9c58e4ab542935c67b24035f53\
        \1925dbb19832099f3620494878669083ecb4e707851d9b7f972859ad53d3e50e"

chunkedGoldenSignature :: ByteString
chunkedGoldenSignature =
    hex
        "d41f3c0b60c053d57b1bfc4bebebdb3bb8730880730ad90a1ac9a82c630da240\
        \11eb56050c6af1d29999c05db572d856baf098b0c2e439e628fa6d3369edbc05"

smallDatum :: AuthorizedBoardDatum
smallDatum =
    AuthorizedBoardDatum
        { authorizedWitnessKey = frozenWitnessKey
        , authorizedEndpointRecord = smallRecord
        , authorizedEndpointSignature = smallEndpointSignature
        , authorizedOwnerKeyHash = owner
        , authorizedNonce = BoardNonce (BS.replicate 32 0x11) 0
        , authorizedSignature = smallGoldenSignature
        }

smallLegacyDatum :: LegacyBoardDatum
smallLegacyDatum =
    LegacyBoardDatum
        { legacyWitnessKey = frozenWitnessKey
        , legacyEndpointRecord = smallRecord
        , legacyEndpointSignature = smallEndpointSignature
        , legacyOwnerKeyHash = owner
        }

chunkedDatum :: AuthorizedBoardDatum
chunkedDatum =
    AuthorizedBoardDatum
        { authorizedWitnessKey = frozenWitnessKey
        , authorizedEndpointRecord = chunkedRecord
        , authorizedEndpointSignature = chunkedEndpointSignature
        , authorizedOwnerKeyHash = owner
        , authorizedNonce = BoardNonce (BS.replicate 32 0x22) 5
        , authorizedSignature = chunkedGoldenSignature
        }

smallGoldenAuthorization :: ByteString
smallGoldenAuthorization =
    hex
        "d8799f582963617264616e6f2d6b6572692f656e64706f696e742d626f617264\
        \2f617574686f72697a6174696f6e581c54494f8a1b2930241b7b9fa010f61f2c\
        \f6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6d\
        \d4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f72\
        \2d31581c33333333333333333333333333333333333333333333333333333333\
        \d8799f582011111111111111111111111111111111111111111111111111111\
        \1111111111100ffff"

chunkedGoldenAuthorization :: ByteString
chunkedGoldenAuthorization =
    hex
        "d8799f582963617264616e6f2d6b6572692f656e64706f696e742d626f617264\
        \2f617574686f72697a6174696f6e581c54494f8a1b2930241b7b9fa010f61f2c\
        \f6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6d\
        \d4d240206fa657f7afe125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\
        \aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\
        \aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41bbff581c33333333333333333333\
        \333333333333333333333333333333333333d8799f5820222222222222222222\
        \222222222222222222222222222222222222222222222205ffff"

wrongDomainGoldenAuthorization :: ByteString
wrongDomainGoldenAuthorization =
    hex
        "d8799f582763617264616e6f2d6b6572692f656e64706f696e742d626f617264\
        \2f6174746573746174696f6e581c54494f8a1b2930241b7b9fa010f61f2cf630\
        \7daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d2\
        \40206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d31\
        \581c33333333333333333333333333333333333333333333333333333333d879\
        \9f58201111111111111111111111111111111111111111111111111111111111\
        \11111100ffff"

smallGoldenLegacyDatum :: ByteString
smallGoldenLegacyDatum =
    hex
        "d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7af\
        \e125f54729536c6f632f736368656d652d766563746f722d3158401a809536db\
        \02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9eb\
        \bd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c333333\
        \33333333333333333333333333333333333333333333333333ff"

smallGoldenAuthorizedDatum :: ByteString
smallGoldenAuthorizedDatum =
    hex
        "d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7af\
        \e125f54729536c6f632f736368656d652d766563746f722d3158401a809536db\
        \02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9eb\
        \bd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c333333\
        \33333333333333333333333333333333333333333333333333d8799f58201111\
        \11111111111111111111111111111111111111111111111111111111111100ff\
        \584061c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77\
        \b0213b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba\
        \8006ff"

chunkedGoldenAuthorizedDatum :: ByteString
chunkedGoldenAuthorizedDatum =
    hex
        "d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7af\
        \e125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\
        \aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\
        \aaaaaaaaaaaaaaaa41bbff58407ad2ae84bf3feb749b85d8110cd9e03f6006eb\
        \9c58e4ab542935c67b24035f531925dbb19832099f3620494878669083ecb4e7\
        \07851d9b7f972859ad53d3e50e581c3333333333333333333333333333333333\
        \3333333333333333333333d8799f582022222222222222222222222222222222\
        \2222222222222222222222222222222205ff5840d41f3c0b60c053d57b1bfc4b\
        \ebebdb3bb8730880730ad90a1ac9a82c630da24011eb56050c6af1d29999c05d\
        \b572d856baf098b0c2e439e628fa6d3369edbc05ff"

-- ---------------------------------------------------------------
-- A complete synthetic authorized record, signed by the frozen test key
-- ---------------------------------------------------------------

{- | A genuine @\/loc\/scheme@ reply event for the frozen test key: correct
embedded size, correct Blake3 SAID over its own blanked bytes, and an @eid@
that is this key's non-transferable CESR spelling. The real preprod fixtures
cannot be used for a positive authorized case because nobody outside the
witness can produce an authorization signature for them.
-}
syntheticEvent :: ByteString
syntheticEvent = body sizeHex (qb64Aid $ blake3Hash blanked)
  where
    eid = BS.cons 0x42 (BS.drop 1 $ qb64Verkey frozenWitnessKey)
    body size digest =
        "{\"v\":\"KERI10JSON"
            <> size
            <> "_\",\"t\":\"rpy\",\"d\":\""
            <> digest
            <> "\",\"dt\":\"2026-08-12T00:00:00.000000+00:00\""
            <> ",\"r\":\"/loc/scheme\",\"a\":{\"eid\":\""
            <> eid
            <> "\",\"scheme\":\"https\""
            <> ",\"url\":\"https://witness-test.example/\"}}"
    placeholder = B8.replicate 44 '#'
    sizeHex = B8.pack (printf "%06x" (BS.length $ body "000000" placeholder))
    blanked = body sizeHex placeholder

syntheticNonce :: BoardNonce
syntheticNonce = BoardNonce (BS.replicate 32 0x55) 1

syntheticDatum :: AuthorizedBoardDatum
syntheticDatum =
    unsigned
        { authorizedSignature =
            signTest . boardAuthorizationBytes $
                reconstructBoardAuthorization policyIdBytes unsigned
        }
  where
    unsigned =
        AuthorizedBoardDatum
            { authorizedWitnessKey = frozenWitnessKey
            , authorizedEndpointRecord = syntheticEvent
            , authorizedEndpointSignature = signTest syntheticEvent
            , authorizedOwnerKeyHash = owner
            , authorizedNonce = syntheticNonce
            , authorizedSignature = BS.replicate 64 0x00
            }

utxoWithDatum :: Data -> ChainAssetUtxo
utxoWithDatum datum =
    ChainAssetUtxo
        { chainAssetTxId = txId
        , chainAssetIndex = 0
        , chainAssetAddress = markerAddress
        , chainAssetLovelace = 2_000_000
        , chainAssetList =
            [ ChainAsset
                { chainAssetPolicy = policy
                , chainAssetName =
                    TE.decodeUtf8 (convertToBase Base16 frozenWitnessKey)
                , chainAssetQuantity = 1
                }
            ]
        , chainAssetInlineDatum = Just (plutusDataJson datum)
        , chainAssetReferenceScript = Nothing
        }

syntheticAuthorizedUtxo :: ChainAssetUtxo
syntheticAuthorizedUtxo =
    utxoWithDatum (authorizedBoardDatumData syntheticDatum)

syntheticEntry :: BoardEntry
syntheticEntry =
    BoardEntry
        { boardWitnessKey = frozenWitnessKey
        , boardAid =
            TE.decodeUtf8 (BS.cons 0x42 (BS.drop 1 $ qb64Verkey frozenWitnessKey))
        , boardScheme = "https"
        , boardUrl = "https://witness-test.example/"
        , boardTxId = txId
        , boardIndex = 0
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = owner
        }
