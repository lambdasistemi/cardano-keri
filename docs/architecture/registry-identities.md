# The identities of this generation

An integrator who wants to run or review a registry on a local test chain asks
which code that registry runs: which model it follows, which public registry
package it builds on, which compiler produced the scripts, and which script
hashes and sizes the chain will see. This page states those numbers for this
generation, and every number comes from a command the page names, so a reader
can run the command and compare.

!!! warning "Not for mainnet"
    This code is not for mainnet.

## The identities

The table is checked: a hosted step recomputes every value and fails when one
differs, so no value here is a stale literal. The application and the state
script do not depend on the registry's seed; the checkpoint validator is
applied to the registry's own identity, which does, so its row is derived for a
fixed reference seed (a transaction id of 32 zero bytes, index 0). A reference
seed is a derivation input, not a deployed registry.

<!-- identities:begin -->
| What | Value |
|---|---|
| Lean model revision | `12fdc460c71ca2bb1ee9991e030034abcc6f929c` |
| Public Singular commit | `d69ab005c3b710aeebf033d3c5cd08c56feb5643` |
| Aiken compiler | `1.1.23` |
| Application script hash | `68b4e61b57e82e583c6cc967f435e7371bb1855296ab434094f75156` |
| Application program bytes | `9092` |
| State script hash | `292690d0079066f2c9505aeff665de9fada8b738c141f432f2ba2253` |
| State script program bytes | `7786` |
| Checkpoint validator script hash | `ee87c60cb511d5b43a8b788e198a0bafe45b919e878dc36527acb762` |
| Checkpoint validator program bytes | `8482` |
| Reference registry name | `a060e76604c811bc4f47264e86a593a4539d57e251709f83af18ad5789d6c0b3` |
<!-- identities:end -->

## How each value is produced

| Value | Command |
|---|---|
| Lean model revision: the last commit that changed `lean/` | `git log -1 --no-merges --format=%H -- lean` |
| Public Singular commit | the `revision=` line of `onchain/stage-dependencies.sh` |
| Aiken compiler | `nix eval --raw github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken.version`, equal to `compiler` in `onchain/aiken.toml` |
| Script hashes and program bytes | `bash scripts/registry-identities.sh` |
| Whole table against the page | `bash scripts/check-identities.sh` |

`scripts/registry-identities.sh` compiles the scripts from the tracked sources
into the blueprint, then runs `scripts/registry-identities.hs`, which calls the
library's own derivation with the deployed generation's terms. The size is the
length of the applied program, which the chain carries and the transaction size
limit counts.

```mermaid
flowchart LR
  T[One set of terms] --> O[Observers: proof policy, lifecycle]
  O --> A[Application validator]
  T --> A
  A --> S[State script]
  S --> C[Checkpoint validator]
  Seed[Seed output] --> C
  T --> C
```

The application is applied to the observer and the amounts of the deposit; the
state script to the application; the checkpoint validator to the state script,
the registry's name (which the seed fixes) and the same amounts. One set of
terms feeds all three, so the amounts cannot disagree.

## The identity of a devnet registry, per run

A registry on the devnet is created by spending one seed output, which fixes
its name; its state policy follows from the application. Every transaction of
the journey has an identifier that depends on the transaction's contents. The
identifiers are therefore derived by each run and printed by it; none is
written here.

The hosted job named "E2E (withDevnet)", step "withDevnet registry and
checkpoint journeys", runs the devnet suite with its log shown. The lines
beginning with `[checkpoint-e2e]` carry the registry's state policy, name and
checkpoint validator hash (the line containing `registry identity`, with the
genesis transaction) and the identifier of each fold that delivers a checkpoint
(the lines containing `registration fold transaction`).

## What the check does and does not establish

The check establishes that the values on this page are the ones the derivation
gives for the repository at this commit, and that changing one character of a
stated hash makes the check fail. It does not establish that a deployed
registry's scripts are these: a deployment's hashes come from its own seed and
terms. Local test chain only; not for mainnet.
