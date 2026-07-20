//// Append-only registration-registry primitives (#116 S3).

use aiken/builtin.{blake2b_256}
use aiken/cbor
use aiken/merkle_patricia_forestry.{Proof, empty, from_root, insert, root}
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference}

pub type RegistryDatumV1 {
  root: ByteArray,
}

const registry_thread_domain: ByteArray =
  "cardano-keri/checkpoint/registry-thread/v1"

pub const registered_marker: ByteArray =
  #"13506209dad003c83b1b6828034166a601500d6c09d622e3196ba78725f1d8ce"

pub fn registry_thread_name(seed: OutputReference) -> ByteArray {
  registry_thread_domain
    |> bytearray.concat(cbor.serialise(seed))
    |> blake2b_256
}

pub fn empty_root() -> ByteArray {
  root(empty)
}

pub fn insert_registered(
  old_root: ByteArray,
  key: ByteArray,
  proof: Proof,
) -> ByteArray {
  insert(from_root(old_root), key, registered_marker, proof) |> root
}
