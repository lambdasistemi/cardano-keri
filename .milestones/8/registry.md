# Milestone 8 contract registry

Updated: 2026-08-02T07:24Z

## Exact production artifact identity

contract: Aiken source and pinned toolchain produce the blueprint UPLC imported by Lean/Blaster.
parties: Cardano-KERI onchain source/build; #189 bridge; #190 theorem portfolio.
invariant: every manifest title resolves through the exact Nix build to a non-empty program hash, and theorem evidence names that hash and source/toolchain identity.
enforced: #189 generated manifest + fail-loud extraction + fresh-checkout CI + audit-manifest hash verification; source mutation and clean-restoration controls prove the seam can fail.

## Frozen bridge consumed by the portfolio

contract: #190 properties consume only #189's accepted artifact and purpose conventions.
parties: epic #189 producer; epic #190 consumer.
invariant: P0 ratification postdates the tractability record and every accepted theorem binds to the frozen bridge manifest.
enforced: milestone dependency order, manifest identity in every theorem record, changed-program invalidation, and independent audit.

## Abstract lifecycle versus compiled lifecycle

contract: the 21 abstract Lean goals and compiled validator baseline may describe different protocol generations.
parties: abstract `lean/` model; production validators; #190 mapping.
invariant: every goal and production path is classified against a named baseline, including MODEL-AHEAD/CODE-AHEAD and existing PENDING parity markers; a baseline change invalidates affected evidence.
enforced: #190 threat/mapping matrix and baseline-triggered rerun rule.

## Deployed instance binding

contract: unapplied blueprint code hashes are not deployed applied-script hashes for parameterized validators.
parties: #189 audit manifest; deployed/integration evidence consumers.
invariant: each deployed instance claimed as covered names parameter values and resulting applied-script hash, otherwise deployment binding is visibly OUT-OF-SCOPE.
enforced: #189 manifest schema and final audit of any claimed applied-script chain.

## Proof vocabulary and trust boundary

contract: readers must not confuse an SMT Valid admitted through `blasterProven` with a Lean kernel proof or whole-system verification.
parties: #189 taxonomy/docs; #190 theorem report; milestone description/audit.
invariant: every claim is labeled KERNEL-PROVED, SMT-VALID (no proof term), TESTED, UNPROVED, OUT-OF-SCOPE, or OUT-OF-SCOPE-BY-FORM; kernel label is abstract-model-only and solver/import/compiler/ledger trust remains explicit.
enforced: published taxonomy, warning visibility, theorem matrix, and independent READY/NOT READY audit.

## Blueprint inventory

contract: prose baseline counts must not outrank the generated production manifest.
parties: Cardano-KERI blueprint; #189 manifest; #190 matrix; final audit.
invariant: every current title/program is classified; 23 titles/8 programs are observations only at baseline `7e19e550b6f107bbc10b4c65e77765e3e439f043`.
enforced: CI fails on unreviewed add/remove/rename and #190/final audit derive scope from the manifest.

## Legacy root gate lifecycle

contract: the shared repository root gate follows the canonical untracked and ignored per-ticket lifecycle without breaking active M1 users.
parties: M8 milestone governance; all Cardano-KERI issue lanes consuming the gate lifecycle; a future standalone M8 migration owner.
invariant: root `gate.sh` becomes untracked, `/gate.sh` is ignored, positive and negative lifecycle controls prove the convention, and normal CI remains green without smuggling the migration into an unrelated feature ticket.
enforced: NONE — operator ruling `2026-08-02` assigns this work to M8 but makes it parallel and non-blocking for #192. Verified `origin/main` `1473885a1a16d5d993b6d0c475566e086bf50dfb` still tracks `gate.sh` blob `2540cdb658ebe0a597ca971f5b81d00500e9ab17`; `.gitignore` blob `545e072cae49dd7605297364552aeb69337b7ce2` has zero exact `/gate.sh` entries. Commission a separately fenced standalone M8 ticket with both-way lifecycle controls and CI. Until then #192 keeps both root files forbidden and uses its frozen runtime gate.

---

