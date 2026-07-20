{- |
Module      : Cardano.KERI.AID.Checkpoint.UnicitySpec
Description : Append-only registration-registry reference model, #116 S3
-}
module Cardano.KERI.AID.Checkpoint.UnicitySpec (
    spec,
) where

import Cardano.KERI.AID.Cage.Types (
    ProofStep (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Unicity (
    RegistrySeed (..),
    emptyRegistryRoot,
    registeredMarker,
    registryThreadName,
    roleHash,
    transitionRoots,
    validAbsenceTransition,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

hexBs :: ByteString -> ByteString
hexBs = either error id . convertFromBase Base16

policy :: ByteString
policy = BS.replicate 28 0xcc

key :: ByteString
key = BS.pack [0 .. 31]

registrationAid :: Int -> ByteString
registrationAid depth =
    hexBs $ case depth of
        0 -> "33f1c3f607175773a00e6750ea9ef24dd7e5cc961b35951b50981e5388374d9a"
        8 -> "395f95ec3a153a976adecb9b5b97a55761452dafb588b3de763a6830c076b982"
        16 -> "072b920b7022eed732095825c0535bd8057986783f501db1b836ed9be72ab45c"
        _ -> error "UnicitySpec: unsupported registration depth"

seed :: RegistrySeed
seed = RegistrySeed{registrySeedTxId = BS.replicate 32 0xa1, registrySeedIndex = 7}

branchProof :: Int -> [ProofStep]
branchProof depth =
    [ Branch
        { branchSkip = 0
        , branchNeighbors = BS.replicate 128 (fromIntegral n)
        }
    | n <- [1 .. depth]
    ]

spec :: Spec
spec = do
    describe "deterministic registry labels" $ do
        it "pins the registered marker" $
            registeredMarker
                `shouldBe` hexBs "13506209dad003c83b1b6828034166a601500d6c09d622e3196ba78725f1d8ce"
        it "pins the three policy-specific role hashes" $
            map (roleHash policy) [0x00, 0x01, 0x02]
                `shouldBe` map
                    hexBs
                    [ "881658d75a7a9154184d35b016cab83368059bf0c0da1befde545ea6"
                    , "44f8b57fb50b9ffee7ec21037a031a61b5b3919a7fee4f5eab4cea77"
                    , "d5a386b02d995fcb2295d04733fc0501108a70d7351a504c53ba711e"
                    ]
        it "derives a stable thread name from the CBOR seed" $
            registryThreadName seed
                `shouldBe` hexBs "c54426c25cb2b66d1891f2430d99eba28805630efa6086d554d45d20361d63fc"

    describe "append-only MPFS absence transitions" $ do
        it "pins the empty root" $
            emptyRegistryRoot `shouldBe` BS.replicate 32 0
        mapM_ validDepth [0, 8, 16]
        mapM_ validRegistrationDepth [0, 8, 16]
        it "rejects a wrong successor root" $ do
            let proof = branchProof 8
                (oldRoot, _) = transitionRoots key proof
            validAbsenceTransition oldRoot (BS.replicate 32 0xff) key proof
                `shouldBe` False
        it "rejects a stale-root proof" $ do
            let proof8 = branchProof 8
                proof16 = branchProof 16
                (_, newRoot8) = transitionRoots key proof8
                (oldRoot16, _) = transitionRoots key proof16
            validAbsenceTransition oldRoot16 newRoot8 key proof8
                `shouldBe` False
        it "rejects re-registration of a present key" $ do
            let proof = branchProof 0
                (_, presentRoot) = transitionRoots key proof
            validAbsenceTransition presentRoot presentRoot key proof
                `shouldBe` False
  where
    validDepth depth =
        it ("accepts a valid absence transition at proof depth " <> show depth) $ do
            let proof = branchProof depth
                (oldRoot, newRoot) = transitionRoots key proof
            validAbsenceTransition oldRoot newRoot key proof `shouldBe` True
    validRegistrationDepth depth =
        it ("accepts the paired registration fixture at proof depth " <> show depth) $ do
            let registrationKey = deriveAidAssetName (registrationAid depth)
                proof = branchProof depth
                (oldRoot, newRoot) = transitionRoots registrationKey proof
            validAbsenceTransition oldRoot newRoot registrationKey proof `shouldBe` True
