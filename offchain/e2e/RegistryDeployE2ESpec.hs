{- |
Module      : RegistryDeployE2ESpec
Description : The installed command creates a registry, and the library books and folds into it

The installed @ckeri@ runs @registry deploy@ on a protocol-11 devnet from an empty
directory with a funded wallet and the registry's terms. Then the library's builders
book one registration with the payer's wallet and fold it with another, reading only
the two files the command wrote, and the checkpoint is delivered with its deposit,
its active token and its initial datum.

The second example runs the same journey on a devnet with preprod's slot length and
block spacing and records the times of its transactions. Tool, not a guarantee: it
measures; nothing is asserted about how long a transaction takes, and it is not part
of the hosted run.
-}
module RegistryDeployE2ESpec (spec) where

import Test.Hspec

import CheckpointTxBuilder (
    DeployTiming (..),
    registryDeployJourney,
    stagedBareDevnet,
 )

spec :: Spec
spec = do
    describe "#351 ckeri registry deploy creates a registry the library books and folds into" $
        it
            "deploys from an empty directory with two files, books with the payer's wallet, folds with another wallet and delivers the checkpoint"
            (stagedBareDevnet HostedTiming (registryDeployJourney HostedTiming))
    describe "#351 measurement: the registry deploy journey at preprod's timing" $
        it
            "records the submit and settle times of the booking, the hash-proof premint and the fold"
            (stagedBareDevnet PreprodTiming (registryDeployJourney PreprodTiming))