```
contract:   UNTRACKED MEANS UNCOVERED — tree-enumerating mechanisms and the
            artifacts they claim to cover
parties:    every M8 mechanism that enumerates, hashes, preimages, packages,
            copies or verifies a working tree (gates, preimages, evidence
            manifests, preservation patches, the #250 stranger bundle) — and
            every reader who trusts their output
invariant:  a mechanism covers ONLY tracked files unless it PROVES otherwise.
            The burden of demonstrating coverage of untracked additions is on
            the MECHANISM, never on the reader to notice an absence.
enforced:   PARTIALLY — check-blaster-identity-consistency.sh classifies and
            compares, and the #234 preservation MANIFEST states the gap
            explicitly with the required 0755 mode. NOT enforced generically:
            no mechanism yet fails automatically when an untracked deliverable
            is silently excluded.
history:    THREE independent occurrences in three mechanisms —
            (1) the whole-tree preimage silently excluded the untracked
                checker; the hole seed F walked through;
            (2) every reviewed gate version inherited the same tracked-only
                assumption;
            (3) the preservation patch omits the untracked checker, so a
                restore from the patch alone yields Stage D WITHOUT the
                deliverable and nothing complains.
            Raised by the #234 lane, not by the desk, on the third sighting.
open risk:  the #246/#250 stranger-runnable evidence bundle has exactly this
            failure mode. A bundle assembled from tracked files drops untracked
            deliverables silently, and the milestone's headline claim — "a
            stranger can reproduce this from the bundle alone" — becomes FALSE
            while every check stays GREEN. This is the milestone's own
            green-without-mechanism disease pointed at its published artifact.
```

---

```
contract:   NO EPIC BUILDS A MECHANISM THE MILESTONE ALREADY OWNS
parties:    every epic and standalone ticket under M8 (producers of reusable
            mechanisms) — and the milestone desk, which is the ONLY seat that
            can see across them
invariant:  before a lane is dispatched to build any MECHANISM (a gate, a
            checker, a falsifier, an inventory, an evidence format, a runner),
            the desk states in the dispatch brief what already exists for that
            purpose and where, or states explicitly that nothing does. A lane
            may not be asked to build what the milestone already owns.
            Corollary: the milestone keeps ONE mechanism per purpose. Two
            checkers that can disagree is a worse failure than one checker that
            misses something, because it destroys the reader's ability to trust
            either.
enforced:   NONE — enforced only by the desk remembering, which is exactly how
            it failed. This entry is the record that it is unenforced.
history:    #189/#234 built check-blaster-identity-consistency.sh (921 lines:
            declared-component inventory, exactly-once enforcement,
            missing/duplicate RED, lock-backed field comparison, CNE=RED, a
            verdict contract treating any unexpected exit code as RED, a
            machine-readable CBIC_RESULT interface, and --self-test running
            seeded negative controls on temporary copies with seed attribution
            by seat) plus a falsification harness under handoffs/.
            #190/#246 was then dispatched to build identity and completeness
            machinery and was never told any of it existed. The desk went
            further and wrote A-e190-007 specifying inventory, missing-file RED,
            mode preservation and an omission falsifier — re-specifying, to a
            lane that could not know better, a script the desk had itself
            reviewed and accepted.
            Caught by the OPERATOR, not by the desk: "you are not using the work
            for 190. So ticket 246 is building from scratch. And you are the
            milestone owner."
remedy:     A-e190-011 reuse map issued. Standing: every future M8 dispatch
            brief carries a "what already exists" section, and its absence is a
            defect in the brief, not an oversight to be excused.
```

---

