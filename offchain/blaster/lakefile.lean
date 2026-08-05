import Lake

open Lake DSL

package «cardano-keri-blaster» where
  moreGlobalServerArgs := #["--threads=4"]
  moreLeanArgs := #["--threads=4"]

require Blaster from git
  "https://github.com/paolino/Lean-blaster" @
    "62d2d59abda37e90097e655b40e27545bba16f3c"

require PlutusCore from git
  "https://github.com/input-output-hk/PlutusCoreBlaster" @
    "7cf5a78c54b9694ef093bf49edb5d3799b2a49c9"

require CardanoLedgerApi from git
  "https://github.com/input-output-hk/CardanoLedgerApiBlaster" @
    "577e3eb03b5be09354cfdb1c0d0c12e9e16541a0"

@[default_target]
lean_lib KeriBlaster
