import Lake

open Lake DSL

package «cardano-keri-blaster» where
  moreGlobalServerArgs := #["--threads=4"]
  moreLeanArgs := #["--threads=4"]

require Blaster from git
  "https://github.com/paolino/Lean-blaster" @
    "d57a9079a164ca25e58f119112162efea617b5e6"

require PlutusCore from git
  "https://github.com/input-output-hk/PlutusCoreBlaster" @
    "17cee18a2058790bca36282d82c19146587fb2d1"

require CardanoLedgerApi from git
  "https://github.com/input-output-hk/CardanoLedgerApiBlaster" @
    "577e3eb03b5be09354cfdb1c0d0c12e9e16541a0"

@[default_target]
lean_lib KeriBlaster
