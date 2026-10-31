{- |
Module      : Cardano.KERI.CLI.CommandSurfaceSpec
Description : The production ckeri parser offers no owner exit

A checkpoint is alive until it is convicted: the accepted model has no owner
close, no parking and no revival. These examples run the production
'Instructions' parser itself and require it to refuse @close@ and @reopen@ as
unrecognised commands.

An unrecognised command is told apart from a recognised command that merely
lacks its options: a recognised command still fails here (no options are
given), but never with 'ParseErrorUnrecognisedCommand'. The @advance@ and
@status@ examples are that control, and the invented command name shows the
refusal is detectable at all.
-}
module Cardano.KERI.CLI.CommandSurfaceSpec (spec) where

import Cardano.KERI.CLI (Instructions)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import OptEnvConf qualified as Opt
import OptEnvConf.Args (parseArgs)
import OptEnvConf.Capability (allCapabilities)
import OptEnvConf.EnvMap qualified as EnvMap
import OptEnvConf.Error (ParseError (..), ParseErrorMessage (..))
import OptEnvConf.Run (runParserOn)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "ckeri command surface" $ do
    it "refuses close: a checkpoint is alive until convicted" $
        unrecognisedCommands ["close"] >>= (`shouldBe` ["close"])
    it "refuses reopen: a checkpoint is alive until convicted" $
        unrecognisedCommands ["reopen"] >>= (`shouldBe` ["reopen"])
    it "refuses an invented command name the same way" $
        unrecognisedCommands ["no-such-command"]
            >>= (`shouldBe` ["no-such-command"])
    it "recognises advance" $
        unrecognisedCommands ["advance"] >>= (`shouldBe` [])
    it "recognises status" $
        unrecognisedCommands ["status"] >>= (`shouldBe` [])

{- | The command names the production parser reports as unrecognised for
these arguments, with no environment and no configuration file.
-}
unrecognisedCommands :: [String] -> IO [String]
unrecognisedCommands args = do
    result <-
        runParserOn
            allCapabilities
            Nothing
            (Opt.settingsParser :: Opt.Parser Instructions)
            (parseArgs args)
            EnvMap.empty
            Nothing
    pure $ either unrecognised (const []) result

unrecognised :: NonEmpty ParseError -> [String]
unrecognised errors =
    [ name
    | ParseError{parseErrorMessage = ParseErrorUnrecognisedCommand name _} <-
        NE.toList errors
    ]
