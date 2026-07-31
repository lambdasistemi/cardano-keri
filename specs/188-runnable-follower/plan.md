# #188 implementation plan

## Architecture and invariants

The new executable is a thin composition root over the library landed by
#175. The store remains the only durable/canonical query state. A local query
record separates command parsing/rendering from `IndexerHandle` and
`FollowerHandle` reads so later backend selection can replace the record,
while #188 constructs exactly one local implementation.

The load-bearing invariants are:

1. one RocksDB handle is shared by follower and shell in one bracketed process;
2. follower failure is linked to the foreground lifetime;
3. each verb and each progress sample performs fresh IO through the store/STM;
4. no cached checkpoint/list/status/payer value exists outside the engine
   transaction;
5. the committed start point is a real intersection preceding all indexed M1
   lifecycle activity;
6. deterministic CI proves code and wiring, while the preprod cast proves the
   live boundary and usability without becoming a flaky gate.

## Slice 1 — executable, local queries, and cold-start artifact

Add the `ckeri-follower` Cabal executable and reusable shell/query module,
using the existing manifest/config/read/follower APIs. Add focused indexer
tests that cross the local query seam and mutate the real in-memory store
between repeated invocations. Wire the executable and focused tests through
flake package/app/runCommand checks and the repository `just ci` path. Commit
the separately-versioned preprod start record with resolution provenance.

This is PAIR work: process lifetime, STM readiness, concurrent prompt output,
state freshness, and cross-platform Nix exposure all require semantic review.

Expected owned implementation paths:

- `offchain/app/CkeriFollower.hs`;
- `offchain/indexer/Cardano/KERI/Indexer/Shell.hs` (name may vary only if the
  navigator records a clearer equivalent);
- focused `offchain/indexer-test/` specs and `Main.hs` wiring;
- `offchain/cardano-keri.cabal`, `offchain/flake.nix`, and `justfile`;
- `deploy/preprod/m1-follower-start.json`.

The slice is bisect-safe: at its commit the binary builds, focused tests run,
the start artifact validates, and the full deterministic gate is green.

## Slice 2 — executable docs and real preprod acceptance cast

Using the accepted Slice 1 binary, dry-run the final documented command on the
live synced preprod node and a fresh private store. Record the cast from the
same final code path with Haskeline in the foreground. Then update the follower
guide and MkDocs wiring, including a preview-safe `site_url`, and commit the
validated cast.

This is PAIR work because the documentation asserts live provenance and the
cast must be audited against the exact command, final binary, socket, start
record, and output. The navigator independently validates the cast and docs;
the preprod run remains outside `just ci`.

Expected owned implementation paths:

- `docs/user/follower.md`;
- `docs/assets/video/follower-preprod.cast`;
- `mkdocs.yml`;
- an optional reproducible recording helper under `scripts/` if it drives the
  production binary without mocks or fabricated output.

## Verification strategy

### Focused deterministic proof

- baseline RED: the frozen gate fails because `ckeri-follower`, its #188 tests,
  and the start record do not exist;
- GREEN: focused Hspec exercises parse/rejection, command re-read behavior,
  readiness/store status, payer reads, completion, and clean quit;
- executable help and Nix app/package exposure are invoked, not merely
  evaluated;
- the start JSON is checked against the manifest's earliest named reference.

The repeated-read test is the invariant negative control: if the local query
implementation caches its first answer, the second invocation remains stale
after apply/spend/rollback-shaped mutations and the test must fail.

### Full deterministic proof

Run `./gate.sh` fresh after every accepted behavior slice and again at final
HEAD, plus the explicitly enumerated offchain flake checks when needed to avoid
glob/eval ambiguity.

### Live proof

Verify the preprod node tip independently, run the production executable from
the committed point, query registered/advanced/closed M1 state, repeat a read,
and record the final cast. Capture the exact runner, command, final commit,
socket, store path, UTC date, and cast hash in durable evidence. The cast gate
proves JSONL/header/sanitization/line-length properties and strict MkDocs proves
the embed.

## Risks and controls

- Prompt corruption from background output: use Haskeline's external-print
  facility and test the formatting boundary.
- Hidden follower failure: link `fhAsync` and test propagation/lifetime.
- Freshness asserted but not proved: mutate the real store between identical
  verb invocations and require changed output/removal.
- Flake check false green: the runCommand must invoke the same focused app
  exposed for local use.
- Published manifest compatibility: do not edit its schema; keep operational
  bootstrap metadata separate.
- Cast provenance drift: record only after Slice 1 acceptance, against final
  production code, and re-record if any behavior/output changes afterward.

