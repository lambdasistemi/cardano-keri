# Milestone ledger — cardano-keri M1.2 (GitHub milestone 11)

**Outcome:** the decomposed record+cursor family — the M1-terminal redesign as
deployable validators, delivered as usable packaged executables on the provisional
`ckeri` line.

**Observable test:** every family member compiles within the per-script ceilings with
stated headroom, each is behind an immutable can-fail gate on the INV-BIND pattern, and
a stranger can OBTAIN and run the packaged `ckeri` artifact. Counting closed children is
the vacuous pass and is not accepted.

**Status:** architectural experiment until its gates pass. The experiment claims policy
is in force for every external word.

Desk: session `keri-m12`, singleton window `cardano-keri-ms11-decomposed-record-cursor`,
pane `%6656` (successor, Claude Fable session resident in the operator conversation), runtime root `/tmp/ms-keri-11`, home repo `/code/cardano-keri`.
Parent: cardano-keri project owner, pane `%6429`, runtime `/tmp/projects/cardano-keri`.

---

## Released scope

**S0 and S1 ONLY**, per machine release `RELEASE-M12-S0-S1-2026-08-18.md`
sha256 `b0453ae755b56857f7f243c8f089be0b121439f5238e64a35d4c8069acd54609`.
Silence never widens these bounds.

| gate | state | owns |
|---|---|---|
| S0 — per-script SIZE fail-fast from skeletons | 🟡 RELEASED, lane requested | the one number M1 left open |
| S1 — HARNESS QUALITY before any subject slot | 🟡 RELEASED, lane requested | the four-slots lesson, applied up front |
| S2 — family behaviour on the INV-BIND pattern | ⏳ WITHHELD | not authorized; no work, not even planning |
| S3 — G2 preprod lineage-activation drill | ⏳ WITHHELD | needs a SECOND written release naming every write |

Mutation fence in force. Allowed: local source commits preserving S0/S1 work;
authenticated mutation ONLY of the `milestones` snapshot branch and the M11 state wiki
page, each with remote read-back; public-reference reads and local read-only inspection.
Withheld: product-code push, PR, merge, release, any other authenticated GitHub mutation;
S2 deep behaviour; S3/G2 preprod; mainnet, production rollout, announcement, external
commitment, product graduation, product-gate work, delegation, credential state; any
modification or restart of custodial-terminal M1.

**Consequence recorded at founding, not discovered late:** because every authenticated
GitHub mutation except the two bookkeeping surfaces is withheld, the S0 and S1 lanes run
**without GitHub issues and without PRs**. Their work is preserved as LOCAL COMMITS only.
This is a deliberate, stated deviation from the normal ticket lifecycle, not an oversight.

---

## The inheritance — verified by this desk, item by item

The machine owner deliberately spot-checked one of eight and left the rest to this desk,
on the correct ground that a custodian should not audit a chain of custody it does not own.
All eight verified 2026-08-18 by the desk:

| inheritance | identity | result |
|---|---|---|
| M1 terminal steering package | sha256 `793bab01…d56410` | OK |
| G1 four-leg results | sha256 `57585ae0…e85160` | OK |
| G1 frozen V13 harness | sha256 `702817f5…84847dcb7b3` | OK |
| G1 contract hashes v13 | sha256 `92a52eea…d9910b5f6` | OK |
| frozen INV-BIND gate | sha256 `7037228b…c25171a7b1` | OK |
| decoder candidate | commit `7f49dd8b` "fix(291): restore p/di parity from event bytes" | OK |
| final released head | commit `d57e4354` "fix(291): remove obsolete integer array helper" | OK |
| fixture-only follow-up, kept DISTINCT | commit `30cab019` "test(291): align registration verdict declarations" | OK — and confirmed a CHILD of `d57e4354`, so it genuinely sits after the released head |
| wiki evidence @ `e040f12a` | `M1-Reshape-2026-08-17.md` `021eb66c…`, `M1-Terminal-Evidence-2026-08-18.md` `56d8d127…` | OK — blobs hashed FROM GIT OBJECTS, not the worktree |
| wiki intake clone | `/tmp/cardano-keri-m12-wiki-intake`, origin `lambdasistemi/cardano-keri.wiki`, HEAD `e040f12a`, clean | OK |
| installed milestone 11 mandate | `.description` CLI-newline sha256 `0c997ebe…a583454` | OK |

The findings are deliberately ASYMMETRIC and are inherited as such: G0's decoder repair is
PROVEN and retained; G1's measurements GUIDE the redesign with every caveat intact; neither
makes the 25,934-byte monolithic checkpoint fit. That architecture is not reopened.

### What the inherited numbers actually say

- `checkpoint.checkpoint` = **25,934 B** = 158.3% of the 16,384 B tx limit, 160.8% of the
  16,133 B reference ceiling. Three more validators sit at **80–92% before parameter
  application**, which only adds bytes. This is a design constraint, not a bug.
- Registration breaches memory at **24 keys** (20 last accepted, 6.60% headroom);
  **memory binds, not CPU** (cpu still 20.5% clear at 24). The exact crossing lies in 21..23
  and was NOT measured — the honest result is the interval, and it is recorded as an interval.
- The "seven keys" maximum is real but enforced one transaction EARLIER than the claim
  implies: an 8-key inception is 1,049 B measured against a 1024-byte SAID bound and is
  refused at the PREMINT validator, so it never reaches registration.
- **Proof depth is NOT the cost driver** — depth 5 at vLEI scale costs 4.6% of memory, and
  the structural maximum of 64 nibbles reaches only ~27%. Whatever drives a 24 M-mem advance,
  depth is not it. This negative result is the useful one.
- Coupling = **15,155,350 mem across TWO transactions** — an upper bound composing the
  heaviest measured instance of each role, NOT a trace of one AID and NOT a headroom claim.
- Witness frontier NEVER REACHED: 24 accepts with 38.85% memory unspent — a maximum
  *measured*, not a bound.

---

## S0 BARE VERDICT — corrected set, 2026-08-18T10:54:39Z (submission 2, source `02c486e`)

Submission 1's rows were **superseded by S0 itself**, naming all three causes:
`anti-stub-reachability`, `lineage-root-flags`, and `actual-INV-BIND-SAID-cost-omitted`.
The corrected set includes the real INV-BIND/SAID cost.

| member | bytes | % of 16,133 ref ceiling | ref headroom | % of 16,384 tx limit | row |
|---|---:|---:|---:|---:|---|
| append | 3,567 | 22.10% | 12,566 | 21.77% | PASS |
| cursor | 3,475 | 21.53% | 12,658 | 21.20% | PASS |
| lineage | 2,078 | 12.88% | 14,055 | 12.68% | PASS |
| maintenance_escrow | 831 | 5.15% | 15,302 | 5.07% | PASS |
| **staging_proof_token** | **13,144** | **81.47%** | **2,989** | **80.22%** | **REDESIGN** |
| consumer_predicates | 699 | 4.33% | 15,434 | 4.26% | PASS |
| reference_cursor_consumer | 1,389 | 8.60% | 14,744 | 8.47% | PASS |

**The gate fired, and it paid for itself on its first use.** Including the omitted cost moved
`staging_proof_token` from 1,609 B (9.97%) to 13,144 B (**81.47%**), across the 80% threshold,
with `action=stop-before-deep-build`. The cheap provisional PASS this desk refused to accept
was wrong in exactly the way its audit predicted. Six members meanwhile got *cheaper* under
the corrected model — the cost redistributed rather than inflating uniformly.

**What it means for the milestone.** The decomposition still answers M1's constraint: the
monolith was 160.8% of this ceiling and could not be redesigned into fitting; here six of
seven members sit at 4–22% and one sits at 81%. The family is viable, and it is **not
uniformly cheap** — the expensive member is exactly the one whose mandate says *token policy =
parser script*, i.e. the member that carries parse work into the token.

**Caveat on every row, in both directions:** *size-only; transaction-fit unproven.* Script
bytes under 16,384 never prove a transaction fits, and these remain SKELETONS — deep work adds
bytes, which is why the gate sits at 80% rather than 100%.

**Desk ruling (NOTE-002 to S0, acknowledged):** the redesign is **in scope for S0**, because
the mandate's own gate text says any member above 80% at skeleton stage is redesigned before
deep work. Bounded to reshaping the skeleton and re-measuring; S2 deep behaviour stays
withheld, and if the only route under 80% is real behaviour, S0 stops and escalates rather
than absorbing a scope change. S0 was pointed at the sibling that already solved this class —
the registration path's two-transaction premint+burn with the SAID/length bound enforced at
the premint validator — before designing anything novel.

**Redesign shape, authorized and bounded.** S0 adopted the sibling pattern rather than inventing:
two-transaction **premint + burn** on the `hash_proof.ak` precedent — TxA carries
length+SAID+Blake3+pair-token, TxB carries total-parse+proof-input+burn, `s2_deep=forbidden`.
Adopting that precedent inherits its measured boundaries, which the desk handed down rather
than letting the lane rediscover them: the **1024-byte SAID bound enforced at the PREMINT
validator** (an 8-key inception measured at 1,049 B is REFUSED one transaction before
registration), the coupling cost of **15,155,350 mem + 7,631,646,035 cpu summed across two
transactions** (no per-tx limit, no headroom claim, an upper bound composing the heaviest
measured instance of each role), and two **known-broken controls** `g1_c4_input_393`/`_966`
which S0 has excluded explicitly. A two-transaction shape makes the standing caveat MORE
load-bearing, not less: per-script bytes now say even less about whether either transaction
fits.

**Co-residency: the finding the per-script gate could not make.** The family's central
transaction structurally requires three of the large members at once —
`TxB-staged-event = append + cursor + staging_proof_token` (plus `maintenance_escrow` when a
fully-witnessed premium is claimed) — because **a single pair-token burn authenticates both
append and cursor**. The structural sum is **25,617 B**. M1's fatal monolith was 25,934 B.

The desk refused to import M1's verdict by resemblance, and was right to: M1's number was ONE
script against a PER-SCRIPT limit, which nothing composes away; this is a SUM of three scripts
each comfortably under that limit. S0 reported `CO-RESIDENCY-FAIL`, then on desk challenge
**superseded its own finding** to `CO-RESIDENCY-UNRESOLVED ... no-fit-claim=true`, because the
skeletons contain **no witness construction** and therefore establish no governing limit.

A read-only inspection of shipped M1 code then shifted the burden: the **established witness
pattern is REFERENCE, not inline** (`CheckpointTxBuilder.hs:2942,2951-2952` — reference inputs
non-empty ⇒ inline script witness map empty, plus three corroborating sites). If the new family
follows it, the transaction body does not carry those bytes and the binding constraints are
Conway's `maxRefScriptSizePerTx` and the tiered reference-script fee — an **expense to
quantify, not an architectural death**. That is a strong prior, not proof, and it is carried as
an open contract scheduled as **S2's first question**, never as a late discovery.

