# cardano-keri project decisions

## D-001 — M1 terminal feasibility ruling (2026-08-18)

**Decision:** do not ship the current monolithic checkpoint design. The
25,934-byte compiled checkpoint exceeds both relevant ceilings before
parameter application. This is an architectural constraint, not another cold
slot's implementation defect.

**Preserved asymmetry:** G0's repair remains proven; G1's measurements remain
useful with caveats; neither rescues the monolith.

## D-002 — found M1.2 / GitHub milestone 11 (2026-08-18)

**Decision:** found `M1.2 — the decomposed record+cursor family` as ACTIVE, the
successor to terminal M1. The installed GitHub milestone 11 description is the
operator's mandate. M1 remains custodial-terminal.

## D-003 — staged execution (2026-08-18)

**Decision:** start with S0 and S1 only. S0 is the first technical verdict and
fails fast on per-script skeleton size above 80%. S1 applies the four-slot
harness lesson before subject work. S2 deep behavior and S3 preprod are
withheld; S3 requires a second written release naming the writes.

## D-004 — project capacity priority (2026-08-18)

**Decision:** new conflicting cardano-keri capacity goes first to M1.2 S0/S1
under the operator's direction to build the redesign now. This does not infer a
release for parked M8 and does not reopen M1.

## D-005 — claims and graduation boundary (2026-08-18)

**Decision:** experiment-claims policy stays in force. Mainnet, production,
announcement, external commitments, delegation/credentials, and product
graduation remain outside the current milestone release. The external pilot
and independent watcher remain the product gate outside M1.2.

## D-006 — resume the M1 product line under M1.2 (2026-08-18)

**Decision:** apply the operator directive immediately at the product layer.
The M1.2 desk triages every one of the 15 open M1 issues as ADOPT, REWRITE, or
CLOSE, non-realizing and without another lane, while S0/S1 audits continue.
M1 itself remains custodial-terminal; “resume M1 line” means successor work
under M1.2, not reopening the dead architecture.

**Mutation fence:** proposed issue text exists locally now. Issue edits,
re-homing, comments, and closures require an exact 15-row manifest accepted by
the project owner and must match it exactly.

## D-007 — co-residency risk is a measured S2 question, not an M1-shaped NO-GO (2026-08-18)

**Decision:** the established M1 reference-input path is a strong prior, not
proof of the new family. Do not relay the 25,617 B / 158.79% structural sum as
a feasibility failure by resemblance to M1's monolithic 158.3%. S2 first
proves witness mode, reads and cites the pinned reference-script size/cost
parameters, tests the inline branch, and only then decides whether the
append/cursor authentication coupling should change.

Answer: `/tmp/ms-keri-11/answers/A-002-co-residency-risk-ruling.md`.

## D-008 — prepared self-executing S2 and decoder release (2026-08-18)

**Decision:** accept machine conditional release sha256
`c6a88a475b2bbecbe6f5d03e2604a132283d52c6f5073077a75b62f7209e2f10`
as PREPARED / INACTIVE. A (S2) and B (decoder repair to main) activate only
after the milestone owner accepts independently audited S0 and S1 artifacts
and the project owner independently verifies them and records
`M12-S2-ACTIVATED`. Each later merge remains milestone-accepted,
auditor-clean, and green-CI fenced. C is exact-manifest bookkeeping, never a
blanket issue mutation grant.

## D-009 — accept the residual M1 triage and retarget cutover (2026-08-18)

**Decision:** accept the complete triage artifact
`6097aa95ece3ec777a3038a958f1473f9c0e1d1f46b0948ea9b445ffbfd7c58f`
at the product-ruling level: ADOPT 7 (`#162 #166 #171 #226 #227 #275 #291`),
REWRITE 8 (`#156 #163 #183 #184 #185 #186 #274 #279`), CLOSE 0. Retain
`#184` and `#185` as inherited release-quality contracts. The retired hunter
economy stays deleted; duplicity detection and consumer refusal survive.

**Cutover ruling:** `#279` targets the M1.2 record+cursor family. Its
inventory-first obligation survives, but this decision starts no preprod read
or write and does not release S3/G2.

**Mutation fence:** classification acceptance is not exact-payload acceptance.
Surface C remains inactive until one deterministic 15-entry artifact contains
the complete final title/body/milestone/state/comment payload for every issue,
is checked against fresh live concurrency bases, and is accepted by the
project owner. Prose such as “body as above” is not executable authority.
