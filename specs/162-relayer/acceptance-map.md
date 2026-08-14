# Finite acceptance map

Exactly these six rows constitute ticket acceptance. Each row has a permanent
proof and a negative control capable of failing. Required Hspec labels begin
with `#162 relayer`; the gate rejects zero selected examples.

| ID | Acceptance | Permanent proof | Negative control / failure oracle |
|---|---|---|---|
| A1 | One unattended process discovers a live checkpoint through an authenticated chain board, fetches the witnessed immediate rotation, advances it in-process, settles, and logs the txid. | Real devnet `#162 relayer unattended` executes production `ckeri relayer run`, real board/checkpoint outputs, loopback keripy-compatible KEL, and asserts final datum plus `result=advanced`. | Forge the board signature or KEL before enabling submission; assert no transaction construction/submission marker and unchanged checkpoint. |
| A2 | Killing and restarting the process loses no progress and creates no duplicate transition. | Real devnet `#162 relayer restart` kills at the blocked HTTP boundary, restarts, releases one valid KEL, and observes exactly one sequence advance/txid. | Seed a second response/restart and assert checkpoint sequence advances only once with no relayer cache file. |
| A3 | Two relayers racing the same event produce one transition and a correct losing result. | Real devnet `#162 relayer race` starts two production processes; final chain history has one advance, winner logs `advanced`, loser logs `already-current` with current txid. | Present equal sequence with a different candidate datum; classification must be conflict, not `already-current`. |
| A4 | Rollback/currentness decisions use one current follower snapshot and never submit a ghost assembled across reads. | Controlled query test changes predecessor or endpoint between discovery and final snapshot; final atomic program rejects it; devnet reconciliation reacquires after submission. | A deliberately split-read fixture exposes mixed generations and must fail the atomicity oracle before build. |
| A5 | Endpoint and KEL authenticity/continuity are enforced before transaction construction. | KEL/CLI tests cover AID, sequence, commitments, threshold signatures, witness delta/receipts, SAID, board authentication, bounds, status/media, and downgrade rules. | Seed one mutation per check plus oversized/redirect/bad-media responses; all must stop before construction and leave chain state unchanged. |
| A6 | Operators can run and diagnose the relayer from maintained user docs. | `docs/user/run-a-relayer.md` appears in MkDocs navigation and documents exact command, prerequisites, chain-board primary/static fallback, 5/15/600 defaults, conditional 620-second bound, restart/race, result logs, and fail-closed behavior. | Documentation checker removes/renames one required token or nav entry and must fail. |

## Exact local gate

After a genuine clear-host preflight before each realizing command:

1. `just deployment-unit "#162 relayer"`
2. `just backend-check`
3. `just e2e`
4. `just ci` from the repository root

The first three logs must prove non-zero selected examples and the expected
`#162 relayer` labels; root `just ci` must include the relayer E2E through the
Nix check graph. The repository root intentionally has no flake, so the final
command is never wrapped in `nix develop`. The gate also enforces clean status
and the owned path fence against the pre-slice planning commit.

## Explicit exclusions

There is no acceptance row for a #220 standalone verifier, raw preprod
transcript, on-chain validator change, persistent cache, `cardano-cli`, Koios,
or static JSON as the primary endpoint source.
