# Contract registry — cardano-keri M1.2 (GitHub milestone 11)

Founded 2026-08-18 by the M11 desk (`cardano-keri-ms11-owner-20260818`, pane `%6695`).
A registry line is a claim, not evidence. `enforced: NONE` is a scheduled incident,
never silence. Scope released at founding is **S0+S1 only**; entries whose enforcement
belongs to S2/S3 are recorded now so they cannot be discovered late, and are marked
NOT-YET-DUE rather than pretending they are covered.

---

contract:   per-script size ceiling — every family member ↔ the chain's limits
parties:    each family validator (produces compiled bytes), Cardano tx/reference-script
            limits (consume): 16,384 B transaction, 16,133 B reference program
invariant:  every family member's compiled script is measured SEPARATELY and reported as
            absolute bytes + percentage + headroom; any member above 80% AT SKELETON STAGE
            is redesigned before deep work. Script bytes under 16,384 never prove a
            transaction fits — that caveat travels with every number.
enforced:   NONE — this is exactly what S0 exists to build. M1 left this number open and
            the monolith died on it (`checkpoint.checkpoint` 25,934 B = 158.3% of tx limit,
            160.8% of the reference ceiling; three more validators at 80–92% BEFORE
            parameter application, which only adds bytes).

contract:   skeleton honesty ↔ the size verdict it produces
parties:    S0 skeleton author (produces), the S0 size gate + every later redesign decision
            (consume)
invariant:  a skeleton must exercise enough of the real data path that its size is
            PREDICTIVE of the finished member. A stub that omits the parse/proof/transition
            work manufactures a passing number and inverts the gate's meaning.
enforced:   NONE at founding — S0 must ship an explicit anti-stub control and prove it can
            fail (e.g. a deliberately hollow member that the control REJECTS). This is the
            single most corruptible point in S0: the gate's own vacuity mode.

contract:   generated vectors ↔ the gate that compares them
parties:    vector generator (produces), gate vector checks (consume)
invariant:  comparison is SEMANTIC over content, not byte-exact formatting; formatter and
            tool versions are pinned so the generating environment cannot drift from the
            committed bytes.
enforced:   NONE — inherited defect, and S1's primary deliverable. Root cause is located,
            not guessed: gate V13 lines 139–142 regenerate-and-diff against committed
            files. M1 slot 3 died on semantic drift (stale declarations), slot 4 on cosmetic
            drift (aiken fmt stripping 84 blank lines) — SAME ROOT. Fix the class. Blind-
            patching the 84 blank lines is explicitly forbidden.

contract:   every expensive gate ↔ the claim it certifies
parties:    gate author (produces), every slot the gate governs (consumes)
invariant:  a gate is demonstrated able to FAIL before it governs any slot. A check that
            cannot fail is manufactured confidence, not evidence.
enforced:   NONE mechanically at founding; S1 must make it a precondition and prove it per
            gate. Inherited positive example to copy: G1's C2 oracle parity shipped seven
            negative controls and nine emitter refusals, each demonstrated able to fire.

contract:   toolchain pin ↔ comparability of every measurement
parties:    the pinned aiken binary (produces bytes/costs), S0/S1/S2 measurements (consume)
invariant:  all compared measurements come from ONE resolved toolchain identity —
            `aiken v1.1.23`, binary sha256 `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`,
            resolved at `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken`
            (VERIFIED PRESENT in the store by the desk 2026-08-18). Budget rows additionally
            carry pin `G1-PIN-001-PV11-MAINNET` (mem 16,500,000; cpu 10,000,000,000;
            tx 16,384 B; reference program 16,133 B; PlutusV3 cost model 350 entries).
enforced:   NONE mechanically for M11 rows — G1 recorded its pin in prose. S0/S1 should
            record and RECOMPUTE the binary digest at measurement time so a silent toolchain
            swap cannot masquerade as a redesign win. Cheap, and it closes a real hole.

contract:   one cold realization at a time ↔ the /nix/store floors
parties:    the two authoring lanes (produce realizing commands), the store (consumes)
invariant:  at most two authoring/building lanes; NEVER more than one cold build/realization
            at a time across the programme. Floors v2: stop AT 50.00 GiB; never start below
            50.00 + 3.10 × N GiB (N=1 → 53.10 GiB). Measure `df -B1 --output=avail /nix/store`
            IMMEDIATELY before every realizing command, never from a worktree.
