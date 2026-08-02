# Frozen `ckeri-follower` capability inventory

This is the retirement inventory required by parent NOTE-001. It was recovered
from `offchain/indexer/Cardano/KERI/Indexer/Shell.hs` at base commit `8153606`:

- Git blob: `43ee97565a94ececdc0d9284134f756a0b26d623`
- source SHA-256: `c19e52276f7f51f2c5a13f832ce7f23a43f631313643626a92465e31dd62cda8`
- authoritative declaration: `verbNames` and `parseCommand`, source lines
  109–138 in that blob

| inherited verb | fork dispatch | classification | production boundary |
|---|---|---|---|
| `status` | zero positional arguments | capability — retain | `ckeri status`; the production source/freshness/checkpoint/watchability envelope replaces the follower-progress rendering |
| `list` | zero positional arguments | capability — retain | `ckeri list` through the selected typed backend |
| `checkpoint <aid>` | one positional argument | capability — retain | `ckeri checkpoint` with a validated AID through the selected typed backend |
| `payer <address>` | one positional argument | capability — retain | `ckeri payer` with a validated address through the selected typed backend |
| `help` | zero positional arguments | REPL affordance — exclude | no top-level `help` command; standard CLI `--help` remains |
| `quit` | zero positional arguments | REPL affordance — exclude | no top-level command |

The invariant is capability, not byte-for-byte shell compatibility. Production
commands use opt-env-conf configuration, typed results, stable renderers, source
and freshness where the operation can supply them, and named
`UnsupportedCapability` errors where a selected backend cannot answer. They do
not inherit the prompt, completion, in-process history, progress loop, or the
fork's ad-hoc output. `--backend` is new in #177 and is outside both inherited
halves.

Acceptance has two independent, mutation-proven halves:

1. **No loss:** disconnect any retained verb from packaged `ckeri`; the focused
   capability gate fails.
2. **No leak:** add `help`, `quit`, or a forbidden REPL marker to packaged
   `ckeri`; the separate surface gate fails.
