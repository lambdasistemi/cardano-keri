# Resume — cardano-keri project owner

## Identity

Project owner pane `%6429`, session `projects`, window `cardano-keri`, runtime
`/tmp/projects/cardano-keri`.

## Current project state

- M1 (`%5511`, `/tmp/ms-keri-1`) is custodial-terminal. Do not reopen.
- M1.2 / GitHub milestone 11 (`%6695`, `/tmp/ms-keri-11`) is ACTIVE under the
  staged S0+S1 release plus PREPARED/INACTIVE conditional S2+decoder authority.
  Its exact brief is `/tmp/ms-keri-11/brief.md`, sha256
  `44a18628e08a4394adae1a6021e00aa7cfa1466551547707a5db72f077d7813e`.
- S0 and S1 are both in fresh audit loops; neither is accepted yet. S0's
  current per-script rows are green after redesign, but the witness-mode and
  reference-script cost question is deliberately carried to S2. S1 repaired
  six findings after its first audit killed one of six invariants.
- Operator directive `681c78cb…` resumed backlog steering now. The complete
  triage `/tmp/ms-keri-11/steering/M1-BACKLOG-TRIAGE.md` is accepted at the
  ruling level (7 ADOPT / 8 REWRITE / 0 CLOSE), sha256 `6097aa95…`.
  `#279` targets record+cursor. Surface C remains inactive while M1.2 authors
  the exact 15-entry payload; no issue or preprod mutation has occurred.
- M8 (`%5331`, `/tmp/ms-keri-8`) is parked and unreleased.

## Exact next action

1. Publish this ruling sweep as a fresh depth-one root against held base
   `abc59ab076fadf37aa594e0bd38d76d3d3a08b3a`, verify sibling preservation,
   then release the milestone owner's branch hold against the new base.
2. Review `/tmp/ms-keri-11/steering/M1-BACKLOG-MUTATIONS.json` when complete:
   require exactly 15 complete final payloads, fresh live concurrency bases,
   and a mechanically clean dry run.
3. On exact-payload acceptance, send a written project barrier release; only
   then may surface C execute byte-for-byte matching issue mutations.
4. Await the milestone owner's S0+S1 activation package. Independently verify
   candidate hashes, fresh-auditor verdicts/report hashes, and can-fail gate
   evidence before recording `M12-S2-ACTIVATED`.
5. After activation supervise only the milestone owner. A/B self-execute; S3,
   preprod, mainnet, release/announcement, M1 restart, delegation/credentials,
   product claims, and the external product gate remain withheld.

## Current authority hashes

- commissioning request: `e072e4960b77c68cfda4d894837330e2e08636d39a43c5d05e409200408c715c`
- staged release: `b0453ae755b56857f7f243c8f089be0b121439f5238e64a35d4c8069acd54609`
- operator resume directive: `681c78cb865011cb938ccd1791edc2dfeb0a5562c28fc316559eb692a382d2e2`
- conditional S2/decoder/bookkeeping release: `c6a88a475b2bbecbe6f5d03e2604a132283d52c6f5073077a75b62f7209e2f10`
- M1 terminal steering: `793bab01059d18bd8f9bd20fd9ec3e37b7454b06ea7bb20f87ec1b9ea3d56410`