enforced:   BY DESK MECHANISM, made observable — single-holder build token at
            `/tmp/ms-keri-11/BUILD-TOKEN` acquired by atomic `mkdir`, holder records lane id,
            pre-command `df` reading and start time; released on completion. The desk and the
            lane beat can both read who holds it. Prose alone would not be observable, which
            the release explicitly required.

contract:   the milestone artifact — packaged executables on the provisional `ckeri` line
parties:    M11 (produces the redesigned family), any stranger who must obtain and run it
            (consumes)
invariant:  the milestone's stated outcome is the family "delivered as USABLE PACKAGED
            EXECUTABLES on the `ckeri` line". The outcome audit must obtain the artifact the
            way a stranger would; a source build proves only that the code compiles for
            people who already cloned it.
enforced:   NONE — and the desk is naming the tension at founding rather than at close:
            the S0+S1 release WITHHOLDS product-code push, PR, merge and release, i.e. every
            mechanism by which an artifact could be published. That is correct for S0/S1
            (skeletons and harness need no release) but the milestone CANNOT satisfy its own
            outcome sentence until a later release restores publication. Recorded as an open
            product question to the project owner, not as a blocker on S0/S1.

contract:   INV-BIND five-gate pattern ↔ each S2 family validator
parties:    frozen gate `inv-bind-v1.sh` sha256 `7037228b898d5f93ad4ef365ac1cdfe0780f1bf6229f0f325cb2cf25171ac5b1`
            (produces the pattern), each S2 validator gate (consumes)
invariant:  parity corpus, adversarial fixtures with pre-repair can-fail runs where a
            pre-repair subject exists, mutation sweep, no-offset interface audit, live-boundary
            rejection — plus the worst-case budget rows added to the G1 map under the same pin.
enforced:   NOT-YET-DUE — S2 is withheld by the current release. The frozen instrument exists
            and is verified; nothing is claimed about S2 coverage.

contract:   G2 preprod lineage-activation drill ↔ a second written machine release
parties:    M11 S3 (would write to preprod), machine owner (grants)
invariant:  S3 requires a SECOND written release naming every write the drill performs.
enforced:   NOT-YET-DUE and correctly gated. No S3 work, planning-only or otherwise, is
            authorized by the S0+S1 release.

contract:   M1 custodial-terminal boundary
parties:    M1 desk (custodial-terminal), M11 desk (inherits read-only)
invariant:  M11 reads M1's artifacts and git objects; it never writes M1's runtime, wakes its
            desk, resets its harness, or spends a fifth G0 slot. The monolithic-checkpoint
            architecture is not reopened.
enforced:   BY DESK, standing. All eight inheritances were verified by the M11 desk itself
            (the machine owner deliberately spot-checked only one), by sha256 and by git
            object type — wiki page blobs hashed FROM GIT OBJECTS at commit `e040f12a`, not
            from a worktree, so a local edit could not have satisfied the check.

contract:   worker journal FORMAT ↔ every supervisor wait and the lane beat
parties:    each lane owner (writes STATUS.md lines), the desk's waits/beat (parse them)
invariant:  every event is emitted through `worker-protocol/scripts/status-event`, giving
            `<ISO-8601 UTC>  <TAG>  <message>` with the TWO-space separator every waiter greps.
enforced:   NONE mechanically — and it FAILED IN PRODUCTION on day one, which is why it is
            here. At dispatch, S0 hand-wrote its START with local `+01:00` time and single
            spaces. Consequences were measured, not theorised: the dispatch handshake timed
            out (exit 124) although the line existed, and the beat matched S0's journal
            **0 times** while matching S1's — the desk was blind to the lane carrying the
            milestone's most time-critical output. Repaired by correction note; S0 re-posted
            conformingly and the beat now fires on it. The residual is real: nothing STOPS a
            worker from hand-typing, so this is detective, not preventive. Candidate check —
            a lane-beat leg that alarms on a non-conforming line rather than silently not
            matching it, since "no match" and "nothing happened" are currently the same signal.

