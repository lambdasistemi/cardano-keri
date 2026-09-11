# DESIGN NOTE 002 — enforcement economics of the record/cursor model

**Source:** design session, 2026-08-28. Successor to
[DESIGN NOTE 001](record-cursor-projection-fidelity.md), whose §3 and §6 this note assumes.
**Status: CAPTURED EVIDENCE, NOT A RULING.** Nothing here is decided. Written for the
milestone owner to accept, amend or discard. Conclusions reached in session are marked
**[settled in discussion]**; everything else is **[OPEN]**.

Every claim is tagged **[fixable]** — the current rule is wrong and a different rule works —
or **[structural]** — no mechanism achieves it and the goal must absorb the limit.

---

## 0. Agreed frame

The six statements below were put to the project owner and accepted without exception on
2026-08-28. Everything later in this note is subordinate to them: where a detail conflicts with
§0, §0 wins.

1. **The chain holds an evidence set, not a KEL.** Every validly-signed event, all branches,
   append-only. A KEL is first-seen filtered; this is deliberately unfiltered, so duplicity is
   visible in the data instead of suppressed.
2. **The chain never rules.** It matches `keripy` exactly on content-derivable rules and abstains
   wherever KERI would need first-seen observation. Consumers decide, through predicates.
3. **Witnesses become optional.** The chain provides availability; abstention removes their
   ordering role. They survive only as an evidence-quality signal on identities that keep them.
4. **The money is an alarm the controller buys on themselves.** A standing bounty: whoever reports
   that the controller's keys are being used without them gets paid. Priced by what the append adds
   to the record — occupancy and event type — never by witness grade, never by a verdict.
5. **The product is notification, not remedy.** One place to look, complete over the record.
   Recovery remains pre-rotation; when pre-rotation is gone, the kill switch is what is left.
6. **Four things the system will never do:** pay for promptness, prove an indexer is serving,
   distinguish victim from thief, or make the victim know without something off-chain watching.

[settled in discussion]

---

## 1. What the escrow is

The escrow is not a bond at risk and not a fee pot. It is a **standing bounty for being
notified**. [settled in discussion]

In the ordinary case the controller publishes their own events and consumes their own escrow;
net cost is transaction fees. Value leaves the escrow only when a stranger publishes something
the controller had not, which is the service being bought. The premium the controller posts is
public, so a consumer can read it as a self-declared measure of how seriously that identity
treats its own key custody. Consumer predicates may require a minimum standing bounty.

This reframing removes the objection that the design makes a compromised identity fund its own
enforcement. It does — deliberately — because that is the product.

### Why KERI cannot buy this

Per `docs/keri-primer.md`, watchers are run by **verifiers**. No KERI role faces the controller,
so KERI has no controller-facing alarm at any price. What reaches a KERI controller is indirect:
their witnesses already receipted the thief's event at seq N, so the controller's own event is
refused a receipt. That signal arrives only at the controller's *next action*, and only if the
thief used the same witness set.

The chain's advantage over polling witnesses is **completeness, not cost**. KERI monitoring is a
search over an open set of witness pools that can never be proven exhaustive. The record is a
lookup on a closed one: exactly one place a fork can be recorded, readable by anyone.

## 2. Fixable defects in the current skeleton

- **F-1 Premium gated on `FullyWitnessed`.** `m12/escrow.ak` pays `Service` only when
  `grade == FullyWitnessed`. The fork-revealer's event is bare *by construction* — witnesses
  first-seen-suppress the second event at a sequence, which is their job. The append most worth
  paying for can never qualify, while routine relay of an event that was going to arrive anyway
  collects the premium. **[fixable]**

- **F-2 The premium has no payee.** `EscrowState` is `{funder, premium, remaining_value,
  notice_start}`. `validate_escrow_transition` checks only that *some* output holds at least
  `remaining_value - premium`; nothing binds who takes it. There is no occurrence of payee,
  commitment, nonce or key hash anywhere in the `m12` family or the `s0_` validators. This is the
  #271 exposure returning — evidence is copied from the mempool and the premium redirected.
  #271 closed it with commit-reveal (marker, nonce, deposit, aging, expiry); that work must be
  carried into the new family. DESIGN NOTE 001 §8's S2 scope list does not mention entitlement.
  **[fixable, but at risk of being dropped]**

