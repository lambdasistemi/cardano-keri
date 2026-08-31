# Delegated AIDs — the feasibility record (#134, milestone M7)

What it would take for Cardano to verify KERI delegated identities, including
GLEIF's production issuer chain. Evidence for milestone **M7 — delegated AIDs
(the GLEIF issuer chain)**; epic is [#134][134].

## Provenance

| | |
| --- | --- |
| Evaluated | 2026-08-14 |
| Sealed commit | `ae99e35e6aee577ccfc61a62f8a72f6067c1154b` |
| Lane | one independent evaluation lane, deliberately blind to a parallel research lane |
| Repository edits during evaluation | none |

Every load-bearing code site named in the report was re-checked against
`origin/main` at `77e392d` before this record landed and was found byte-identical,
so the findings describe current `main`, not only the sealed commit.

## Files

| File | What it is |
| --- | --- |
| `opus-feasibility-report.md` | The full evaluation: acceptance predicates, architecture comparison, threat model, transaction counts, costs, probability bands, spikes, and a claim ledger naming every source |
| `OFF-T-COLLISION-WITNESS.md` | Executable witness — a genuine signed delegated inception that passes the registration path's type gate |
| `OFF-T-COLLISION-DIP-DRT-WITNESS.md` | Executable witness — its genuine signed delegated rotation, passing the advance path's type gate |

Both witnesses were produced in the pinned keripy 1.3.5 fixture environment and
independently re-verified: digests re-derived with `b3sum`, Ed25519 signatures
re-checked outside keripy, every field offset confirmed, and the pre-rotation
commitment between the two events re-computed.

## How to read the numbers

The report labels every quantity `MEASURED`, `REPRODUCED`, `BOUND`, `ESTIMATE`,
`INFERENCE`, or `UNKNOWN`, and keeps a register of eight named unknowns rather
than averaging them away. Section 11 states exactly which claims are measurement
and which are analysis. Four probability bands are given, not one number.

## The findings, in one screen

1. **The event-type boundary is not closed.** The checkpoint decides what kind
   of KERI event it is reading from three bytes at a position the submitter
   chooses. A delegated inception registers as independent, and a delegated
   rotation advances with no parent approval. Live in preprod-deployed code, and
   **not delegation work** — tracked as [#291][291] in M1. Every M7 estimate is
   conditioned on it being fixed first.
2. **Reading the ancestry directly cannot work.** Recording each parent approval
   once, as its own on-chain fact, turns unbounded recursion into ordinary
   induction. [#292][292].
3. **The real GLEIF Root does not fit our hashing path** — 1,181 bytes against a
   1,024-byte ceiling, measured live. GLEIF External clears it by seven bytes.
   [#295][295].
4. **Every approval GLEIF publishes lives in an event type the checkpoint never
   reads**, and those are only provable until the parent next rotates.
   [#294][294], with the deadline removed by [#293][293].
5. **Delegation buys no revocation.** There is no way for a parent to withdraw a
   delegation in KERI. That is a credential-and-registry fact, not a key-log
   fact, and must be said wherever the feature is announced.

Two corrections to standing beliefs also came out of it: the headroom gate
measures against a stale memory budget ([#296][296]), and an abandoned identity
cannot currently be represented at all ([#297][297]).

## Sources

Primary sources are cited with stable identifiers in the report's claim ledger:
the ToIP KERI specification v1.1 (DOI `10.5281/zenodo.18887102`), keripy at a
named commit, GLEIF's own operational configuration repositories, live
production KELs fetched from a GLEIF witness, this repository at the sealed
commit, and live mainnet protocol parameters. Reproduction commands are included
so any measurement can be re-run independently.

[134]: https://github.com/lambdasistemi/cardano-keri/issues/134
[291]: https://github.com/lambdasistemi/cardano-keri/issues/291
[292]: https://github.com/lambdasistemi/cardano-keri/issues/292
[293]: https://github.com/lambdasistemi/cardano-keri/issues/293
[294]: https://github.com/lambdasistemi/cardano-keri/issues/294
[295]: https://github.com/lambdasistemi/cardano-keri/issues/295
[296]: https://github.com/lambdasistemi/cardano-keri/issues/296
[297]: https://github.com/lambdasistemi/cardano-keri/issues/297
