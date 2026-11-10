{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.ApplicationSpec
Description : the names and records of the application agree with the Lean vectors

Every expected value comes from @lean/application-vectors.json@ or from the
layout of the Aiken types, never from the code under test: the token names are
the hashes of the Lean preimages, the state policy is the one the pinned
compiler computes for the application of the vectors, and the datum bytes are
written out from the field order of the Aiken records.
-}
module Cardano.KERI.AID.ApplicationSpec (spec) where

import Cardano.KERI.AID.Application
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Migration.Types (canonicalCborData)
import Codec.Serialise (deserialise)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Containers.ListUtils (nubOrd)
import PlutusCore.Data (Data (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

-- | Bytes from base 16 text.
unhex :: ByteString -> ByteString
unhex = either error id . convertFromBase Base16

hexOf :: ByteString -> ByteString
hexOf = convertToBase Base16

-- | The Data a Lean vector carries as canonical CBOR.
dataOfVector :: ByteString -> Data
dataOfVector = deserialise . BSL.fromStrict . unhex

-- | The registry of the Lean vectors: the abstract state policy and the registry's name.
vectorRegistry :: RegistryIdentity
vectorRegistry =
    RegistryIdentity
        { registryStatePolicy = unhex "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , registryName = unhex "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        }

-- | The seed of the vectors' registry.
vectorSeed :: OutputReference
vectorSeed =
    OutputReference
        { outputTransactionId = unhex "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , outputIndex = 0
        }

-- | The checkpoint address the approvals commit: a script credential with no stake credential.
vectorHoldingAddress :: PlutusAddress
vectorHoldingAddress =
    unstakedAddress (ScriptCredential (unhex "bcc1c6cbd0d5dadfe4e9eef3f8fd02070c11161b20252a2f34393e43"))

-- | An approval vector: its name, key, datum, deposit, datum hash and approval name.
data ApprovalVector = ApprovalVector
    { avName :: String
    , avKey :: ByteString
    , avDatum :: ByteString
    , avDeposit :: Integer
    , avDatumHash :: ByteString
    , avApproval :: ByteString
    }

approvalVectors :: [ApprovalVector]
approvalVectors =
    [ ApprovalVector
        { avName = "approval"
        , avKey = unhex "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550"
        , avDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d879800a581d604d52575c61666b70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , avDeposit = 15
        , avDatumHash = unhex "0600c5de826967d04aef7aa9d986b5dc8be700398efb7239480083b399048c6e"
        , avApproval = unhex "16df829c60f09d10b2ca9e94790ec5123c2d45a17c69e9a66800544620334784"
        }
    , ApprovalVector
        { avName = "approval-other-deposit"
        , avKey = unhex "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550"
        , avDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d879800a581d604d52575c61666b70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , avDeposit = 16
        , avDatumHash = unhex "0600c5de826967d04aef7aa9d986b5dc8be700398efb7239480083b399048c6e"
        , avApproval = unhex "abd4ba9461adbba96c3190a5a3fc9220f660dc0d28b7a1dbd8cf2cbd262ec6e0"
        }
    , ApprovalVector
        { avName = "approval-other-aid"
        , avKey = unhex "4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f"
        , avDatum = "d87a9fd8799f582c4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f0000d87980d879800a581d604d52575c61666b70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , avDeposit = 15
        , avDatumHash = unhex "64663b92795e9684fc729721f4c59913a1d75aaadd71c8c5ddaf7f191b932ae1"
        , avApproval = unhex "88c1f0f2bc435f053b72b40e56af1cbeadcb625a75f1427fc1e021ed3b4dedc7"
        }
    ]

spec :: Spec
spec = describe "KERI's application on the public registry" $ do
    describe "token names agree with the Lean preimages" $ do
        it "the state token is named from the seed" $
            stateTokenName vectorSeed `shouldBe` registryName vectorRegistry
        it "the configuration token is named from the registry" $
            configurationTokenName vectorRegistry
                `shouldBe` unhex "bbb895f9594c6a51a81fae044cfbc4549f82e213e22808b7f5bcf557260d535c"
        mapM_
            ( \v ->
                it ("the approval of the vector " <> avName v) $ do
                    let datum = dataOfVector (avDatum v)
                    initialDatumHash datum `shouldBe` avDatumHash v
                    registrationApprovalName
                        vectorRegistry
                        (avKey v)
                        vectorHoldingAddress
                        datum
                        (avDeposit v)
                        `shouldBe` avApproval v
            )
            approvalVectors
        it "a registry's active token is named by the registry and the key" $
            map (activeTokenName vectorRegistry . avKey) approvalVectors
                `shouldSatisfy` \names ->
                    length (nubOrd names) == 2
        it "the active token of a key is another asset than the registry's own" $
            activeTokenName vectorRegistry (BS.replicate 44 0x45)
                `shouldNotBe` registryName vectorRegistry
    describe "the state policy" $ do
        it "is the hash the pinned compiler computes for the application of the vectors" $
            hexOf (statePolicy stateTemplate (unhex "282d32373c41464b50555a5f64696e73787d82878c91969ba0a5aaaf"))
                `shouldBe` "12f48ebdf08f7e210fd3907ad1e5206b377cfae7483f0d8875cbf30d"
        it "moves with one byte of the template (the control can fail)" $
            statePolicy (BS.cons 0 (BS.drop 1 stateTemplate)) (BS.replicate 28 1)
                `shouldNotBe` statePolicy stateTemplate (BS.replicate 28 1)
    describe "the records of the application address" $ do
        it "the configuration record is constructor 0: parameters, then the checkpoint credential" $
            hexOf
                ( canonicalCborData
                    ( heldDatumData
                        ( Configuration
                            (ApplicationParameters 2 1 5 1)
                            (ScriptCredential (BS.replicate 28 0xab))
                        )
                    )
                )
                `shouldBe` "d8799fd8799f0201050001ffd87a9f581cababababababababababababababababababababababababababababffff"
        it "a request is constructor 1 holding the registration" $
            hexOf
                ( canonicalCborData
                    ( heldDatumData
                        ( Registration
                            RegistrationData
                                { requestRegistry = RegistryIdentity (BS.replicate 28 1) (BS.replicate 32 2)
                                , requestKey = "key"
                                , requestController = BS.replicate 28 3
                                , requestRefundAddress = unstakedAddress (KeyCredential (BS.replicate 28 4))
                                , requestHoldingAddress = unstakedAddress (ScriptCredential (BS.replicate 28 5))
                                , requestInitialDatum = I 7
                                , requestDeposit = 15
                                , requestBookedAt = 10
                                , requestProcessDeadline = 20
                                , requestReclaimEnd = 20
                                }
                        )
                    )
                )
                `shouldBe` "d87a9fd8799fd8799f581c0101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ff436b6579581c03030303030303030303030303030303030303030303030303030303d8799fd8799f581c04040404040404040404040404040404040404040404040404040404ffd87a80ffd8799fd87a9f581c05050505050505050505050505050505050505050505050505050505ffd87a80ff070f0a1414ffff"
    describe "the operations" $ do
        it "the mint redeemer numbers the creation of a configuration 0 and a booking 1" $ do
            actionData (BookRegistration 3) `shouldBe` Constr 1 [I 3]
            actionData (CreateConfiguration vectorRegistry vectorSeed 2)
                `shouldBe` Constr
                    0
                    [ Constr 0 [B (registryStatePolicy vectorRegistry), B (registryName vectorRegistry)]
                    , Constr 0 [B (outputTransactionId vectorSeed), I 0]
                    , I 2
                    ]
        it "the spend redeemer numbers the fold 0 and the return 1" $ do
            spendActionData (FoldRegistration 0) `shouldBe` Constr 0 [I 0]
            spendActionData ReturnRegistration `shouldBe` Constr 1 []
