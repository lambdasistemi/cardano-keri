# Compromise of the current keys

This page answers one question: an attacker holds the identity's **current**
KERI signing keys — not the pre-rotated successor keys — what can they do, on
Cardano and off it, and what does the owner do about it?

It is the counterpart to [Pre-rotation](aid-model.md#pre-rotation). Pre-rotation
is what stops the attacker from taking the identity *forward*. It is not what
stops them from using it *now*.

## What the stolen current keys authorize

| Surface | Attacker can | Attacker cannot |
|---|---|---|
| KERI KEL | Sign an interaction (`ixn`) event and whatever seals it anchors | Rotate — the `n` commitment names successor keys they do not hold |
| Cardano checkpoint | Authorize `Close`: burn the token and send the whole escrow to an address of their choice | Advance the checkpoint — an Advance is a rotation, and the dual threshold rejects them |
| A consuming application | Satisfy any authorization the application resolves against the ACTIVE checkpoint's current weighted key state | Change which keys the checkpoint publishes |

The last row is the one that matters most and is easiest to miss. An
application built on [Value authorization](../architecture/value-auth.md) asks
*"do the current controllers of this AID authorize this operation?"*. Stolen
current keys answer that question correctly. **No KERI event is involved, and
none is needed.**

## An interaction event is an off-chain instrument

An `ixn` changes no key state. Its entire power is what it *anchors* — seals
pointing at TEL events (ACDC issuance and revocation), delegation approvals.
A thief who publishes an `ixn` is issuing or revoking credentials under the
victim's identifier. That harm lands in the credential graph, not on Cardano.

**V1 cardano-keri does not project `ixn` events at all.** Register admits only
`icp`; Advance admits only `rot`; the event decoder rejects every other type.
This is a stated scope decision, not an oversight — see
[#115](https://github.com/lambdasistemi/cardano-keri/issues/115): *an advance
is a rotation by definition; non-establishment events never touch the
checkpoint.*

Two consequences follow, and they point in opposite directions:

- A thief's `ixn` **cannot** advance, arm, freeze, or convict a checkpoint. It
  is invisible to the chain.
- Publishing an `ixn` is therefore **neither necessary nor helpful** for
  on-chain theft. On-chain exposure comes from key-state authority, above. The
  `ixn` is the off-chain instrument and the stolen keys are the on-chain one.

An identity whose Cardano checkpoint is perfectly current can still be having
credentials issued under it by a thief, because that traffic never reaches
Cardano in V1.

## Why we do not replicate first-seen

A KERI witness applies **first-seen**: it accepts the first event it sees at a
sequence number and refuses conflicting ones. So if the thief's `ixn` reaches
the witness threshold before the owner's honest `ixn` at the same sequence, the
thief's event *is* the event. A served KEL is one linear branch, and the
conflict is not in it. The victim's evidence may never reach a watcher at all.

First-seen is a **witness-local observation**. It is not in the events, not in
any proof, and not on Cardano. The target record deliberately does not
reconstruct it, and deliberately does not substitute for it:

- The record keys every event by **location plus SAID**, so two validly-signed
  rivals at one sequence coexist instead of overwriting each other. Duplicity
  becomes a shape in the published data rather than a verdict someone issues.
- For rules that are **derivable from event content** — superseding, next-key
  commitment validity, prior-digest chaining, thresholds — the projection must
  match `keripy` exactly.
- For a contest that KERI could only settle by **witness-local observation** —
  `ixn` against `ixn`, which is symmetric — the projection **abstains** and
  publishes both candidates.
- Cardano's settlement slot is stored as **evidence, never as verdict**.
  Resolving by slot would make the chain the authority and would diverge from
  KERI exactly whenever the thief reached witnesses first and the victim
  reached the chain first.

What the chain adds is not a better tie-break. It is a **censorship-resistant
publication path** for evidence that witnesses would otherwise suppress.

This is why the duplicity fact and the tip are reported separately, and why
neither is a judgement. A consumer cannot demand evidence it does not know
exists, so the permanent duplicity fact is the trigger that makes "show me the
competing branches" an enforceable requirement rather than a hope. Verifying
that a presenter has produced *all* of them needs the record to commit to what
occupies each location, not merely to prove that individual events are present
— an enumeration requirement the current skeleton's running-hash occupancy
does not yet meet.

!!! info "Status"
    The multi-branch record and its cursor are stated as requirements in
    [#300](https://github.com/lambdasistemi/cardano-keri/issues/300) and are
    **not built**. The delivered V1 checkpoint keeps a single tip and admits
    establishment events only. The worked-through reasoning behind the target
    shape is captured in
    [the record/cursor design note](record-cursor-projection-fidelity.md),
    which is evidence rather than a ruling.

One honest limit applies to both KERI and Cardano: **the victim's own event is
what makes the fork visible.** Until the owner publishes a competing event, the
thief's branch is cryptographically indistinguishable from the controller's.
Neither system detects a thief who is alone on the history.

## Rotation is the remedy

A rotation **supersedes** an interaction event at the same sequence, because
it proves possession of pre-committed keys — strictly stronger evidence than
signing with current keys. Descendants of the superseded event die with it.
The attacker cannot answer: revealing next keys reveals **public** halves, which
permits verification, not production.

The asymmetry is exact and worth stating: a rotation supersedes an interaction,
but a non-delegated rotation **cannot** supersede another rotation. Rotation
beats `ixn`; nothing beats a first-seen rotation.

On Cardano the rotation is an ordinary Advance. It installs the new keys, and
any authorization the thief had bound to the previous checkpoint input becomes
invalid — pending authorization does not silently survive a rotation.

Rotation is **not retroactive**:

- a Cardano transaction that already settled under the older ACTIVE checkpoint
  is not reversed;
- a relying party that already accepted a credential anchored by the superseded
  `ixn` loses it when recovery discards that branch; and
- in the target record, *"has this identity ever been duplicitous"* is a
  permanent, unerasable fact. The tip resolves in the ordinary way and the
  chain issues no verdict about the history behind it — it does not pronounce
  an identity recovered. That permanent fact is what tells a consumer there is
  something to ask for: it can then **require the presenter to produce the
  competing branches** and judge them under its own policy. Which policy is
  deliberately left to that consumer.

**Operator rule: when in doubt, rotate — never interact.** Rotation supersedes;
interaction contests. A controller who always rotates can never create the
unresolvable case themselves.

## If the successor keys are gone too

If the next keys are unavailable, rotation is closed and the only remaining
instrument is a **deliberate conflicting event** — poisoning the identity so
that careful consumers refuse it. It needs only current keys, which is exactly
the material still held when pre-rotation has failed.

This is not a new primitive. KERI already concludes *duplicitous ⇒ untrusted*.
What the chain contributes is publication that witnesses cannot suppress.

Its strength is a function of the grade policy consumers adopt: if the thief's
branch is fully witnessed and the poison event is bare, a grade-weighting
consumer may discount it. That policy is not settled.

## Related pages

- [AID cryptographic model](aid-model.md) — pre-rotation and event binding
- [Trust model](trust-model.md) — residuals, including current-key theft
- [Value authorization](../architecture/value-auth.md) — what an application
  must check
- [Lifecycle and the two bonds](../architecture/lifecycle-and-bonds.md)
- [Convicting a witnessed fork](../user/conviction.md)