**Audit history and the standing ruling.** Submission 2 (`3fa75055`) returned `blocking=0`,
invariants 10/10, gate exit 0, all seven rows independently matched, and the original 2 blocking
+ 9 tier-2 + owner-held SAID findings CLOSED. **Anti-stub held** — the hollow constant-`True`
family fails 10 of 17 cases, exactly the `reject_*` ones. Blake3 reachability was established
four independent ways, including an executed surgical mutation (8,757 → 1,121 B, −87.2%, with
`append`, `cursor`, `lineage` and released `hash_proof.mint` byte-for-byte unchanged), and the
honest fixture was verified against an independently written BLAKE3 with official test vectors
and a negative control.

The desk nevertheless authorized **one fresh narrow repair campaign** (A-001) — fresh owner
`claude`, fresh auditor `codex`, grok correctly excluded because its one-per-ticket seat was
already spent — for exactly three items:

1. disclose the **unmerged #291 decoder dependency** and correct its false "released" header —
   `append` 8,471 B and `cursor` 8,389 B measure code `main` does not have;
2. fix three percentages rounded half-up against a declared truncation method;
3. add a **Blake3-isolating negative case**, because removing `blake3.verify` alone survives the
   suite green while the program loses 87% of its bytes.

Item 3 is recorded as **deliberately exceeding the mandate's letter**: "every expensive control
must show it can fail" is already satisfied by the both-ways proof. It is required anyway
because S0's numbers gate S2 activation and will be inherited for months, and a control blind to
the removal of the component that dominates the artifact is the failure mode this programme has
repeatedly paid for. The auditor's `blocking=0` severity is explicitly **not** disputed.

## Evidence correction — inherited G0 decoder claims are qualified

`EVIDENCE-CORRECTION-001-inherited-decoder-claims.md`, sha256 `d2f19779…`, append-only, required
by ruling `A-006`. **The activation package is not rewritten**; both submissions are retained and
future citations must point at the correction.

Two of M1's three headline G0 claims do not hold for the **malformed protected-array class**: the
`496/496` sweep could not reach it (fixtures had empty `b`/`br`/`ba`, positions hand-written), and
cross-decoder parity fails for it (`Err(_) -> []` in `event_decoder.ak` made Aiken accept bytes the
Haskell mirror rejects, reaching registration and advance witness-state decisions).

**Activation stands.** S0 and S1 were accepted on their own independent evidence and Surface B
landed nothing, so no product code of this class reached `main`. Repair is authorized as one
bounded campaign under A-006.

## Activation — M12-S2-ACTIVATED recorded 2026-08-18T14:58:10Z

Surfaces **A** (S2 full behaviour/budget work) and **B** (the accepted decoder repair path to
current `main`) self-execute under RELEASE-006, activated by RELEASE-015 after the project owner
independently reverified both accepted commits, the S0 final tree, all six retained audit-report
hashes, clean worktrees, and the submission-1→2 package diff.

Activation package submission 2, sha256
`9cab6884ad7c2de29bd6c26fde286123fe7d4febc017b42d32ba5f9fe7f8ce85`, superseding submission 1
`1b2bdf58…` which was returned for a **hybrid S0 table** — the desk had printed pre-redesign
append/cursor rows beside the post-redesign co-residency sum they contradicted.

**Activation discharges nothing.** Every residual in the package is inherited: all S0 figures are
size-only; the 25,617 B and 26,448 B sums are **evidence, not a NO-GO**; the pair-token coupling is
a **skeleton artifact, not a released invariant**; #291 is unmerged and prose-controlled; S2
measurement inherits S0's binary-content digest control because A3-F1 stands; mutation coverage is
not general; `Q-003` is unresolved; and no offchain TxB builder, manifest or transaction test
exists yet.

**Every merge remains separately fenced:** milestone-owner acceptance, auditor-clean evidence for
that exact candidate, and green CI. **Activation authorizes no cold realization** — the two-token
interlock governs every build.

### The candidate boundary (project owner, A-004 — tighter than the desk proposed)

The lanes run in parallel, but **no S2 final candidate may be declared or accepted until Surface
B's accepted final SHA is landed on `main`, incorporated into the S2 branch, and S2's applicable
gates are rerun on that ancestry.** All final byte baselines, the 25,617/26,448 comparison and any
transaction-fit statement are regenerated after that incorporation. **No pre-B number may travel as
current**; anything decoder-dependent before that point is provisional and labelled so.

The desk's own proposal bound only the byte baselines; the project owner bound the whole candidate,
which closes the gap where a candidate could have been declared on pre-B evidence with only its
numbers flagged.

## PARKED FOR SUCCESSION — 2026-08-18T18:42Z

Incumbent owner pane `%6695` parked under operator ruling `08f50ecd…e72a5` (NOTE-018); successor is
pane `%6656`. **Owner transfer, not a milestone pause.** `children-retained=true`: no lane halted,
no process killed, no worktree or runtime root torn down, no evidence removed.

Both lanes are parked on **rulings, not stalls**: Surface B on `Q-007`, S2 on the mechanized
accepted-landed-Surface-B boundary. Both hold frozen candidates, unspent build budgets and clean
worktrees, and neither has pushed anything.

Full resurrection detail, including the successor's exact next action, is in
`.milestones/11/resume/ms.md`, with per-lane fragments in `resume/b-decoder.md` and
`resume/s2-witness.md` written by the lanes themselves rather than reconstructed by the desk.

## Immediate children — both DISPATCHED

Two lanes, matching the two-lane bound exactly. No epic layer: each stage is one bounded
deliverable with no cross-ticket contract for an epic owner to hold, so inserting one would
add authority without adding a job.

| lane | stage | role | family | state |
|---|---|---|---|---|
| `s0-owner` | S0 size fail-fast | ticket-orchestrator | codex | ✅ ACCEPTED, archived — final `137edef0`, tree `f7718f58` |
| `s1-owner` | S1 harness quality | ticket-orchestrator | codex | ✅ ACCEPTED with named residual A3-F1, archived — final `cde29251` |
| `b-decoder` | Surface B — land the decoder on `main` | ticket-orchestrator | codex `gpt-5.6-sol` high | 🟡 DISPATCHED — pane `%6715`, window `@4653`, worktree `/code/cardano-keri-ms11-b-decoder`, branch `ms11/b-decoder-land`, base `77e392d` |
| `s2-witness` | Surface A slice 1 — witness mode | ticket-orchestrator | codex `gpt-5.6-sol` high | 🟡 DISPATCHED — pane `%6716`, window `@4654`, worktree `/code/cardano-keri-ms11-s2-witness`, branch `ms11/s2-witness-mode`, base `77e392d` |

Family map and why it is legal: the desk is `claude`, so both ticket-owner seats alternate
to `codex` and stay on a metered family per the role fence. Inside each lane the intended
chain is T.O. `codex` → commit owner `grok-4.6` (preferred for the owner seat) → auditor
`claude`, which keeps all three seats distinct and holds to one grok seat per ticket.
No AGY or Gemini Flash seat exists for any role (REVOKED 2026-08-14). Qwen is draft-only.

A child is called DISPATCHED only after its own post-cursor `START`. Both have one, verified
against the launch: reported pane and family match what the machine owner built, and the two
worktrees are genuinely separate trees on separate branches off the same base.

## M1 backlog triage — 15 of 15, complete 2026-08-18

Operator priority directive (`681c78cb…`, relayed as NOTE-004): triage every open
milestone-1 issue against the record+cursor family. Manifest at
`/tmp/ms-keri-11/steering/M1-BACKLOG-TRIAGE.md` (sha256 `6097aa95…`), 473 lines, every
REWRITE carrying its complete proposed replacement contract.

**ADOPT 7** — #162 relayer (the unattended append path) · #166 stranger run (the outcome
test in issue form) · #171 indexer (design-independent; consumers need it *more* now) ·
#226 two-UTxO first-run wall (worsens — the family's staged proof-token inherits the premint
shape) · #227 close helper missing from release artifacts (directly fails the packaged-artifact
outcome) · #275 PR-description scrub (public repo hygiene) · #291 the INV-BIND fix (repair
already proven; defect class applies directly to a family whose staging policy *is* a parser).

**REWRITE 8** — #156 producer epic (Hunter role deleted, Consumer added) · #163 hunter I
(bond/ARMED/claim/FROZEN/thaw die; duplicity DETECTION survives into the cursor's
`duplicity-detected` state and the mandated AUTHORIZING-before / REFUSED-after demonstration) ·
#183 tx-builder reuse (retargeted, and now intersecting S2's witness-mode question) · #184/#185
release-quality children · #186 release-hardening epic (retargeted to the `ckeri` line — the
only backlog item that enforces quality before the artifact ships) · #274 on-chain block
(projection law preserved word for word; bounty-authentication child dies with the economy) ·
#279 preprod inventory (finding preserved verbatim, destination open).

**CLOSE 0**, stated as a self-challenge rather than left to look like laziness: M1's
*architecture* died, but its *backlog* is overwhelmingly infrastructure, UX, docs, release
quality and one proven security fix — categories indifferent to which validator family sits
underneath. The freeze/convict economics lived in #164 and #271, and **neither is in the 15**.

**Nothing is applied.** Two barriers stand: the machine's manifest-bound bookkeeping extension,
and the project owner's acceptance of the exact 15 rows.

**Open question, escalated not guessed:** #279's destination — does the preprod cutover still
target checkpoint-v1, retarget to the family, or is it abandoned?

## Priority

S0 and S1 are **co-equal and parallel** — the release authorizes both and they are
independent (S0 measures new skeletons; S1 repairs the inherited harness class). No
inversion is recorded because none was made. If capacity forces a choice, **S1 outranks
S0**, because S1 is what stops a scaffolding defect from eating a second slot for the same
cause, and M1 proved that cost is real: four cold slots, four distinct harness failures,
zero subject verdicts.

## Serialization — TWO tokens, programme then host (binding from 2026-08-18)

