# Tasks — CI org-standard shape (#56, #57)

## Slice 1 — offchain flake: run tests + dev-shell tools
- [ ] T56-S1 add fourmolu/hlint/cabal tools to shell; format/format-check/hlint/unit-tests runners; apps + runCommand check that runs tests; .fourmolu.yaml/.hlint.yaml; format sources; gate green

## Slice 2 — onchain: aiken check + fmt
- [ ] T56-S2 onchain CI runs `aiken check` + `aiken fmt --check`; sources pass fmt

## Slice 3 — justfile
- [ ] T56-S3 root justfile with format/format-check/hlint/build/test/ci; `just ci` mirrors CI

## Slice 4 — CI workflow
- [ ] T56-S4 build-gate + cachix + offchain runs tests/format/hlint + dev-shell gate job
