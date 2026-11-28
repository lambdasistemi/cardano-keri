# Sourced by the rehearsals after `log` is defined: records, once per run, the helpers and the environment exactly as the
# run resolves them (absolute path and sha256 of each helper script and of the Haskell source it runs, the node
# environment file, the node it puts on the path, its genesis directory), the repository revision they sit in and how many
# files that tree has changed. Needs HERE, NODE_ENV and the helper variables the caller has resolved.
helper_pair() { # helper_pair <variable name> <haskell source beside it>
    local path="${!1}" src
    path="$(readlink -f "$path")"
    src="$(dirname "$path")/$2"
    log "binding: $1 $path sha256 $(sha256sum "$path" | cut -c1-64); $2 $src sha256 $(sha256sum "$src" | cut -c1-64)"
}
bind_helpers() {
    local helper_root
    helper_root="$(dirname "$(readlink -f "$ENACT_PV11")")"
    log "binding: helper source revision $(git -C "$helper_root" rev-parse HEAD 2>/dev/null || echo unknown) with $(git -C "$helper_root" status --short 2>/dev/null | wc -l) changed files in its tree"
    helper_pair ENACT_PV11 EnactPV11.hs
    helper_pair INSPECT TxInspect.hs
    if [[ -n "${MUTATE:-}" ]]; then helper_pair MUTATE MutateTx.hs; fi
    log "binding: NODE_ENV $(readlink -f "$NODE_ENV") sha256 $(sha256sum "$NODE_ENV" | cut -c1-64)"
    ( source "$NODE_ENV" >/dev/null 2>&1
      log "binding: cardano-node $(command -v cardano-node) $(cardano-node --version 2>/dev/null | head -1 | tr -s ' ') sha256 $(sha256sum "$(command -v cardano-node)" | cut -c1-64); E2E_GENESIS_DIR ${E2E_GENESIS_DIR:-unset}; cardano-node-clients source $(pwd)" )
    log "binding: singular $SINGULAR sha256 $(sha256sum "$SINGULAR" | cut -c1-64); devnet $DEVNET sha256 $(sha256sum "$DEVNET" | cut -c1-64); blueprint $BLUEPRINT sha256 $(sha256sum "$BLUEPRINT" | cut -c1-64)"
}