A host-wide interlock now sits above this milestone's own token, because a second programme
(`cardano-node-antithesis` #214) can now build on this host. The defect it closes is the per-lane
floor gap one level up, and the arithmetic was re-derived at this desk rather than accepted:

```
one programme   53.10 -> 50.00   clears the 48.00 min-free trigger by 2.00
TWO programmes  53.10 -> 46.90   1.10 BELOW the trigger
```

Each programme passes its own start check and the pair still crosses. Crossing `min-free` is a
**correctness** risk, not a stall: the daemon collects concurrently with running builds and can
invalidate a dependency mid-flight.

**Acquisition contract — no lane may realize without it:**

1. acquire the programme token `/tmp/ms-keri-11/BUILD-TOKEN` atomically with `mkdir`;
2. **only then** acquire the host token `/tmp/machine/BUILD-TOKEN` atomically with `mkdir` — this
   order stops an M1.2 lane occupying the host token while queued behind another M1.2 lane;
3. if the host token cannot be acquired, **do not realize**: unwind only this attempt's own
   acquisition, wait, retry from step 1, and never remove or modify another holder's directory;
4. with both held, re-measure with exactly `df -B1 --output=avail /nix/store` — never a worktree
   path — and apply the exact-byte start bar and the 50.00 GiB stop;
5. record holder, command, exact starting bytes and both acquisitions in the lane's STATUS
   **before** executing;
6. release host token, then programme token, via a cleanup trap owned by the holder, including on
   failure; record exit status, final available bytes and both releases.

An invalid or missing store path, an unexplained realizing process, a token anomaly or a floor
violation is a **machine event**: stop, preserve evidence, report upward, never retry.

Before any planned build cluster the desk notifies the project owner, so the machine owner can
collect ahead under a timestamped gap report and declare its start.

**Dispatch obligation:** no future M1.2 lane brief may authorize a realizing command without
carrying this contract verbatim. At the time it was instituted there were no active lanes to
cascade to, so it binds the next dispatch rather than any current one.

## Lane-terminal beat — armed day one, and proven able to fire

Mechanism: **Monitor task `bmibxhszr`**, persistent, event-firing INTO the desk conversation
(not a background tail — a tail nobody reads is telemetry, not supervision).
Script `/tmp/ms-keri-11/beat/lane-beat.sh` sha256
`9f6d305ee49da340b5f915b7f3a94fed1df9497574b1e12a577dc2aca25ff9c3`.
Subjects: `/tmp/ms-keri-11/<child>/STATUS.md`, **depth-2 only** — immediate children,
never grandchildren.

Three legs, because silence has three causes: `EVENT` (terminal/actionable lines, and
`COMPLETE` is in the alternation so a capacity death is not silent), `STALE` (started, no
`COMPLETE`, journal quiet > 900s — the WEDGE leg a tail cannot see), `NEVER-STARTED`
(root exists, STATUS still empty > 600s — a dispatch that did not take).

Can-wake demonstration, run on the SAME script with small constants: EVENT fired on a
`BLOCKED` line; STALE fired on a started-not-complete lane quiet 7,202s; NEVER-STARTED
fired on an empty STATUS. **Silent control held** — a lane with a `COMPLETE` and an
identical two-hour-old mtime produced NO stale alarm, proving the instrument discriminates
rather than alarming on age alone.

## Parked decisions / open questions to the project owner

1. **The outcome names an artifact the release cannot produce.** M11's outcome sentence
   requires "usable packaged executables on the `ckeri` line"; the S0+S1 release withholds
   release and every authenticated product mutation. Correct for S0/S1; must be resolved by
   a later release before the outcome audit can pass. Recommendation: schedule the artifact
   release question now, decide it later — do not let it surface at close.
2. **RESOLVED 2026-08-18 — description state-URL grant.** The installed description carried
   no bare M11-State URL, so the publisher RED'd. The desk recorded the exact RED and did
   NOT widen its own bookkeeping grant to "fix" a one-line append. AMENDMENT 02 (machine
   owner, source sha256 `7f22bf6a…f120f`) granted exactly one append; the machine owner
   recorded the scoping gap as its own ("I authorized the artifact and not its address").
   Executed as append-only: first 4942 bytes proven byte-identical to the original, URL
   present exactly once, remote read-back byte-identical to intent, and the SAME publisher
   gate that produced the RED now exits 0. Description CLI-newline hash moved
   `0c997ebe…a583454` → `c11b08ae…6a7d25cb`.
3. **S0/S1 run without GitHub issues or PRs** as a consequence of the mutation fence
   (item above). Stated, not discovered.
4. **Sibling-tree anomaly, reported not touched:** the `milestones` branch contains a
   nested duplicate `.milestones/1/1/` alongside `.milestones/1/`. It belongs to M1's tree,
   which is custodial-terminal and not this desk's to edit. Preserved byte-for-byte.
5. **The bundled `ledger-sweep.sh` no longer implements the documented invariant.** It now
   parents each commit on the pulled base and pushes fast-forward, which cannot produce the
   depth-1 fresh root that both the milestone skill and NOTE-002 require. The desk followed
   NOTE-002 (fresh root + force-with-lease bound to the named SHA), which preserves the
   sibling-clobber protection the script's rewrite was reaching for.

## Backlog steering — status of the mutation payload

The 15-row triage was **accepted at ruling level** (RULING-008), including the zero-CLOSE
self-challenge and the retention of #184/#185 as rewrites. `#279`'s destination was ruled: the
cutover targets the **record+cursor family under M1.2**, and that ruling starts no preprod read
or write.

Execution is gated behind an **exact-payload barrier**, deliberately separate from the ruling:

- **Submission 1** (`6e4c4803…`) — REJECTED by project review on blocking finding **P1**: several
  bodies preserved retired normative M1 text and appended contradictory M1.2 corrections, leaving
  a reader to decide whether the first or last incompatible requirement wins. The finding was
  correct and is the desk's own defect: it optimised for "preserve original content" at the cost
  of internal consistency.
- **Submission 2** (`dbcd520e…`, dry run `bcdf6350…`) — returned for acceptance. 13 of 15 bodies
  rewritten; operative goal/scope/dependencies/acceptance transformed to the M1.2 contract;
  retired norms deleted rather than appended around; retained history under explicitly
  non-operative headings with no unchecked acceptance items. Two live reads, **0/15 drift**.
  A targeted stale-norm scan explains all 22 surviving operative hits by issue and line, of which
  #279's ARMED/FROZEN and #291's decoder vocabulary are the review's own carve-outs.
- One defect the review did not name was found by that scan: **#291 carried an unchecked
  acceptance item requiring the retired conviction-evidence path be fixed.** Replaced with a
  no-offset interface audit item.

**Nothing is applied.** Surface C stays inactive until the project owner accepts an exact payload.

## Conditional release surfaces — prepared, inactive

RELEASE-006 grants three surfaces conditionally: **A** S2 full-logic behaviour gates, ExUnits and
size rows, the reference-input cost branch, and accepted S2 push/PR/merge; **B** landing the
proven decoder repair on `main`; **C** issue mutations matching an accepted manifest exactly.

A and B self-execute only after the desk submits an activation package naming the exact accepted
S0 and S1 candidate hashes, each fresh auditor verdict and report hash, the can-fail gate evidence
supporting acceptance, and any residual qualification — and the project owner independently
verifies it and records `M12-S2-ACTIVATED`. **Neither S0 nor S1 is accepted yet**, so nothing is
active.

## Surface B — terminal findings and bounded re-cut (2026-08-18T20:30Z)

Submission-2 auditor returned terminal AUDIT-FINDINGS: candidate 0a12237b REJECTED
(five malformed base16 literals — onchain project unparseable, 22 legs wrong-reason
RED; frozen-gate RED control inert via unread INV_BIND_PHASE; F1 non-discriminating).
Exhausted ticket terminal/read-only; main untouched; old gate 7037228 immutable
refusal evidence. Project A-010 grants ONE bounded re-cut: 2 submissions, 5
realizing clusters, three-file scope (no production edits), NEW gate freezing a
mechanism (mutant-proved RED, both-ways scope fence, cause-specific markers),
parse-gate-first in every cluster. Fresh seat requested (tB2-decoder-recut).
S2 remains parked on accepted-landed-B ancestry. Standing resource rule: start bar
50.00+3.10×N+0.90 GiB (N incl. self) + two-token interlock; per-run machine
coordination retired.

## Contract registry addition

contract:  edited Aiken proof files -> pre-audit whole-project parse/typecheck
parties:   every M1.2 lane editing onchain proof files; S1 harness (gap found)
invariant: no paid audit may start on an unparseable proof project
enforced:  re-cut gate (parse-gate-first); repo-wide S1 follow-up = separate
           commissioned scope, PARKED at project owner

## Surface B — A-010 terminal (gate defect), A-011 two-phase successor (2026-08-18T21:52Z)

Re-cut run 1 terminated pre-work (append-only journal rewritten; archived with
pane evidence; machine process-kill doctrine applied). Re-cut proper ended
pre-realization on a replacement-gate defect: environment-dependent manifest
(unqualified PATH names + foreign mutable cache) — third environment-dependent-
control instance today. A-011 grants a two-phase successor: PHASE G gate-only
qualification (hermetic env -i bootstrap, sealed content-addressed inputs, two
real invoking environments with identical digests, poisoned-shim adversarial
control, one-byte live negative, both-ways scope kills; desk records
GATE-STANDARD-PASS before MANDATE-FROZEN; probe grok seat has no write/build
authority) then PHASE P product campaign reset to 0/2 submissions, 0/5 clusters,
re-derived from rejected ancestry 0a12237b (candidate 31d746af = comparison-only,
postdates the defective gate). Phase-G seat live: %6729@4658, START 21:06:25Z.
Zero realizations spent across all three terminations.

## Contract registry addition

contract:  frozen gates prove environment invariance across invoking seat families
parties:   every lane freezing a gate; every seat family invoking one
invariant: a frozen gate's verdict and manifests are a function of its sealed
           inputs only — identical across ticket-owner, commit-owner, auditor
           environments, and under adversarial PATH/locale/shim poisoning
enforced:  A-011 Phase-G standard for Surface B; repo-wide = the separately
           commissioned consolidation scope (with INV_BIND_PHASE, dev-less
           bwrap, PATH-wrapper instances as the class evidence)

## Surface B — Phase G passed, Phase P open (2026-08-18T23:02Z)

Gate inv-bind-recut-v3 GATE-STANDARD-PASS: verified by THREE independent
environments (ticket owner codex, probe grok-4.6, desk claude) with identical
ENV-INVARIANCE-DIGEST under adversarial poisoning; live negative reproduced by
the desk (sealed one-byte flip → cause-specific 67 → restored GREEN); the gate
also self-enforces its input seal (writable input → 66). MANDATE-FROZEN
21:38:19Z; probe promoted via RESUMED WRITE-AUTHORIZED; PHASE-P-START 21:41:13Z
(worktree cardano-keri-ms11-b-recut2 from rejected ancestry 0a12237b, zero
delta, counters 0/2 0/5). Campaign proceeds: repair authoring → parse-first
qualification → submission 1 → fresh Opus audit.

## Surface B — successor-2 (A-012) live (2026-08-19T00:12Z)

b-recut2 terminated by frozen-gate materialization defect (cp -a propagated
sealed 0555/0444 into the disposable build tree; parse-first Permission-denied;
1 cluster spent; candidate e8c06afd authored clean and ADMITTED by A-012 on
proven orthogonality). Registry class refined: 'frozen-gate verdict path !=
realizing path exercised before freeze'. Successor-2: gate v4 + Phase G-prime
(six controls + seventh paid qualify-path dry-run, cluster 1/6), six-cluster
ceiling with lineage accounting, Phase P starts at the admitted candidate.
Seat %6731@4659 START 22:27:02Z, counters 0/2 0/6.

## Surface B — v4 frozen, Phase P live at admitted candidate (2026-08-19T01:40Z)

Pre-freeze cycle: lane's own acceptance rejected probe-1's claimed PASS (two
v4 cleanup defects), corrected at zero cluster cost, replacement probe GREEN.
Paid qualify-path dry-run PASSED (cluster 1/6: PARSE-FIRST-GREEN on fixture
77e392dd, materialization mode-control can-fail pair via shared function,
SOURCE-IDENTITY, CLEANUP-PASS). Desk GATE-STANDARD-V4-PASS after full
reproduction (third-environment GREEN exact digest; desk-run negative 67
cause-specific). MANDATE-FROZEN gate 5d603349; probe promoted WRITE-AUTHORIZED;
product worktree /code/cardano-keri-ms11-b-recut3 at e8c06afd. Next: owner
qualification, submission 1, fresh Opus audit. Counters 0/2, 1/6.

## Surface B — successor-2 TERMINAL at the first true fork (2026-08-19T03:55Z)

v5 cycle succeeded end to end (data-driven six-path gate, all controls, paid
dry-run green 959/0). New candidate 337d0cdc PARSES — the fence expansion
worked. Owner qualification then failed one level deeper: inv_bind_f1_inner
crashes on an expected-ok icp fixture. With every scaffolding class fixed,
this is the campaign's first unblameable failure: either a residual test
defect or a TRUE production finding (the inherited decoder repair crashing on
a valid inception). A-013 no-extension honored: terminal at 0/2 submissions,
4/6 clusters, auditor unspent, main untouched. Q-014 asks the project for a
bounded read-only classification BEFORE any disposition — if the production
reading holds, Surface B's premise (repair proven, evidence missing) is false
and a production re-repair ruling precedes everything.

Lineage accounting across all Surface-B campaigns: 0 submissions ever
recorded, main untouched throughout, every failure caught pre-merge.

## Surface B — F1 classified; successor-3 endgame live (2026-08-19T05:35Z)

A-014 classifier verdict (read-only, fence proven intact): PRODUCTION decoder
defect, narrow — error-constructor masking in event_decoder.ak finish k/n arms
(inner ErrValueShape collapsed via :346 catch-all to ErrFieldOrder; b arm and
Haskell propagate correctly). Fail-closed intact, no crash, no valid input
rejected: a true Haskell/Aiken parity divergence in rejection classification,
caught by the F1 test. A-015 grants successor-3: ONE production file, finish
k/n error propagation only, direct parent 337d0cdc, v6 gate (nine planted
scope kills), clusters 5-8 (ceiling extended to 8, historical 0/2 4/6
append-only), captured cluster-4 failure = permanent regression RED. Seat
%6736@4662 START 02:58:48Z. Terminal on any failure; no successor-4 implied.

## Surface B — repair PROVEN GREEN; successor-3 terminal on gate rendering (2026-08-19T06:35Z)

Candidate 7c78e5f2 (one-file, parent 337d0cdc): parse 944/0 GREEN,
inv_bind_f1_inner GREEN — THE A-015 PRODUCTION DEFECT IS REPAIRED — census
PASSES with decoded trace exactly matching the required line. Frozen v6
exits 78: its census assertion greps ASCII while Aiken renders traces hex;
the qualify-only leg was unreachable by the pre-freeze dry-run (the
verdict-vs-unexercised-leg class, one level deeper). Terminal per A-015:
0/2 submissions, 6/8 clusters, auditor unspent, main untouched. Q-015
recommends narrow successor-4: rendering-aware assertion + marker-parser
can-fail control; candidate admitted as seed on the established
orthogonality precedent.

## Surface B — TERMINAL under A-017; S2-without-B disposition requested (2026-08-19T06:10Z)

Successor-4 (v7, A-016) died at cluster 7 on the missing gate-owned source-census
producer (`INV-BIND-SOURCE` marker impossible at the exact candidate; both
interface logs byte-identical `70813c1f…`). A-017 (`523cc1c2…`) granted ONE final
successor-5: v8 = gate-owned source census restored + non-short-circuiting
full-ladder rehearsal collector (26 rows, 14 columns, UNATTEMPTED=failure),
ceiling extended once to 11, any failure terminal with automatic Option 3.

v8 passed the full desk battery (my independent reproduction: manifests 136+25
zero-mismatch, dual scanners live, planted locator/primitive kills exit 88,
strict marker consumer, TWO-simultaneous-failure collector proof overall_exit=1,
one-byte sealed negative 67→restored GREEN, confinement diff `f07c52bc…` gate-only).
Rehearsal seat %6741 (grok-4.6, read-only) ran the ONE paid cluster 8/11:

**TERMINAL-FAIL** — wrapper exit 1, finalize exit 116, ledger `4fd8a69f…`,
26/26 rows, 18 PASS / 8 FAIL / 0 UNATTEMPTED. Causes: (1) six command legs
(focused-haskell 127, four vector legs, full-ci) — sealed hermetic path exposed
no `bash` basename to `env`/`just` (v8 gate-environment defect, not product);
(2) live-rejection 7/7 — `observer_advance` reference program 18,732 B vs
16,133 B budget (classification with project owner); (3) cleanup-release row
carries the failing release decision (cleanup itself 0, tokens released).
Candidate preserved exact/clean: `7c78e5f2`, tree `14885456`, parent `337d0cdc`.
Counters final: submissions 0/2, clusters 8/11; 9–11 unspent and dead.

The repair (one file, two insertions) remains proven through parse/F1/census/
mutants/A-007 isolation and UNLANDED. Escalation
`NOTE-M12-cluster8-terminal-s2-without-b` (sha `bd569a31…`) filed in the project
inbox; desk holds; no lane has product authority. Rehearsal seat closing via
machine owner; ticket owner %6740 held until the disposition lands.

## Design evidence — DESIGN-NOTE-001 (2026-08-19)

Operator design session (captured by parked incumbent %6695, HANDOFF-001):
record/cursor model. Settled: key=location+SAID; no version counters; value=
post-event key-state snapshot; whole-record cursor derivation; record is a
watcher evidence set (KEL superset); content-derivable rules match keripy,
observation-dependent rules ABSTAIN; settlement slot stored as evidence never
verdict. OPEN: naming, exact leaf schema, grade-policy tension, successor-stamp
sequencing. S0 skeleton gaps: redeemer-chosen MPF key (#291 class one level up),
SAID-only leaf, running-hash occupancy. Affects #163/#171/#274 (behind inactive
Surface C payload) and S2 scope. Highest-value check: cursor-vs-keripy parity
oracle with proven ABSTENTION + resolve-by-slot mutant.

- 2026-08-19 design/: DESIGN-NOTE-001 + TICKET-DRAFT (4a03a6a9, NOT FILED — RELEASE-015 holds issue mutations) + HANDOFF-001/002 landed on the milestones branch for durability; repository landing + ticket filing await project-owner authority (Q-017).

- 2026-08-19 HOST BINDING (machine): in hook-bearing repos `git commit` is a realizing command and takes both build tokens; never `--no-verify`; hook failure on missing cache path = machine event (stop, report, never retry). Desk audit: cardano-keri + b-recut4 worktree currently hook-free (zero non-sample, no hooksPath) — re-audit on any landed hook installer. Every future lane brief carries this clause.

## A-018 — Surface B ARCHIVED-RED; S2 recut without B; design authority (2026-08-19T08:53Z)

A-018 (final sha 1c9788a6…; pre-freeze aa296be7 consumed in a publication race, corrected by REV1 ecc8be81) accepted the cluster-8 terminal: Surface B closed
ARCHIVED-RED (candidate 7c78e5f2 + A-010..A-017 chain immutable evidence, never
a code seed); F1 error-constructor parity repair stays OPEN as labeled residual.
Oracle shortcut DENIED — no fabricated surface_b_sha; frozen s2w-v2 preserved
as evidence of the superseded contract. Replacement: fresh ticket-owner-authored
gate `s2w-no-b-v1` binding main snapshot 77e392dd + accepted S0 head 137edef0
(both ancestors of the fresh candidate), A-018 SHA + archived-RED hash,
manifest surface_b.status=ARCHIVED_RED + evidence hash, A3-F1 advisory + F1
residual + S0 digest control, the original witness-mode objective (REFERENCE vs
INLINE with INLINE executed; pinned maxRefScriptSizePerTx + fee tiers;
25,599/25,600/25,601 and 25,617/26,448), separate per-program/signed-creation
envelope vs ledger aggregate, and final then-current-main re-integration with
full rerun (drift ⇒ new SHA ⇒ fresh audit). Old S2 commits 0e6fb8d0/9049f379 =
evidence only; fresh branch/worktree from 77e392dd; per REV1 the old diff MAY be replayed/cherry-picked as implementation seed, gaining no acceptance by identity.

Topology: fresh Opus[1m] ticket owner → fresh Codex gpt-5.6 commit owner →
fresh distinct Opus[1m] auditor. %6718 barred (no local grok reading); %6716
terminalizes (handoff, no product write) then evidence-only. Cluster-8 failure
classes per A-018: six bash/just legs = v8 hermetic-gate environment defects;
18,732>16,133 live-rejection = real deployment-budget failure OF THE REJECTED
B ANCESTRY (50 paths vs main) — not evidence about no-B main; distinct from
maxRefScriptSizePerTx (report separately).

Q-017 granted narrowly: (1) docs lane lands DESIGN-NOTE-001 exact bytes at
docs/design/record-cursor-projection-fidelity.md (issue-backed, single file);
(2) exactly ONE issue — CREATED as #300, read back byte-exact (body 4a03a6a9),
milestone M1.2, web 200. Surface C otherwise PREPARED-INACTIVE.

Four design requirements = ordered post-slice OWNER slices (separately gated,
no bundling, [OPEN] semantics return to project before write). S2 COMPLETE bar:
witness slice + all four accepted with fresh audits (or explicit deferral).
Operator goal "complete S2" accepted as programme priority.

## A-018 execution — witness slice audited; landing paused at CI-red repair (2026-08-19T12:41Z)

Docs: DN-001 landed byte-exact on main (PR-301 → c2cd6d6e, desk-verified
80feb30f); issue #300 open by design. Recut lane (@4667): gate s2w-no-b-v1
frozen+falsified (57 checks) → desk-verified; v1.1 (envelope-provenance kill,
58 checks) after the TO caught my A-001 coverage error; candidate d5e542bc
(RED-first 6bd579fa, one-M-class witness slice, submission 1) → fresh Opus
audit PASS (report 16bbb311, ten invariants, three focuses independently
proven) → MILESTONE-ACCEPTED. Determination MEASURED: witness_mode=REFERENCE;
aggregate 25,617 vs maxRefScriptSizePerTx 204,800; signed creation envelopes
append 8,680 / cursor 8,598 / staging 8,966 all FIT vs maxTxSize 16,384;
INLINE live-exceed 25,969. Landing chain: stamp → final gate GREEN on 8c546e16
→ PR-302 → CI RED: real defect, three examples read repo files by relative
path (dead in packaged nix sandbox) — the documented just-ci≠nix-build class;
blind spot shared (TO gate + desk brief). A-005 ruling: option (b) — v1.2 gate
(+Build-Gate leg), Codex repair owner now (submission 2/2, budget 4), audit
PARKED to post-reset (Aug 21 09:00Z, fresh Opus), merge VOID until audit-2
PASS + green CI. Claude 68-70%/80% pause line governs. Q-018 (R1/R2/cursor-
output/R4-scope OPEN rulings + audit families) pending with project.
Phantom composer injections (2, unattributed, client-less) = open host defect;
standing rule: no pointer-id + no matching file = not an instruction.

- 2026-08-19T14:05Z Repair round closed GREEN: candidate 6a8d6ef6 (two paths,
  accepted artifacts byte-identical, assertions preserved, locator fixed via
  env-bound store paths with throw-on-unset, both execution paths bound) —
  desk-ruled push-now (A-007); PR-302 CI 20-success/2-skipped/0-fail on the
  repair head, Build Gate green, e2e residual answered by the real jobs.
  Remaining for the slice: parked audit-2 (fresh Opus, 2026-08-21T09:00Z
  reset) then guard-merge; merge VOID till then. Gate residuals named: v1.2
  does not realize the e2e check; A5 self-test gap.

## A-019 — requirement semantics fixed; audits post-reset (2026-08-19T14:14Z)

A-019 (sha 5ac7e868…) rules Q-018: option (a); all four requirements retained
in the S2 COMPLETE bar. Semantics now closed: R1 domain-separated event key
over verified i/s/p/d (exact Plutus constr + golden vectors, redeemer =
sibling proof only); R2 EventLeafV1 + KeyStateSnapshotV1 (validator-derived
witness set, ordered traits, last-establishment inheritance, delegation
anchor w/ seal_index, receipts as verified attestations never counts,
settlement slot evidence-only); cursor = two-facts CursorV1 (monotone
ever_duplicitous + ResolutionV1 Resolved/Abstained/NoValidTip); R4 abstention
= exactly first-seen-order-dependence after all content-derived rules, pinned
keripy digest, resolve-by-slot mutant must fail; R3 whole-record with
poison-survival attack case. Status correction bound: witness slice is
CI-GREEN/PROVISIONAL-PENDING-AUDIT-2 (audit-1 bound d5e542bc; repair head
6a8d6ef6 unaudited; audit-2 findings TERMINAL, no 3rd submission). Post-reset
order: audit-2 → guard-merge PR-302 → R1 → R2 → R3 → R4, one at a time, each
on predecessor's merged result. Families fixed Codex-owner/Opus-auditor.
M1.2 cold-start bar raised to 62.00 GiB one-lane (store below it at ruling
time — no cold realization now). Four mandate skeletons staged in mandates/
(hashes in desk STATUS); staged ≠ dispatched.

## Operator-directed day: grok pilot, NO-MERGE integrity, docs correction (2026-08-20)

Operator drove capacity policy live: resume → reduce-Claude-favor-Codex →
grok-attested. Machine reborn as Codex. Arc (A-020/A-021/A-022): instrumented
grok-4.6 pilot trial ran on operator-attested capacity over 6a8d6ef6 —
**4/4 planted faults (both classes), zero false positives/unsupported/
fabricated, independent live-state refresh** — AND one REAL candidate finding:
the committed mandate named gate v1.1 (+stale hashes) while v1.2 governs.
TO verified it, applied its own pre-registered bar: **NO MERGE** (A-021
condition 3), immediate hand-up. Desk authority-race error (both-tracks
composition) corrected by A-021: the mid-flight Opus seat was SCOPE-STOPped
unconsumed. Desk also self-caught a typed-not-computed hash in Q-021
(corrected; rule: only interpolate computed hashes).

A-022: docs-only forward correction granted (4 identity sites + both stale
hashes; NOT a submission) — commit 228a0cdd (parent 6a8d6ef6, 3-path fence,
desk pre-push verified) pushed; PR-302 now OPEN-CLEAN-GREEN-UNMERGED at the
corrected head. Old-head shadow packet sealed BEFORE the correction (manifest
93111c32, desk-verified: isolation proved). Tomorrow after 08:00Z + natural
rollover reading, sequential: (1) fresh Opus pilot-shadow on 6a8d6ef6
(packet-only, blind → grades grok trial, shadow_audits=1); (2) different
fresh Opus formal audit-2 on 8c546e16..228a0cdd — the ONLY merge gate;
FINDINGS ⇒ campaign terminal. R1 dispatches post-merge (Codex owner; store
GC'd above bar, acquire-time remeasure).

## WITNESS SLICE MERGED; R1 running (2026-08-20T10:38Z)

A-023/A-024 chain: grok trial-2 on the corrected head — 4/4 NEW-class
plants (incl. full primary-evidence refutation of a fabricated-waiver
plant), zero false positives — one predicate-3 dispute honestly handed up
(finding was a stale usage string in the /tmp gate INSTRUMENT, not the
candidate); project CONFIRMED PASS-AS-SCOPED (INSTRUMENT-RESIDUAL,
symmetry-test controlling). Predicates 5+6 ran clean: PR-302 guard-MERGED
as d68030fa, main read-back verified at desk. Standing:
PILOT-TRIAL-2-PENDING-SHADOW; both post-reset Opus audits MANDATORY
(old-head shadow via packet 93111c32 grades trial-1; formal audit-2 on
8c546e16..228a0cdd governs the product retroactively — FINDINGS ⇒
revert/freeze/terminal even post-merge). R1 DISPATCHED immediately:
retained TO per A-019 §8, fresh runtime r1-event-key, branch from
d68030fa, gate-first (r1-event-key-v1: domain-separated i/s/p/d key,
CESR golden vectors, rival-SAID coexistence proof), fresh Codex owner
next, Opus audit post-reset only.

## R1 full-gate abort under the one-shot grant (2026-08-20T13:13Z)

R1's candidate 6312a751 (RED-first, static-contract GREEN, submitter-key
defect structurally gone, fence-clean) reached its realizing gate under
machine one-shot token HOST-R1-COLD-20260820T125254Z (store restored to
68.1GB, PASS-THIN). Legs 1-2 (aiken fmt/check) acquired ABOVE bar and are
machine-accepted. Leg 3 (packaged) acquired 1.99GB BELOW bar in the same
second leg 2 released — the 0.2s predicate guard lost the race — with a
competing Plutus nix build independently violating the no-competing
predicate. The lane's own watch fired: owner interrupted, abort before my
stop order arrived; leg 4 never started; wrapper-trap termination
preserved release accounting; machine VETO ratified the abort (dual
cause; completed leg 3 correctly not retro-killed). One further honest
defect self-caught: the guard's trap-based release leaked the programme
token when killed (trap didn't run) — TO verified ownership and released;
LESSON: trap-based release is not a release; future guards are
owner-checked, not trap-trusted. Tokens FREE; zero R1 descendants; store
63.0GB and falling under the competing build. R1 PARKED at 6312a751:
full gate re-runs only under a future machine grant with real headroom.
Residuals ledger grows: campaign-bar-as-wrapper-parameter; guard-release
robustness; per-leg fail-before-command needs wrapper support, not
external races.

## Audit-2 FINDINGS; counterpower executed; witness campaign TERMINAL (2026-08-21T10:00Z)

The retroactive formal audit-2 (fresh Opus, blind, range 8c546e16..228a0cdd)
returned FINDINGS, 3 BLOCKING — desk-reproduced with the auditor's pinned
instrument before execution:
- F1: the repair's own two files sit in MEASURED_SOURCE_PATHS; the committed
  manifest still declares the pre-repair source-set digest — the frozen gate
  is RED (measured-source-set-drift) on the repair AND shipped head; the one
  executable manifest↔tree tie was severed by the shipped tree (S2W-I10 OPEN).
- F2 (generative): the GREEN authorizing submission 2 printed head=BASE —
  proof ran on a dirty worktree BEFORE commit; no gate run ever certified the
  candidate's tree. Survives F1's repair.
- F3: declared mandate bundle hash stale after the docs correction.
The repair's SUBSTANCE was verified sound (CI class truly fixed, fail-closed
proven by instrument, both surfaces store-path-identical by construction,
assertions identical, extra changes justified). The failure is the proof
system's. Pilot gradings: trial-1 shadow-graded (arithmetic half corroborated
with stronger refutations; live-state half ungradeable — blind-shadow packet
design residual); trial-2 graded by audit-2; shadow_audits=2; grok 2/3
trials, unqualified (machine decision).
Counterpower (A-023 precommitment) executed by the lane, verified at desk:
full revert PR-303 merged as ad0c99bb (targeted revert would restore red CI;
witness proof invalidated by the OPEN row) — main back to the
c2cd6d6e-equivalent green state, docs record retained; S0 acceptance
PRESERVED-AS-HISTORY (relands first in any recut); R1 frozen
ANCESTRY-DEPENDENT-PENDING-DISPOSITION at 6312a751; campaign terminal 2/2
submissions, no third. Registry gains audit-proposed invariants: CI-S2W-C
(gate receipts must print the candidate's head/tree), CI-S2W-D (no
contract-GREEN on dirty worktrees), CI-S2W-E (flake inputs not ../ literals)
— all enforced=NONE, mandatory in every future gate.
S2 CONSEQUENCE: the witness slice is no longer accepted-and-merged; the S2
COMPLETE bar cannot be met without a project disposition (witness recut under
the hardened invariants; R1 rebase target; bar restatement). Escalated.

