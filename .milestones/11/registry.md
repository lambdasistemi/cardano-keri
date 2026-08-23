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
