import PlutusCore.UPLC

namespace KeriBlaster.CompatibilityNamespaceMoveReference

-- Both leaves exist at the pin, but neither exists in the namespace named.
-- This is the upstream namespace-move failure class the resolver must reject.
open PlutusCore.UPLC.CekMachine (evaluateBuiltinFunction)
open PlutusCore.Default (cekExecuteProgramWithSemanticVariant)

end KeriBlaster.CompatibilityNamespaceMoveReference
