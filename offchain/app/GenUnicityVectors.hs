{- |
Module      : Main
Description : Deterministic append-only registry vector generator, #116 S3

Emits the shared Aiken registry seed, thread name, empty root, and valid MPFS
absence transitions at proof depths 0, 8, and 16.
-}
module Main (main) where

import Cardano.KERI.AID.Cage.Types (
    ProofStep (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Unicity (
    RegistrySeed (..),
    emptyRegistryRoot,
    registryThreadName,
    transitionRoots,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (
    intercalate,
 )
import System.Environment (
    getArgs,
 )

main :: IO ()
main = do
    args <- getArgs
    case args of
        [output] -> writeFile output renderVectors
        _ -> error "usage: gen-unicity-vectors OUTPUT"

seed :: RegistrySeed
seed =
    RegistrySeed
        { registrySeedTxId = BS.replicate 32 0xa1
        , registrySeedIndex = 7
        }

-- The three #116 S6 registration fixtures, paired to their ratified proof
-- depths. The committed constants are derived here rather than copied from
-- opaque roots or proof bytes.
registrationAid :: Int -> ByteString
registrationAid depth =
    hexBs $ case depth of
        0 -> "33f1c3f607175773a00e6750ea9ef24dd7e5cc961b35951b50981e5388374d9a"
        8 -> "395f95ec3a153a976adecb9b5b97a55761452dafb588b3de763a6830c076b982"
        16 -> "072b920b7022eed732095825c0535bd8057986783f501db1b836ed9be72ab45c"
        _ -> error "gen-unicity-vectors: unsupported registration depth"

branchProof :: Int -> [ProofStep]
branchProof depth =
    [ Branch
        { branchSkip = 0
        , branchNeighbors = BS.replicate 128 (fromIntegral n)
        }
    | n <- [1 .. depth]
    ]

renderVectors :: String
renderVectors =
    unlines
        [ "//// Auto-generated append-only registry vectors for #116 S3."
        , "//// Regenerate with `just gen-unicity-vectors`; drift is forbidden."
        , ""
        , "use aiken/merkle_patricia_forestry.{Branch, Proof}"
        , "use cardano/transaction.{OutputReference}"
        , ""
        , "pub const registry_seed: OutputReference ="
        , "  OutputReference {"
        , "    transaction_id: #\"" <> hex (registrySeedTxId seed) <> "\","
        , "    output_index: " <> show (registrySeedIndex seed)
        , "  }"
        , ""
        , byteConst "registry_thread_name" (registryThreadName seed)
        , byteConst "empty_root" emptyRegistryRoot
        , ""
        , renderDepth 0
        , ""
        , renderDepth 8
        , ""
        , renderDepth 16
        ]

renderDepth :: Int -> String
renderDepth depth =
    unlines
        [ byteConst prefixKey registrationKey
        , byteConst prefixOld oldRoot
        , byteConst prefixNew newRoot
        , "pub const " <> prefixProof <> ": Proof ="
        , "  ["
        , intercalate ",\n" (map renderStep proof)
        , "  ]"
        ]
  where
    registrationKey = deriveAidAssetName (registrationAid depth)
    proof = branchProof depth
    (oldRoot, newRoot) = transitionRoots registrationKey proof
    prefix = "depth_" <> show depth <> "_"
    prefixKey = prefix <> "key"
    prefixOld = prefix <> "old_root"
    prefixNew = prefix <> "new_root"
    prefixProof = prefix <> "proof"

renderStep :: ProofStep -> String
renderStep Branch{..} =
    "    Branch { skip: "
        <> show branchSkip
        <> ", neighbors: #\""
        <> hex branchNeighbors
        <> "\" }"
renderStep _ = error "gen-unicity-vectors: only deterministic Branch proofs are emitted"

byteConst :: String -> ByteString -> String
byteConst name bytes =
    "pub const " <> name <> ": ByteArray = #\"" <> hex bytes <> "\""

hex :: ByteString -> String
hex = BC.unpack . convertToBase Base16

hexBs :: ByteString -> ByteString
hexBs encoded =
    case convertFromBase Base16 encoded of
        Left err -> error err
        Right bytes -> bytes