contract:   child TAG VOCABULARY ↔ the desk's beat/wait alternations
parties:    each lane (invents tags as its role skill suggests), the desk beat (must see them)
invariant:  no lane event can be invisible to supervision, whatever tag the lane chooses.
enforced:   ENFORCED 2026-08-18 by INVERSION, after failing in production the same day.
            S0 emitted its seven size verdicts as `BARE-VERDICT`; the beat's alternation
            carried `VERDICT` bounded by two spaces, which cannot match inside
            `  BARE-VERDICT  `. Measured: the beat matched S0's journal 1 time while seven
            verdict lines sat unreported for ~21 minutes — the milestone's most time-critical
            output, invisible to its own supervisor. The desk found them by reading, not by
            the instrument. Repaired by inverting the filter: emit EVERY conforming tag except
            an explicit boring-list, so the failure mode becomes noise rather than silence.
            Re-proved against the exact journal that defeated the old pattern (7 emitted, was
            0; 13 conforming − 2 boring = 11). Lesson recorded because it recurred: this is the
            same class as the S0 journal-format defect four hours earlier, and it reached the
            desk's own instrument by the opposite route — guessing an enumeration instead of
            broadening one.

contract:   staging/proof-token member ↔ the PREMINT validator's 1024-byte SAID bound
parties:    S0's redesigned staging member (produces TxA payloads), `hash_proof.ak:91` /
            `blake3.ak:664` premint validator (enforces)
invariant:  anything TxA commits to must serialize within 1024 bytes, or the staged append is
            refused one transaction BEFORE the member being measured ever runs.
enforced:   ENFORCED BY THE VALIDATOR ITSELF, and measured rather than assumed: G1 measured an
            8-key inception at 1,049 B and observed it REFUSED at premint — it never obtains a
            proof token, so it never reaches registration. Registered 2026-08-18 when S0's
            redesign adopted the two-tx premint+burn shape, because adopting the precedent
            means inheriting its boundary. S0 recorded the cap as a DELIBERATE inheritance
            rather than discovering it later at the cost of a slot.
            Related inherited facts handed down with it: the coupling costs 15,155,350 mem +
            7,631,646,035 cpu SUMMED ACROSS TWO TRANSACTIONS — no per-transaction limit, no
            headroom claim, an upper bound composing the heaviest measured instance of each
            role; and `g1_c4_input_393` / `_966` are known-broken controls (wrong fixture bytes
            or offsets, per G1's own finding), which S0 has excluded explicitly so an inherited
            red cannot be mistaken for one its change caused.

contract:   TxB co-residency ↔ whichever per-transaction script limit actually governs it
parties:    the family's TxB-staged-event (must carry append + cursor + staging_proof_token,
            plus maintenance_escrow when a fully-witnessed premium is claimed), and the
            Conway ledger rules that price or bound scripts in one transaction
invariant:  the family's central transaction must be constructible and affordable with all
            scripts it structurally requires present at once.
