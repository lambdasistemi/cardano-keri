{- |
Module      : Cardano.KERI.SurfaceFixture.Umbrella
Description : #266 T266-S1-05 — re-export shapes, where route and defining identity part company
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The re-export half of the compiled fixtures. Three shapes live here, and all
three make the ROUTE module differ from the DEFINING module — which is the
distinction #266 keys public membership on (RQ-266-02):

  * a whole-module re-export, @module Cardano.KERI.SurfaceFixture.Defining@,
    the shape that made "Cardano.KERI.ChainQuery" report zero exports to a
    reader that did not expand it;
  * an IMPORTED re-export, 'outputAt', defined in another package entirely —
    the shape 'Cardano.KERI.Deployment.Registration.plutusDataJson' had been
    leaving the #262 enumeration through unnoticed;
  * an ordinary local definition, so the module is not made only of
    re-exports and a control can tell the two apart.
-}
module Cardano.KERI.SurfaceFixture.Umbrella (
    module Cardano.KERI.SurfaceFixture.Defining,
    outputAt,
    fixtureLocalDefinition,
) where

import Cardano.KERI.ChainQuery.Program (outputAt)
import Cardano.KERI.SurfaceFixture.Defining

-- | Defined here, so its route and its defining module coincide.
fixtureLocalDefinition :: Int
fixtureLocalDefinition = 0
