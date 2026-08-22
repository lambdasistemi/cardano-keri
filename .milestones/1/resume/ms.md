# Resume brief — M1 milestone owner

**State: TERMINAL, ruled NO-GO 2026-08-18.** The feasibility programme delivered
both commissioned artifacts and the project owner ruled the current monolithic
checkpoint design **not shippable**. **There is no successor clearance and no
work in flight.** If you have been resurrected, you are not resuming a
programme — you are custodian of a closed result.

## Do not do these

- **Do not grant a cold-build slot.** None is pending; the G0 harness valve is
  fired and **held at project altitude**, not by me — a fifth G0 slot needs a
  redesign decision *and* new authority.
- **Do not treat G0's green results as a shipping signal.** See the asymmetry.
- **Do not re-open G0 to chase the terminal marker.** It is absent for a
  formatter-whitespace harness defect. Buying it adds zero information.
- **No authenticated GitHub mutation. G2 plan-only. Preprod prohibited.**

## The result, in one paragraph

`checkpoint.checkpoint` compiles to **25,934 bytes** before parameter
application — **158.3 % of the 16,384 transaction limit, 160.8 % of the 16,133
reference-program ceiling**. Three more validators sit at 80–92 % before
parameters. This is an **architectural constraint, not a defect a build can
repair.** Separately: G0 proved the INV-BIND defect real and its repair
effective (16/16 RED-unfixed → GREEN-repaired, same gate, never re-versioned);
G1 answered the budget question inside a measured regime (memory breach at 24
keys, ~7-key practical ceiling enforced at premint, proof depth *not* the cost
driver).

**The asymmetry, which is what a later reader will get wrong:** the G0 repair
may be retained and the G1 numbers may guide a redesign, **but neither rescues
the oversized architecture.** Good evidence about a component does not make an
oversized component fit.

## Caveats that must never be dropped when this is retold

Witness frontier **not reached** (24 is a maximum measured, not a bound);
historical-recovery terminal **blocked**; respelling **1 of 4**, cause traced to
fixture provenance rather than a validator defect; depth beyond 5 **extrapolated
from a measured slope**, not generated; coupling an **upper-bound composition**
across two transactions, not a same-AID trace and not a headroom claim; and
script byte lengths under 16,384 **do not prove any transaction fits**.

## Open, and owned elsewhere

- **Vector-check brittleness redesign** — non-realizing, uncommissioned.
  Root cause: the gate's vector checks are regenerate-and-diff against committed
  files (gate lines 139-142), brittle to any drift. Fix = pin/normalize
  formatter output **and** compare generated vectors semantically. Its value is
  that this stops eating slots on G2 and beyond.
- **Wedged process pid 948866**, alive since 2026-08-14, stuck mid `tmux
  send-keys` carrying a 3-day-old pointer to pane `%6501`, which still exists.
  Reported to the machine, **not killed** — no foreign process is signalled.
- **This ledger and the state page are UNPUBLISHED.** Authored, current, and
  blocked on the no-authenticated-GitHub-mutation constraint. **`/tmp` dies with
  the host, so this record is single-copy.** Publishing it is the operator's
  call to release, not mine to assume.

## Operating discipline worth carrying forward

Floors v2: stop **AT** 50.00 GiB; start bar **50.00 + 3.10 × N** — parameterised
because a fixed bar silently changes meaning when lanes multiply. Verify host
idleness by **listing** processes, never `pgrep -c`, which matches your own
shell. Gap reports carry a **timestamp** and never clear a lane in the same
breath; the machine declares its **start time** before collecting. Consume
completion reports — **never infer them from a store delta**.

## Host build-token interlock (passive — binding only if authority is ever granted)

M1 is custodial-terminal and **no build is authorized**. If some future written
authority ever permits a cold realization, this interlock binds *in addition to*
M1's own serialization:

- **Acquire `/tmp/machine/BUILD-TOKEN` atomically with `mkdir` before realizing.**
- **If acquisition fails, another programme is building — wait and re-measure.
  Never proceed.**
- While held, re-measure with `df -B1 --output=avail /nix/store`, never a
  worktree.
- **Release after the command, including on failure. Never remove another
  holder's directory.**
- Invalid store path, unexplained build, **token anomaly**, or floor violation
  is a machine event: stop, report, **never retry**.

Authority: `/tmp/projects/cardano-keri/inbox/NOTE-machine-host-build-token.md`,
sha256 `2f476637ebbbdbc5823266bfc4360189428737727f244de450ac69a025d7e17e`.
It grants **no** implementation, build, GitHub, preprod, mainnet, merge,
deployment, publication, announcement or product authority.