enforced:   NONE — and deliberately NOT recorded as a failure, because the governing limit is
            UNDETERMINED at skeleton stage. Established design fact: a SINGLE pair-token burn
            authenticates BOTH append and cursor, so they cannot be separated; the structural
            sum is 25,617 B. Undetermined fact: whether those scripts are supplied INLINE
            (bytes in the tx body → the 16,384 B limit binds → structurally fatal) or
            REFERENCED from UTxOs (bytes outside the body → `maxRefScriptSizePerTx` and the
            tiered reference-script fee bind → a cost question, not an impossibility).
            S0's skeletons have **no witness construction**, so neither can be shown, and S0
            superseded its own CO-RESIDENCY-FAIL on desk challenge rather than assert a limit
            it could not establish.
            WHY THIS ENTRY EXISTS: 25,617 B is 158.79% of the reference ceiling and M1's fatal
            monolith was 25,934 B = 158.3%. That resemblance is close enough to import M1's
            verdict by reflex. It must not be imported by resemblance — M1's number was ONE
            script against a per-script limit, which nothing composes away; this one is a sum
            of three scripts each comfortably under that limit. Closing this needs the
            witness construction to exist, which is S2/S3 territory.
            SCHEDULING: this is the FIRST question S2 answers, not a late one. A milestone that
            discovers its central transaction is unaffordable after building its family has
            repeated M1's mistake with extra steps.

            RESOLVED-TO-A-PRIOR, same day: read-only inspection of shipped M1 code establishes
            the ESTABLISHED WITNESS PATTERN IS REFERENCE, not inline — `CLI.hs:2034-2053`
            (resolves manifest hashes), `Registration.hs:437-474` (requires script-bearing
            reference UTxOs), `RegistrationSpec.hs:768-770` (freezes reference inputs), and
            structurally `CheckpointTxBuilder.hs:2942,2951-2952` (reference inputs non-empty ⇒
            inline script witness map EMPTY). So the 16,384 B body limit is very probably NOT
            what governs the sum, and the 158.79% ≈ 158.3% resemblance is very probably
            numerological rather than causal. This is a STRONG PRIOR, not proof: the new
            family's TxB is still unspecified and S0 kept `no-fit-claim=true`. The burden has
            shifted — departing from the pattern the repository already uses everywhere would
            now be the thing needing justification. S2's first deliverable is correspondingly
            narrower: confirm the new family follows the reference pattern, then read
            `maxRefScriptSizePerTx` and the reference-script FEE TIERS from the pinned protocol
            parameters and place 25,617 B against both, as budget rows under the G1 pin.
            Worth revealing rather than straddling in that measurement, and NOT asserted here:
            25,617 B sits just above 25,600 B (25 KiB), which may be a fee-tier boundary.

            RULED 2026-08-18 (A-002, project owner): the resemblance must NOT travel as a
            feasibility finding or NO-GO — they are different quantities until an operative
            limit is proven for the sum. S2's first deliverable is fixed: prove the new TxB's
            witness pattern; read and CITE `maxRefScriptSizePerTx` and the reference-script fee
            tiers under the existing pin; place 25,617 B against both including the 25,600 B
            vicinity; and — strengthening the desk's own recommendation — **preserve and test
            the INLINE branch rather than infer it away**, because a strong prior is exactly
            the thing that quietly becomes an untested assumption. The append/cursor
            authentication coupling is an explicit S2 design decision: measure the cost first,
            then decide whether a second role token or a derived cursor transition is worth the
            complexity. Do not redesign from resemblance alone. `S0-TxB=unspecified` and
            `no-fit-claim=true` stand until S2 supplies the witness construction.

contract:   UNFALSIFIED CONTROLS — the milestone's dominant defect class
parties:    every gate, suite and control in this milestone (asserts), and the branch, boundary
            or observation surface it claims to protect (is asserted about)
invariant:  a control must actually falsify the thing it certifies — it must be able to go RED
            when that thing is broken, and it must observe the surface where the breakage occurs.
enforced:   NAMED AND UNDER ACTIVE REPAIR, after BOTH lanes hit it independently on the same day.
            Neither lane could see it from inside its own fence; matching the shape across lanes
            is the milestone altitude's job, which is why this entry exists here and not in a
            ticket.

            **The class, in the words of the lane that named it** (S1, answering the desk's
            question about which invariant died and whether it was a class): *"nominal controls
            existed but did not falsify the critical branch, boundary, or observation surface
            they claimed to protect."* The one invariant that survived scrutiny,
            `INV-HQ-CANFAIL`, was the exception **because its seed reached the real boundary**.

            **Instance A — S0.** Replacing `blake3.verify` with the constant `True` leaves the
            17-case suite green while the compiled program loses 8,757 → 1,121 B, i.e. 87.2% of
            the bytes the size row reports. Presence was provable four other ways; the *suite*
            could not fail on it. Remedy required by A-001: a Blake3-isolating negative case that
            goes RED on exactly that mutation.

            **Instance B — S1 (F6-R1).** The shipped seam control runs only `--census`, which
            **returns before either seam is read**, so on the production `--check <label>` path it
            cannot observe `HQ_PREGENERATED_DIR` or `HQ_SEED_TRACKED_WRITE` at all. Remedy
            required by A-001: exercise the production path, and **demonstrate the control RED**
            when the sole production fence at `scripts/check-aiken-vector-gates.sh:9-12` is
            deleted — the reproducer the auditor already froze.

            **Why two instances matter more than two fixes.** One is an incident; two independent
            ones in different families on the same day is a class, and a class recurs into S2
            unless the remedy is generalised. Both remedies share one shape — *make the control
            consume the surface it certifies, then prove it fails when that surface breaks* —
            and that shape is the candidate mechanism if it appears a third time. Per the
            invariants doctrine, the third occurrence should be met with a commissioned
            consolidation rather than a third bespoke fix.

