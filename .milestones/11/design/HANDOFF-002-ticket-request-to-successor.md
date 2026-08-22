# HANDOFF-002 — operator wants this filed; you'll need authority neither of us currently has

From: parked incumbent `%6695`. To: sitting M1.2 owner `%6656`. 2026-08-19.

**The operator has asked that the design record be pushed to the repository and filed as a ticket.**
I have written the ticket and I have not filed it. Passing it to you with the blocker named, because
you will hit the same one.

## The artifacts

- design record: `design/DESIGN-NOTE-001-record-cursor-projection-fidelity.md`
  sha256 `80feb30fc26b6939e907eed44b38937ebfb7058bdfc7ae5e85a959ce32c15ac2` (you acknowledged it)
- **ticket draft, ready to file verbatim**:
  `design/TICKET-DRAFT-record-cursor-projection-fidelity.md`
  sha256 `4a03a6a93ee9bf74e7c76609bb9728c302e5dda66ae22d4af4ed185d477697f9`

Written for a human reader with the jargon glossed, normative text under **Technical contract**,
and an explicit **Out of scope** so it cannot be read as authorising implementation.

## The blocker, stated plainly

**Neither of us can file it.** RELEASE-015: *"Surface C issue mutations remain PREPARED-INACTIVE
pending independent project acceptance of an exact manifest."* Creating a new issue is an
authenticated GitHub mutation, and no grant covers it — not the S0+S1 release, not RELEASE-006, not
the A-006 repair grant, which is confined to `event_decoder.ak` and named test files.

Pushing the document to the repository is likewise a product-code push, which is withheld outside
Surface B's decoder-only path.

So the honest routing is: **you ask `%6429` for the authority.** Two things worth separating in that
ask, because they have different risk:

1. **landing the document** — additive, no behaviour change, no bearing on the accepted 15-row
   manifest;
2. **filing the ticket** — a new issue outside that manifest, which is exactly what the Surface C
   barrier was drawn around.

The project owner may well grant (1) while holding (2) until the manifest lands. That would be a
coherent ruling and worth offering rather than asking for both as one.

## Why it is worth pressing

Requirements 1 and 2 in the draft say today's skeleton is **unsafe** (submitter-chosen tree key) and
**insufficient** (cursor not computable from the leaf). If you agree, that is **new S2 scope not
written down anywhere** — a plan change, not documentation. It should land as such rather than be
filed beside the plan.

And the record currently lives in `/tmp`, which dies with the host. That is the whole argument for
landing it: an hour of design reasoning is one machine event away from being lost.

## What I am not doing

Not filing, not pushing, not deciding, not directing you. You own whether any of this happens.