## A-026 disposition + warm recut package (2026-08-21T10:2xZ)

A-026: witness recut GRANTED as ONE fresh campaign (reland S0 first w/
equivalence evidence → one clean candidate carrying witness+repair+
re-derived manifest digest+docs+hardening → one fresh audit; findings ⇒
terminal); gate contract = six mandatory controls (receipt head/tree
print+verify; dirty-tree refusal; manifest/tree re-derivation with
narrowing barred; executable bundle-hash recipe; CI-S2W-E conversion of
the ../ literals; free-prefix-after-commit + full gate on same SHA);
topology fresh Opus TO + Codex owner + Opus auditor, %6752-line never
reused; R1 preserved as ANCESTRY-DEPENDENT-SEED, recreated on the
recut's merged head (rebase ≠ acceptance); S2 bar = strict serial
S0-reland → witness-recut → R1 → R2 → R3 → R4. Execution
READY-BUT-HOST-BLOCKED (store 53.3GB < bar, falling): warm package
authored + swept (recut-prep/: brief, composition manifest,
non-realizing falsification plan — hashes in desk STATUS); no seat, no
candidate, no realization until the machine's campaign-specific
capacity release. Grok ruling (machine): 2/3 graded, NOT qualified as
Opus substitute, standing family membership unaffected, trial-3 needs
gradeable-shadow packet design.

