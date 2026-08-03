# Plan — #177 one production query command across three backends

## Architecture

Introduce a small typed backend seam at the read boundary, not inside the CLI
renderer and not as a cache. A selected adapter returns a provenance-bearing
snapshot or a typed closed error:

```text
ckeri status parser
  -> validated BackendConfig
  -> QueryBackend { checkpoint, board, watchability }
  -> one common StatusView renderer
```

The local adapter reuses the transactional query engine. The endpoint adapter
is a strict client for the frozen #176 HTTP contract. The Koios adapter
refactors the current checkpoint/board logic so provenance is explicit. No
adapter may call another adapter as fallback.

The executable composition may live in a new internal library or in the
production executable layer, provided dependency direction stays acyclic and
both adapters and dispatch are directly testable. Do not move persistence into
the deployment library merely to share a type.

## Load-bearing invariants

1. one selected backend per command, with no fallback;
2. payload and `as_of_slot` describe one coherent observation or the command
   fails closed;
3. local payload and watermark share one engine transaction;
4. endpoint payload is accepted only with exact #176 provenance and identity;
5. Koios data slot comes from the supporting records, never wall clock or tip;
6. all successful adapters feed one renderer;
7. no derived cache exists outside the engine transaction;
8. `ckeri-follower` has no surviving package, app, check, or interactive shell
   surface, while its `status`, `list`, `checkpoint`, and `payer` capabilities
   remain reachable from packaged `ckeri`;
9. `help`, `quit`, prompt/completion/history, progress-loop framing, and ad-hoc
   fork output do not leak into production.

## Slice 1 — backend seam, production CLI, and fork retirement

PAIR implementation. Add the common types/configuration and three adapters,
route production `status` through them, retain the released default Koios
journey, and remove the temporary follower executable/shell surface. Tests are
written and observed RED before implementation.

Expected implementation surface includes:

- production CLI/settings and a backend composition module;
- strict endpoint decoding/client code;
- refactored Koios query/provenance helpers;
- reused transaction-scoped local query code;
- deployment/indexer tests and exact CLI checks;
- Cabal, flake, justfile, and public docs affected by fork retirement.

The original Slice 1 gate proved backend dispatch and artifact retirement, but
encoded only one half of the retirement boundary. Corrective Slice 1R freezes
the six-verb inventory, exposes the four retained capabilities on packaged
`ckeri`, and rejects the two REPL affordances plus shell-only presentation.
Its no-loss and no-leak checks are distinct and each is mutation-proven red
before restoration. Existing backend dispatch mutation evidence remains valid.

Bisect condition after Slice 1R: the accepted behavior commits leave `ckeri`
and `ckeri-query` buildable, the three adapters tested, the fork retired, all
focused/full gates green, and the corrective tasks stamped without rewriting
the accepted Slice 1 history.

## Slice 2 — user docs and truthful three-tier evidence

After Slice 1 acceptance, update the user journey around the packaged `ckeri`
binary, add a deterministic transcript validator/helper, and capture local,
hosted, and Koios raw transcripts for the same AID. The helper records UTC
time, operator identity, binary/store/source provenance, command, raw output,
and exit code. It never controls the hosted service.

If live state makes a tier fail closed, preserve and explain that truthful
result; do not massage outputs into artificial parity. The committed concise
transcript must be traceable to raw evidence under the ticket runtime root.

Bisect condition: docs and validator are executable, no fork-era public claim
remains, the three-tier record is honest, and Slice 2 gate/tasks are green in
one docs/evidence commit.

## Verification

- negative-control the frozen slice gate on base;
- PAIR RED/GREEN review and navigator verification for Slice 1;
- `just backend-check`, packaged help for every retained capability, and fork
  artifact absence checks;
- independent no-loss (disconnect one retained verb) and no-leak (add one
  forbidden affordance/output marker) negative controls;
- deliberate dispatch disconnection with named failing assertion, then restore;
- exact local rollback, endpoint contract, and Koios provenance tests;
- live three-tier commands using the same AID and production binary;
- fresh `just ci`, `./gate.sh`, diff audit, PR checks, and task stamping at the
  final head.

## Risks and controls

- **False cross-call coherence:** represent provenance in adapter results and
  reject compositions whose slots cannot be reconciled.
- **Endpoint drift:** decode exact #176 shapes and validate echoed identifiers
  and non-negative freshness.
- **Koios convenience masquerading as provenance:** source the bound from
  supporting transaction/output records and test missing/inconsistent slots.
- **Hidden fallback:** inject failures for each adapter and assert no other
  boundary is invoked.
- **Fork residue:** mechanical Cabal/flake/docs/install checks plus semantic
  review of all remaining references.
- **Live service disruption:** read-only requests only; no infrastructure or
  process lifecycle operations in this ticket.
