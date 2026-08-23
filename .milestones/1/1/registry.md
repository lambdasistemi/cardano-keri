# Contract registry — cardano-keri M1
Founding sweep 2026-07-29. Seeded from epic/issue text; entries marked TODO are
provisional until independently audited (a registry line is a claim, not evidence).

contract:   kli/keripy artifact formats (KEL events, receipts, OOBIs) consumed by ckeri
parties:    WebOfTrust keripy `kli` (produces), cardano-keri `ckeri` (consumes)
invariant:  ckeri parses/verifies real kli-produced artifacts; we never wrap or fork kli UX
enforced:   TODO-AUDIT — presumed story-level transcript tests; verify some CI check
            exercises real kli output (positive control), else downgrade to NONE

contract:   preprod witness stack + published OOBI list
parties:    witness/infra host (produces), every controller and watcher (consumes)
invariant:  the running stack matches a declared IaC description; OOBI list is current
enforced:   ENFORCED 2026-07-30 — declared as NixOS-managed IaC (infrastructure#137
            merged; bare-host convergence proven pre/post-fix incl. warm reboot);
            residual: dev-host services still imperative (infra#138, machine-owner)

contract:   V1 script deployment on preprod (script hashes, addresses)
parties:    publisher via `ckeri deploy` (produces), all producers + watchers (pin/consume)
invariant:  deployed scripts match the repo's verifiable release manifest
enforced:   `ckeri manifest verify` (born in #158) — TODO-AUDIT whether anything runs it
            automatically (CI/gate) or only by hand; if by-hand only, treat as NONE

contract:   preprod cardano-node N2C socket / protocol version
parties:    cardano-node deployment (produces), ckeri + future indexer follower (consume)
invariant:  ckeri is built against the node's live protocol version (pv11 rework in t115
            is the historical drift instance)
enforced:   NONE explicit — drift surfaces as runtime failure; candidate: N2C smoke in gate

contract:   hosted read API surface (#176 produces, #177 consumes) — SPLIT RULED 2026-08-01
parties:    #176 is PRODUCER-ONLY (HTTP endpoint over the merged ckeri-follower main);
            #177 owns the ckeri CLIENT side. Epic #171 arbitrated this at 09:19:53Z
            on its child's Q-001-ckeri-status-ownership, 73 seconds after it was filed.
invariant:  the wire surface (checkpoint by AID, board by witness key, watchability
            grade, as_of_slot) is agreed once and both sides bind to the same schema;
            the producer never grows a client and the consumer never re-specifies the
            wire
enforced:   NO LONGER NONE — the ruling installs the check on the producer side: a
            schema golden with a proven RED, plus curl-level acceptance, both landing
            in #176. That is the first enforcing mechanism this contract has ever had;
            it was the epic's only NONE entry. Desk verifies at #176 acceptance that
            the golden can actually fail and that #177's client is bound to the same
            schema object, not a hand-copy of it — a producer and consumer each green
            against their own copy is the drift this registry exists to prevent.

contract:   indexer runnable artifact and hosted query API (#188/#176/#177)
parties:    #188 standalone follower/query shell, #176 hosted endpoint, #177
            production `ckeri` backend selection
invariant:  one running `IndexerHandle` owns state; shell and HTTP are views over
            it, never derived caches; #177 merges the epic fork into production
            `ckeri` and retires the standalone artifact without losing verbs
enforced:   PARTIAL — #188 vertical demo and no-cache checks establish the local
            artifact; hosted API surface remains NONE until #176 freezes it

contract:   indexer interest-set patterns (now THREE: checkpoint, board, funding-address)
parties:    e171 library (produces reads), e156 acting stories #162 relayer / #163-164
            hunter (consume ALL THREE — they act, so they fund txs from indexed state,
            never GetUTxOByAddress over N2C; operator catch 2026-07-29 09:18Z)
invariant:  no consumer of the library issues address-scan N2C queries; funding
            addresses are declared config (opt-env-conf, plural)
enforced:   NONE mechanical yet — desk folds the rule into every #162/#163/#164 dispatch
            brief; candidate check when #175 lands (grep gate for query utxo --address)

contract:   board address/policy (on-chain OOBI endpoint board)
parties:    e156 story #165 (landed 2026-07-29), e171 indexer follower
            (consumes as one of its two filter patterns)
invariant:  the follower binds to what #165 actually deploys — never invented. Ratified
            semantics (A-002, 2026-07-29): current = exactly the unspent set (no TTL, no
            clock inputs — follower filter stays deterministic and replay-equal);
            lifecycle auth = Cardano owner envelope (payment vkey hash in datum +
            extra_signatories on spend), KERI reply sigs are content-auth only. RELEASE
            payload = policy-id + address + FROZEN datum schema incl. owner field
            (followers parse past it, never select by it)
enforced:   values SUPERSEDED once already (blueprint fix, 16 min after first release —
            provenance lesson live). CURRENT 10:10Z: policy 54494f8a…210c,
            addr_test1wp2yjnu2…d4hm4, schema@bb26876c (re-pin after branch re-sign; content identical); relayed NOTE-005 + NOTE-007.
            Mechanical fixture-from-deployment check when #165 lands is now MANDATORY,
            not candidate — hand-copied values went stale within the hour

contract:   indexer follower built ON cardano-node-clients (cross-repo library reuse)
parties:    lambdasistemi/cardano-node-clients (produces chain-sync/indexer services),
            cardano-keri e171 indexer (consumes); cardano-mpfs-offchain + amaru-treasury-tx (reference consumers)
invariant:  no duplicated follower logic in cardano-keri — missing capabilities are
            extended upstream in node-clients, then consumed; MPFS E2E runs before any
            cardano-node-clients merge (standing org rule)
enforced:   NONE mechanical — held by desk review of e171 story bodies (each must name
            the upstream modules consumed); NOTE-001 in e171 inbox is the directive

contract:   indexer store technology (rocksdb-kv-transactions, was "sqlite" in epic body)
parties:    cardano-node-clients block-indexer stack (dictates via closed Cols GADT +
            monomorphic csHandlers), e171 stories #175/#176/#177 (consume)
invariant:  reusing the upstream follower forces the upstream store; no parallel store
            technology without abandoning reuse (measured: mpfs paid 321 lines for that)
enforced:   the upstream type system itself (closed GADT) — drift impossible while reuse
            holds; arbitrated change A-001, 2026-07-29

contract:   preprod cardano-node socket
parties:    container cardano-preprod on the dev host (produces; node 11.0.1, up 2mo,
            N2C at /code/cardano-preprod/ipc/node.socket — VERIFIED LIVE 2026-07-29),
            e171 #176 daemon + ckeri write path + #166 stranger run (consume)
invariant:  a documented, reachable socket path exists where the docs point
enforced:   PARTIAL — socket named and verified, but (a) docs still name stale
            /node/preprod/... (defect, fix rides #176/#166) and (b) the container is
            imperative docker state — desk recommends #168 scope covers cardano-preprod
            and cardano-mainnet containers alongside the witness stack. #176 hold LIFTED

contract:   gate greenness vs live behavior (repo cardano-keri)
parties:    justfile ci targets (produce the green), every story with a live criterion
            (consumes it as proof)
invariant:  GATE-PASS must not be read as live-suite evidence; tickets with live criteria
            wire `just ci-live` into their gate.sh and carry raw-output evidence captured
            after the last code change
enforced:   ci-live target lands in #175's PR (A-005); desk review checks the wiring at
            acceptance. Standing audit question for every criterion in M1: "if the
            mechanism were broken, would this signal still be green?" (4 instances on
            2026-07-29 alone)

## Standing audit questions (cross-epic, applied to every criterion and every desk instrument)
1. Green-signal class: "if the mechanism were broken, would this signal still be green?"
   (7 instances on 2026-07-29, two of them the desk's own: late-armed monitor, unverified
   archive.)
2. Provenance class (e171 epic ledger, 2026-07-29): an artifact asserting its own
   provenance (fixture timestamps, as_of_slot, acceptance transcripts, txids) can be
   false while all surrounding data is true — testing the data never detects it; only
   independent re-derivation of the capture does. Applies to e156 transcript acceptances
   identically. Second concrete recurrence triggers a commissioned consolidation ticket.

contract:   tx building via cardano-tx-tools (cross-repo reuse, e171 story #181)
parties:    lambdasistemi/cardano-tx-tools (produces Build/Balance/Inputs/Witnesses),
            cardano-keri acting roles (consume; replaces cardano-cli incl. its HIDDEN
            internal UTxO+pparams queries)
invariant:  no O(UTxO-set) node queries anywhere in the tx path — visible or internal
enforced:   NONE yet — #181 acceptance is the enforcement candidate (operator-filed with
            the hidden-query rationale recorded)

contract:   mainline signature integrity vs merge method (cardano-keri, systemic)
parties:    GitHub merge machinery (rebase-merge recreates commits UNSIGNED on main),
            every lane's signed-branch discipline (destroyed at merge time)
invariant:  the standing signed-commits rule applied to main history — currently FALSE
            for every rebase-merged PR (12/12 recent main commits unsigned, verified
            2026-07-29 despite fully-signed source branches)
enforced:   PARTIAL — operator chose merge-commit; policy landed in llm-settings#70 and
            enforcement code in mcp-merge-guard#36. Current host agent processes still
            run mcp-merge-guard 0.4.0, so the 0.5.0 refusal of signature-stripping
            rebase is not yet live here. Desk authorizations explicitly require merge
            method until every server is refreshed.

## Standing audit question 3 (operator, 2026-07-29 — ticket-independent)
Reuse honesty: every ticket names the upstream surface it consumes (module headers +
story body) and closes every capability gap with evidence-it-is-unnecessary or a linked
upstream PR consumed back. A silent local fork of upstream capability is an acceptance
failure, whatever the ticket. (Origin: #175's reuse criteria, generalized by operator
ruling; joins green-signal and provenance as the desk's acceptance layers.)

contract:   checkpoint-grade tx assembly (upstreaming, tickets tx-tools#135 / keri#183)
parties:    cardano-tx-tools tx-build (will produce the abstraction),
            cardano-keri CLI builders (will instantiate; today: 4,919 bespoke lines)
invariant:  generic assembly lives upstream once; downstream instantiates, never
            re-implements (reuse-honesty standing question 3 applied at scale)
enforced:   NONE until #183 lands — its acceptance (named imports, deleted-line count,
            evidence for any residue) is the enforcement

contract:   M1 release-quality verdict vs the separately authorized release operation
parties:    release-hardening epic #186 (produces READY/NOT READY evidence),
            future release operator/workflow (consumes only after explicit authorization)
invariant:  the verdict is derived from the exact settled candidate, the full owned
            repository is accounted for, every automated check is proven reachable and
            able to fail, and READY never performs or implies versioning, release
            automation, tagging, packaging, publication, deployment, or distribution
enforced:   PLANNED — #184 produces the finding/invariant ledger and conflict-safe child
            map; milestone desk accepts the map; finding-derived children install the
            durable `just release-quality` equivalent; #185 independently re-runs from
            a clean checkout and may report READY only with no critical waiver

contract:   release-hardening audit scope and generated/vendor boundary
parties:    every owned cardano-keri source/tooling/docs surface (audited by #184),
            generated outputs and vendored inputs (provenance/drift only)
invariant:  owned production code, tests, scripts, Cabal, Nix, CI, public APIs and
            architecture/user docs are fully audited; generated/vendor material is not
            hand-refactored or counted in owned-code coverage; known debt #179/#180 is
            allocated without duplication or silent closure
enforced:   PLANNED — GitHub #184 acceptance plus parent #186 quality constitution;
            no remediation ticket is filed until #184 evidence determines coherent
            conflict/contract ownership fences

contract:   the milestone artifact and its release line (M1)
parties:    #196 release pipeline (produces the line), epic #171 (merges its #188
            follower fork in at #177), epic #156 (extends production `ckeri`
            directly), #166 stranger run and every external user (consume)
invariant:  M1 is represented in the repository's published outputs, not only in
            merged code — a person who has cloned nothing can obtain and run the
            artifact; epic forks merge UP into the milestone line rather than
            sideways into production; temporary lines are visibly marked
            pre-release so nobody mistakes a fork for the product
enforced:   NONE — and today the strongest possible NONE: zero releases, zero
            tags, no release automation (verified 2026-07-31, positive control
            against a releasing repo). #196 is the commissioned check; until it
            lands, the outcome test is satisfiable only by a source build, which
            is a contributor-run wearing a user-run's name

contract:   ckeri query service as NixOS IaC on the shared dev host (#176 S3)
parties:    cardano-keri #176 (produces nixos/development/ckeri-query.nix in
            paolino/infrastructure, branch feat/cardano-keri-176-query-endpoint
            off d968cd4), the dev host (consumes/runs it), #166 stranger run
            (depends on the service actually being reachable)
invariant:  the module does not merely exist, it brings the service up and the
            endpoint answers; and a live apply to this host is a MACHINE-level
            act, not a milestone-level one — it is cleared by the machine owner
            through the desk, never by a ticket or epic GREEN alone
enforced:   PARTIAL — #176's S3 immutable gate (sha256 4ebebc24…, proved RED for
            the missing module at infra base d968cd4) is the mechanism, but a
            file-presence assertion would satisfy it while the service stays
            down. Desk requires the gate to assert the CONTENT contract and will
            check what it asserts at GREEN. Deployment clearance is additionally
            gated on the machine owner while OMNIA PAUSA remains in force for
            every other session on this host.

contract:   M1 preprod deployment manifest pinned to its producer commit
parties:    cardano-keri `deploy/preprod/m1-manifest.json` (produced at commit
            50a582064), the deployed `ckeri-query-preprod` service (mounts it
            read-only), #176's CI (fetches it to verify the deploy transcript)
invariant:  the pinned producer commit is reachable from a ref, so the pin cannot
            evaporate. An unadvertised commit is not guaranteed to survive on the
            remote; if collected, the contract breaks with NO code change and NO
            signal, and the enforcing check keeps passing until the day a fetch
            fails
enforced:   ENFORCED 2026-08-02 — annotated tag `deploy/preprod/m1-manifest-source`
            on 50a582064ddf, pushed and verified by the desk (commit resolvable via
            the API, tag present alongside v0.1.0/v0.1.1). Chosen deliberately over
            a deepened clone / fetch-by-sha, which would have preserved the
            fragility behind working CI. The epic also picked a name outside the
            `v*` pattern so the tag cannot trigger the release publish workflow —
            a second-order trap the desk had not raised.

## CORRECTION 2026-08-02 — the CI-runner contention entry above was wrong on mechanism

Recorded as a visible correction rather than an edit, because a tidy false story
is worse than a messy true one.

**What this ledger said:** ten `github-runner` units execute from the same
`/nix/store` on `/dev/md127` as every lane, so their `No space left on device`
failures and this host's 93%->99% root emergency were one event on a shared store.
Sourced from the machine owner, who had tested it; relayed by the desk to both
lanes as established fact and acted on.

**What is actually true**, measured by the machine owner 2026-08-02T19:50Z: the
runners' `RUNNER_ROOT` on `/` holds **4 KiB**. Their live working directories are
under **`/run` — a 32 GiB tmpfs, in RAM**. During the failures `/run` was **100%
full, 24 MiB free**, holding 21 GiB of checkouts from ten runners unrestarted for
seven days, while root still had 45 GiB free.

So it was **tmpfs exhaustion, not store exhaustion**, and the **runner restart**
cleared it — not the 29 GiB store collection.

**What survives:** the store is genuinely shared, and lanes do compete on `/`.
**What does not:** the causal claim that the shared store caused the CI failures,
and any budgeting that treats `/` as the binding constraint for CI.

**The resource to watch is `/run`** — 32 GiB of RAM that refills from empty to
5.8 GiB in about an hour under load, because nothing cleans a runner working
directory between jobs. It is tighter than the disk and it was invisible to
everyone until it filled.

**The lesson, which is the reusable part:** two parties confirmed a plausible
mechanism to each other and both were wrong. A hypothesis tested by the only
party able to test it is still a hypothesis until the *specific* claim is
measured — "same host" was verified, "same store caused it" was assumed on top of
it and inherited the first claim's credibility.

## Sweep 2026-08-03 — entries from the no-asymmetry ruling, and two state updates

contract:   advance authorization layer (validator ↔ every advancing party)
parties:    onchain V1 validator advance path (enforces), relayer #162, hunters
            #163/#164, stranger run #166 (consume — they all advance unattended)
invariant:  controller authorization verifies against the public KEL's event
            bytes — never a Cardano-domain preimage binding a TxOutRef; a
            competing spend invalidates the transaction, never the
            authorization; the same ordinary permissionless Advance is
            admissible from every non-terminal role (spec 114 advance-totality)
enforced:   NONE at discovery — commissioned as #219 (t219 lane, desk-parented).
            Enforcement = new aiken properties with both halves proven RED
            (public-KEL-only advance fails on current code; replay fails on a
            weakened variant). DISCOVERY RECORD: this seam had no registry
            entry; #114/#115/#116 closed a half-finished migration with no
            successor and it surfaced from a consumer story (#162) a week
            later. The registry was seeded from epic/issue text — cross-layer
            seams predating the milestone were invisible to it.

contract:   rotation hearing (witness boards ↔ unattended watchers)
parties:    witness boards + OOBI endpoints (publish), relayer #162 and hunters
            #163/#164 (consume continuously), `ckeri verify` (user surface)
invariant:  an unattended process can resolve witnesses from the board, fetch a
            KEL over HTTP, verify it, and notice a rotation — no human running
            `kli export` and handing files around
enforced:   NONE at discovery (zero OOBI/KEL fetch in offchain/; only outbound
            HTTP was the Koios client) — commissioned as #220 under e156.

contract:   preprod deployment cutover (deployed validator + manifest version)
parties:    t219 (will publish the V1′ redeploy + new manifest), ckeri-follower,
            ckeri-query-preprod, producer witness boards, #166 transcript (all
            pin the deployment)
invariant:  the deployed validator/manifest version changes only by
            desk-arbitrated cutover with an ordered re-pin plan for every
            consumer; no lane redeploys on its own GREEN
enforced:   desk gate written into t219's brief (phase boundary); mechanical
            form decided at cutover time. Extends the existing manifest-pin
            entry (deploy/preprod/m1-manifest-source) which continues to hold
            for the CURRENT deployment.

contract:   release planner liveness (planner ↔ the release line)
parties:    .github/workflows/release-plan.yml + scripts/release/plan
            (produce release PRs), every future release (consumes)
invariant:  every release-worthy merge yields a fresh release PR; a planner run
            that does nothing must fail loudly, never report SUCCESS
enforced:   NONE — WAIVED post-M1 by desk ruling 2026-08-03. Finding #218
            (evidence: the #204-merge planner run skipped on stale #213 and
            reported SUCCESS). Workaround documented: close the stale release
            PR. Waiver recorded here so the NONE is never implicit; joins #205
            (smoke bypasses AppImage nix-store remapping) as deliberate
            instrument debt on an otherwise-proven pipeline.

UPDATE — "the milestone artifact and its release line (M1)": enforced status
was "strongest possible NONE" (zero releases). Now: **ENFORCED in substance**
— v0.1.0/v0.1.1/v0.2.0 published; all three formats proven through real
install mechanisms in one machine-captured transcript attached to v0.2.0;
planner + App-token automation proven by mechanism (#217, 20 checks). Residual
debt is the two waived instrument gaps above; the manual transcript remains
the strongest evidence class until they close.

UPDATE — "tx building via cardano-tx-tools (#181)": enforcement candidate is
now IN FLIGHT — t181 lane live under e171 (keri:4, base c9c1f96), the
hidden-internal-query trap centred in its brief.

## Standing audit question 4 (desk, 2026-08-03 — completeness class)
A contract spanning repos or layers with NO registry entry is invisible until
a consumer trips it — the advance-asymmetry is the canonical instance. At
every operator scope change and at every epic intake: sweep ratified specs for
half-finished migrations (a spec whose scope names N surfaces, with successors
closed after fewer than N) and require every cross-layer assumption a story
consumes to have a registry line, even as NONE. An assumption with no line is
not "obvious"; it is unenforced.

contract:   compiled UPLC proof target (M1 onchain ↔ M8 blaster)
parties:    M1 onchain source + pinned Aiken toolchain (produce the blueprint
            UPLC), milestone 8 Blaster bridge #189 / theorem portfolio #190
            (consume it as the Lean verification target; operator is investing
            in these theorems)
invariant:  M1 never moves the proof target silently — every validator-
            semantics change is announced to the ms8 desk at ACCEPTANCE time
            (commit named) and again at deployment cutover (applied-script
            hashes named); #219 is the announced in-flight instance and the
            LAST planned semantic onchain change in M1; post-#219 the source
            freezes for #166/#186 and hardening remediation is fenced away
            from validator semantics
enforced:   desk duty at every onchain-touching merge authorization (this
            desk's STATUS + a durable note to /tmp/ms-keri-8/inbox/); ms8's
            own side already enforces changed-program invalidation and
            baseline-triggered reruns (their registry). First note delivered
            2026-08-03 (NOTE-001-m1-t219-moves-the-proof-target).

UPDATE 2026-08-03T10:40Z — "hosted read API surface": AMENDED by #224 (merged
a51192d5). The wire surface now includes GET /board catalog enumeration
(BoardListResponse/BoardListEntry, as_of_slot, tip_lag_slots), schema at
commit 0041394. Forwarded upward by e171 explicitly "before #162 binds" —
#162's and #220's board-discovery consumers bind to the AMENDED surface, never
the pre-restack 5ccb6f1 draft. Enforcement unchanged (producer-side schema
golden with proven RED). LIVE-DEPLOYMENT LAG on record: deployed
ckeri-query-preprod predates the merge, /board answers 404 until the service
re-pins — redeploy is a machine-owner-cleared act through the desk (S3/IaC
contract); e171 owes the ask when ready.

UPDATE 2026-08-03T13:35Z — "gate greenness vs live behavior": LARGEST INSTANCE
FOUND. The E2E (withDevnet) blueprint is a fixed-output derivation
(offchain/flake.nix) whose outputHash was set once at 8edfa8b and never
bumped — every E2E green since substituted a frozen ancient compiled script
from cache, certifying Haskell-vs-frozen-script agreement rather than live
validator behavior. Found by t219 (the first honestly-rejected change),
desk-confirmed (single -S commit; zero aiken-build strings in the failing
job's log). Enforcement commissioned INTO t219's PR #222 under extended
fence: input-addressed derivation or pinned-toolchain drift check (bare hash
bump refused — it re-arms the trap); all 22 blueprint reference sites
enumerated; production deploy path independence PROVEN not assumed. Standing
audit question 1 vindicated verbatim.

contract:   release gate — tested releases only (operator ruling 2026-08-03)
parties:    the release pipeline / planner PRs (produce releases), every
            release consumer incl. #166's stranger (consume)
invariant:  no release is cut from a head whose E2E (withDevnet) ran against
            a substituted stale blueprint; the head must carry the #235
            structural fix and its E2E must demonstrably have BUILT the
            blueprint from that head's source (aiken-build output in the job
            log, or the drift check's pass) — the green badge alone is never
            the evidence
enforced:   desk gate on every release-PR merge authorization (NOTE-026 binds
            the executing lane) until the #235 fix makes staleness
            structurally impossible, after which the invariant holds by
            construction and this entry records why

CORRECTION 2026-08-03T14:35Z — recorded visibly, not edited away: the desk's
A-005 ratified "the production deploy path never consumed this FOD." FALSE at
the shipping layer, refuted by t219's Opus navigator with direct build
evidence: offchain/flake.nix's ckeriRunner bakes CKERI_BLUEPRINT defaulting
to the stale FOD store path (sha byte-identical to the frozen hash), and
packages.ckeri / apps.ckeri / the AppImage-DEB-RPM release bundles ALL
resolve through it. The documented `manifest verify` runs with no explicit
blueprint, silently uses the stale default, and prints "rebuilt from source:
OK" — the third-party release-verification instrument can lie. What remains
true: the LIVE preprod deployment demonstrably runs post-freeze validators
(the operator's 0.2.0 run used permissionless-registration semantics that
postdate the frozen blueprint). Release-gate entry gains a dimension: the
tested release must demonstrate the shipped wrapper's baked default resolves
to the head's fresh-built blueprint (added to t219's standalone-PR
acceptance). Instrument lesson: the desk inferred deploy-path independence
from live behavior; the navigator BUILT the artifact and looked.

CORRECTION 2026-08-03T15:0xZ — two corrections to the FOD entries above,
recorded visibly: (1) "set once at 8edfa8b, never bumped" is WRONG — the
navigator showed `git log -S` is blind to value-only edits; `git log -p`
shows ~nine manual bumps, last at a09058f. The staleness window is "since
a09058f" and the failure mode is a DECAYED MANUAL DISCIPLINE, which is worse
and more instructive than a never-touched hash. The desk's "independent
re-derivation" used the same blind -S and inherited the blindness —
independent commands, not just independent eyes. (2) The board-policy
divergence was TOOLCHAIN, not code: same source reproduces the live bytecode
exactly under aiken 1.1.21 (deploy-era) and diverges under 1.1.23 (validation
toolchain). Ruled: blueprint derivation pins 1.1.23 (test what ships);
deployed identities are literals-with-provenance until the cutover, which now
provably moves EVERY M1 script identity by compiler alone. Shipped-releases
erratum ruled (A-011): drafted by e156, posted only on operator approval;
0.4.0 is the remediation release.

contract:   chain-access provider rule (operator architecture ruling 2026-08-03)
parties:    every ckeri verb that touches the chain (consumes), the local tier
            (node socket + indexer/hosted) and the third-party tier
            (Koios/Blockfrost) as interchangeable providers
invariant:  "OR local node OR blockfrost/koios" — one provider choice covers
            the ENTIRE chain-access surface (lookups, protocol parameters,
            submission, settlement); no verb may require both tiers at once;
            third-party mode is fully node-free including submission
enforced:   NONE today (writes are an AND: Koios lookups + node
            params/submit) — commissioned as the e156 write-path story
            (NOTE-030/031); #177's backend record is the seam it extends

AMENDMENT 2026-08-03T15:2xZ to "chain-access provider rule": operator
re-ruled minutes after stating the OR-rule — **"for now only local node"**
and **"this blocks M1"**. M1 scope: the write path moves onto the LOCAL TIER
ONLY (node + indexer/hosted + follower settlement tracking); Koios is
REMOVED, not optionalized; the third-party tier (Koios/Blockfrost incl.
node-free submission) remains the documented future seam with ZERO M1
implementation. The commissioned e156 story is M1, critical-path, sequenced
post-#181 / pre-#162, and #162's wake gains it as a fourth predecessor.

UPDATE 2026-08-03T18:45Z — EIGHTH SHAPE added to the gate-greenness class,
found by the machine owner inside #243's Build Gate: **a red that does not
name its cause** — `set -euo pipefail` + a bare `test` fails with zero
diagnostic output anywhere (nix log, -L, CI). Mirror image of the seven
silent greens; both defeat the reader. Standing remedy wherever it appears:
print both sides of every comparison before exiting. Bonus finding in the
same arc: #243's consumer enumeration missed a CROSS-MILESTONE consumer
(ms8's blaster-artifact baseline assertion consuming ${blueprint}) — ruled:
ms8's frozen-baseline pin is correct-by-design, gets an explicit pinned
input decoupled from the live blueprint; ms8 desk notified per the
proof-target contract. Enumeration lesson: consumer sweeps must cross
milestone boundaries when the surface is shared.

CLOSED WITH EVIDENCE 2026-08-04 — the July-29 board "blueprint fix" incident
retro-diagnosed as a TOOLCHAIN-VERSION event: release-1's recorded policy
(398a358ad6729f877809b6bd573b680c0e247be00f380a1f93279d4d, recovered by e171
from the a09058f record) equals BYTE-EXACTLY the policy t219's navigator
derived from current source under aiken 1.1.23; current source under 1.1.21
derives the deployed release-2 policy (54494f8a…), and onchain/ is unchanged
on main since deploy day. Three independent derivations, one conclusion: the
16-minute supersession was compiler-line drift, undiagnosed at the time. The
provenance lesson upgrades: record the TOOLCHAIN alongside every published
artifact identity (the cutover will; the manifest-verify wording becomes
toolchain-explicit per A-011).

AMENDMENT 2026-08-04 — "release gate — tested releases only": fix landed as
INPUT-ADDRESSED derivation (#243 merged 7d90c9a2a; #235 closed), so the gate
evidence amends to any-of: (a) blueprint derivation verified input-addressed
in the merged source — staleness impossible by construction, cache
substitution honest; (b) real aiken-build output in the head's CI; (c) drift-
check pass. The rebuild-on-change demonstration is banked once: #243's CI run
30888480032. Q-014's refusal to quietly reinterpret the gate is the model:
the letter bends only through the desk, on the record.

AMENDMENT 2026-08-05 — "compiled UPLC proof target": (1) the target gains the
SEMANTICS-VARIANT dimension (M8 moved to PlutusV3 post-Conway variantE; all
prior M8 evidence was variantC via a silently-selecting upstream helper —
relabelled not deleted; the announce duty now covers commit + toolchain +
variant). (2) NEW M1-CLOSE GATE (operator via M8 desk): the M8 verification
"is blocking M1, as soon as it is ready" — publication decision taken by M1:
option (b), an independently-runnable hash-bound evidence bundle attached to
the ckeri release line; M1 close gates on its existence. (3) M1 re-committed:
one-line pointer to the M8 inbox at every onchain-touching merge acceptance.

FINDING 2026-08-05 (operator-surfaced) — endpoint-board OOBI registration has
NO nonce; same "anti-replay at the wrong layer" class as #219. Verified in
onchain/validators/endpoint_board.ak: datum_is_authentic signs endpoint_record
ONLY — the signed preimage does NOT bind owner_key_hash and carries no
sequence/TxOutRef/nonce. Consequences (real): (1) CUSTODY SQUATTING — anyone
observing a witness's valid (endpoint_record, signature) can Post a fresh entry
with THEIR own owner_key_hash and seize lifecycle custody (the witness cannot
manage its own listing); (2) STALE-ENDPOINT RESURRECTION — a superseded
endpoint's signature stays valid forever, re-postable, no on-chain revocation.
BOUND: validate_update re-runs datum_is_authentic (line 117), so a squatter
CANNOT forge the endpoint URL — griefing/squatting/resurrection, not forgery.
Board contract is #165 (landed). Fix: bind the preimage to owner_key_hash + a
monotonic sequence or the witness KEL event digest. In scope for the M8
compiled-UPLC verification.
STATUS 2026-08-05 (supersedes the "post-M1, not filed" line this block used to
carry): FILED as #253 and ruled an M1 BLOCKER by the operator. Onchain board
hardening, sequenced with the #219 family and the cutover, gates #162+#166,
decoupled from #220 (post-M1). Placed 14:14Z as a STORY OF EPIC #171 on a
demonstrated consumer stake, with a two-part scope split (below).

contract:   endpoint-board registration binding (#253) consumed by the follower/query surface
parties:    onchain `endpoint_board.ak` validator (produces the binding rule — DESK-PLACED,
            not started from any epic lane), e171 follower + query API (#175/#176/#177) consume
invariant:  the signed preimage binds owner_key_hash + a monotonic sequence (or witness KEL
            event digest), AND a board entry failing that binding never surfaces through the
            query endpoint or any `--backend` tier
enforced:   NONE — placement recorded 2026-08-05; the consumer half is e171's obligation and
            attaches to whichever of #175/#176/#177 is open when the binding lands. Until then
            this is a scheduled incident: an indexer that cannot tell a squatted endpoint from
            a genuine one indexes forgeries faithfully. Commission the check WITH the binding.

contract:   checkpoint-validator version migration (#254) across every hash-pinning consumer
parties:    onchain checkpoint validator (produces new hashes at the cutover — DESK-PLACED),
            consumers: the follower/indexer, ckeri CLI pins, MPFS token state, the M8
            compiled-UPLC proof target, and the live preprod board
invariant:  existing preprod checkpoints and the live board are CARRIED ACROSS the new
            validator hashes at the cutover, not orphaned; no consumer goes blind across the
            migration in either direction (pre-cutover history stays readable, post-cutover
            events are seen)
enforced:   NONE — and this one has no mechanism at all yet, which is the finding: MPFS is
            stuck-at-v0 with no migration path. The CUTOVER IS THE FIRST MIGRATION EVENT and
            #219 + #253 are the pending validator changes that make it live, so the cutover is
            no longer "redeploy and re-pin" — it is a data-carrying migration. e171 ran the test 2026-08-05T14:37Z and DEMONSTRATED the obligation against code,
            not argument: `mkChainSyncConfig` pins `csInterestSet` once at startup off a
            SINGULAR `checkpointAddress manifest`, with no multi-address/previous-address/
            version awareness in Follower.hs, Config.hs, Board.hs or Reads.hs. At the cutover
            the interest set is wrong on one side whichever way it is pinned, and the failure
            is SILENT — an empty interest match is indistinguishable from a quiet chain.
            PLACED as story 5 of epic #171 (consumer obligation: cross-migration recognition
            plus a proof that FAILS when the indexer is blind on either side of a simulated
            migration). The migration mechanism itself remains desk-placed and unstarted.

contract:   registration certificate deposit ↔ live protocol parameters
parties:    ckeri registration path (produces stake-credential/lifecycle certificates),
            the Cardano ledger on preprod and mainnet (accepts or rejects them)
invariant:  a lifecycle/stake-credential registration carries the deposit the LIVE protocol
            parameters require (production code is correct today: SJust (pparams ^.
            ppKeyDepositL)); a fixture whose pparams leave ppKeyDepositL unset cannot
            witness this, because the asserted and observed sides both default to zero
enforced:   ENFORCED 2026-08-06, and proven able to fail — not asserted. Slice
            `slice2c-deposit-oracle` (commit `35627f47`, parent `52db21a2`, ONE file, TWO
            insertions: the `ppKeyDepositL` import and `& ppKeyDepositL .~ Coin 2_000_000`
            in `testPParams`) gives the fixture a real key deposit, so the hardcoded-zero
            mutant now FAILS: `expected SJust (Coin 2000000)` / `but got SJust (Coin 0)`,
            recipe exit 1. Desk re-derived all four hashes byte-for-byte (RED `cfd6c1af`,
            GREEN `d3474856`, gate `3d076c40`, audit `44d3a1c4`) rather than reading the
            reports.
            RESIDUAL, named because an unnamed one is how this comes back: the expectation
            at `RegistrationSpec.hs:604` derives from the SAME `testPParams` the production
            path reads. That coupling is why the mutant dies — and it means the proof's whole
            discriminating power now rests on that fixture constant staying non-zero, which
            NOTHING GUARDS. Reset it to zero and both sides go to zero and the check silently
            stops discriminating: the same defect one level further out, a check that could
            quietly stop being able to fail. Next enforcement step (candidates: assert the
            fixture deposit is non-zero, or derive the fixture from a real pparams snapshot).
            Deliberately NOT chased by widening the slice — scope is the honest lever.
            HISTORY: proven NONE on 2026-08-05, when #181's second 2C auditor mutated
            the deposit to a hardcoded zero and the mutant SURVIVED GREEN. The production
            code was never shown defective; the PROOF could not fail, and the half it could
            not witness guards a LEDGER-INVALID transaction. Commissioned to the carved slice
            slice2c-deposit-oracle (e171/#181), whose acceptance is a DEMONSTRATED RED of
            that exact mutant rather than a passing suite.
            HONEST LIMIT of that check once it lands: it is fixture-level. It will show the
            deposit is READ FROM pparams, not that the resulting certificate is ACCEPTED BY
            A NODE. That residue closes at the live boundary — #166's stranger run and the
            cutover — and is recorded here so the new slice's green is not read as more than
            it earns.

contract:   what "an identity" means to a consumer — TWO LIVE MODELS in one repository
parties:    the checkpoint stack (sovereign per-AID token: weighted current keys, threshold,
            rotation-following, freeze-aware) vs `onchain/validators/cage.ak`'s
            `verifyOwnerAuth` (global `identity_root` MPF inclusion proving
            `identity_root[owner_aid] = blake2b_256(owner_key)` — one key, no threshold,
            no rotation semantics)
invariant:  a consumer that authorizes "the controller of AID X" resolves the SAME notion of
            control the checkpoint stack enforces; a 2-of-5 identity must not degrade to a
            single key at the point of use, and a rotated-away key must not still authorize
enforced:   NONE at 2026-08-06 — and this is not drift between two teams, it is the design
            the checkpoint work explicitly REPLACED (a shared root: contention on one piece of
            state, plus a freshness question that keeps pulling an oracle back into a design
            whose point is not having one) still living in a sibling validator. Found while
            designing the M1 consumer example; the cage's own step 2 is sound and reusable —
            a domain-separated Ed25519 signature over the request's `OutputReference`, which
            is exactly the transaction-binding the token demo lacks.
            NOT M1 scope: the operator ruled MPFS/cage integration OVERKILL for the M1
            consumer example (2026-08-06); the example stays the standalone
            mint-a-CID-signed-by-a-KEL app, and the cage/MPFS direction is carried in the M1
            blog post as the scaling answer, not built. Registered so the inconsistency has an
            owner when someone does bind a consumer to identity — whoever does it first
            should not discover this by reading `verifyOwnerAuth`.

contract:   registration-deposit-vs-live-pparams
parties:    ckeri tx path (produces registration certs), Cardano ledger rules
            (preprod/mainnet reject zero-deposit stake registration)
invariant:  the registration deposit asserted in tests equals what the
            production path reads from live protocol parameters; a zero-deposit
            fixture is ledger-invalid on any real network
enforced:   ENFORCED 2026-08-06 — commit 35627f47 sets a real key deposit in
            testPParams; the hardcoded-zero mutant now dies (expected SJust
            (Coin 2000000), got SJust (Coin 0), exit 1). History: proven NONE
            2026-08-05 by that same mutant SURVIVING green (M6b).
            RESIDUAL, named: the proof derives its expectation from the SAME
            testPParams the production path reads, so its discriminating power
            rests on that deposit constant staying non-zero and nothing guards
            it. Feeds #255 (deposit value-coverage class).

contract:   identity-authorization-model
parties:    ckeri identities (KEL key state); downstream Cardano validators
            gating actions on it (first consumer: "mint a CID signed by a KEL")
invariant:  a consumer validator resolves the identity's checkpoint as a
            reference input and revalidates it fully (policy, quantity-one
            asset, script version, AID, datum, role address) before trusting
            its key state; attestation (signature over a CID) is never
            presented as authorization of a spend
enforced:   NONE — registered 2026-08-06, deliberately NOT scheduled as
            infrastructure: operator ruled MPFS/cage integration overkill for
            M1. The enforcing check arrives WITH the consumer-example epic (its
            9 negative controls ARE the check); the scaling answer goes in the
            blog post, not the milestone.

contract:   packaged-runner-ships-no-cardano-cli
parties:    ckeri release artifacts (what a stranger installs), the #181 product
            claim (full write journey with no cardano-cli installed)
invariant:  the PACKAGED closure — not just the source tree — contains no
            cardanoCli on any internal PATH; the artifact's independence claim
            is a property of what ships, not of what the repo says
enforced:   ENFORCED 2026-08-07 (merged in #181's slice-4 repair): the control
            is proven at closure level — reintroducing cardanoCli into the
            packaged closure turns the check RED. History: found 2026-08-06 by
            the slice-4 auditor as a PRE-EXISTING defect at flake.nix:591,
            outside the frozen fence, while the source-level battery passed —
            the exact gap between "the code does not call it" and "the package
            does not carry it".

contract:   flake-inputs-locked
parties:    flake author (offchain/flake.nix) ⟷ every gate invocation in every
            lane (just ci, GitHub workflow)
invariant:  every input declared in offchain/flake.nix is locked in the
            COMMITTED offchain/flake.lock; the gate never silently regenerates
            lock state (a pristine checkout stays pristine through just ci)
enforced:   NONE 2026-08-07 — COMMISSIONED same day (Q-017/A-017): gate
            evaluates with --no-write-lock-file + post-gate git-diff-exit-code
            on the lock, proven able to fail by deleting the deployPreprod
            node; e156 files, #257 T.O. places (tail slice or queued before
            #240). Found because a ticket-257 worker REFUSED a dirty baseline
            instead of quietly restoring the tree — the instance (deployPreprod
            declared at flake.nix:46, absent from the committed lock) dirties
            every checkout repo-wide; #257 fixes the instance under A-001.

contract:   provider-admissibility (sharpens or-local-or-provider)
parties:    every chain-state consumer ⟷ any state source
invariant:  state is admitted by DERIVATION, not assertion: a source is a trust
            root only if its claims verify client-side (own-node derivation, or
            certified state with client-checked proofs). Reputation-only APIs
            (koios/blockfrost as-is) are transitional legacy, never trust roots
enforced:   by architecture direction (#257: local interpreter = derived;
            koios interpreter = legacy, documented non-atomic; differential
            invariant measures providers against self-derived truth). Operator
            ruling 2026-08-07 at the desk.

contract:   auditor-skill-pinning (CLOSURE FORM since 2026-08-08, A-021)
parties:    every M1 auditor spawning brief ⟷ the commit-auditor skill text
            (llm-settings shared/skills/commit-auditor/SKILL.md)
invariant:  the contract CORPUS an auditor obeys is named and reproducible:
            the brief pins the NAMED-DELEGATION CLOSURE (every skill file the
            seat delegates to by name, each rev+sha256 — today: commit-auditor
            + haskell); START echoes every hash read; mismatch on ANY member
            (incl. dirty copy) = STOP. haskell dbb058b QUARANTINED: its
            module-shadowing technique silently fails to load = manufactured
            audit confidence
enforced:   RULED 2026-08-07 (A-016b), mechanically checkable from brief+START
            pairs. Trigger: operative text sat UNCOMMITTED — committed as
            969ff86. PIN UPDATED SAME DAY (A-016c) to 02ab0d7 / sha256
            deb56d78… after the evidence-freeze doctrine landed — the rule
            demonstrated its purpose: a stale-pinned brief STOPS instead of
            obeying text the auditor never agreed to. First pinned seat:
            #257 auditors, under the NEW pin.

contract:   chain-types-home-and-indexer-read-surface (transient, #257)
parties:    #257/e156 producer (relocates ChainAsset/ChainAssetUtxo out of the
            provider module into Cardano.KERI.ChainQuery; deletes
            ChainAssetHistory as dead; adds derived watermarkPointTx) ⟷ e171
            indexer consumers (Board.hs + eleven more modules)
invariant:  consumers learn of the relocation BEFORE it reaches them as a merge
            conflict; in-flight sibling branches get a stated migration cost or
            a held boundary, never a surprise rebase
enforced:   NONE — compiler at merge time only. ACCEPTED AS TRANSIENT by desk
            ruling 2026-08-07: the seam dissolves at #257's merge; mitigation =
            PR must enumerate every e171-owned file touched + state in-flight
            migration cost, plus the desk relay (A-cross-epic-257). Standing
            fence line ratified: derived reads from existing data IN; persisted
            columns / rollback-log shape / on-disk format OUT, stops for ruling.

contract:   mutation-stopping-rule (Q-020 CLOSED 2026-08-09)
parties:    every commit-auditor campaign ⟷ every commit-owner ⟷ ticket specs
invariant:  mutation campaigns terminate by DECLARED RULE, never by patience:
            per-invariant row states, severity fixed at spec time
            (chain-state/money/signature blocks; else advisory), a
            build-denominated budget, a recorded tail-stop. Legacy code
            acquires invariants PER-TOUCH: each commit owner opens by
            declaring what its change relies on; "enforced: NONE" is a
            complete outcome.
enforced:   BY CONTRACT TEXT since llm-settings 59865be (merged during the
            08-08 pause; keri released after so new seats pin the new text —
            the doctrine lane's own sequencing point). #257 finishes under its
            started contract (machine ruling); #259 onward pin 22e4976+.
            Origin: e156's Q-020 + operator amendment (auditors-at-old-code;
            the 12-vs-zero declared-invariants corpus fact).

contract:   disk-cost-model (which filesystem pays for what)
parties:    every lane spawning audit/commit worktrees ⟷ the host's finite
            filesystems (/ = nix store, /code = checkouts + dist-newstyle)
invariant:  reclaim is reported on the term that actually pays: **audit
            worktrees cost /code; audit BUILDS cost /**. Worktree retirement
            NEVER relieves the pressured filesystem. A reclaim claim names its
            filesystem or it is not a claim.
enforced:   BY MEASUREMENT 2026-08-09 (machine's controlled bare-worktree
            probe: du 10,551,565 vs /code fall 12,722,176 — du under-counts,
            double-counting refuted; / fell ZERO). History: the desk's
            shared-object-store hypothesis was FALSIFIED and dropped in one
            line; TWO desks (M1 and e171) independently reported reclaim on
            the wrong term this week and both said so out loud, which is why
            the machine's published model got corrected instead of
            propagating. OPEN-AND-DEPRIORITIZED with reason: ~15.5 GB of du
            across eight retired worktrees showed no demonstrated /code
            reclaim; almost certainly built term masked by concurrent lane
            builds on a 312 GiB-free volume — not worth a build to prove,
            because /code cannot pressure the machine. NEXT INSTRUMENT (the
            machine's, not M1's): 728 entries in /nix/var/nix/gcroots/auto —
            result symlinks pinning closures on /, which worktree removal
            provably does not touch.

contract:   259-flake-lock-guard rows 2-6 (RESIDUAL, operator-priced)
parties:    #259's declared invariant set ⟷ the evidence actually produced
invariant:  every declared blocking row is killed by a real mutation, proven
            by a seat that did NOT repair it
enforced:   PARTIAL, and named rather than papered over. Of six declared rows,
            ONE is fully proven: INV-259-FALSIFIABLE (real deployPreprod
            missing-node mutation killed by the guard, exact restore, receipt
            retained). FOUR blocking rows (DATA-INV-259-01, INV-259-NOWRITE,
            INV-259-ASSERT, INV-259-PARITY) were repaired after audit 1 and
            certified BY THE SEAT THAT REPAIRED THEM — a human override
            stopped the audit campaign with no second auditor. e156 withheld
            acceptance and escalated rather than merge a green board or
            overrule the override; the OPERATOR merged (#260 -> 5bf84982,
            2026-08-09T17:20:47Z), which is their authority and is recorded as
            a priced decision, not an oversight. The guard is live and CI-green
            (22/22); what is unproven is the independence of four proofs, not
            the behaviour. Campaign cost: 6 of 8 builds — under budget, but the
            comparison against #257's eight rounds is NOT clean because the
            campaign was cut short by override.

contract:   agent-death-modes (machine-wide watch list)
parties:    every authoritative seat on this host ⟷ the machine owner's
            inventory
invariant:  a seat death is REPORTED as a recovery, never silently reseated —
            a failure nobody hears about cannot be watched for
enforced:   BY PRACTICE. STUCK COMPACTION, now THREE occurrences, ALL on
            #240's commit-owner seat: %6038 -> %6045 -> %6049 -> reseat
            (2026-08-09 19:30Z, then twice more by 2026-08-10 00:24Z).
            Signature identical: automatic compaction reaches 0% and hangs;
            the lane checkpoints, preserves runtime+diff, closes by exact PID,
            relaunches the SAME authoritative seat. Handling correct all three.
            MACHINE SWEEPS (twice): still ONE SEAT, no live hang anywhere else
            — not spreading.
            WORKING MECHANISM (lane hypothesis, machine-adopted, FALSIFIABLE):
            the stalls follow the 26-stage pre-clear MATRIX DRIVER opening. A
            mechanical enumeration produces large LOW-ENTROPY context that is
            not implementation context; a compactor compressing that inside an
            implementation seat is doing the worst job on the worst input. So
            the failure is caused by TOPOLOGY, not a broken compactor.
            FALSIFIERS NAMED IN ADVANCE: a fourth stall on that seat with NO
            matrix running, or a long mechanical enumeration elsewhere that
            never stalls.
            *** HYPOTHESIS FALSIFIED 2026-08-10 BY ITS OWN NAMED FALSIFIER ***
            commit-owner-s1-v1 (%6062, Claude) stalled on context compaction at
            ~08:00 after acknowledging N-076 — a CLOSE instruction, NO matrix
            running. The topology explanation is dead exactly as the machine
            said it would be if this occurred. What survives: the signature
            (automatic compaction hangs at 0%), the one-seat locality, and the
            recovery discipline. What is now open: the real mechanism. Naming
            the falsifier in advance is what let a hypothesis die in one
            observation instead of accumulating supporting anecdotes.
            STRUCTURAL FIX (suggestion, both altitudes — topology inside the
            fence stays the ticket owner's call): a run-a-stage-record-a-result
            matrix is disposable-seat work the commit-owner contract already
            has a home for. The fix is not a bigger context; it is moving the
            enumeration OUT and handing back only results.
            Altitude discipline that made all of this visible: the ticket owner
            classified and reseated its own child; the desk observed a vanished
            pane and HANDED IT DOWN; the machine swept and adopted rather than
            ordering. A recovery reported as a recovery is why the pattern
            exists as knowledge at all.

contract:   delivery-is-an-acknowledgement (machine-wide, adopted 2026-08-10)
parties:    every orchestrator dispatching to a child pane ⟷ every child seat
invariant:  a SEND-KEYS IS NOT A DELIVERY. A delivery is a post-cursor
            acknowledgement in the CHILD'S OWN JOURNAL. Always dispatch
            through send-pointer, whose postcondition is exactly that
            acknowledgement; never a raw send-keys.
            COROLLARY, equally load-bearing: send-pointer's RETURN VALUE IS
            ADVISORY. It reports "did not consume" / "wait-status: timed out"
            for pointers that DID land. Check the child's journal before
            re-sending, or you double-deliver — and never record a lane as
            unacknowledged on the strength of the return code alone.
enforced:   BY MECHANISM (send-pointer), adopted machine-wide 2026-08-10.
            History: found agent-to-agent by e156 on #240 — raw send-keys
            landed text with the Enter dropped, twice in 90 minutes; the
            sender believed it dispatched, the receiver never saw it, both
            went quiet. e156 diagnosed it as MECHANICAL AND PANE-SPECIFIC and
            DECLINED to write a be-careful rule, on the grounds that no
            discipline defeats a dropped keystroke.
            PROVIDER ASYMMETRY PROPOSED BY THIS DESK AND FALSIFIED BY THE
            MACHINE'S OWN INVENTORY — the cross-lane fact only it could hold:
            on 2026-08-08 its crew panes %5248 and %5011 (both CODEX-raw) sat
            TWO DAYS with pointer text visibly unsent in their prompts, and
            the crew was recorded as unresponsive when it had never received
            anything. Same mechanism, both providers; a provider-scoped fix
            would have left half the machine exposed. Interim workaround,
            named as a workaround: double-Enter until dispatches move to
            send-pointer. Consequence accepted on the record: some
            "unacknowledged" entries from this week are wrong.

contract:   RETRACTED — mint-once-unicity / tombstone-terminality
parties:    checkpoint_register validator ⟷ every consumer of a checkpoint;
            the enforcement layer (#163/#164 hunters) ⟷ its own economics
invariant:  one AID, one checkpoint token, forever: a duplicate seq-0
            registration is impossible, and conviction is TERMINAL — a
            convicted AID can never re-register
enforced:   **ENTRY RETRACTED 2026-08-11 BY OPERATOR RULING, SAME DAY IT WAS
            WRITTEN. TOMBSTONES ARE AGAINST THE KERI PROJECTION
            CONSTITUTION**: Cardano PROJECTS the KEL and may only reflect
            state that key events express. A tombstone would have the chain
            ORIGINATE identity state with no KEL preimage — asserting rather
            than deriving, the same principle that governs providers
            (see provider-admissibility). Burn-only conviction is therefore
            CORRECT, not incomplete: the chain stops projecting, it does not
            pronounce. The doc line "TOMBSTONE | Fork conviction is terminal"
            (overview.md:86) is itself in tension with the constitution, and
            overview.md:89 already flags TOMBSTONE as an UNOPENED target role
            (#151) — which the desk read past.
            DESK ERROR, recorded because it is instructive: I verified that
            Tombstone was ABSENT FROM THE CODE and treated that as confirming
            the finding, WITHOUT verifying that its PRESENCE WAS REQUIRED.
            Measurement checked, claim unchecked — the exact failure this desk
            polices in others, committed while relaying a security finding.
            WHAT SURVIVES, downgraded: duplicate registration is a TRUE
            PROJECTION of a genuine published event (registration.ak:386-404
            verifies controller sigs over real KERI event bytes), so nothing
            is forged — someone else merely pays the deposit to publish a
            public fact. The residual is a CONSUMER DISCOVERY AMBIGUITY (two
            UTxOs project one AID; "the checkpoint for this AID" has two
            answers), which the spec already documented and accepted. That is
            a consumer resolution-rule question — material for the consumer
            example — not a validator defect. The former "discharged
            obligation" framing about #116 is void with it. specs/114-registration/spec.md:283-312
            ruled unicity a ratified epic invariant (not a residual), accepted
            the window ONLY pre-deployment, named post-conviction
            re-registration as the exact consequence, and ruled "the gate
            ships with #116". **#116 CLOSED 2026-07-21T16:35:13Z without it.**
            Desk-verified 2026-08-11: Tombstone appears ZERO times in either
            deployed validator (checkpoint_register.ak imports role.{Active,
            Armed} only, :34); the convict branch :619-677 burns the token,
            pays the convictor, writes no tombstone. So conviction is a fine,
            not a revocation, and a convicted identity re-registers pristine
            for d_reg + freeze_bond.
            NOTHING IN THIS MILESTONE'S MACHINERY WOULD HAVE CAUGHT THIS: a
            spec obligation assigned to a named ticket and closed unmet is
            invisible to auditors of the ticket that closed it. That is the
            finding above the finding.

contract:   enforcement-bounty-context-binding (SECURITY)
parties:    freeze/convict branches ⟷ hunters (#163/#164) whose economics
            depend on being paid for the work they did
invariant:  the party named in a bounty payout is the party that authorized
            the transaction
enforced:   NONE — FILED 2026-08-11 as issue #271 (M1 milestone), on operator
            order after the assessment. Desk-verified: `extra_signatories` appears ZERO
            times across checkpoint_register.ak, checkpoint_observer.ak and
            the checkpoint lib (all 4 hits are in endpoint_board.ak).
            hunter_pkh/convictor_pkh are plain redeemer fields written into
            the ARMED datum and payout; the KERI evidence is fully replayable,
            so any mempool observer rebuilds the tx with their own pkh and
            wins on fee. #219's shape exactly — content authenticated, context
            not. MUST land before the hunter economy goes live; cheap fix
            (bind pkh to extra_signatories), batch into whatever next touches
            the enforcement branches.
