# Functions model — #355

No function signatures change. The executable surface is the frozen slice
gate (`/gate.sh`, untracked, backed up under the ticket runtime root):

- `mkdocs build --strict --site-dir site` via the CI nix invocation
- lychee over `docs/` with the CI flags from
  `.github/workflows/deploy-docs.yml`
- INV-355-01 leg: deleted basenames absent; no inbound links
- INV-355-03 leg: zero hits for internal shorthand
- INV-355-05 leg: each story-family page contains its local simulator link