```
contract:   AN AGGREGATE MUST PUBLISH ITS DENOMINATOR
parties:    every M8 mechanism that reports a COUNT as evidence — the identity
            checker, gate result lines, evidence manifests, the #250 bundle
            completeness check — and every reader who treats a zero as good news
invariant:  a mechanism reporting "N problems found" must also report HOW MANY
            THINGS IT EXAMINED. Without the denominator, "0 mismatches" and
            "examined nothing" are the SAME OUTPUT, and the second reads as the
            first. Where the denominator cannot be established, the mechanism
            emits MEASUREMENT-FAILED — never a zero.
            Corollary, from the machine owner's fix: BOTH branches must be
            falsification-tested before the instrument is trusted — the
            genuine-zero branch AND the no-input branch. Testing only the
            happy path is how the two stay indistinguishable.
enforced:   PARTIALLY. check-blaster-identity-consistency.sh already does this
            correctly: it reports classified_rows, lock_backed_rows and
            compared_fields ALONGSIDE mismatches, so "0 mismatches" is read
            against "12 compared". That is the pattern to copy.
            NOT enforced for #246/#250's bundle completeness check, which is
            being authored now — see open risk.
history:    This rule was adopted ABOVE M8 as machine doctrine after arriving
            from FIVE independent mechanisms, only three of them M8's:
            (1) the whole-tree preimage silently excluding untracked files;
            (2) gate versions v1-v5 passing without ever executing the
                deployment unit;
            (3) the preservation patch omitting the untracked deliverable;
            (4) the machine owner's capacity prober degrading silently to
                "claude ?%" when its probe session vanished;
            (5) machine-night-watch summing to tok=0 msgs=0 BOTH when it
                genuinely measured zero AND when it found no files — the
                instrument behind an overnight spend conclusion. Blind, it
                would have reported the identical thing.
            (5) is the strongest form: the conclusion drawn from it happened to
            be correct, but ONLY provably so afterwards, because the samples
            read tok=3083 msgs=3 and non-zero proves files were found. A true
            conclusion resting on an instrument that could not have told you
            otherwise is luck wearing the clothes of evidence.
open risk:  #246/#250's bundle completeness check has exactly this shape. "0
            declared artifacts missing" is TRUE and MEANINGLESS if the declared
            inventory was empty or unreadable. It must publish the count of
            declared artifacts, and both branches must be falsified.
```

---

```
contract:   A MEASUREMENT CARRIES ITS WINDOW AND ITS PROVENANCE
parties:    every M8 record that reports a measured quantity — evidence
            manifests, gate receipts, capacity figures relayed between desks,
            the #250 bundle — and every reader who acts on one
invariant:  a number is not a measurement unless it states WHO READ IT and
            OVER WHAT WINDOW. A bare percentage cannot distinguish a reset
            from a misread; a bare count cannot distinguish a real zero from
            an empty denominator; a bare hash cannot distinguish "current"
            from "whatever was cached". Absent either, the value is
            COULD-NOT-EVALUATE, which is RED.
enforced:   PARTIALLY. check-blaster-identity-consistency.sh emits its
            counters with their denominator. The proof-target triple
            (commit + toolchain + variant) is the same rule applied to
            identity — a commit without its variant is a bare number.
            NOT enforced for relayed capacity figures or for #246's evidence
            records, which are being authored now.
history:    Arrived from the machine owner, 2026-08-10, as their own error
            rather than the provider's. Codex readings ran 50% (08-07), 0%
            (08-08), 1% (08-09), 16% (08-10); the desk was told to treat the
            bucket as unverified and M8 accepted a dispatch gate on it. The
            explanation was available and uncaptured: THE RESET DATE MOVED,
            from a recorded "Aug 11" to an actual 15 Aug. The bucket genuinely
            rolled around the 8th — the 50%->0% drop was a real reset, and the
            instrument had been fine. What was missing was the window.
            Re-probe read TWICE, identical, deliberately against the
            stale-first-read trap.
            Third member of a set this registry already holds:
              1. could not evaluate must be RED
              2. an aggregate must publish its denominator
              3. a measurement carries its window and its provenance
            All three are one shape: a value that cannot distinguish two very
            different states of the world, presented as though it could.
open risk:  #246 is authoring evidence records now. Every measured quantity in
            its bundle must carry what read it and over what window, or the
            published artifact repeats this defect in front of an auditor who
            cannot see our instruments.
```

---

