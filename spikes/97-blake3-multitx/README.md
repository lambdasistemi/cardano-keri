# Spike #97 - checkpointed single-chunk BLAKE3

This standalone Aiken spike carries the optimized single-chunk BLAKE3 hash-mode
core from spike 88 and adds checkpoint helpers for issue 97.

The public chaining-value wire representation is 32 bytes: eight BLAKE3 u32
chaining-value words encoded little-endian and concatenated in word order
`h0..h7`. This is the same word byte order used by BLAKE3 digest output.
