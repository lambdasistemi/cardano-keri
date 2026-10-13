# Plan

One vertical dependency slice: add the exact Git requirement and lock; import
Singular through a small KERI binding module; use a dedicated Lean Nix flake
with the upstream compiler pin, avoiding the existing offchain Lean 4.24.0
package. A sandboxed check and runnable app share one script, build all three
libraries without cached build products, and retain logs and identities.

Given any Singular registry state, when `step` receives the canonical
`updateActive` request, then it returns `edge-inadmissible`. This follows the
pinned `allowed`, `canonicalRequest`, `refusal`, and `step` definitions before
any approval lookup. The theorem quantifies every registry state. Guards
exercise the real API with a concrete empty state; wrong-result and
wrong-action controls must fail at that same boundary. Axiom inspection must
report only the upstream step dependencies `propext` and `Quot.sound` for
this binding and reject an injected unproved proof. KERI's existing theorem
trust gate remains required with its inventory and policy preserved.

Risks: Lake Git resolution in a networkless sandbox, stale package products,
compiler mismatch, and proof producers that silently skip. Keep source and
lock validation separate from behavior controls. No live boundary is claimed:
this slice only checks model-library consumption. Strict docs build and links,
script/Nix lint, relevant Lean gates and the native aggregate precede push.

Solo plan review: matches #478 and brief; scope and proof boundary are explicit;
no independent audit or product acceptance is claimed.
