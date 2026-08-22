# cardano-keri product premises

## 2026-08-18 — premises in force

- The project is an **architectural experiment**, not a production or mainnet
  system. Source: GitHub milestone 11 mandate and the written S0+S1 release.
- M1 is terminal. Its monolithic checkpoint compiles to 25,934 bytes before
  parameter application, 158.3% of the 16,384-byte transaction limit and
  160.8% of the 16,133-byte reference-program ceiling. The project decision is
  DO NOT SHIP that architecture.
- The INV-BIND decoder defect was real and its repair is proven. That component
  evidence is retained and does not make the oversized architecture feasible.
- M1.2 is the operator-commissioned redesign: a decomposed append/record,
  derived cursor, lineage lifecycle, maintenance escrow, staged proof-token
  path, and consumer predicate family.
- The current S0 evidence is not the early provisional 6–31% table. After the
  audit-triggered redesign, all seven members pass the per-script threshold,
  with append/cursor/staging near 52–54%; acceptance is still under fresh
  audit. Per-script green does not prove the central transaction fits.
- Shipped M1 code structurally uses reference inputs when spending against
  deployed validators, making reference-script cost the strong prior for the
  new family's 25,617-byte co-residency set. The new TxB has not yet proven its
  witness construction; S2 must measure both the reference and inline branches.
- Conditional release `c6a88a47…` is in hand but inactive. It changes no
  present experiment claim and authorizes no S2 work before the two-party
  S0/S1 activation record.
- The residual M1 backlog is not being carried forward unchanged. Its accepted
  ruling is 7 ADOPT / 8 REWRITE / 0 CLOSE against record+cursor. The hunter
  bounty/freeze economy is retired; projection law, duplicity detection,
  consumer refusal, infrastructure, artifact UX, release quality, and the
  proven INV-BIND repair survive in their named forms.
- The preprod inventory issue `#279` targets a future record+cursor cutover.
  This is a product destination premise, not permission to read or write
  preprod; S3/G2 remains withheld.
- A prose triage is not a GitHub mutation manifest. Exact complete final
  issue payloads, fresh concurrency bases, mechanical validation, and project
  acceptance are required before conditional release surface C can execute.
- Graduation remains gated outside M1.2 by one named pilot gating real
  authority on the cursor and one independently operated watcher with a
  published time-to-record. No candidate has been converted into an external
  commitment by this founding.
- Delegation and credential state remain M7/M1bis. No M1.2 scope inference may
  absorb them.
- No mainnet, production rollout, announcement, external commitment, or
  product graduation is authorized.
- Host floors v2 are a correctness boundary: stop AT 50.00 GiB and never start
  a sequence of N cold realizations below `50.00 + 3.10 × N` GiB; one cold
  realization at a time for M1.2.

## Sources

- `/tmp/projects/cardano-keri/inbox/REQUEST-M12-commissioning-2026-08-18.md`
  sha256 `e072e4960b77c68cfda4d894837330e2e08636d39a43c5d05e409200408c715c`.
- GitHub milestone 11 description snapshot sha256
  `0c997ebe646a583e8f95c40a15cb2245c19447cdc69b96f6837a05a8da583454`.
- `/tmp/projects/cardano-keri/inbox/RELEASE-M12-S0-S1-2026-08-18.md`
  sha256 `b0453ae755b56857f7f243c8f089be0b121439f5238e64a35d4c8069acd54609`.
- `/tmp/projects/cardano-keri/inbox/DIRECTIVE-OPERATOR-resume-m1-line-work-2026-08-18.md`
  sha256 `681c78cb865011cb938ccd1791edc2dfeb0a5562c28fc316559eb692a382d2e2`.
- `/tmp/projects/cardano-keri/inbox/RELEASE-M12-S2-CONDITIONAL-2026-08-18.md`
  sha256 `c6a88a475b2bbecbe6f5d03e2604a132283d52c6f5073077a75b62f7209e2f10`.
- `/tmp/machine/TERMINAL-M1-BOTH-VERDICTS-STEERING-PACKAGE.md`
  sha256 `793bab01059d18bd8f9bd20fd9ec3e37b7454b06ea7bb20f87ec1b9ea3d56410`.
