# Spec — CI: org-standard shape (closes #56, #57)

## Problem

CI is a **false green**: it builds artifacts but never runs their tests.

- Onchain job runs `aiken build`, which does not execute `cage.tests.ak` /
  `base64url_tests.ak`. A failing Aiken test still passes CI.
- Offchain job runs `nix build .#checks…unit-tests`, which is the test
  *executable derivation* — it compiles the binary but does not run it. A
  failing hspec test still passes CI.
- Dev shell is bare `project.shell` with no tools, so `nix develop -c cabal …`
  fails with `cabal: not found` (#57).
- No `justfile`, no `format-check` / `hlint`, no cachix, no build-gate — the
  org new-repository CI standard is not met.

## P1 user story

As a maintainer, when I open a PR that breaks a test or leaves code unformatted,
CI must go **red** — so green means the code actually passes its own checks.

## Functional requirements

- FR1 — Onchain CI runs `aiken check` (tests) and `aiken fmt --check`.
- FR2 — Offchain CI **runs** the unit test binary, not just builds it, via a
  runnable `.#unit-tests` app; `nix flake check` executes it too.
- FR3 — Offchain dev shell provides `cabal`, `fourmolu`, `hlint` (and `just`),
  so `nix develop -c cabal build` and in-shell tooling work (#57).
- FR4 — Fourmolu format-check and hlint run in CI as `.#format-check` / `.#hlint`
  apps; existing offchain sources are formatted to pass.
- FR5 — A `justfile` provides `format`, `format-check`, `hlint`, `build`, `test`,
  `ci` recipes; `just ci` mirrors the GitHub CI jobs exactly.
- FR6 — CI has a Build Gate job (warms the nix store, incl. the dev-shell
  `inputDerivation`) and uses `cachix/cachix-action` with cache `paolino`.
- FR7 — A dev-shell CI gate job runs `nix develop -c cabal build` (the nix
  skill's mandatory rule — packaged checks never enter the shell).

## Out of scope

- #58 release pipeline — nothing releasable (version 0.0.0, no tags). Deferred.
- Any onchain/offchain behavior change. This ticket only makes CI honest.

## Success criteria

- Introducing a deliberately failing Aiken test OR hspec test turns CI red
  (verified locally via the gate).
- `nix develop -c cabal build` succeeds.
- `nix flake check`, `nix run .#format-check`, `nix run .#hlint` pass.
- `main` branch protection required checks updated to the new job names.
