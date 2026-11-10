{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.CLI.RegistryAwareDeploymentSpec
Description : manifest verify refuses where it would need the checkpoint artifact

The checkpoint validator is applied to a registry, which this source cannot
supply to the command. The command stops at the point where it would derive
the artifact set and says so.
-}
module Cardano.KERI.CLI.RegistryAwareDeploymentSpec (spec) where

import Cardano.KERI.Deployment.Script (registryAwareDeploymentRefusal)
import Cardano.KERI.Deployment.Verify (
    VerifySettings (..),
    runVerify,
 )
import Control.Exception (SomeException, displayException, try)
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldContain)

spec :: Spec
spec =
    describe "ckeri manifest verify of this source" $
        it "refuses with the registry-aware deployment message" $ do
            manifest <-
                getDataFileName
                    "deployment-test/fixtures/register-preflight-m1-manifest.json"
            result <-
                try
                    ( runVerify
                        VerifySettings
                            { verifyManifest = manifest
                            , verifyBlueprint = "unused"
                            , verifySourceRepo = "unused"
                            , verifyKoiosUrl = "http://localhost:0"
                            , verifyKoiosToken = Nothing
                            }
                    )
            case result of
                Left e ->
                    displayException (e :: SomeException)
                        `shouldContain` registryAwareDeploymentRefusal
                Right () ->
                    expectationFailure "manifest verify did not refuse"
