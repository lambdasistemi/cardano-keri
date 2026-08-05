{- |
Module      : Cardano.KERI.Deployment.CLISpec
Description : #181 Slice 2C register composition fail-closed proof
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The register command deliberately retains parsing, plan construction,
read-only chain preflight, and warnings while Slice 4 owns the real runtime
composition. This source-boundary proof freezes the tail between
@runRegister@ and @runAdvance@: it must end in the exact fail-closed message
and must contain none of the retired funding/build/sign/submit/success path.
-}
module Cardano.KERI.Deployment.CLISpec (spec) where

import Data.List (find)
import System.Directory (doesFileExist)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldContain,
    shouldNotContain,
 )

spec :: Spec
spec =
    describe "runRegister composition boundary" $
        it "fails closed before funding, build, sign, submit, or success until Slice 4 composition" $ do
            cliSource <- readCliSource
            let registerBlock =
                    takeUntil "runAdvance ::"
                        . dropUntil "runRegister ::"
                        $ lines cliSource
            unlines registerBlock
                `shouldContain` "fail \"registering pending #181 Slice 4 composition\""
            unlines registerBlock `shouldNotContain` "runRegistration"
            unlines registerBlock `shouldNotContain` "RegistrationRunnerConfig"
            unlines registerBlock `shouldNotContain` "resultPremintTxId"
            unlines registerBlock `shouldNotContain` "resultRegisterTxId"

readCliSource :: IO String
readCliSource = do
    let candidates =
            [ "deployment/Cardano/KERI/Deployment/CLI.hs"
            , "offchain/deployment/Cardano/KERI/Deployment/CLI.hs"
            ]
    existing <- traverse (\path -> (path,) <$> doesFileExist path) candidates
    case find snd existing of
        Just (path, _) -> readFile path
        Nothing -> fail "cannot locate deployment CLI source for the register-tail fence"

dropUntil :: String -> [String] -> [String]
dropUntil prefix = dropWhile (not . startsWith prefix)

takeUntil :: String -> [String] -> [String]
takeUntil prefix = takeWhile (not . startsWith prefix)

startsWith :: String -> String -> Bool
startsWith prefix value = take (length prefix) value == prefix