- **F-3 Paying the second arrival rewards withholding.** If an append into an occupied slot pays
  more than one into an empty slot, holding an event and waiting has option value: publish now at
  the participation rate, or sit on it hoping a conflict appears. The larger the premium, the
  stronger the incentive to delay ordinary publication — so the premium taxes the participation it
  is meant to fund. Two holders of the same pair produce a standoff.
  **Fix: pay the pair, not the second arrival.** Record the first publisher's payee in the leaf;
  when a conflicting sibling lands at the same location, both leaves pay. Being first then costs
  nothing and withholding earns nothing. **[fixable]** [settled in discussion]

- **F-4 Leaf insufficiency is the indexer's economics.** DESIGN NOTE 001 §2 already flags that the
  skeleton stores only the SAID as the value, so the cursor is not computable from the tree without
  re-reading every event off-chain. This is not only a correctness item. It is what decides whether
  an indexer is a cheap name-resolution service (AID → UTxO, given away freely at Koios scale) or
  an expensive state-derivation service with no revenue. **[fixable]**

- **F-5 Submitter-chosen slot.** DESIGN NOTE 001 §2: the append key comes from the redeemer. It must
  be derived from the event bytes — location from parsed sequence and prior digest, SAID from
  content — with the MPF proof used only to prove absence at the derived key. **[fixable]**

## 3. Grade versus occupancy

Two different questions are currently answered by one field.

| Question | Who asks it | Correct input |
|---|---|---|
| How much should I believe this event? | consumer | `grade` |
| How much was it worth having this published? | escrow | slot occupancy + event type |

`grade` is **controller-dependent**: a GLEIF-style identity keeps a witness set and its events carry
real grades; an identity that publishes to Cardano *instead of* running witnesses has every event
bare and a constant-zero grade. Optional is acceptable for a consumer signal. It is fatal as a
payment gate — a witness-free identity could never pay a premium to anyone, switching off the entire
incentive layer, fork bounty included, for exactly the identities that depend on the chain most.

Occupancy has no such dependency. Every identity has slots. **[settled in discussion]**

## 4. The four rungs — a classification first, a price schedule second

Slot occupancy and event type are content-derivable, so classifying by them never requires the chain
to rule on which branch is honest. Pricing the *shape* of an append is not resolving the conflict —
which is what makes a bounty compatible with §6's abstention.

The same classification does two jobs. It prices appends for the escrow, and it tells a consumer
which forks are fatal and which are noise. State it as a taxonomy and derive the price schedule from
it, not the other way round. **[settled in discussion]**

| Rung | Shape | Rationale |
|---|---|---|
| 1 | empty slot | participation; the ordinary case |
| 2 | `rot` over `ixn` at the same seq | supersession resolves it by content rule; cursor `forked-recovered`; the record self-heals, so cheap |
| 3 | `ixn` vs `ixn` | symmetric, unresolvable, `duplicity-detected` |
| 4 | `rot` vs `rot` | both events prove possession of the same pre-committed next keys, so the pre-rotation secret itself leaked — the victim has no recovery instrument left |

Rung 4 is the case the M1 trust model explicitly deferred as "next-key theft … outside the current
protocol." It is as derivable as the others and arguably deserves the top price. **[OPEN: whether
rung 4 is priced separately, and the magnitudes.]**

## 4b. Type the duplicity flag by rung

DESIGN NOTE 001 §4 reports two facts: *ever duplicitous* (permanent, unerasable) and *current tip
state*. It files a rung-2 supersession under the first, so a consumer has to *forgive* the flag —
§4's own "a pragmatic one accepts an identity that has since demonstrated pre-rotation control."

That conflates two different objects. A fork the content rules resolve is not the same as one they
cannot. Type the flag by rung instead:

| Level | Set by | How a consumer should read it |
|---|---|---|
| never contested | — | no information |
| **contested and resolved** | rung 2 | the controller was attacked, still held their pre-rotated keys, and used them — demonstrated key hygiene, proven in public. Arguably *better* than an identity never tested |
| **unresolvably duplicitous** | rungs 3, 4 | fatal; grade is irrelevant, two signatures exist that cannot both be legitimate |

Consequences:

- The default consumer policy stops being a research problem. It is roughly *tolerate rung 2, refuse
  rungs 3 and 4*; everything beyond that is a relying party's own risk appetite. This closes the
  gap that S0-M07's "expose no always-true default" otherwise leaves open. **[fixable]**
