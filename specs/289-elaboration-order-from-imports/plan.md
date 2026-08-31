# plan — #289

## Base

Branch `fix/289-elaboration-order-from-imports` from `stack/246-590f492b`, an
immutable staging ref pinned to #246's parked candidate
`590f492b928d4a177ac28d5785f0234a3a76078c`. PR base is that staging ref, not
`main`.

Reason: the elaborator, its `offchain/flake.nix` wiring and the entire
re-elaboration apparatus exist only on #246's branch. `main` has none of it, so
`main` is not a tree in which this ticket's subject exists. Ruling
`A-t289-001`.

## Strategy

Replace the ordering mechanism, not the elaboration mechanism. Staging, the
tracked-set fence, the S2 artifact handling, the `.ilean` version and module
identity checks, and the aggregate-root-last rule are all correct and stay
untouched. The single defect is that the compile sequence is produced by `sort`
rather than by the dependency relation the sequence is supposed to respect.

The relation is already present and declared in the sources: each module's
`import KeriBlaster.*` lines. It is read from the staged copies the script has
already made, so the order is derived from the exact bytes about to be
compiled rather than from a second, possibly divergent, read of the source
tree.

## Constraints

- The derivation runs entirely before the first `lean` invocation, so R3/R4
  abort with nothing elaborated.
- Tie-breaking between mutually independent modules must be stated and
  reproducible, so R2 holds without depending on hash or filesystem iteration
  order.
- Diagnostics reuse the established
  `construct=... outcome=COULD-NOT-EVALUATE layer=...` shape. New classes take
  new `layer=` tokens.

## Live boundary

The decisive proof is the flake-owned runner, which performs real Lean
elaboration under nix. Unit-level reasoning about a topological sort cannot
observe the failure this ticket exists to fix: the failure is `S2Cek.olean`
being absent at the moment `lean` runs. The gate therefore executes the runner
and asserts on its output, and does not accept a simulation of it.

## Vacuity hazard — the load-bearing design constraint

The current tracked set is a falsifying case for the ordering bug **only by the
incidental spelling** of `Entitlement`, `Migration`, and `RegisterArity`. A
control written against the real set is green today and would stay green
forever if those modules were renamed or dropped their `S2Cek` import — still
executing, still passing, no longer testing ordering at all.

The ordering control must therefore construct the
dependent-sorts-before-prerequisite situation itself, so that its power to fail
does not depend on a property of the current tracked names. This is the
difference between a control and a coincidence, and it is the reason this
ticket exists at all.

## Slices

One bisect-safe slice, `S1`. The change is a single mechanism plus its proof;
splitting it would leave a commit whose gate cannot pass.

## Risks

- **Pre-existing red in full repo CI at this base.** The base is #246's
  unaudited candidate. A `just ci` failure attributable to #246 is a
  pre-existing baseline condition, not a #289 implementation failure; it is
  escalated, not absorbed.
- **Build cost.** Every runner execution is a real nix realisation. Build events
  are budgeted, journaled, and preflighted from the store subject
  (`df -B1 --output=avail /nix/store`), never a worktree-relative `df`.