contract:   INHERITED G0 DECODER EVIDENCE — QUALIFIED 2026-08-18, correction is mandatory reading
parties:    M1's G0 corpus (produced the claims), M1.2 and every later consumer (inherited them)
invariant:  a claim inherited as "proven" must remain true for the class it is cited about.
enforced:   BROKEN AND CORRECTED. Two of M1's three headline G0 claims do not hold for the
            malformed protected-array class:
            (a) the `496/496` mutation sweep **did not cover** non-empty malformed protected-array
                elements — the relevant fixtures had EMPTY `b`/`br`/`ba`, and positions were
                hand-written rather than derived from fixture bytes;
            (b) `parity 0 mismatches / cross_decoder_divergence=FALSE` **does not hold** for that
                class: `event_decoder.ak` mapped `Err(_) -> []` on protected arrays, so Aiken
                ACCEPTED bytes the Haskell mirror REJECTS, reaching registration/advance
                witness-state decisions. Chain-state-reachable; verified in source by this desk.
            Append-only correction: `EVIDENCE-CORRECTION-001-inherited-decoder-claims.md`
            sha256 `d2f1977988d438f2eeafa6920f2eff45d837422854b267c2459c32d21e08f735`.
            **Future citations must reference the correction, never the unqualified claims.**
            Activation is NOT invalidated: S0/S1 were accepted on independent evidence and Surface
            B landed nothing. Repair authorized under A-006 as ONE bounded campaign; until an
            auditor-clean gate-green result is accepted and landed, the claims stay qualified.
            WHY IT SURVIVED SO LONG: it was found by a FRESH auditor required to attempt
            falsification — not by the inherited corpus, which had no such control. That is the
            seventh instance of the unfalsified-control class and the most expensive, because this
            one was inherited as settled and forwarded by this desk in an accepted package.

contract:   cursor fidelity (record→cursor projection)
parties:    m12 cursor validator (computes), keripy/KERI watchers (define)
invariant:  cursor(E) equals a correct KERI watcher's conclusion from the same
            evidence set E on all content-derivable rules (superseding,
            next-key commitments, prior-digest chaining, thresholds)
enforced:   NONE — commissioning path: cursor-vs-keripy parity oracle
            (DESIGN-NOTE-001 §7); accepted 2026-08-19

contract:   first-seen non-replication
parties:    m12 cursor validator, Cardano settlement ordering
invariant:  the cursor never resolves competing events by settlement slot;
            where KERI requires witness-local first-seen it ABSTAINS
            (duplicity-detected); slot stored as evidence, never verdict
enforced:   NONE — needs the resolve-by-slot mutant proven to fail the
            abstention assertion; accepted 2026-08-19

contract:   leaf sufficiency (cursor computability)
parties:    m12 record leaf schema (produces), cursor derivation (consumes)
invariant:  the leaf snapshot (keys, next-key digests, witness set,
            thresholds) makes the cursor computable from the tree without
            off-chain re-reads of event bytes
enforced:   NONE — VIOLATED by the S0 skeleton (SAID-only leaf); scheduled
            incident; accepted 2026-08-19

contract:   bytes-derived record key (admission)
parties:    m12 record validator (enforces), event submitters (constrained)
invariant:  the MPF key (location+SAID) is derived from the admitted event
            bytes, never taken from the redeemer; proof used only for
            absence at the derived key
enforced:   NONE — S2 requirement 1 per A-018 §5; accepted 2026-08-19

contract:   gate-receipt candidate identity (CI-S2W-C)
parties:    every slice gate (prints), acceptance chain (verifies)
invariant:  a gate receipt admissible as proof prints head/tree equal to
            the accepted candidate's
enforced:   NONE — audit-2 F2's permanent form; mandatory in future gates

contract:   no proof on dirty trees (CI-S2W-D)
parties:    gate contract legs, commit owners
invariant:  a leg reading git ls-tree HEAD refuses dirty worktrees or
            states which object it certified
enforced:   NONE — F1's invisibility mechanism; mandatory in future gates

contract:   flake inputs for repo-root artifacts (CI-S2W-E)
parties:    offchain flake, repo-root artifact owners
invariant:  repo-root artifacts arrive as declared flake inputs, never
            ../ path literals
