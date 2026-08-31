# modules model — #289

## Changed

### `offchain/blaster/elaborate-ilean-root.sh`

Gains one responsibility: **decide the compile sequence from the declared
dependency relation of the staged tracked sources.**

It does not gain a new consumer, a new argument, or a new output artifact. Its
existing contract — stage the tracked set, elaborate each module, emit
`.ilean`/`.olean` into the output root, aggregate root last — is unchanged.

Dependency direction is unchanged: the script depends on the staged sources and
on `lean`; nothing depends on the ordering mechanism as a separate surface. The
derivation stays internal. It is deliberately **not** promoted to a reusable
component and **not** generalised beyond the tracked `KeriBlaster` set, because
its only consumer is this script and a repository-wide Lean dependency manager
is out of scope.

## New

### `offchain/blaster/test-elaboration-order.sh`

Owns the ordering property's controls, and nothing else.

The elaborator's existing harness is `test-ilean-reference-collector.sh`, whose
declared job is the reference collector's population, and which drives the
elaborator only as a means to that end. Ordering is the elaborator's property,
not the collector's. Placing ordering controls inside the collector harness
would leave the check with no clear owner — the exact seam at which a check
later stops being maintained and quietly goes vacuous.

Consumes: the elaborator under test, the tracked source root, the pinned
dependency root, the S2 artifact root. Emits: per-control evidence lines on
stdout, non-zero exit on any control failure. Depends on the elaborator; the
elaborator does not depend on it.

## Wiring

`offchain/flake.nix` — the existing `blaster` runner gains one invocation of
the new harness, alongside its existing `test-ilean-reference-collector.sh`
invocation, so the controls execute through the same single flake-owned entry
point that already carries the rest of the suite. No new check attribute, no
new app, no change to `checks.blaster`'s identity.

## Unchanged and read-only

`KeriBlaster.lean` and every `KeriBlaster/*.lean` tracked source; the collector
(`collect-ilean-references.sh`, `collect-lean-references.pl`); the compatibility
audit and its oracles; the baseline manifest and identity scripts. This slice
changes how the bridge is *built*, never what it *says*.