- 2026-08-21T10:3xZ LEDGER CORRECTIONS (machine NOTE-048): (1) the "store
  53.3GB and falling" figure in the A-026 chapter was a stale trough sample —
  the store OSCILLATES around ~61.5GB, net-unmoved over a day; deficit vs the
  canonical bar 66,571,993,088 B is 4.59 GiB. (2) The store-erosion
  attribution to a tokenless-build interlock breach is WITHDRAWN — the
  consumer is the GitHub Actions runner fleet (10 units on this host), whose
  CI realizes and releases in multi-GB oscillations. Capacity release DENIED
  for now; machine announces unprompted when the bar is met; a read-only GC
  dry-run is measuring reclaimable bytes; the lanes-barred-while-CI-builds
  POLICY question is with the operator.

## A-027 — WATCHER-FIRST re-scope (operator ruling, 2026-08-21T15:5xZ)

Operator deferred witness mode out of M1.2; A-027 grants: S2 bar =
S0-exact-equivalence-reland → fresh R1 (base = read-back main after S0;
6312a751 read-only seed) → R2 → R3 → R4 → WORKING DEVNET WATCHER DEMO
(events appended via existing e2e; record grows; cursor returns permanent
ever_duplicitous + current resolution incl. valid coexistence after
recovery; txids/SAIDs/roots/cursor outputs preserved as the receipt; no
slot tie-break, no mock). Witness mode + its warm package move INTACT to
registered milestone #12 M1.3 "on-chain witnessing" — REGISTERED-ONLY,
ordered after M1.2, PRE-MAINNET MANDATORY, no present authority; package
hashes preserved (brief fe07215b, composition 0ef116ef, plan 89afc734).
All new gates inherit the six-control hardening. HOST-BUILD-HOLD stands
(14:38 sample 56.65GB, deficit ~9.92GB — corrected arithmetic). Restaged
warm: watcher-prep/ (s0-reland brief, R1-v2 brief, demo acceptance
spec). R2-R4 staged mandates unchanged.

