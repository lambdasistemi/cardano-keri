# Rebased Variant-E baseline reconciliation

This table reconciles the accepted prior baseline to the complete current
compiled blueprint. The prior input is
`evidence/accepted-manifest-9a45919.json` (SHA-256
`a0724537b2dc316f6fa2bc11c76be7d3448dde1e5f4fbbaf400bda1175426abb`):
23 titles and 8 distinct programs at commit
`9a45919e34b669c7405fe7c0858e4f097420d03d`. The current side was extracted
from the source-built `e2eWiring.blueprint` during Slice D building event 1:
32 titles, 11 distinct programs, blueprint SHA-256
`bb63130026f90b4b7d67889841e104d0c59cedb5d86e7d23c5786999caaaa079`.

`carried` means the title and compiled program hash are unchanged. `changed`
means a prior title remains but its compiled program hash changed. `added`
means the title was absent from the prior 23-title inventory; an em dash is
therefore the only truthful prior hash.

| Validator title | Prior program SHA-256 | Current compiled-code SHA-256 | Disposition | Reconciliation |
|---|---|---|---|---|
| `bounty_commitment.bounty_commitment.mint` | — | `6fe39761ec695ea81628416d1302a86e6476cb9c2f8fe757441dcc87296fa60c` | added | New bounty-commitment program; 1 parameter. |
| `bounty_commitment.bounty_commitment.spend` | — | `6fe39761ec695ea81628416d1302a86e6476cb9c2f8fe757441dcc87296fa60c` | added | New bounty-commitment program; 1 parameter. |
| `bounty_commitment.bounty_commitment.else` | — | `6fe39761ec695ea81628416d1302a86e6476cb9c2f8fe757441dcc87296fa60c` | added | New bounty-commitment program; 1 parameter. |
| `cage.mpfCage.mint` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | carried | Program and 2-parameter signature unchanged. |
| `cage.mpfCage.spend` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | carried | Program and 2-parameter signature unchanged. |
| `cage.mpfCage.else` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | `7c9f4fe644a8627af28396f89214e3cabeab326eb5373caff6cae70264e27f79` | carried | Program and 2-parameter signature unchanged. |
| `checkpoint.checkpoint.mint` | `1e6359e69ccc517e5446370d448b3d0d5a7b86d49c4785f49cf90835f6f2ff52` | `fc58197eda8c92c2cf647d814b8804d0aef6d7ce3fbdfdf5ab95ac5c3708375b` | changed | Program changed with parameter count 6 to 7. |
| `checkpoint.checkpoint.spend` | `1e6359e69ccc517e5446370d448b3d0d5a7b86d49c4785f49cf90835f6f2ff52` | `fc58197eda8c92c2cf647d814b8804d0aef6d7ce3fbdfdf5ab95ac5c3708375b` | changed | Program changed with parameter count 6 to 7. |
| `checkpoint.checkpoint.else` | `1e6359e69ccc517e5446370d448b3d0d5a7b86d49c4785f49cf90835f6f2ff52` | `fc58197eda8c92c2cf647d814b8804d0aef6d7ce3fbdfdf5ab95ac5c3708375b` | changed | Program changed with parameter count 6 to 7. |
| `checkpoint_observer.observer_advance.withdraw` | `00c2897c2830add9413a2fefd0a5896402052e1cfc3420e7498d7148d56416a2` | `bcda14c5f061045a93cb9e8bcc8ac4a5284a36e44bdf15b3f446b0e2fc464783` | changed | Program changed; parameter count remains 1. |
| `checkpoint_observer.observer_advance.publish` | `00c2897c2830add9413a2fefd0a5896402052e1cfc3420e7498d7148d56416a2` | `bcda14c5f061045a93cb9e8bcc8ac4a5284a36e44bdf15b3f446b0e2fc464783` | changed | Program changed; parameter count remains 1. |
| `checkpoint_observer.observer_advance.else` | `00c2897c2830add9413a2fefd0a5896402052e1cfc3420e7498d7148d56416a2` | `bcda14c5f061045a93cb9e8bcc8ac4a5284a36e44bdf15b3f446b0e2fc464783` | changed | Program changed; parameter count remains 1. |
| `checkpoint_observer.observer_enforcement.withdraw` | `bddd7aa51c53f37e6d303eb919c45baa6e6da07a6a95cb9c4a2cfbfa156ae0bc` | `b95291a608eded4c05991e19c7e81221d613deaf8370bae5cdd04ed374fb1f6a` | changed | Program changed with parameter count 1 to 2. |
| `checkpoint_observer.observer_enforcement.publish` | `bddd7aa51c53f37e6d303eb919c45baa6e6da07a6a95cb9c4a2cfbfa156ae0bc` | `b95291a608eded4c05991e19c7e81221d613deaf8370bae5cdd04ed374fb1f6a` | changed | Program changed with parameter count 1 to 2. |
| `checkpoint_observer.observer_enforcement.else` | `bddd7aa51c53f37e6d303eb919c45baa6e6da07a6a95cb9c4a2cfbfa156ae0bc` | `b95291a608eded4c05991e19c7e81221d613deaf8370bae5cdd04ed374fb1f6a` | changed | Program changed with parameter count 1 to 2. |
| `checkpoint_observer.observer_entitlement.withdraw` | — | `9942119d8ce0c2ea82d5291b39c70308bbc45ec7188c71210bf027d49695a576` | added | New entitlement-observer program; 2 parameters. |
| `checkpoint_observer.observer_entitlement.publish` | — | `9942119d8ce0c2ea82d5291b39c70308bbc45ec7188c71210bf027d49695a576` | added | New entitlement-observer program; 2 parameters. |
| `checkpoint_observer.observer_entitlement.else` | — | `9942119d8ce0c2ea82d5291b39c70308bbc45ec7188c71210bf027d49695a576` | added | New entitlement-observer program; 2 parameters. |
| `checkpoint_observer.observer_lifecycle.withdraw` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | carried | Program and 3-parameter signature unchanged. |
| `checkpoint_observer.observer_lifecycle.publish` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | carried | Program and 3-parameter signature unchanged. |
| `checkpoint_observer.observer_lifecycle.else` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | `8b20d65a45e785e06b753c8e430c41db1ecc43e338c137ef3839da8a744dcd90` | carried | Program and 3-parameter signature unchanged. |
| `checkpoint_observer.observer_migration.withdraw` | — | `e749908308e110dff22752d787c8942419c380e0a188953b21160c4529b343ce` | added | New migration-observer program; 1 parameter. |
| `checkpoint_observer.observer_migration.publish` | — | `e749908308e110dff22752d787c8942419c380e0a188953b21160c4529b343ce` | added | New migration-observer program; 1 parameter. |
| `checkpoint_observer.observer_migration.else` | — | `e749908308e110dff22752d787c8942419c380e0a188953b21160c4529b343ce` | added | New migration-observer program; 1 parameter. |
| `checkpoint_register.checkpoint_register.mint` | `8f91d90f70f551dcd5651272e0c39ffd7c868263b040c65c607b6610710fb327` | `e3c0714230b8beba0264347dd8303620a579f58c9e5e29ea739df4a7451932f8` | changed | Program changed with parameter count 8 to 9. |
| `checkpoint_register.checkpoint_register.spend` | `8f91d90f70f551dcd5651272e0c39ffd7c868263b040c65c607b6610710fb327` | `e3c0714230b8beba0264347dd8303620a579f58c9e5e29ea739df4a7451932f8` | changed | Program changed with parameter count 8 to 9. |
| `checkpoint_register.checkpoint_register.else` | `8f91d90f70f551dcd5651272e0c39ffd7c868263b040c65c607b6610710fb327` | `e3c0714230b8beba0264347dd8303620a579f58c9e5e29ea739df4a7451932f8` | changed | Program changed with parameter count 8 to 9. |
| `endpoint_board.endpoint_board.mint` | `d67b3449a0387522cde1f0e290fb3cbff1ae977f388291dcc7374ac3f8b13317` | `4f1cfc4c1a16f6b69e0e76fb2eba3146252a5a7231a0a845d48c9fe29ee87593` | changed | Program changed with parameter count 0 to 1. |
| `endpoint_board.endpoint_board.spend` | `d67b3449a0387522cde1f0e290fb3cbff1ae977f388291dcc7374ac3f8b13317` | `4f1cfc4c1a16f6b69e0e76fb2eba3146252a5a7231a0a845d48c9fe29ee87593` | changed | Program changed with parameter count 0 to 1. |
| `endpoint_board.endpoint_board.else` | `d67b3449a0387522cde1f0e290fb3cbff1ae977f388291dcc7374ac3f8b13317` | `4f1cfc4c1a16f6b69e0e76fb2eba3146252a5a7231a0a845d48c9fe29ee87593` | changed | Program changed with parameter count 0 to 1. |
| `hash_proof.hash_proof.mint` | `35e3969a160ee92c3630f2e36e5df1a1afdec455b8e540249dd26495383f76ef` | `35e3969a160ee92c3630f2e36e5df1a1afdec455b8e540249dd26495383f76ef` | carried | Program and parameter-free signature unchanged. |
| `hash_proof.hash_proof.else` | `35e3969a160ee92c3630f2e36e5df1a1afdec455b8e540249dd26495383f76ef` | `35e3969a160ee92c3630f2e36e5df1a1afdec455b8e540249dd26495383f76ef` | carried | Program and parameter-free signature unchanged. |

The reconciled title disposition is 8 carried, 15 changed, and 9 added. At the
distinct-program level, 3 prior programs are carried, 5 are changed, and 3 are
added. Thus every prior title and each of its 8 prior program identities is
accounted for; the current count is derived rather than forced to the old one.
