# Fresh verification commands

Working tree: /code/cardano-keri-368, rebased HEAD in identity.json.
All model/library inputs equal the released bytes. These are report-author
checks, not an independent auditor invocation. No mutation campaign ran.

| Command (cwd lean unless specified) | Exit | Output |
|---|---:|---|
| nix shell --no-write-lock-file ../offchain#lean --command lake build | 0 | build.log; initial .lake absent; build-start.txt/build-end.txt |
| nix shell --no-write-lock-file ../offchain#lean --command lake env lean <evidence>/Inventory.lean | 0 | inventory.log |
| nix shell --no-write-lock-file ../offchain#lean --command lake env lean <evidence>/Axioms.lean | 0 | axioms.log |
| nix shell --no-write-lock-file ../offchain#lean --command lake env lean <evidence>/Retired-Lifecycle.lean | 1 expected | retired-Lifecycle.log |
| same command, Retired-Goals.lean | 1 expected | retired-Goals.log |
| same command, Retired-Invariants.lean | 1 expected | retired-Invariants.log |
| nix shell --no-write-lock-file ../offchain#lean --command lean --version | 0 | toolchain.log |
| nix shell nixpkgs#ripgrep nixpkgs#gawk nixpkgs#gnused nixpkgs#gnugrep nixpkgs#coreutils nixpkgs#diffutils --command bash scripts/check-lean-traceability.sh (cwd repo) | 0 | traceability.log; driver performs another clean library build and 210 source axiom queries |

build.sh and trust-checks.sh retain the exact capture wrappers. Invocation
counts are not mutation-campaign spend. Only the first build has explicit
start/end timestamps; exact durations of other commands were not captured.
The toolchain is pinned through offchain/flake.lock; the traceability wrapper's
utility packages follow the repository CI command's nixpkgs reference.

Library build diagnostics are retained in full, including unused-simp warnings.
The query compiler returned one axiom receipt for each of the 749 discovered
compiled theorem constants, allowing only propext and Quot.sound. Its 210
explicit source declarations are listed separately. No proof of statement
fidelity or mutation adequacy is inferred from an axiom receipt.

Python was unavailable during initial manifest setup (shell exit 127); no
manifest or Lean command ran in that failed setup. The manifest was subsequently
created with Node from git ls-tree. This setup failure is not a semantic result.

Historical report/gate files are copied verbatim and named inherited-*. Their
commands were not rerun here. source-sha256.txt binds the frozen decision and
model inputs; inherited-byte-identity.tsv identifies the limited reused byte
comparisons. Local whole-repository just ci was not run for this report-only
change; the changed Lean/report surface was checked locally, and final remote
repository checks are recorded in the runtime handoff after push.
