# Modules model — #368 hash-bound Lean audit report

Artifact ceiling: 120 lines. No production module changes are licensed.

## MOD-368-REPORT — terminal audit document

- Path: `lean/AUDIT-REPORT.md`.
- Responsibility: present exactly one verdict and the seven required FULL Lean
  audit sections against one frozen input identity.
- Depends on MOD-368-EVIDENCE and the released tracked `lean/` inputs.
- Must not become an authority for product rulings; it reports their observed
  coverage and limits.

## MOD-368-EVIDENCE — immutable evidence packet

- Path: `lean/audit-evidence/<audited-input-digest>/`.
- Responsibility: store the sorted input manifest, evidence manifest, compact
  ledgers, and raw command/negative-control receipts cited by the report.
- The directory name is the SHA-256 of the audited-input manifest defined by
  DAT-368-INPUT. Files are content-addressed by `MANIFEST.sha256`.
- Depends on released `lean/` inputs and the frozen release gate only.

## MOD-368-GATE — ticket-owned mechanical acceptance

- Path: ignored `./gate.sh`, backed up under `/tmp/epic-367/to-368/`.
- Responsibility: enforce release identity, allowed delta, report shape,
  evidence integrity, input digest equality, and exact verification commands.
- It remains read-only to the owner and every auditor. Planning v1 is replaced
  and re-falsified after the merged-base release before dispatch.

## MOD-368-MANDATE — ticket contract

- Path: `specs/368-lean-audit-report/`.
- Responsibility: stable requirements, invariants, data/function boundaries,
  topology, task accounting, and acceptance rules.
- It depends on issues #368 and #367 and the durable epic-owner release.

## Dependency direction

`released Lean inputs -> evidence packet -> report -> acceptance gate`.
The mandate constrains every node but imports none. No Lean input depends on
the report, evidence, gate, or mandate.
