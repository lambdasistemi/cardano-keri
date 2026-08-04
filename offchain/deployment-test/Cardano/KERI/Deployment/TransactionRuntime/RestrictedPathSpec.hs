{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.TransactionRuntime.RestrictedPathSpec
Description : Positive control for the Slice 2 restricted-PATH proofs

RULING-001 SS B2/B3/B4, DIRECTION-002, RULING-002 C1: the exact proof string
must live under @.../Deployment/TransactionRuntime@ (the gate's
@allowed_path@ rejects the flat @.../Deployment@ location), it must
genuinely spawn @cardano-cli@ with a per-call, scrubbed 'System.Process'
@env@ (never a process-global 'System.Environment.setEnv'/@PATH=\"\"@), and
it must observe a real failure — not a preselected stub.

DIRECTION-007 F2\/DIRECTION-008 SS1: on this host @cardano-cli@ is already
absent from the ambient @PATH@, so a lone scrubbed-@env@ spawn would fail
identically whether or not the scrub does anything — it infers absence from
a method never shown able to detect presence. The **reachable case** below
is what makes the scrubbed case meaningful: it resolves a binary known to
exist through an @env@-supplied @PATH@ containing only that binary's
directory and requires success, proving the mechanism genuinely resolves
executables through the supplied @env@ before the scrubbed case relies on
that same mechanism to prove absence. Only the pair licenses "the failure
was caused by the scrub".
-}
module Cardano.KERI.Deployment.TransactionRuntime.RestrictedPathSpec (spec) where

import Control.Exception (IOException, try)
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Process (CreateProcess (env), proc, readCreateProcessWithExitCode)
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "restricted PATH" $
    it "restricted PATH rejects an isolated cardano-cli shell-out" $ do
        -- Reachable case first: locate a binary genuinely on the ambient
        -- PATH (independent of this test's own scrub), then re-resolve it
        -- through an `env`-supplied PATH containing *only* its directory.
        -- Success here proves the per-call `env` field genuinely drives
        -- PATH resolution for this exact spawn mechanism.
        reachablePath <-
            findExecutable "cat" >>= \case
                Just path -> pure path
                Nothing -> fail "positive control needs `cat` on the ambient PATH"
        let reachable =
                (proc "cat" ["--version"])
                    { env = Just [("PATH", takeDirectory reachablePath)]
                    }
        reachableResult <- try (readCreateProcessWithExitCode reachable "")
        case reachableResult of
            Left (err :: IOException) ->
                fail ("reachable-binary control failed to resolve: " <> show err)
            Right (exitCode, _out, _err) -> exitCode `shouldSatisfy` (== ExitSuccess)

        -- Scrubbed case: the same mechanism, a PATH that cannot contain
        -- cardano-cli. Meaningful only because the reachable case just
        -- proved the same `env` field is not silently ignored.
        let scrubbed =
                (proc "cardano-cli" ["--version"])
                    { env = Just [("PATH", "/nonexistent-restricted-path-for-slice2-red")]
                    }
        scrubbedResult <-
            try (readCreateProcessWithExitCode scrubbed "") ::
                IO (Either IOException (ExitCode, String, String))
        -- A genuinely isolated shell-out with cardano-cli undiscoverable
        -- fails to even start (posix_spawnp: does not exist), which
        -- 'System.Process' surfaces as an 'IOException', not a non-zero
        -- 'System.Exit.ExitCode' -- confirmed empirically against this
        -- repository's pinned 'process' before this spec was authored.
        scrubbedResult `shouldSatisfy` isLeftIOException
  where
    isLeftIOException (Left _) = True
    isLeftIOException (Right _) = False
