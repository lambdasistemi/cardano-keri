{- |
Module      : Cardano.KERI.AID.E2E.Script
Description : Compatibility re-export of the production deployment scripts

The implementation moved to 'Cardano.KERI.Deployment.Script' so E2E and
@ckeri@ cannot drift.  Existing E2E imports retain this module name.
-}
module Cardano.KERI.AID.E2E.Script (
    module Cardano.KERI.Deployment.Script,
) where

import Cardano.KERI.Deployment.Script
