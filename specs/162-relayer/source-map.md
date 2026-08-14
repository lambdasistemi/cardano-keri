# Source map at frozen base

Base: `ae99e35e6aee577ccfc61a62f8a72f6067c1154b`. Hashes below were measured
before repository mutation and let the commit owner detect stale assumptions.

| SHA256 prefix | Source | Planning fact |
|---|---|---|
| `968e1b` | `offchain/cli/Cardano/KERI/CLI.hs` | Top-level opt-env-conf instruction/parser insertion point. |
| `b51a5a` | `offchain/write-composition/Cardano/KERI/KEL.hs` | Existing first-rotation verifier; add immediate-next entry point without #220 CLI. |
| `2194fd` | `offchain/query/Cardano/KERI/ChainQuery/EndpointBoard.hs` | Authenticated board catalog and endpoint identity fields. |
| `4dfb65` | `offchain/query/Cardano/KERI/ChainQuery/Program.hs` | Snapshot algebra exposes live checkpoints, board, current checkpoint, scripts, funding, output. |
| `7136bd` | `offchain/query/Cardano/KERI/ChainQuery/Types.hs` | Active checkpoint carries datum/outref/address but no previous-event SAID. |
| `af6bfa` | `offchain/query/Cardano/KERI/Indexer/ChainQuery.hs` | One RocksDB transaction executes a whole query program plus watermark. |
| `a7f908` | `offchain/query/Cardano/KERI/Indexer/App.hs` | Promote follower/query-handle callback from existing wiring. |
| `37c651` | `offchain/query/Cardano/KERI/Indexer/Follower.hs` | Follower lifecycle/status source. |
| `77a5e0` | `offchain/query/Cardano/KERI/Query/Server.hs` | Promote exact private readiness semantics rather than duplicate. |
| `6ec92c` | `offchain/write-composition/Cardano/KERI/Deployment/CLI.hs` | Refactor private active-checkpoint submission/live settlement service. |
| `8a1e85` | `offchain/write-composition/Cardano/KERI/Deployment/AdvanceTransaction.hs` | Existing in-process build/submit and native-signature attachment. |
| `e874c0` | `offchain/write-composition/Cardano/KERI/Deployment/LiveRuntime.hs` | Existing live runtime/settlement boundary. |
| `095d8a` | `offchain/cardano-keri.cabal` | Package/module/test declarations. |
| `203a9e` | `offchain/flake.nix` | Existing E2E and Linux check graph; relayer journey must become unavoidable. |
| `6db580` | `docs/user/discovery-endpoint-board.md` | Existing board operator context. |
| `125ea6` | `mkdocs.yml` | Add relayer user page to navigation. |

## External protocol evidence

Pinned keripy 1.3.5 commit `95c1ba6ccb7abe07428494a7843224daddb1af6a`
defines the witness KEL route as `GET /query?typ=kel&pre=<aid>&sn=<n>` and returns
CESR JSON media. Planning reference:

`https://github.com/WebOfTrust/keripy/blob/95c1ba6ccb7abe07428494a7843224daddb1af6a/src/keri/app/indirecting.py#L1201-L1266`

The owner must remeasure touched-source hashes at its pre-slice base. A mismatch
is a challenge, not permission to improvise across ownership boundaries.