- A survivable current-key compromise no longer downgrades an honest controller. **[fixable]**
- **Requirement:** the unresolvable level must be derived **ungraded, over the whole record**. If a
  consumer policy could filter bare branches before that level is computed, the §3 kill switch leaks
  — the victim's poison is bare by construction. This is the same shape as §4's existing hard
  requirement that the cursor be whole-record rather than tip-derived. **[fixable]**

## 5. Structural limits — the goal must absorb these

- **S-1 Promptness cannot be paid for.** When the thief holds only current keys, the victim's
  recovery window is a race and speed is worth far more than the fact. But §6 forbids replicating
  first-seen, and the chain has no reference clock for "when could you have published this."
  A finder who waits a week collects the same as one who publishes in a minute. The principle that
  keeps the projection honest is the same one that makes timeliness unpayable. **[structural]**

- **S-2 Indexer service cannot be proven.** No chain observes endpoint liveness. The usual
  storage-proof proxy fails here because the data is already on chain, so an indexer can answer any
  challenge by fetching on demand — holding it is not scarce. The lever is not payment; it is F-4,
  making the work small enough that nobody needs paying. **[structural]**

- **S-3 Victim and thief are indistinguishable** when both hold the same key material. DESIGN NOTE
  001 §5 already concedes this: heirship is decided out of band and the chain projects that decision
  rather than originating it. **[structural]**

- **S-4 Publication is not notification.** The chain can make a fork public; it cannot make the
  victim know. Something off-chain must watch the record on the controller's behalf — an hourly
  check is cheap and, unlike KERI polling, complete over the record. But it is complete over the
  *record*, not over reality: a fork nobody appended is invisible to it.
  **Therefore the notification guarantee and the append bounty are one mechanism, not two.**
  **[structural, and it is why §2's premium work is load-bearing for the security goal]**

## 6. Consequences of witnesses evaporating

If the KEL is served by Cardano, witnesses lose their availability role; §6 already removed their
ordering role by abstaining on first-seen rather than resolving. They survive only as a `grade`
input, per §3 above.

One residual function was considered and dismissed. Witnesses *prevent*: first-seen means a thief
holding only current keys cannot get a fork receipted, so the branch is stillborn and the controller
carries on clean. The chain prevents nothing — it records both branches. That looked like a
permanent reputational cost the chain imposes and witnesses avoid, i.e. witnesses as a reputation
shield rather than a truth mechanism.

§4b removes it. Once the flag is typed by rung, surviving a current-key theft costs the controller
nothing and reads as positive evidence. There is then **no function witnesses perform that the chain
does not, for a controller whose consumers read Cardano.** A controller wants witnesses only when
they know their consumers will disregard the chain. **[settled in discussion]**

Second-order effect not yet worked through: the parties best placed to front-run the controller on
ordinary appends are the controller's own witnesses, since they receive every event first by
construction. Under a flat premium they can harvest the routine stream, which finally gives them a
stake in the Cardano layer but also rebuilds them as paid dependents of the controller — precisely
the relationship that makes reporting that controller's fork unattractive.

**Candidate lever:** make empty-slot appends payable only to a controller-designated payee while
occupied-slot appends stay open to anyone. Costs some liveness on routine projection; keeps the fork
bounty uncontaminated. **[OPEN — a trade, not an answer]**

## 7. Carried forward from DESIGN NOTE 001, unresolved

- §3's kill switch can be **out-graded**. If the attacker's branch is fully witnessed and the
  victim's poison is bare, a grade-weighting consumer discounts the poison. The witness set is
  designated by the controller in the accepted rotation — which may be the thief's. The kill switch
  is strongest against a sloppy attacker and weakest against a competent one. **[OPEN in §3;
  unchanged]**

- Escrow **starvation**. If only the controller can refill, a thief who has taken the identity stops
  topping it up and closes the publication path §3 depends on. Session position: any party may
  refill, which resolves it — **[settled in discussion]**, but it should be stated as a requirement
  rather than left implicit, since `EscrowState.funder` currently names a single funder.

## 8. Where this lands

- **F-2** is the highest-risk item: a solved problem (#271) absent from the S2 scope list.
- **F-4** connects DESIGN NOTE 001 §2's leaf-sufficiency item to the indexer economics; it is one
  decision serving two goals.
- **F-1 / F-3 / §4** together constitute the enforcement-pricing rewrite.
- **S-1 … S-4** should be recorded as declared limits in user-facing docs, in the same spirit as
  §6's "a declared limit of the projection, not a failure."
