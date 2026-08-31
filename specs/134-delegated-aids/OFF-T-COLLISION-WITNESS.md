# Executable witness: a signed `dip` passes the V1 substring type gate

Observed 2026-08-14 against the repository's pinned keripy 1.3.5 fixture
environment, after the required `/nix/store` free-space check reported
65,119,281,152 bytes available. The repository was not modified.

## Generation

Using `nix develop` in `offchain/test/keri-fixtures`, a deterministic loop
derived one current and one next Ed25519 signer per trial from
`Salter(raw=b"0123456789abcdef")`, constructed a genuine
`eventing.delcept(...)`, searched the resulting serialized bytes for `icp`,
then signed the selected event with its current controller key and verified
that signature with keripy.

The first match occurred at deterministic trial 283:

```text
event_type dip
said EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL
raw_len 351
canonical_t_offset 30
collision_off_t 237
collision_context yUoVz0YWjQYDicp_f6h6Xk1dWuI
current_key DGdjpn4Eux10KNiXtV2ReFoMpRvRcfX_LuMa1U946w_j
next_digest EIOyUoVz0YWjQYDicp_f6h6Xk1dWuI30DfuWmjNotom2
controller_signature AAAfKChMXdMiCq86oCPt_IH6dDxj3FqeIMzGJk95CK-3Xb-5Zz97KvdA7dS9Spuji9CG8xhbaCw-ZuP9cm5D0BgG
signature_verified True
raw_sha256 36efe0ac9fb3371804464ca4017dcf5ca1e5a3bd3c91aded682136fbac376c8f
```

The collision is inside the genuine next-key digest at its character offset
15. The actual event is:

```json
{"v":"KERI10JSON00015f_","t":"dip","d":"EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL","i":"EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL","s":"0","kt":"1","k":["DGdjpn4Eux10KNiXtV2ReFoMpRvRcfX_LuMa1U946w_j"],"nt":"1","n":["EIOyUoVz0YWjQYDicp_f6h6Xk1dWuI30DfuWmjNotom2"],"bt":"0","b":[],"c":[],"a":[],"di":"EJS85W7KSMtJamWFRViub4yNhrt6sPd1dKklSIYCN2SE"}
```

Its genuine E2--E9 content offsets use the same 351-byte keripy layout as
the committed `reg_dip` fixture: `off_i=91`, `off_s=142`, `off_kt=151`,
`off_k=[160]`, `off_nt=213`, `off_n=[222]`, `off_bt=275`, `off_b=[]`.
Supplying `off_t=237` makes current `event_binding` find `icp` even though the
canonical type at offset 30 is `dip`. The datum can faithfully project the
event's key state; `di` is not represented or rejected. The hash-proof path
accepts the genuine self-addressing `d`/`i` pair and does not inspect `t`.

This witness proves practical constructibility and a genuine controller
signature. A production-remediation ticket should turn it into full Haskell,
Aiken, and live-boundary failing tests before changing the validator.
