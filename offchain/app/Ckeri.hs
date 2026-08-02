module Main (main) where

import Cardano.KERI.CLI (Instructions, runInstructions)
import OptEnvConf (runSettingsParser)
import Paths_cardano_keri (version)

main :: IO ()
main = do
    instructions <-
        runSettingsParser
            version
            "Publish and verify cardano-keri releases"
    runInstructions (instructions :: Instructions)