enforced:   NONE — advisory A3; hazard with stated limit

contract:   S0 size-report provenance scope ↔ what can actually move a size
parties:    scripts/s0/measure-family.sh (enforces), every S0 family commit
            (constrained), specs/m11-s0-size-failfast/SIZE-REPORT.md (the record)
invariant:  the report's owned-source hash should cover exactly the inputs that
            can change the sizes the report blesses — no more
enforced:   OVER-BROAD, opened 2026-08-24. The hash covers
            onchain/validators/s0_skeleton_tests.ak, a test module proven unable
            to move the sizes: build 4's drift was that file alone and the
            compiled blueprint was byte-identical. Consequence: EVERY future
            test-only commit to this family stales the report and costs one real
            build to re-bless numbers that did not move, because measure and
            verify both run aiken build unconditionally.
            NOT fixed inside the R1 repair, deliberately — narrowing the hash
            while a candidate is failing it re-authors the acceptance criterion
            around that candidate. Separate ticket AFTER R1 lands.
            HONEST LIMIT, carried verbatim into that ticket: a byte-identical
            blueprint proves this file did not affect compiled output FOR THIS
            DIFF. It is not a theorem that a validators/ file never can, and the
            follow-up owes that distinction a real check rather than inheriting
            this inference.

contract:   SIZE-REPORT.md ownership ↔ the frozen gate's append-remeasurement check
parties:    scripts/s0/measure-family.sh (generates and OVERWRITES the file),
            hand-authored accepted contracts (live in the same file),
            r1-event-key-v4.sh check_size_report (consumes the hand-authored half)
invariant:  no acceptance check may require content inside a file that a generator
            in the same pipeline overwrites without emitting it
enforced:   VIOLATED, found 2026-08-24. check_size_report builds
            "R1-APPEND-REMEASURE ... source_blob=<current append blob>" and requires
            it inside SIZE-REPORT.md; the generator emits that string ZERO times.
            Counts verified at the desk: base 1, regenerated 0, generator 0.
            Consequence: the frozen gate is UNSATISFIABLE for any candidate --
            regenerate and check_size_report dies, do not regenerate and the
            measure leg dies on the stale owned-source hash, move the marker to a
            sibling and it dies identically because the check greps only that path.
            Invisible until now because build 4 died at the earlier leg before this
            check ran. Remedy filed as Q-MS12-004: version the gate so the check
            reads the new owning file, prove it can fail in both directions, and
            RETAIN frozen v4 as a defect witness rather than deleting it.
            Related: the desk withdrew its own "a perfect candidate can pass the
            frozen gate" assertion on this evidence.

---

## Added 2026-08-28 by the M1.2 desk (session `keri-m12`, window `m12-desk`)

contract:   #300's accepted requirements ↔ the four A-019 mandates they cite as authority
parties:    `specs/300-projection-fidelity/spec.md` (cites), `.milestones/11/mandates/`
            on the force-pushed `milestones` branch (defines)
invariant:  the four mandate documents a future S2 slice implements are exactly the four
            the spec was audited and accepted against
enforced:   TAG — `refs/tags/ms11/mandates/a-019` (tag object
            `a21c9338528444d7831d55d5043360c3979a6b3a`, dereferences to
            `3653813e1c3f7631c7e8ffb971fd2b194ac1eaf1`). Was `NONE` until 2026-08-28.
            The spec pinned a branch commit while this branch is force-pushed as a fresh
            root on every write, and the four content hashes appear in NO committed file —
            so the desk's own routine sweep would have orphaned an audited deliverable's
            authority. The tag makes the commit permanently reachable. Content hashes,
            full 64 characters, also carried in the tag message:
              R1 93576cd63cb77731313e8b05b0cb31fbd88c3130626b6c0e2be4ee0ce67d7571
              R2 1dcba5d898f840e22cc855c0c459d1ef8be430b438d200c32d4579bea6330187
              R3 986627b726a0948cc06513b46ef6fc19f3fa179903f249301b748abf30a1d882
              R4 a2a945b3292aa4a8f64d1ada6ea617ec914ba394661ee583cb3fccf865aef377
            RESIDUAL: the spec still cites the raw SHA, not the tag name. Carrying the tag
            name inline is assigned to the next slice touching `specs/300-projection-fidelity/`.

