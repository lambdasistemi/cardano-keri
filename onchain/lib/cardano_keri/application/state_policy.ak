//// The state policy of an application, computed on chain.
////
//// ## Responsibility
//// `state_policy` is the script hash of the public `singular_state` validator
//// applied to an application policy: the policy of the registry state token
//// and the credential of the state address (Lean `PublishedRelease.statePolicy`).
////
//// ## Dependencies
//// `aiken/crypto` for BLAKE2b-224.
////
//// ## Assumptions
//// The template is the compiled `singular_state` script up to its parameter,
//// as the pinned compiler's blueprint application lays it out: the script of
//// `singular_state` applied to a 28-byte policy is the template, then the
//// flat-encoded parameter (`1e 58 1c`, the policy bytes, `00`) and the end of
//// the program (`01`). The policy is a 28-byte script hash.
////
//// ## Invariants
//// The result equals the hash `aiken blueprint apply` computes for the same
//// policy; one changed template byte changes it.

use aiken/crypto.{blake2b_224}
use aiken/primitive/bytearray.{concat}
use cardano/assets.{PolicyId}

/// The tag a Plutus V3 script is hashed under.
const plutus_v3_tag: ByteArray = #"03"

/// The flat encoding of the parameter: a byte-string chunk of 30 bytes, which
/// are the CBOR header of a 28-byte byte string and then the policy.
const parameter_head: ByteArray = #"1e581c"

/// The end of the chunks and the filler that ends the flat program.
const program_end: ByteArray = #"0001"

/// The script hash of `singular_state` applied to `application_policy`.
pub fn state_policy(
  template: ByteArray,
  application_policy: PolicyId,
) -> PolicyId {
  blake2b_224(
    concat(
      concat(plutus_v3_tag, template),
      concat(parameter_head, concat(application_policy, program_end)),
    ),
  )
}