```
contract:   AN ADVISORY NEEDS AN OWNER AND AN EXPIRY, OR IT IS A DECISION NOT
            TO LOOK AGAIN
parties:    every auditor that files a finding below BLOCKING severity, every
            commit owner that ships beside one, and every ticket owner that
            terminates a row RESIDUAL
invariant:  an ADVISORY row, or any finding whose severity is guessed rather
            than derived from the value it constrains, carries a NAMED OWNER
            and a FILED FOLLOW-UP ID at the moment it is filed. Severity is a
            guess made early; when the guess is wrong the class is real and
            only the instance looked cosmetic. Nothing else in the process
            forces an advisory to be closed or explicitly accepted, so an
            unowned one is not "deferred" — it is a finding the project has
            agreed in advance never to look at again.
enforced:   PARTIALLY. commit-auditor requires a RESIDUAL row to carry a named
            owner, a filed follow-up ID and an honest limit — that path is
            enforced. NOT enforced for advisories filed OUTSIDE a residual
            row, which is exactly the gap this entry was written from.
history:    #246 Slice C, 2026-08-13. An auditor filed a SIGPIPE class as an
            ADVISORY two submissions earlier: "a naming obligation can be lost
            to SIGPIPE ... $(comm -23 ... | head -1) aborts with rc 141".
            Cosmetic in the instance it was found in. Nobody owned it, nothing
            expired it, and it survived two submissions.
            It then reappeared in a DIFFERENT FILE as a flake-owned runner
            dying SIGPIPE 141 on the CLEAN PRODUCTION ARTIFACT — a shipped
            check that dies on valid input — and cost one of four granted
            builds on a host that supports roughly one build at a time.
            The build was not wasted: gate-C-v4 caught it at step 3 rather
            than letting it reach a green, which is the one outcome worth
            paying for. But the class had been visible, in writing, for two
            submissions before it was expensive.
            Raised by the machine owner against the desk's own framing, which
            had filed it as a footnote: "That is the finding, not a footnote."
open risk:  not M8-specific. Any lane on this host can file an advisory today
            and inherit its cost weeks later, in a different file, at a moment
            when capacity is the binding constraint.
```

---

```
contract:   A HOST THAT CAN INVALIDATE A RUNNING BUILD'S DEPENDENCIES —
            min-free is a CORRECTNESS risk, not only a hang risk
parties:    every lane on this host that realises anything, the machine owner
            who sets the thresholds, and every auditor who will later read a
            build failure and try to attribute it
invariant:  a build that crosses the nix `min-free` trigger can be SILENTLY
            CORRUPTED MID-FLIGHT BY ITS OWN HOST. The daemon's auto-GC fires
            during the build and can reap a derivation's database entry while
            the build still holds the file open. The failure does NOT look
            like a host event: it wears the costume of a broken recipe or a
            bad tree, in a file nobody on the lane touched.
            Therefore: on a build failure naming a store path as "not valid",
            STOP. Do not retry. Verify disk-vs-database and report it upward
            as a machine event.
enforced:   NONE at the host level until the threshold rebuild lands — the
            trigger can still fire mid-build. Enforced only by lane
            DISCIPLINE: stop-and-verify rather than retry.
history:    2026-08-13, #246 Slice C. A granted cold `just ci` consumed
            ~2.7 GiB, taking / from 52.58 to 49.88 GiB and crossing min-free
            (48 GiB) mid-run. It died on
            `dummy-ghc-9.6.7.drv is not valid`.
            The desk verified the file was PRESENT on disk while
            `nix derivation show` reported NOT VALID — file present, database
            entry absent — and reported it as a machine event with the
            auto-GC hypothesis marked EXPLICITLY UNASSERTED, because the desk
            cannot read the collector's log.
            The machine owner tested the competing explanation first (that
            THEIR collections killed the build) and cleared it: both ran
            after the failure. Corroboration came from the cna-214 lane's
            independent tripwire, which recorded headroom at -357 MiB and
            -360 MiB INSIDE the M8 build window. Two lanes with no knowledge
            of each other measured the two halves: cna-214 caught the
            crossing, M8 caught the corpse.
            Machine owner's verdict on the near-miss: "A retry would have
            re-realised the path and quite possibly gone green, and then the
            real defect — a host that can invalidate a running build's
            dependencies — would have been written off as a flake."
open risk:  until the threshold rebuild, ANY lane's build that crosses the
            trigger is exposed, and the resulting failure is attributable to
            the lane's own code by every instrument we have. A green obtained
            by retrying such a failure is not evidence that the code was fine.
```
