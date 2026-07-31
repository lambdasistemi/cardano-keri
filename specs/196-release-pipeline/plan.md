# Plan — #196 day-0 release pipeline

## Mechanism

Use the Cabal-owned planner from
`new-repository/references/release-haskell.md`, the flake-owned packaging model
from `distribute-binaries`, and App-minted push credentials from
`github-app-ci-tokens`. The release-please manifest mechanism is explicitly
inapplicable.

## One cohesive PAIR slice

Planner, packaging, workflow modes, release metadata, and clean-install proof
form one relational contract: a version selected by the planner must name the
tag, artifact, CLI output, and release evidence. Splitting those surfaces would
permit independently green halves that disagree at the seam. Execute them as
one PAIR-reviewed, bisect-safe release-pipeline commit.

### Release planning

Add release helper scripts and a `Release Planner` workflow. The scripts derive
versions from `offchain/cardano-keri.cabal`, generate release notes from
conventional commits, maintain `release/cabal-release`, validate the changelog,
and tag only after the release commit reaches `main`. The workflow mints the
scoped App token before checkout, uses it for git pushes, and leaves ordinary
GitHub API calls on `github.token`.

### Release identity

Add one small validated configuration document containing the channel label
and prerelease flag. Workflows/scripts read it; epic #171 is initial data, not
embedded workflow policy.

### Linux artifact

Add `NixOS/bundlers` to the offchain flake with an additive-only lock change.
Declare a release-executable attrset containing `ckeri`, wrap each executable
with an explicit main program and CA environment, and expose:

- `linux-release-artifacts` using the Cabal version;
- `linux-dev-release-artifacts` using `<version>-<short-revision>`;
- `linux-artifact-smoke`, which extracts the produced AppImage and exercises
  the extracted wrapper.

The artifact package stages versioned/stable AppImage names and `SHA256SUMS`.
If the bundler path cannot be made green within this slice, stop and file
Q-002; do not silently substitute another package format.

### Workflow and live acceptance

Add `Linux Release` with PR, tag, and safe manual modes. PR mode builds and
smokes but never publishes. Tag mode validates version consistency, publishes
the GitHub prerelease, then runs a no-clone Ubuntu-container download/run and
attaches its transcript.

### Documentation

Document installation and the one executable-inventory extension point for
#188. Do not touch `docs/user/follower.md`.

## Invariants and proof controls

- **Version agreement**: negative controls cover a mismatched tag and missing
  changelog section; a successful smoke prints observed/expected versions.
- **No release-please**: validator rejects either manifest/config file.
- **No accidental publication**: static workflow tests cover PR/default manual
  guards and tag publication.
- **Artifact boundary**: smoke runs an extracted artifact, never the Nix build
  tree, and checks the CA file inside the extracted closure.
- **Planner event propagation**: workflow checkout uses the App token; a plain
  `GITHUB_TOKEN` push is not accepted as equivalent.
- **Pin fence**: compare the base/current lock graphs and reject changed
  `rev`/`narHash` values for every pre-existing node.
- **Epic marking**: release title/prerelease status come from validated config.
- **Future executable extension**: one inventory is shared by artifact
  creation and smoke expectations.

## Verification

Focused slice gate:

1. release-script and workflow negative/positive controls;
2. `actionlint` over all workflows;
3. additive-only lockfile proof;
4. build `linux-dev-release-artifacts`;
5. run `linux-artifact-smoke` against the extracted dev artifact and exact
   Cabal/revision version.

Ticket gate:

1. unchanged repository `./gate.sh`;
2. build every `offchain#checks.x86_64-linux.*` derivation;
3. rerun the focused release gate.

After merge, acceptance continues through the actual planner PR, tag workflow,
release URL, and attached clean-environment transcript. The ticket does not
complete merely because its workflow files are ready.

