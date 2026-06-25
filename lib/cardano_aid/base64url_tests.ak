use cardano_aid/base64url

// RFC 4648 §5 test vectors

test encode_empty() {
  base64url.encode("") == ""
}

test encode_f() {
  base64url.encode("f") == "Zg"
}

test encode_fo() {
  base64url.encode("fo") == "Zm8"
}

test encode_foo() {
  base64url.encode("foo") == "Zm9v"
}

test encode_foobar() {
  base64url.encode("foobar") == "Zm9vYmFy"
}

// 32 zero bytes (e.g., a blake2b_256 output): every 6-bit group is 0 → all 'A'
test encode_32_zeros() {
  base64url.encode(
    #"0000000000000000000000000000000000000000000000000000000000000000",
  ) == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}
