# Data model

## DM-280-ENV — E2E commitment deployment

The checkpoint devnet environment retains the applied commitment family and
the script identity/material required to create and spend authentic #271
outputs. Its family is the same family already applied to the enforcement and
entitlement observers.

Invariant references: INV-280-LIVE-OPEN, INV-280-BINDING.

## DM-280-RESERVATION — Live enforcement reservation

One reservation relates:

- the exact checkpoint output reference being settled;
- one `Freeze` or `Convict` action;
- the complete actual enforcement evidence digest;
- one fixed beneficiary key hash;
- one hidden nonce shared only by opening and reveal;
- the opening validity upper slot, eligibility slot, and expiry slot;
- the resolved on-chain output carrying the marker, inline datum, and deposit.

The reservation is authentic only when its observed value and credential match
the production commitment family. A negative evidence row gets its own bound
reservation so its rejection remains attributable to enforcement evidence,
not to an unrelated entitlement mismatch.

Invariant references: INV-280-LIVE-OPEN, INV-280-BINDING, INV-280-MATURE.

## Output ceiling

This artifact is limited to 60 lines and 5 KiB.
