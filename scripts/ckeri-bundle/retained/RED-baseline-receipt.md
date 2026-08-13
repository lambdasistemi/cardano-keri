# RETAINED RED MEASUREMENT — pre-slice baseline receipt

**Classification: `REFUTED` / RED.** Not a baseline. Not to be repaired in
place, rewritten, or deleted. Retained as the evidence that the inconsistency
was real and was detected, in the same way #192's terminal FAIL is retained as
a valid measurement of an obsolete pin.

Ruled by `/tmp/ms-keri-8/answers/A-e190-009-baseline-receipt-is-RED.md`.

## Provenance

| field | value |
|---|---|
| command | `nix run --quiet .#blaster`, CWD `/code/cardano-keri-246-e-baseline/offchain` |
| observed exit | `0` |
| duration | 137668 ms |
| command sha256 | `15758783d9c96f65cf7d2b8bec286542058468c670a4aa9b14bda64dd9a6d2fd` |
| raw evidence | `/tmp/ms-keri-8/e190/t246/evidence/baseline-blaster.log` |
| evidence sha256 | `6a0459158505243ac6eb3451d08240c47977338d4b558ee93562908cd402b3e6` |
| tree | `feat/246-post-conway-e-baseline` at `fe535810…` plus untracked planning artifacts |
| run at | 2026-08-05, ticket owner `%5458`, before any implementation |

## Why it is RED despite exit 0

| element of the triple | what the receipt says | verdict |
|---|---|---|
| COMMIT | `artifact.source_identity=fe535810d7bb7a343b0cb30c950c43ea356105e7` — post-#219 | disagrees with the artifact below |
| ARTIFACT | `artifact.blueprint_sha256=896d2c46…`, `artifact.program_sha256=713c747b…` — pre-#219 | pre-#219 material presented under a post-#219 commit |
| TOOLCHAIN | `toolchain.aiken=1.1.21` | the repository validates its onchain sources with `1.1.23` |
| VARIANT | absent — zero occurrences of any variant name in the whole run | `COULD-NOT-EVALUATE`, which is RED |

Each element is individually true of *something*. Together they describe no
single configuration, and the element that would disambiguate them is missing.

## Why this receipt is worth keeping

Nothing failed. The artifact is fine, the run is fine, every check passes — and
the *description of what was verified* is wrong. That is the exact failure this
milestone exists to eliminate, and a passing exit status is what was carrying
it.

It is therefore a real, non-synthetic falsification case. The baseline identity
checker must be demonstrated RED **against this receipt** before any clean
baseline is accepted (T246-B7/T246-B8). A checker validated only against an
invented broken input would not have been shown to catch the case that actually
occurred.

## Fence

This file and `baseline-blaster.log` are read-only to every child of this
ticket. No slice may edit, regenerate, relocate, or "fix" them.
