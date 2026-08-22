# Milestone 8 — Blaster compiled UPLC verification

Updated: 2026-08-14
Legend: ✅ done · 🟡 active/next · ⏳ queued · ⛔ blocked · ❓ unknown

> **⏸ PARKED — OMNIA PAUSA 2026-08-14T14:59Z**, machine owner, on the operator's
> order. Machine-wide. `#246` had already parked itself at **12:15Z** at candidate
> `590f492b`, **pending issue #289** — the blocking repair was **split out rather
> than widening `#246`**, and `commit-owner-D2` was closed as not-at-fault.
>
> No M8 build was in flight at declaration. Store **59.1 GiB** avail, 11.1 above
> `min-free`. Nothing killed, no worktree retired, no commit dropped.
> **Release is the machine owner's alone, scoped and in writing — silence is not
> release.**



The living state of [milestone 8](https://github.com/lambdasistemi/cardano-keri/milestone/8). The milestone description holds the *definition* — outcome, test, artifact, boundaries — and changes almost never; this page holds the *currency*.

## Delivery — dated, not estimated

Only bars with real recorded start and end have widths.

```mermaid
gantt
    title M8 — recorded work (real dates)
    dateFormat YYYY-MM-DD HH:mm
    axisFormat %m-%d
    section Landed
    192 tractability - terminal Blake2b_256 FAIL recorded :done, a1, 2026-08-03 13:48, 1h
    234 Stage D verified green                           :done, a2, 2026-08-05 07:42, 30m
    P0 ratified + post-Conway target ruled               :milestone, a3, 2026-08-05 08:02, 0d
    234 merged to main - PR 252, checker in CI           :done, a4, 2026-08-05 08:26, 2026-08-05 10:13
    worktrees cleaned - 7.4G, 192 FAIL record tagged     :done, a5, 2026-08-05 10:13, 30m
    section 246 post-Conway E baseline
    lane open - rebased onto merged main                 :active, b1, 2026-08-05 08:26, 2026-08-05 13:33
    Slice A campaign - CLOSED on 2nd audit rejection     :crit, b2, 2026-08-05 12:00, 2026-08-05 13:33
    section Skill lane
    grill operator - SKILL.md written, unaccepted        :active, c1, 2026-08-05 11:16, 2026-08-05 13:50
    section Paused
    OMNIA PAUSA - M8 not in the 08-08 release            :crit, d1, 2026-08-05 15:57, 2026-08-08 12:00
```

## Remaining chain — order only

No estimates exist for this work, so it is drawn as sequence, not schedule.

```mermaid
flowchart LR
    R[RELEASE from machine owner] --> M["#246 rewrite the MANDATE"]
    M --> A["#246 Slice A re-dispatch"]
    A --> B["#247 checkpoint + observer"]
    B --> C["#248 cage / board / hash"]
    C --> D["#249 P0-14 controls"]
    D --> E["#250 acceptance + ckeri evidence bundle"]
    E --> O[outcome audit against the published artifact]
    R --> S["skill: accept or continue"]
    P["#193 → #194 → #195"] --> O
    R --> P
```

## Blockers — each with what would unblock it

| | Blocker | Unblocked by |
|---|---|---|
| ✅ | **`#246` Slice B — CLOSED** via the operator's option-C ruling. Campaign `rows=18 killed=14 residual=2 blocked=2 open=0` | Closed. The `BLOCKING` row terminated **`BLOCKED`** — not killed, not accepted — with its exact fact recorded, the claim versioned v1/v2, and follow-up **`T246-F7`** filed and pushed |
| 🟡 | **`#246` Slice C — OPEN** 16 rows declared (15 `BLOCKING`, 1 advisory), `INV-246-C1..C13`, severities fixed at spec time. Gates `C-v1` and `ticket-v5` frozen and **both falsified** (exit 1) before implementation | Parked at this boundary by operator order. Budget `lifetime=10, release grant 8, spent 3, remaining 5` |
| ✅ | **`#246` Slice A + A2 — ACCEPTED** `4a956102`, pushed; audit report hash and remote SHA independently re-read, not relayed | Closed. The re-cut ruled on 08-10 worked: Slice A closed on a **bounded, true** claim with its coverage published, and A2 carried the closure property the auditor named |
| ⛔ | **Lean-blaster PR #110** shows "changes requested" for a fix the rebase already landed | One operator word — it is a public action in an external repo. https://github.com/input-output-hk/Lean-blaster/pull/110 |
| ❓ | **Skill page** written and auto-discovered, but **nothing in it has been executed**, and it is untracked in `llm-settings` | Operator acceptance, and either running its commands or marking them unverified |
| ✅ | **Codex VERIFIED 2026-08-10T12:35Z** — 84% left, resets 15 Aug, read twice identical (machine owner's instrument). The erratic week was a **moved reset date**, not a bad instrument: the bucket genuinely rolled on the 8th | Resolved. Alternation unblocked; `#246` seats its Codex commit owner. Doctrine it produced: **a measurement carries its window** — a percentage without its reset boundary cannot tell a reset from a misread |

| ⛔ | **`INV-246-IDENTITY-FIELD-EXPECTATION-DISJOINT` — `BLOCKING`, terminating `BLOCKED` by operator ruling.** The manifest's top-level object is neither enumerated nor key-set-pinned: a key added there is outside `fields`, `reconciled` and `unexpected`, and read by nothing. **The `variant` field sits at top level.** Desk-verified after the ruling: the #234 checker has no variant handling, the trust-base table has no variant row, and `S2Cek.lean` takes the variant as a runtime parameter — so **nothing in the checked surface pins the semantics variant of the frozen baseline** | A filed follow-up for container closure. Blocking fact recorded: *placed out of scope by operator decision 2026-08-12; settling it requires a scope change above the ticket.* The shipped record must carry this boundary wherever `outcome=ESTABLISHED` appears, and into the `ckeri` bundle — not the ledger alone |

| ✅ | **Topology ruled 2026-08-13** — `#246` reports **directly to the desk** while it is the sole active ticket; `e190` retains `#247`-`#250` and regains `#246` when the portfolio opens. Effective at release | Desk ruling, not escalated. Structural rather than performance: an epic owner with **one** child has nothing to coordinate and is a relay by construction. `e190` is invited to argue it down |

## State by unit

| | Unit | State |
|---|---|---|
| ✅ | `#192` tractability | Terminal Blake2b_256 FAIL retained as a valid measurement of the obsolete pin; preserved as tag `m8/192-terminal-fail-record`, pushed |
| ✅ | `#234` dual-head bump + identity checker | **Merged** (PR #252, `9d4eb957`). The checker is on `main`, wired into `just ci-offchain` and `ci.yml` — runs on every change, no opt-in. Authenticates **lock-backed rows only** |
| ✅ | P0 scope | 14 claims + 4 written exclusions ratified. Operator: *"this is not final, it's a start"* — a first set, not a ceiling |
| ✅ | Proof target | **PlutusV3 post-Conway (`variantE`)**. All earlier variant-C evidence relabelled *pre-Conway*, not deleted; 12 of 23 rows re-baseline |
| ✅ | Artifact decision | Ships on the `ckeri` release line as an attached, independently-runnable evidence bundle, hash-bound to commit + toolchain + variant. **M1's close gates on it** |
| ⛔ | `#246` post-Conway E baseline | Rebased onto merged `main`; tree clean; **9 unpushed commits, single-copy on this host**. Slice A closed on second audit rejection; replan filed |
| ⏳ | `#247` `#248` `#249` `#250` | Filed, undispatched. One ticket at a time; 2/3 overlap suspended |
| ⏳ | `#193` `#194` `#195` | Unparked — their `#219` precondition merged 2026-08-04. Need the combined post-#219 **and** post-Conway rerun |
| ⛔ | Blaster/Aiken skill | `SKILL.md` written and live; unaccepted and untracked |

## Artifact

The verification ships as an additive asset on the **`ckeri`** release line — one thing a stranger can obtain and rerun — hash-bound to the exact commit, Aiken toolchain and semantics variant it verifies. M1's close gates on its existence, not on every 0.x release. Decided with the M1 desk; M8 keeps an internal line for iteration only.

## Discipline in force

One ticket at a time · Claude T.O. → Codex commit owner → fresh Claude auditor · `agy`/`qwen` draft-only, secrets a hard bar · no claim accepted until its own falsifier is shown **RED before** its GREEN · untracked means uncovered · **could not evaluate must be RED** · every aggregate publishes its denominator.
