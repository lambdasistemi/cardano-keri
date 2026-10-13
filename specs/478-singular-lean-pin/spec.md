# #478: pinned Singular Lean dependency

As a Cardano KERI model contributor, I can import the public Singular library
at `f844a8f423eaf65009c587b9d7dd9ad3e00d21af`, prove a fact over its actual
`RegistryState`, `Request` and `step`, and build both KERI libraries and the
full Singular root under Lean 4.27.0 from a clean checkout.

Acceptance requires an immutable Lake lock, compiler/source receipts, an
executable public proposition and wrong-result control, and the same check in
local Nix checks and hosted CI. Missing or invalid dependencies must fail.
KERI's model is frozen at `99bc98c085d6968da501e0cc86595759bf74450c`.
This is code-the-design rung 0 plus these dependency/proposition controls.

No lifecycle migration, changed KERI propositions, new axioms, deployment,
merge or release. Compilation proves no correspondence and discharges none
of #437/#438/#439/#468. #446 and draft #447 retain their v0.6.1 evidence;
owner disposition remains required before acceptance of this successor.
