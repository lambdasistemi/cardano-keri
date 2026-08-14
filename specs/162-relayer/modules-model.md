# Module model

No implementation bodies are specified here. Names are proposed and may be
refined without changing the constraints.

| Module / package | Responsibility | Allowed dependencies | Prohibited responsibility |
|---|---|---|---|
| `Cardano.KERI.CLI` / `cli` | Add `Relayer` instruction and opt-env-conf parser | relayer settings and runner | business logic, alternate parser library |
| `Cardano.KERI.Relayer` / `cli` | Poll orchestration, endpoint choice, fetch boundary, stable result logs | query handle, HTTP client, KEL intake, advance service | durable cursor, raw RocksDB access, shell commands |
| `Cardano.KERI.Relayer.Query` / `cli` | Discovery and final-decision snapshot programs | `ChainQuery.Program`, board/checkpoint types | network calls, submission |
| `Cardano.KERI.Query.Readiness` / query library | One shared connected/fresh readiness sample | follower status/watermark | relayer-specific policy |
| `Cardano.KERI.Indexer.App` / query library | Run follower and callback with the same query handle/store runner | existing follower/query application wiring | opening a second local store |
| `Cardano.KERI.KEL` / deployment library | Verify immediate next rotation and expose native signatures | existing CESR/KERI crypto | standalone #220 CLI, HTTP |
| `Cardano.KERI.Deployment.Advance` / write-composition | Reusable in-process live advance and settlement | existing deployment CLI and `AdvanceTransaction` services | file-based controller signatures, discovery |
| `Cardano.KERI.RelayerSpec` / cli tests | Pure/controlled boundary proofs for parser, discovery, race, logs | production modules, test doubles | replacing live devnet proof |
| `Cardano.KERI.KELSpec` / deployment tests | Immediate-next positive and forged/mismatch negatives | KEL verifier | network behavior |
| `Cardano.KERI.RelayerE2ESpec` / e2e tests | Production-command devnet journey and loopback witness | real devnet, Warp test server | mock-only transaction proof |
| `offchain/flake.nix` | Package and make relayer E2E unavoidable in existing checks | existing Nix check graph | root `justfile` mutation |
| `docs/user/run-a-relayer.md` | Operator command, prerequisites, security and logs | MkDocs | unverified deployment transcript |

## Dependency direction

CLI orchestration depends inward on typed query programs, KEL verification, and
the advance service. Those services do not depend on CLI parsing or logging.
The query program remains pure over the existing algebra; the network fetch is
outside its transaction. The final snapshot produces a self-consistent typed
submission context, never a bag assembled across independent reads.

## Ownership fence

Production/test/package edits remain under `offchain/**`. User documentation is
under `docs/user/**` plus `mkdocs.yml`. No module in `onchain/**`, no root
`justfile`, and no #220-owned standalone interface may change.
