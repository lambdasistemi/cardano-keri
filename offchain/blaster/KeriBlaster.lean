import Blaster
import CardanoLedgerApi.V3
import PlutusCore.UPLC

/-!
The S1 root deliberately has no solver theorem yet. Elaborating these imports
proves that the exact Lean-Blaster, PlutusCoreBlaster, and
CardanoLedgerApiBlaster packages form one compatible pinned build graph.

Production `#import_uplc`, preparation, and SMT properties begin in later
slices. A future successful solver result is reported as
`SMT-VALID (no proof term)`, never as a kernel proof.
-/
