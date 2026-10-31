Outcome: prove selected security properties about the exact compiled Plutus V3 UPLC that Cardano-KERI actually deploys — not about its Aiken source — and label honestly what each proof does and does not establish.

Observable test: from a fresh checkout, the repository CI command demonstrates that the pinned Aiken build's production blueprint is completely reconciled, the selected P0 security properties execute against the exact compiled UPLC, source-level negative controls make the instrument fail, clean artifact hashes are restored, and the report distinguishes SMT-valid results without proof terms from kernel proofs, tests, unproved claims, and out-of-scope claims.

Artifact: the verification ships as an additive, independently-runnable evidence bundle on the ckeri release line, hash-bound to the exact commit, Aiken toolchain and BuiltinSemanticsVariant it verifies. Milestone 1's close gates on its existence.

Scope: the compiled on-chain programs and the evidence about them. Cryptographic primitives are assumed sound; the cage library's internal correctness, whole-system liveness, and deployed parameter hashes are explicitly out of scope. Production rollout and announcement are separate.

Live state, refreshed daily and on every material transition:
https://github.com/lambdasistemi/cardano-keri/wiki/M8-State