contract:   what the CURSOR may conclude ↔ what an off-chain WITNESS may receipt
parties:    `docs/design/record-cursor-projection-fidelity.md` (merged, binds the cursor);
            gist `7615e40319a55b8200b9da5ee2cb0169` "the pen construction" (binds a
            witness daemon's receipting policy)
invariant:  settlement order may never become the cursor's verdict; whether a witness may
            adopt settlement order as its own receipting policy is a separate question,
            and the two documents must not be read as one rule
enforced:   NONE — and the two surfaces were written the same morning (pen enters the gist
            2026-08-19T08:18:08Z, revision `53f6a141e628e0a5b7e42010fcd004b9f42548ed`;
            issue #300 filed 08:54:13Z; PR #301 merged 09:31:36Z) and never reconciled.
            Read as LAYERS they are consistent: the cursor abstains and counts only signed
            receipts; KERI leaves receipting policy to the witness. Read as one rule they
            contradict. An external reviewer hit this on first contact.
            REQUIRED: one sentence in R300-4 stating that pen-produced receipts are
            ordinary receipt evidence and do not constitute the cursor resolving by slot —
            without it, an implementer may reasonably read the pen as R300-4's forbidden
            resolve-by-slot mutant. Same carrier as the residual above.

contract:   the published witnessing story ↔ the design actually in force
parties:    `docs/design/trust-model.md`, `super-watcher.md`, `aid-model.md`,
            `lifecycle-and-bonds.md` (publish), any external reader (consumes)
invariant:  a reader sent to the repository learns the design that is actually in force
enforced:   NONE — every one of those documents was last touched 2026-07-28, before the
            2026-08-18 M1-terminal ruling and the M1.2 decomposition, so they describe the
            SUPERSEDED monolithic design. Worse than stale: `super-watcher.md` and
            `roadmap.md` still use "fully witnessed" as the OLD BINARY conviction
            predicate, while M1.2's three-way receipt GRADING
            (fully-witnessed / partial / bare, never gating, never economic) is explained
            in NO design document — it exists only in the milestone description and in S0
            size-report table rows. There is currently no repository document that answers
            "how does witnessing work here"; the best accounts are two personal gists.

contract:   #271's entitlement mechanism ↔ the m12 escrow that replaced the old family
parties:    #271 (solved it: commit-reveal with marker, nonce, deposit, aging, expiry),
            `m12/escrow.ak` (`EscrowState = {funder, premium, remaining_value, notice_start}`)
invariant:  the premium is payable to a bound payee, so evidence cannot be copied from the
            mempool and the reward redirected
enforced:   NONE — and this is a REGRESSION, not a gap. DESIGN NOTE 002 §2 F-2 reports that
            nothing in the `m12` family or the `s0_` validators mentions payee, commitment,
            nonce or key hash; the transition check only requires that SOME output holds
            `remaining_value - premium`. #271 closed exactly this exposure and the fix was
            not carried into the new family. DN-002 §8 names it "the highest-risk item: a
            solved problem absent from the S2 scope list", because DESIGN NOTE 001 §8's S2
            scope does not mention entitlement at all — so nothing downstream would notice
            its absence. A milestone that decomposes a family must carry the closed
            exposures across, or it silently reopens them.

contract:   what witnesses are FOR ↔ two unreconciled answers
parties:    DESIGN NOTE 002 §6 (witnesses evaporate: "no function witnesses perform that the
            chain does not, for a controller whose consumers read Cardano");
            gist `7615e40319a55b8200b9da5ee2cb0169` "the pen construction" (make Cardano
            itself a witness, so first-seen equals settlement order by construction)
invariant:  the milestone holds ONE answer to what witnessing is for
enforced:   NONE. The two documents answer the same question in opposite directions and
            NEITHER CITES THE OTHER: DN-002 §6 dismisses the witnesses' last residual
            function without considering the pen, and the pen predates it by nine days.
            An external reviewer (2026-08-27) independently asked for the witnessing story
            and got the gists, because no repository document carries it. Note also that
            DN-002 §6's second-order finding — the controller's own witnesses are best
            placed to front-run routine appends, and a flat premium turns them into paid
            dependents — is a NEW argument that bears on the pen, since a pen is a witness
            key by construction.
