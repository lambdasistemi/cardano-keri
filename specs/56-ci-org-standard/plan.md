# Plan — CI org-standard shape

## Tech / pattern

Copy the proven org pattern from `cardano-mpfs-offchain`:
`writeShellApplication` runners exposed as both `apps.<name>` (runnable) and,
where useful, `checks.<name>` via a runCommand that invokes the app — the
nix-skill "checks as source of truth" shape. Tools come from
`haskell-nix.tool "ghc9123"`. CI mirrors `just ci`.

## Slices (bisect-safe, one commit each)

### S1 — offchain flake: run tests + dev-shell tools (#57 + offchain false-green)
`offchain/flake.nix`: add `fourmolu`/`hlint`/`cabal` to a proper `shell` with
`tools`; add `format`/`format-check`/`hlint`/`unit-tests` `writeShellApplication`
runners; expose `apps.{format,format-check,hlint,unit-tests}`; replace
`checks.unit-tests = <test component>` with a runCommand that **invokes**
`.#unit-tests`. Add `.fourmolu.yaml`, `.hlint.yaml` (default, org convention).
Format existing sources so `format-check` passes.
Gate: `nix run .#unit-tests`, `nix run .#format-check`, `nix run .#hlint`,
`nix develop -c cabal build`, `nix flake check`.

### S2 — onchain: run aiken check + fmt
`.github/workflows/ci.yml` onchain job: `aiken check` + `aiken fmt --check`
instead of `aiken build`. Ensure onchain sources pass `aiken fmt --check`.

### S3 — justfile mirroring CI
Root `justfile` with `format`, `format-check`, `hlint`, `build`, `test`,
`ci-onchain`, `ci-offchain`, `ci`. `just ci` runs exactly what CI runs.

### S4 — CI workflow: build-gate, format, hlint, dev-shell gate, cachix
`.github/workflows/ci.yml`: Build Gate job (warms store incl.
`devShells…inputDerivation`) + cachix `paolino`; offchain job runs
`.#unit-tests`, `.#format-check`, `.#hlint`; dev-shell gate job
`nix develop -c cabal build`. Job names align with a ruleset update.

## Post-merge (operator step, not a commit)
Update `main` ruleset required status checks to the new job names
(Build Gate, Onchain, Offchain, Format, Hlint, Dev shell). Documented in PR body.

## Gate (local, mirrors CI)
`just ci` from the worktree root.
