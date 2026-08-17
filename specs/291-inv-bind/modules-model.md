# Modules model

## MOD-291-DECODER-AIKEN — shared on-chain event decoder

Responsibility: totally decode one bounded canonical KERI JSON establishment
event from bytes alone and expose a variant-tagged projection of protected raw
field values plus the structure-derived SAID blanking result.

It owns framing and schema truth. Registration, Advance, enforcement, and
hash-proof must not implement local field-location logic.

Depends on: byte/list primitives only.

## MOD-291-DECODER-HS — Haskell parity decoder

Responsibility: mirror MOD-291-DECODER-AIKEN verdict-for-verdict, feed
off-chain predicate parity, and report keripy corpus/adversarial/mutation
counts.

Depends on: committed keripy oracle fixtures. It does not make fixture offsets
part of a production value.

## MOD-291-REGISTRATION — registration binder

Responsibility change: consume only a decoded `icp` projection and compare its
protected values with the genesis datum before existing signature/quorum and
deposit checks.

Depends on: MOD-291-DECODER-AIKEN.

## MOD-291-ADVANCE — Advance binder

Responsibility change: consume only a decoded `rot` projection and bind all
protected state and witness-delta values before existing authorization and
receipt checks.

Depends on: MOD-291-DECODER-AIKEN.

## MOD-291-ENFORCEMENT — Freeze/Convict binder

Responsibility change: consume only a decoded `rot` projection before creating
`EventEvidence`; retain existing exact-byte signatures and semantic checks.

Depends on: MOD-291-DECODER-AIKEN.

## MOD-291-HASH-PROOF — hash-proof policy

Responsibility change: accept an offset-free redeemer, require a decoded `icp`,
and verify SAID over MOD-291-DECODER-AIKEN's structure-derived blanking result.

Depends on: MOD-291-DECODER-AIKEN and the existing Blake3 verifier.

## MOD-291-WIRE — wire and builder surfaces

Responsibility: encode the four offset-free interfaces once, propagate the
new arities through observers/builders/digests, and own golden ABI evidence.

Depends on: the data types below; never on oracle offsets.

## MOD-291-PROOF — permanent proof families

Responsibility: own the keripy parity corpus, eight RED-first adversarial rows,
framing mutation census, no-offset source/ABI audit, and bounded live-node
rejection with no product-state delta.

Depends on: both decoder modules and existing local devnet infrastructure.

## Direction invariant

Validators and builders depend on the shared decoder/interface owners. Test
oracle metadata may observe decoder results but cannot flow back into
production arguments.

## Output ceiling

This artifact is limited to 85 lines and 7 KiB.