- 2026-08-21T16:0xZ CORRECTION-050 executed: S0 brief r2 (TO=pure orchestrator, OWNER topology mandatory, no LIGHT-by-prose); R1 v2 brief rewritten SELF-CONTAINED (all witness-era ancestry + pre-reset timing VOID; sole predecessor = read-back main after S0). Demo spec, R2-R4 mandates, M1.3 package byte-preserved.

## 2026-08-22 — hourly loop killed, session swept, state page corrected, RELAND DISPATCHED

**The desk's hourly wake loop was the most expensive defect this milestone produced, and it
produced no product artifact at all.** Machine order (sha256
`ad6e9e2b37c3febfa6ac9c839ba1f0421d27077af625a97df1574ed0c5413926`) killed it at 07:22Z:
`scheduled_wakeups=0`, `replacement_poll=NONE`, context disposed by `/clear`. It had been
waking an ~850k-token context hourly to run three shell commands — 2.55M tokens a tick, 218
ticks, ~34% of a weekly ceiling, zero output, and it was the operator who found it rather than
any instrument. The governing doctrine was rewritten the same morning: **edge wake with no
timer wherever something can push**, and a wake is priced at context size × messages per tick
before it is armed. The desk now holds no timer, no loop and no poll; the machine owner
announces capacity unprompted and did exactly that today.

**Session swept (operator-directed, 07:55Z).** Five windows and eight idle seats retired: the
superseded incumbent desk and its worker, the terminal Surface B lane, the terminal witness
lane and its two workers, and the closed codex-succession pair. Every pane was verified idle at
a prompt before removal; no file, worktree, branch or product state was touched, and every
retired seat's STATUS, handoff and receipts remain on disk — the durable record was never in
the panes. Two live re-wake hazards went with them: an 874k-token idle Claude context, and
three Monitors still firing into a 100k context on a campaign that had been terminal for a day.

**State page corrected (08:0xZ).** The published page's journal tail was current, but
everything above it had been fossil since 2026-08-18: both entry gates shown as ACTIVE when
they are accepted and archived, lanes described as dispatched that no longer exist, a completed
owner succession presented as in progress, answered questions listed as open, the dominant
defect class understated at four instances instead of seven, and — worst — **a supervision beat
recorded as armed when it was not running.** That last one is this milestone's own dominant
defect class turned on its own state page, so it is named on the page rather than quietly
deleted. Retired text was **deleted rather than annotated**, applying the precedent the project
review set when it rejected submission 1 of the backlog payload for appending corrections
around retired norms. The beat must be re-armed and demonstrated able to fire before the first
watcher-first lane runs its gate.

**HOST-BUILD-HOLD LIFTED; the size-reland lane is DISPATCHED** — the first M1.2 lane to run
since the revert. RELEASE-001 (sha256
`3a70baf3faa740d08981c96c5a6b8f5a6058e5f9fdbb74c7da5a400a6c2bf663`) measured 72,305,041,408 B
available against the 66,571,993,088 B one-lane bar, a 5.34 GiB surplus produced by collecting
5,253 store paths rooted in 40 provably-dead worktrees (16.04 GiB reclaimed, four-way liveness
test on every target, no worktree deleted). Scope is host capacity only: **no acceptance, no
merge, no push, no R1 restart.** Conditions bound: remeasure at acquire and obey that number,
journal available bytes at acquire AND release, STOP at 53,687,091,200 B non-negotiable, N=1
lane.

**A gap was closed at dispatch.** The staged brief (sha256
`3f4cff86aee2ecb45ff2eed27a38b5b5f043e8c5256f2f6644bc3dd1ceeda9a4`, r2 per CORRECTION-050)
carried the realization law but **not the two-token acquisition contract**, which this desk's
own standing dispatch obligation requires every realizing brief to carry verbatim. It had been
authored under a hold, when no leg could realize and the omission was invisible. The dispatch
addendum `/tmp/ms-keri-11/s0-reland/inbox/DISPATCH-001-s0-reland-placed.md` carries the
contract verbatim, the four release conditions, the scope limit, and the reporting protocol.
Topology as mandated: fresh Opus ticket owner as pure orchestrator, Codex commit owner for
every repository write, fresh Opus auditor after the owner parks; merge only on audit PASS plus
green CI plus guard read-back.

One condition is a **deliverable, not bookkeeping**: the per-build store cost on this host has
only ever been estimated. This run is the chance to measure it, and both byte figures are owed
upward.

### Supervision beat — re-armed, and two more instances of the class found in the arming

Recorded 2026-08-22T08:09Z, while satisfying this desk's own published bar that the beat be
demonstrated able to fire before a watcher-first lane runs its gate.

**Instance 8 — the certified bytes were not the bytes.** This ledger recorded
`lane-beat.sh` sha256 `9f6d305ee49da340b5f915b7f3a94fed1df9497574b1e12a577dc2aca25ff9c3`; the
file on disk hashed `6198eb20feb0401a9588c8d6f5838cc9510d0f5c2c843438223a1f8d08d2bbcf`. The
can-fire demonstration this ledger relies on was therefore performed against a **different
program** than the one that would have been armed. The ledger further described **three legs**
where the script implements **four** — an `AWAITING-DESK-ANSWER` leg, which uses the protocol's
own state machine (an unanswered `BLOCKED` has no later `RESUMED`) to keep a lane that is
waiting on the desk from being reported as a wedge. That leg is real, is good, and was
undocumented.

**Instance 9 — the `NEVER-STARTED` leg was inert for the failure it names.** It fired only when
`STATUS.md` existed and was empty. A dispatch that genuinely does not take writes **no file at
all**, and the subject list was built by `find … -name STATUS.md`, so such a lane was never a
subject and never alarmed. The current lane is the proof: its `STATUS.md` was created by the
worker itself, not seeded by the desk at dispatch, so had that dispatch failed the leg built to
catch it would have stayed silent. **Seeding an empty `STATUS.md` at placement is now the
alternative convention if this fix is ever reverted.**

**Both closed, and the instrument re-certified on its actual bytes** — new sha256
`e0bf7e626ae1ce0f9882458add83419afbee36cb55bf80be2c0f548ee664a0e2`. All four legs shown able to
fire (`EVENT`; `STALE`; `NEVER-STARTED` on both an empty **and** an absent file;
`AWAITING-DESK-ANSWER`), with the **silent control holding**: a lane carrying `COMPLETE` at an
identical two-hour-old mtime produced no wedge alarm, so the instrument still discriminates a
finished lane from a dead one rather than alarming on age.

A `BEAT_LANES` allowlist was added and is mandatory in practice: pointed at the unfiltered
runtime root, the beat's first cycle would have replayed **291 journal lines from thirteen
closed campaigns** into the desk — the same flood-the-context failure mode that produced this
milestone's most expensive defect. It is armed on `s0-reland` alone (monitor `bmxwrdsyu`) and
fired correctly on that lane's `START` within seconds, with routine notes filtered.

⛔ **Order deviation, recorded not smoothed.** The published bar said re-arm *before* the first
watcher-first dispatch. Capacity landed mid-turn; the lane was dispatched at 08:04Z and the beat
armed roughly ten minutes later. A deliberate call on an oscillating store window, and a
deviation from this desk's own stated sequence either way.

## 2026-08-22 08:04–09:25Z — the first lane since the revert: product proven, apparatus rebuilt four times

Capacity was released unprompted at 08:04Z and the size-reland lane was
dispatched. **The product work finished in fourteen minutes. The remaining hour
went entirely into the machinery that certifies it**, and that is the story of
this chapter.

### The product, which is done

Candidate `26bea8843401ff19327ef6ae45e4f496844fc8d8`: 31 paths, **add-only, zero
modified files**. The lane derived that scope itself and proved three files which
differ between the accepted head and current `main` were advanced by other
people's later work — excluding them with evidence rather than relanding blind
and reverting others' edits. Exact blob-and-mode equivalence, 31/31, pinned by a
frozen manifest.

**The proof leg PASSED**: `measure-family.sh verify` re-derived the blueprint and
owned-source hash **from the relanded sources** and matched the frozen size
report. That is a level of proof a doctored file list cannot fake. The candidate
has not been re-cut, amended or rebased since, and is unpushed.

### Four gates, each fixing what the previous could not see

| gate | fixed | found by |
|---|---|---|
| v1 `fd7d74f3` | — (seven falsification legs) | desk reproduced all seven independently, in an isolated worktree, **before any product write** |
| v2 `46d53be7` | nested-token self-deadlock | the first realizing leg, which hung |
| v3 `fc035d38` | tokens leaked on the **success** path | a completed leg that locked the host |
| v4 `d4b2dfe2` | the cleanup control tested a **copy**, not production | desk mutation test |

