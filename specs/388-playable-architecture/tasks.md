# Tasks

- [x] T388-1: ship progressive chapter, four complete examples and navigation.
- [x] T388-2: verify canonical/rendered/downloaded text, replay and negative controls; wire docs CI.
- [x] T388-3: verify browser copy/load/play and public candidate preview; independent Opus audit.

Validated: four scenarios, 21 trunk/fork steps, 12 permanent negative controls,
strict MkDocs build and actual browser copy/load/play in both simulator families.
Full Opus audit passed b4661c9; focused recheck passed 88c5db8 after assertion
hardening and bond-label correction. Final report SHA-256:
`612b7252c01f80b3bd79d50fee2636763d8fcdc26b2e899fcc4c6ec6cb83ac58`.

Ordinary narrative prose remains human-reviewed; the check does not parse every
sentence into a model assertion. Simulator semantics and deployed contracts are
unchanged. Existing checkpoint declaration-accounting issue #387 is outside scope.
