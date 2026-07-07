use cardano_keri/base64url

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

// url-safe alphabet: '-' (index 62) and '_' (index 63)
// 0xfbefbe = 11111011 11101111 10111110 → groups 111110 111110 111110 111110 → all 62 → "----"
test encode_url_safe_dash() {
  base64url.encode(#"fbefbe") == "----"
}

// 0xffffff = 11111111 11111111 11111111 → groups 111111 111111 111111 111111 → all 63 → "____"
test encode_url_safe_underscore() {
  base64url.encode(#"ffffff") == "____"
}