**v1→v2.** The acquisition contract — carried verbatim into the brief as the
dispatch obligation requires — makes the outer runner acquire
`/tmp/ms-keri-11/BUILD-TOKEN`. The accepted S0 content being relanded ships
`scripts/s0/token.sh`, which acquires **the same path** with a blocking `mkdir`
loop. A `mkdir` mutex is not re-entrant, so the inner acquire waited forever on
the outer's own directory. **Invisible for four days because nothing could
realize under the hold; found within two minutes of the first leg that could.**
Fixed by handing the accepted helper a lane-private inner token through the
environment variable it already reads — no accepted byte edited, exact
equivalence intact, outer contract unchanged.

**v2→v3.** A leg then completed its proof and **left both tokens held by a dead
process**: `got_prog`/`got_host` were `local` to `realize_leg` while the `EXIT`
trap fires after that function returns, so the trap saw unbound names. The host
token blocks every programme on this machine, not only M1.2. The lane refused to
self-heal machine-jurisdiction state while parked and escalated; the desk
captured evidence, proved both directories empty and the holder dead, released
them in the contract's order — host then programme — and reported to the machine
owner. **Neither token directory carried a holder marker despite the marker
protocol: an orphaned lock is currently anonymous on disk.**

**v3→v4, and this is the one worth remembering.** v3's fix was correct, and its
new legs were built RED-before-GREEN as required. The desk took the frozen gate,
re-introduced **the exact defect** — one line, `local got_prog got_host` — and
ran the selftest: **it reported 13/13 GREEN.** `realize_leg` is invoked from one
place, the `realize` dispatch, and the selftest never calls it; both new legs
exercised a scratch *copy* of the teardown. The gate's own comment said so. That
is a control certifying a copy of the surface it claims to protect — **instance
eleven of this milestone's dominant class, inside the very leg written to close
instance ten.**

v4 ties the leg to the production path. Verified at the desk by the same
mutation: **full selftest RED, exit 1**, failing on `success-cleanup-green` with
the scratch token surviving. The mutant drove the real `realize_leg` to
`REALIZE-PASS` and printed a `REALIZE-RELEASE` journal line claiming both tokens
released **while the directories survived** — so the gate now mechanizes this
milestone's most expensive lesson: *a journal asserting success is not success.*

### The machine deliverable, measured at last

`acquire 71,963,664,384 → post-leg 71,962,693,632`, **delta 970,752 B (948 KiB)**.
The per-build store cost the machine had only ever estimated. The pinned Aiken
path is already present, so this leg class is not a cold build in any meaningful
sense — with the consequence recorded below.

### Topology: Claude is off the worker seats

Operator order, after an orchestrator defect at this desk overdrew the fleet's
Claude allowance. Worker seats are Codex and Grok only; the desk remains Claude
as the operator's interlocutor. The Opus ticket owner parked at a clean seam with
a hashed handoff and was retired once its Codex successor resumed **citing the
correct superseding handoff** — proof the durable artifacts were sufficient and
the pane was a fallback, not a dependency. Two mid-slice reseats were recorded as
deviations rather than laundered as policy. The auditor is Grok under a **graded
shadow** with a sealed plant list, because Grok is the only family distinct from
a Codex commit owner once Claude is barred, and the machine has ruled it not an
Opus substitute: an ungraded Grok PASS is not acceptance-grade evidence.

### A finite ship gate, declared against the desk's own drift

After rejecting v3 the desk declared the v4 bar **once and final** — production
tie, mutation goes RED, provenance assertion — with an explicit commitment not to
reject v4 for any further instance of the control class. v4 met two of the three;
the third (selftest asserts installed-equals-under-test) was **accepted as unmet
and carried to the gate template**, because the property is already enforced twice
procedurally and the failure it guards was the desk's own. Recorded openly rather
than declared a clean pass. *The owner holds the balance, not the audit.*

### Where it stopped

`REALIZE-PRECHECK`: available `66,089,857,024` against the `66,571,993,088` start
bar — **short by 460 MiB**, floor clear by 11.55 GiB. The lane held without
starting, exactly as the acquire-time re-measure requires.

The bar guards a multi-gigabyte cold build; this leg measures **948 KiB**. The
desk has asked the machine to authorize the leg class against a **declared
expected delta** with halt-and-report on overrun, floor explicitly untouched. The
store is trending away from the bar — 72.3 GB at release to 66.09 GB now — with
this lane consuming under a megabyte across the whole window.

### Defects this desk recorded against itself, today

Kept because a ledger that only records other people's failures is not evidence:
ordering a destructive reseat before inspecting the target; asserting a leg "ran
and released cleanly" from an absent pid when it had died and its trap released
on failure; issuing a disposition by pane message after instructing the worker
that only files count; nearly recording a false verification when a denied copy
left the *unmutated* gate under test; and a pointer that sat unsent, caught only
by the beat's `AWAITING-DESK-ANSWER` leg — the undocumented fourth leg of an
instrument whose certified hash had not matched its own bytes until that morning.

## 2026-08-22T11:43Z — S0 RELAND MERGED. First step of the watcher-first bar is done.

`main` = `84e3b7159115e9169b57a85cbf9053b94aa889ba`, via PR 304
<https://github.com/lambdasistemi/cardano-keri/pull/304>, from candidate
`a8b5dabf1098d320c00398b88f1be33a2cda1298`. **R1 has not started.**

### What landed

31 paths at exact S0 blobs and modes, add-only, **plus one adopted modification**:
a classification of S0's own seven validators as `Unapplied` against an
`s0MeasurementBoundary` reading *"M1.2 S0 measurement-only skeleton: no
production application site or published deployment identity."*

**Confirmed by two independent read-backs** — the lane's and the desk's — each
re-reading the remote and checking every path by blob *and* mode, plus the
classifier hunk. Neither accepted the other's word. This milestone exists because
a gate once reported green about a tree that was never the candidate's; a merge
is not a state until something reads it back.

### The finding that made this hard, and what it cost

Submission 1 was audited PASS with **seven of seven invariants**, behind a gate
the desk had verified four separate times, including an independently reproduced
mutation test. **CI rejected it**, and CI was right.

The revert had done two different things: deleted the files S0 added, and
modified pre-existing files. The lane's scope rule — *present at S0, absent at
main* — captures deletions exactly and is **structurally blind to
modifications**. Seven restored validators entered the blueprint with nothing
classifying them, and the deployment-arity invariant is set-equality both ways.

**`INV-ADD-ONLY` passed and was the wrong invariant.** `A=31 M=0 D=0` was verified
faithfully, and that property was *produced by excluding the very file that needed
modifying*. Not a control that failed to fire — a control certifying a true
property that was not the property that mattered. Every static control agreed;
the live boundary disagreed and was right.

Submission 2 replaced it with **`INV-COMPLETE-RELAND`**, mutation-proven: a
`production-missing-classifier` mutant goes RED. The invariant that did not exist
that morning now demonstrably catches the exact gap that had slipped past
everything else.

### The desk got the repair wrong, and the lane refused it

The first disposition ordered restoration of "S0's contributions" to five files.
**False.** The classification was authored in witness commit `8c546e1`, is absent
at S0 head, and four of those five files have S0 blobs identical to current
`main`. **The lane refused a parent instruction, produced object history, and was
correct.** Had it complied, witness-authored content would have landed in a
milestone whose operator ruling defers witness mode to M1.3.

The corrected ruling **adopts** the classification as S0 content — it describes
`s0_*` artifacts exclusively and carries no witness behaviour; authoring history
records when someone typed it, not what it describes. The commit message says so
in those terms, and **`INV-HONEST-PROVENANCE` makes that falsifiable**: a
`provenance-wrong-commit` mutant goes RED. A prose requirement became an
executable check.

### Machinery rebuilt five times to get one change through

v1 seven falsification legs · v2 fixed a nested-token self-deadlock against
accepted content · v3 fixed a teardown that leaked both build tokens on the
**success** path and left this host's lock held by a dead process · v4 tied the
cleanup control to the production path after the desk re-introduced the exact
defect and watched v3 report **13/13 green** · v5 installed a wrapper that
verifies the frozen gate's hash before exec and refuses on drift.

That wrapper closed an obligation the desk had accepted as **unmet** in the v4
acceptance and carried to the gate template — implemented unprompted a submission
later, and stronger than asked: hash identity enforced *at every invocation*
rather than at the moment someone looks.

### Numbers worth keeping

Measured verification leg: **962,560 B** actual against **970,752 B** declared —
0.84% under, 0.36% of its 256 MiB ceiling. Two runs of the class agree within
8 KB. The machine adopted a per-leg-class predicate on that evidence rather than
waiving its bar, on the reasoning that *a rule firing on every expected case
carries no information and lanes learn to route around it*.

**Corrected upward:** the desk had offered "lane 948 KiB vs fleet 4.2 GB" as a
policy datum. Withdrawn — this lane's own CI does a cold dev-shell build on this
host, and the store fell 3.58 GiB during it. The honest marginal cost of landing
an M1.2 change is the leg **plus its CI**.

### Desk defects recorded against itself, this lane

Eight, kept because a ledger recording only other people's failures is not
evidence: ordering a destructive reseat before inspecting the target; reading an
absent pid as a clean release when the trap had fired on failure; issuing a
disposition by pane message after instructing the worker that only files count;
a mutation test that silently ran the **unmutated** gate; a waiter matching
history, then the same waiter matching history **again** an hour later because
the instance was patched and the class was not; a ruling whose central premise
was false; and — sharpest — **a guard read-back that reported 31 mismatches on a
flawless merge because its own column mapping was wrong.** The verifier needed
verifying. Caught by reading the output rather than the summary line.

### Carried out of this lane

Two onward discoveries, desk-owned, **not** re-opened here: the frozen gate's
`free` mode dies on branch-name checking in detached audit worktrees before
reaching object equivalence; and the accepted `token.sh` wait loop swallows TERM
and requires `timeout -s KILL` — which is why the morning's deadlock had to be
killed rather than interrupted.

Open upward: a completeness census over the revert before R1 is dispatched, since
the coupling CI found was invisible to every static control and R1's base is this
merged head.

## 2026-08-22T13:20Z – 2026-08-23T08:15Z — pause, release, and R1 finding a hole in product authority

### Paused, and a `PARKED` that was false when filed

The operator paused the milestone; OMNIA PAUSA followed machine-wide. The desk
answered `PARKED` — and it was **not true**. The project desk inspected process
state and found two `until` watcher shells still alive as children of the desk,
one of them **twenty-seven hours old, inherited from before the desk's own
`/clear`** and outliving the conversation that armed it.

Two independent checks had said clean. The desk's `pgrep` pattern was
`until \[` — a literal bracket — while the watchers were written `until grep` and
`until tail`, so **the search could not match what it searched for**. And
`TaskList` returned "No tasks found" while both were live, harness-tracked tasks
with IDs. Neither instrument was careless; both were wrong, and only an outsider's
process-level inspection caught it. The correction was appended to the
acknowledgement rather than edited over it, and the machine was told that any
`PARKED` self-reported on `TaskList` evidence should be treated as unconfirmed.

### Released — Cardano-KERI only, at operator priority

