# Plan: #300 — projection-fidelity requirements record

Artifact ceiling: 120 lines / 8,000 bytes.

## What this slice is

One local docs+spec commit stating the four projection-fidelity requirements
as four ordered, separately gated future OWNER slices. It implements none of
them, settles no design-note OPEN item, and changes no product code, test,
fixture, or dependency manifest.

## Future-slice topology

R1 -> R2 -> R3 -> R4, strictly. No bundling and no overlap: each requirement
is one future slice with its own merge predecessor:

- R300-1 bases on the witness slice MERGED on main — never on unmerged
  witness ancestry;
- R300-2 bases on R300-1 accepted and merged;
- R300-3 bases on R300-2 accepted and merged;
- R300-4 bases on R300-3 accepted and merged.

Each future slice gets a fresh immutable gate (desk-verified before write), a
fresh runtime root, worktree, and branch, a fresh owner, and a fresh distinct
auditor after park; no reuse across requirements. Owners and auditors come
from distinct model families under the standing alternation rule; grok, AGY,
and Qwen are barred by the mandate skeletons. One slice is in flight at a
time.

## Acceptance meaning

Completing R300-4 — together with R300-1 through R300-3 and the witness
slice — satisfies the S2 COMPLETE bar and moves the registry contracts
cursor-fidelity and first-seen-non-replication from enforced=NONE to
enforced.

## This slice's own gate

The ticket-owner runtime gate `requirements-v1.sh` (hash-pinned, immutable
here) exposes `record`, `r1`, `r2`, `r3`, `r4`, `self-test-r4`, `candidate`,
and `final`. Baseline RED evidence for the missing contract is frozen by the
ticket owner; `self-test-r4` proves the R4 negative control rejects the
resolve-by-Cardano-slot mutant; the `candidate` leg runs the four independent
requirement checks plus full repository CI; `final` additionally requires
every task stamped.
