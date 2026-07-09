use aiken/primitive/bytearray
use blake3

fn singleton(byte: Int) -> ByteArray {
  bytearray.push(#"", byte)
}

fn append_byte(out: ByteArray, byte: Int) -> ByteArray {
  bytearray.concat(out, singleton(byte))
}

fn vector_input_go(i: Int, len: Int, out: ByteArray) -> ByteArray {
  if i == len {
    out
  } else {
    vector_input_go(i + 1, len, append_byte(out, i % 251))
  }
}

fn vector_input(len: Int) -> ByteArray {
  vector_input_go(0, len, #"")
}

fn matches_vector(len: Int, expected: ByteArray) -> Bool {
  blake3.hash(vector_input(len)) == expected
}

// Official BLAKE3 test vectors, hash mode. Each expected value is the first
// 32 bytes of the extended output in BLAKE3-team/BLAKE3 test_vectors.json.

test hash_len_0() {
  matches_vector(
    0,
    #"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
  )
}

test hash_len_1() {
  matches_vector(
    1,
    #"2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213",
  )
}

test hash_len_63() {
  matches_vector(
    63,
    #"e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b",
  )
}

test hash_len_64() {
  matches_vector(
    64,
    #"4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98",
  )
}

test hash_len_65() {
  matches_vector(
    65,
    #"de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee",
  )
}

test hash_len_127() {
  matches_vector(
    127,
    #"d81293fda863f008c09e92fc382a81f5a0b4a1251cba1634016a0f86a6bd640d",
  )
}

test hash_len_128() {
  matches_vector(
    128,
    #"f17e570564b26578c33bb7f44643f539624b05df1a76c81f30acd548c44b45ef",
  )
}

test hash_len_1023() {
  matches_vector(
    1023,
    #"10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11",
  )
}

test hash_len_1024() {
  matches_vector(
    1024,
    #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
  )
}

test verify_len_1024() {
  blake3.verify(
    vector_input(1024),
    #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
  )
}

test checkpoint_1024_split_8_then_8() {
  let input = vector_input(1024)
  let first_half = blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let blake3.Checkpoint { chaining_value, offset } = first_half
  offset == 512 && blake3.finish(chaining_value, input, offset) == #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"
}
