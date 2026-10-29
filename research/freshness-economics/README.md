# Freshness economics: experimental research

This is the runnable research starting point for the freshness economics discussion.
It imports the existing checkpoint and revocation-mirror laws and adds illustrative
observations, costs, choices and funding traces. **C1, C2 and C3 are intentionally
unproved proposals, each using `sorry`.** They are not accepted protocol law.

Start with the [illustrated meeting guide](meeting.md), then the
[presenter brief](presenter-brief.md) and [discussion/debrief](discussion-debrief.md).
The debrief has no recorded meeting outcomes.

| Lean file | What to inspect |
|---|---|
| [Concepts](Freshness/Concepts.lean) | Observed frontier, lag, delay, utility, actual-law executions, game and funding trace |
| [Examples](Freshness/Examples.lean) | Concrete assertions and executable outcomes; no import of Claims |
| [Claims](Freshness/Claims.lean) | Exact C1–C3 types, Given/When/Then, assumptions and intentional admissions |

## Run from this branch

Requirements: Lean **4.27.0**, Python 3.9 or later, git, bash, coreutils and Linux
user systemd services. The repository must retain the named model commit below.
Provide a local checkout of public Singular at the exact revision below, or use
an existing `lean/.lake/packages/singular` checkout. The runner fetches nothing.
With `lean` and `python3` on PATH, run from the repository root:

```sh
SINGULAR_SOURCE=/path/to/public-singular \
bash research/freshness-economics/run.sh
```

To select tools and the output location explicitly:

```sh
SINGULAR_SOURCE=/path/to/public-singular \
LEAN_BIN=/path/to/lean-4.27.0/bin/lean \
PYTHON_BIN=/path/to/python3 \
TMPDIR=/path/to/temporary-directory \
RUN_DIR=/path/to/new-receipt-directory \
bash research/freshness-economics/run.sh
```

`KERI_SOURCE` defaults to the enclosing repository. `RUN_DIR` must not exist and
must be outside both source checkouts; it defaults to a unique directory under
`TMPDIR` (or `/tmp`). Each run uses a named systemd scope with `MemoryMax=12G`
and `timeout 1800`. It compiles the complete transitive import closure into the
receipt directory, executes the examples, checks their concrete proof terms,
and records commands, source snapshots/hashes, compiler hash, outputs and exit
status. Failed runs remain available. No Lake target or production gate is run.

Optional `DEPENDENCY_RUN=/path/to/successful-receipt` reuses only non-Freshness
objects after checking the same compiler binary, source snapshots, recorded
source hashes and every recorded output hash. The three research modules are
always compiled afresh. Omit it for a full rebuild. Do not reuse artifacts from
an untrusted receipt. The Lean distribution and its standard library belong to
the trusted toolchain; a compiler hash is provenance, not a toolchain audit.

## Source binding and research boundary

| Input | Required revision |
|---|---|
| Imported behavioral model | `1bd8b08ccde5597a629a1c75de2de0c274b49397` |
| Original reviewed delivery | `6734348688a82f31e4be38b83332144e450e618f` (historical provenance only) |
| Public Singular | `d69ab005c3b710aeebf033d3c5cd08c56feb5643` |
| Lean | `4.27.0` |

The enclosing branch can advance. Its HEAD need not equal the old delivery.
The runner instead rejects changes under `lean/` relative to the model revision,
checks every imported protocol source byte against that revision, verifies the
actual Singular checkout and manifest pin, and checks source stability throughout
the run. New research files do not amend the accepted protocol definitions.

The expected admission inventory is exactly:

- `Freshness.Claims.C1_submit_over_stop`
- `Freshness.Claims.C2_delay_composition`
- `Freshness.Claims.C3_funded_work_bound`

Each must report `sorryAx`. Compilation establishes the concrete examples and
well-typed proposals; it does not prove these universal claims. Example outputs
include observed lag 2, submission utility 7, net loss −2, race loss −4, two paid
rotations from a pool of 20, renewed premiums of 30, delay 90 for a profitable
late update, and mirror coverage changing from false to true after a push.

This package preserves the reviewed mathematical source bytes, including their
historical pre-meeting labels. The publication authorization covers this isolated
research package. It does not adopt its claims into the protocol. No production
imports, validators, builders, CLI behavior or zero-admission checks change.
The tooling/package work is below the accepted model; the proposed economics
remain experimental design questions. No implementation conformance rung or two
implementation test layers is claimed.

Observed data may be incomplete or unauthenticated; the examples use hypothetical
evidence and costs. Local checkpoint reachability is not a composed registry
receipt or physical ledger execution. No equilibrium, guaranteed promptness,
anti-farming result, calibrated probability or Checkpoint–Mirror composition is
established. C2 already assumes an included event. C3 bounds premiums on a
restricted funded trace, not every cost or unpaid update.

## Figures and equations

The meeting guide displays the reviewed PNGs at natural widths. Sources and
rendered assets are retained unchanged:

- [Freshness diagram](freshness.mmd) and [PNG](img-freshness.png).
- [Incentives diagram](incentives.mmd) and [PNG](img-incentives.png).
- [LaTeX](freshness-math.tex), [two-page PDF](freshness-math.pdf),
  [definitions preview](img-math-1.png) and [claims preview](img-math-2.png).

The Lean types give the exact premises; the equations are a reading guide.