The machine released this project's seats alone. Cold realization stayed barred
(store 5.19 GiB under the bar), the per-leg-class grant stood, and the CI fleet
stayed down deliberately.

### R1 dispatched, and its first candidate audited to failure

R1 — the event-derived MPF key — was dispatched onto the merged S0 head with the
staged brief's stale clauses voided: Opus seats barred by operator order, "grok no
seats" void for Grok, the old cold bar re-ruled. Families: **Codex owning, Grok
implementing, Codex auditing.**

A fresh Codex auditor **failed** the first candidate with three blocking findings,
and the desk verified the two load-bearing ones against source rather than
relaying them.

**F1 is a hole in product authority.** `s0_append.ak` takes `proof_policy` as a
**redeemer field** — the caller chooses the policy that authenticates their own
proof. A permissive policy satisfies the token burn while an unrecomputed `d`
reaches the key derivation and the record.

**That is the sixteenth instance of this milestone's defect class and the first in
the product rather than a harness or a gate.** The burn certifies a true
proposition — *a token was burned* — that is not the one that matters — *a trusted
verifier recomputed this SAID*. Prior instances cost gate revisions. This one
would have inverted the projection law the milestone rests on: a caller-chosen
verifier means the chain originates whatever the caller asserts.

**Ruled an expansion of R1, not a predecessor** — on evidence the audit did not
cite: `checkpoint_observer.ak` in the same tree **already** takes its policy as a
validator parameter, deployment-fixed and beyond caller control. The correct
boundary is not missing architecture awaiting authority; it exists, is deployed,
and `s0_append` deviates from it.

Consequence recorded rather than discovered later: parameterizing that validator
changes its compiled size, so **S0's size row for that member went stale four
hours after S0 merged**. The desk proposed to the project owner that S0's figures
be declared a skeleton baseline with **one** re-baseline after R4, rather than
churn per slice against a still-moving target.

### The floor was breached, and it was not us

While the lane sat halted holding no tokens, `/nix/store` fell **below the
machine's non-negotiable floor** by 0.93 GiB. Our total consumption for the whole
session was 112 MiB and change; the store fell 1.61 GiB after our halt with the
lane idle.

**The desk came close to making it worse.** Ten minutes before that reading it was
preparing to relax its own realizing hold, reasoning that the lane's floor guard
had proven itself and a blanket hold was over-cautious. Had it done so, the lane
would have been realizing below the floor and would have appeared to be the cause.
The hold was right for a reason the desk had partly talked itself out of: **a
guard protects against a breach you cause, not against operating inside one
someone else caused.**

### The demand, and what it changed

On the operator's instruction the desk **fought** rather than waiting, and the
machine upheld every point.

The argument was the machine's own doctrine turned one notch sharper. It had
written that a rule firing on every expected case carries no information and lanes
learn to route around it. The sharper form: **a rule that binds only its
volunteers teaches them that volunteering is a tax.** The lane that implemented
the interlock was the lane that stopped; the consumer that ignored it crossed the
floor.

**The machine owned its own fault unprompted** — it had started three CI runners
fifteen minutes before the breach to unblock another project, while this lane sat
inside its interlock. It also refused to dress up what it could not prove: the
8.35 GiB fall was **never attributed to a live process**, recovery came from
collecting 11,023 dead paths, and *"the consumer is a hole in my instruments, not
a name I can give you."*

Granted: **host-token acquisition is now mandatory** for every agent lane that
realizes — a breach if skipped, not a convention — with the honest limit that a
runner is a systemd service no message reaches, so enforcement there is the
machine stopping them by hand, admitted as weaker. A **standing rule** that the
fleet does not run while a compliant lane is held by a floor breach. Resumption
returned **as a number rather than a permission** — 56,000,000,000 B, self-checked,
no message needed in either direction. `packaged` reclassified to measure-it. Cold
legs granted at `N=1`. CI runners on a named count, never speculative.

### The best behaviour of the milestone came from the implementer

Gate v5 exists because **the commit owner challenged the gate that judges it**.
It proved the frozen wrapper could enforce neither condition the grant depended on
— no resume threshold, so a store at 55.0 GiB would pass the predicate while
violating the standing number; and no live guard, sampling only after the process
exits — and it **refused to spend a granted realization on machinery that could
not honour the grant's terms.**

An implementer declining a permission for that reason is the exact inverse of
every failure this week, all of which came from a green control believed rather
than interrogated.

v5's two new controls are mutation-proven load-bearing — with them RED, without
them PASS — and tested at the boundary: the threshold one byte below, the live
floor landing exactly on it. The threshold check runs **before acquisition**, so a
below-threshold lane never takes the interlock at all. The live guard halts on
`available − declared_ceiling ≤ floor`: it stops when the work still to come
would cross, not merely when the floor already has.

### The desk's own defects this stretch

Recorded because a ledger that records only other people's failures is not
evidence. A `PARKED` that was false when filed. Two instrument false positives
where a search matched its own invocation — one of which was repeated to the
operator as fact before being caught. And **a misattribution the desk repeated
upward**: it credited the lane with a mid-run floor guard, called it beyond spec,
and told the machine owner the lane ran one as part of the case for being the
compliant party. The guard was real in conduct and **absent from the frozen
wrapper** — verified afterwards at grep-count zero. v5 is the first version where
that protection is actually frozen, inherited and falsified.

## 2026-08-23 — R1: a security hole found, a green gate reached, and the ticket re-cut anyway

R1 ran from 06:05 to 11:10 and ended in a re-cut. **The work survived; the ticket
did not.** Both halves of that sentence matter.

### What R1 found, and it justifies the whole apparatus

A fresh audit failed R1's first candidate on three blocking findings. One was a
hole in **product authority**, not in scaffolding:

`s0_append.ak` took `proof_policy` as a **redeemer field** — so the caller chose
the policy that authenticated their own proof. A permissive attacker policy would
satisfy the token burn while an unrecomputed `d` reached the key derivation and
the record. **A caller-chosen verifier means the chain originates whatever the
caller asserts**, which is the precise inversion of the law this milestone rests
on.

It was ruled an **expansion of R1 rather than a predecessor ticket**, on evidence
the audit had not cited: `checkpoint_observer.ak` in the same tree already takes
its policy as a *validator parameter*, deployment-fixed and beyond caller control.
The correct boundary was not missing architecture awaiting authority — it existed,
was deployed, and one validator had departed from it.

### The apparatus was rebuilt five times and verified by breaking it each time

v2 through v6, each frozen, each layered over an unchanged predecessor, each
independently reproduced at the desk **by re-introducing the defect it claimed to
catch**:

- v3 added a leak tolerance after the desk proved the zero-tolerance detector
  fired on ambient host noise — two of four *idle* sampling intervals tripped it.
- v4 tied the cleanup control to the production path after the desk re-introduced
  the exact S0 token-leak defect and watched v3 report **13/13 green**.
- v5 turned the machine's resume threshold and the floor guard into gate controls
  with their own mutants, after the **commit owner challenged the gate that judges
  it** and refused to spend a granted realization on machinery that could not
  honour the grant's terms.
- v6 added the post-repair dressing world after the full gate found the real
  protocol defect below.

Along the way the lane **falsified a desk oracle**. The desk had accepted a
formatter's rewrite on a citation from Aiken's glossary; the lane replied *"we do
not infer language equivalence from the formatter having produced it"* and
replaced it with compiled-code identity. Result: **the blueprint hash was
byte-identical across all 46 validators.** The conclusion held; the desk's basis
for it did not, and the standing rule is now **where the artifact can settle it,
the artifact settles it.**

### The protocol defect the full gate found

`splice_dummies` blanked **both** the `i` and `d` spans unconditionally before
recomputing the SAID. That is correct only for self-addressing inception. For an
ordinary rotation, `i` is the established controller prefix — an *input* to the
digest — so blanking it destroys the preimage and the validator **rejects every
valid rotation.**

A-019 had already ruled the semantics (*"it is not `i` except where KERI itself
requires equality for a self-addressing inception"*), so the repair implemented a
decision already in force rather than extending it. The fix branched the dressing
on the CESR ilk. The full gate then went **green end to end** — mutations,
formatting, the Aiken suite, both measurements, the packaged build, the dev shell
and the local CI run.

### The first complete per-leg cost profile this host has ever had

```
aiken-fmt 0 B · mutations 12 KiB · append-remeasure 0.94 MiB · aiken-check 1.04 MiB
append-measure 1.34 MiB · packaged 1.59 GiB · devshell 3.99 GiB · local-ci 5.68 GiB
whole gate ≈ 11.3 GiB, peak single leg 5.68 GiB
```

Reported upward, since the machine owner stated plainly that these are the only
real per-build figures it has.

### Why it was re-cut anyway

**Two consecutive auditors terminated contract-blocked on their own instruments,
before delivering any verdict on the code.**

The first asserted that all fourteen changed paths must be mode `100644`; one is a
legitimately executable script whose mode had not changed. The second — after a
corrected, desk-verified, per-path mode rule proven in three directions — died
when its `EXIT` trap dereferenced function-local state after return.

The desk's own A-019 had said one replacement, and that a second instrument
failure is a pattern rather than an accident, sending the ticket to re-cut without
further argument. **The second failure came *after* the semantic controls rather
than before, and the desk considered whether that distinction saved the ticket. It
does not.** An instrument that dies in teardown has produced no verdict, and
reading an exception into a rule written four hours earlier — because of where it
lands — is the move this desk had refused from everyone else all week.

### The claim the desk withdrew

Before dying, the replacement auditor formed an **unjudged hypothesis**: the rival
test stages and invokes the validator only for event one, calls a lower append
helper directly for event two, omits independent retrieval of both MPF entries,
and varies only `d` — leaving the dressed preimage non-rival.

If it holds, the test passes **while event two never crosses the validator**: the
original F2 finding, alive behind a green tick.

**The desk therefore withdrew its own claim that F2 was verified.** It had written
that F2 would become evidence when the suite executed. It should have added that
**a suite executing is not the same as a suite exercising what it claims.** The
four causal properties are carried into the new mandate as requirements.

### The lifecycle defect, at four appearances

An `EXIT` trap dereferencing function-local state after return has now: orphaned
both build tokens and crossed this host's floor; forced gate v3 to v4; appeared in
gate v6's authoring (caught and disclosed by the lane itself); and killed the
replacement audit. **The new mandate requires every frozen instrument to falsify
its cleanup and exit path as part of preflight, before its semantic controls are
trusted.**

### What carried forward

Re-cut placed as **forward-only continuation** from `8aa1de39` — the product work
is proven and re-deriving it would be waste — **with the new audit scoped to the
full delta from `84e3b715`, so nothing rides on unjudged work.** All sixteen rows,
the verified mode rule, and the gate stack carry as tools. Budget two builds,
explicitly not a reset. PR #305 retained as draft evidence, unmodified; the CI
runner request withdrawn before the machine spent anything on an unshippable
candidate.
