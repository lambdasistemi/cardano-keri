{- |
Module      : Cardano.KERI.Deployment.LegacyCardanoCli
Description : Shared error rendering for transaction paths awaiting Slice 3 migration
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Temporary compatibility surface for the remaining subprocess-backed
advance, close, and endpoint-board transaction paths. Slice 3 retires this
module when those paths move onto the shared in-process runtime.
-}
module Cardano.KERI.Deployment.LegacyCardanoCli (
    renderCardanoCliFailure,
) where

import Data.Text qualified as T

{- | Keep validator failures actionable without echoing cardano-cli's opaque,
multi-kilobyte base64 script dump. Other failures remain verbatim.
-}
renderCardanoCliFailure :: Int -> String -> String -> String
renderCardanoCliFailure code err output =
    unlines
        [ "cardano-cli failed with exit " <> show code
        , "stderr: " <> summariseValidatorFailure err
        , "stdout: " <> output
        ]

summariseValidatorFailure :: String -> String
summariseValidatorFailure err
    | "scripts have execution failures" `T.isInfixOf` rendered =
        T.unpack . T.unlines . filter isMachineFact . T.lines $ rendered
    | otherwise = err
  where
    rendered = T.pack err
    isMachineFact line =
        any
            (`T.isPrefixOf` T.stripStart line)
            [ "Command failed:"
            , "Error: The following scripts have execution failures:"
            , "the script for policyId "
            , "Script hash:"
            , "Script language:"
            , "Protocol version:"
            , "ScriptInfo:"
            , "Script evaluation error:"
            , "The machine terminated because of an error"
            , "Caused by:"
            ]
