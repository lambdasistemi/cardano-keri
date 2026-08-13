#!/usr/bin/env bash
# #254 T254-109 (S254-R) — permanent version-remnant census.
#
# Cutting a pervasive feature scatters remnants that surface one at a time.
# The version integer was cut from the #254 checkpoint family, and the pieces
# have been found one by one: the #253 sequence field, then the register's
# stray applied argument (A-007), which had been shifting every ledger-supplied
# slot of an eight-parameter program since 449b14d. This script is the standing
# census that stops the next one arriving by surprise.
#
# ── WHAT IT ENFORCES ───────────────────────────────────────────────────────
#
# For every declared surface, every CODE line mentioning a version must be
# either
#
#   * CUT — named in the removal ledger and verified absent, or
#   * RETAINED — matched by an allowlist row that names a CONCRETE CONSUMER,
#     itself a file and pattern this script checks still exists.
#
# A bare "legacy" label is not a row. An allowlist row whose consumer has
# disappeared fails, and so does an allowlist row that no longer matches
# anything: a stale permission is how a census turns into decoration.
#
# ── ROW FORMAT ─────────────────────────────────────────────────────────────
#
# Rows are delimited by ASCII UNIT SEPARATOR (0x1f), never by `|`, because `|`
# is also the alternation operator inside the very patterns these rows carry.
# Peeling fields from the right happens to work until a rationale contains the
# delimiter, at which point a row silently changes which file is the consumer.
# Field counts are checked exactly and a wrong count is a failure, not a
# shorter row.
#
# ── WHAT IT DOES NOT SWEEP (declared, not implied) ─────────────────────────
#
#   * Comments and Haddock prose. The scope is code that can put a value into
#     a script, a hash or a manifest; a sentence recording that the version was
#     cut is not a remnant. Comment lines are stripped before matching.
#   * The blueprint's own declared parameter titles, and which applied argument
#     lands at each of them. That is a structural fact about the derivation,
#     not a textual one, and it is owned by
#     `s254_r_version_remnant_sweep_is_complete` in ScriptAritySpec, which
#     requires every version-shaped declared parameter to receive
#     v1CheckpointVersion and the register to declare and apply none.
#   * Immutable deployed evidence under deploy/preprod. Those bytes are
#     settled history and are reported below as ADVISORY only; this script
#     never asks them to change.
#
# ── OUTPUT CONTRACT ────────────────────────────────────────────────────────
#
#   exit 0  every remnant accounted for; prints exactly one
#           `S254-R version-remnant-sweep: PASS removed=<n> kept=<n>` line
#   exit 1  an unaccounted remnant, a returned cut, a stale row, a missing
#           consumer, or a malformed row
#
# `--self-test` seeds mutations into an isolated temporary copy and requires
# this same scanner to reject each one. It never mutates the repository tree
# or any historical fixture.

set -euo pipefail

US=$'\x1f'
repo_root=${S254R_SWEEP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

fail() {
    printf 'S254-R version-remnant-sweep: FAIL %s\n' "$*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Surfaces: the deployment, derivation, serialization and manifest code whose
# values reach a script hash, an address or a published manifest.
# ---------------------------------------------------------------------------
surfaces=(
    offchain/deployment/Cardano/KERI/Deployment/Script.hs
    offchain/deployment/Cardano/KERI/Deployment/Manifest.hs
    offchain/deployment/Cardano/KERI/Deployment/EndpointBoardManifest.hs
    onchain/validators/checkpoint_register.ak
    onchain/validators/checkpoint_observer.ak
)

# ---------------------------------------------------------------------------
# The removal ledger: cut, and verified absent on every run.
# name US path US pattern-that-must-not-match
# ---------------------------------------------------------------------------
removals=(
    "register-applied-version-argument${US}offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyCheckpointParams version"
    "register-declared-version-parameter${US}onchain/validators/checkpoint_register.ak${US}[_]?version|validator_version|checkpointVersion"
)

# ---------------------------------------------------------------------------
# The allowlist: retained remnants, each with a consumer that must exist.
# surface US match-pattern US consumer-path US consumer-pattern US rationale
# ---------------------------------------------------------------------------
retained=(
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}v1CheckpointVersion${US}deploy/preprod/m1-manifest.json${US}\"checkpointVersion\"${US}the released M1 family generation; applied only where the blueprint declares a version parameter, and serialized into the deployed manifest"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyParams version|I version, B predecessorPolicy${US}onchain/validators/cage.ak${US}mpfCage\(_version: Int${US}the legacy Cage applier, whose validator declares the parameter it applies"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyLifecycleParams version|I version, B proofPolicy${US}onchain/validators/checkpoint_observer.ak${US}validator observer_lifecycle${US}observer_lifecycle declares _version as its first applied parameter"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyAdvanceParams version|\[I version\]${US}onchain/validators/checkpoint_observer.ak${US}validator observer_advance\(_version: Int\)${US}observer_advance and observer_enforcement each declare _version as their only applied parameter"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}versionTag${US}offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}UntypedPlutusCore \(Program${US}the UPLC program-format version field, unrelated to the checkpoint family; carried through so an applied argument keeps the program's own encoding"
    "offchain/deployment/Cardano/KERI/Deployment/Manifest.hs${US}v1CheckpointVersion|parameterCheckpointVersion|checkpointVersion${US}deploy/preprod/m1-manifest.json${US}\"checkpointVersion\":0${US}a field of the deployed manifest schema; cutting it would make the settled preprod manifest unparseable"
    "offchain/deployment/Cardano/KERI/Deployment/Manifest.hs${US}manifestSchemaVersion${US}deploy/preprod/m1-manifest.json${US}\"schema\":\"cardano-keri/m1-deployment-manifest/v1\"${US}the manifest schema identifier the deployed manifest carries"
    "offchain/deployment/Cardano/KERI/Deployment/EndpointBoardManifest.hs${US}endpointBoardManifestSchemaVersion${US}deploy/preprod/board-manifest.json${US}\"schema\":\"cardano-keri/m1-endpoint-board-manifest/v1\"${US}the board manifest schema identifier the deployed board manifest carries"
    "onchain/validators/checkpoint_observer.ak${US}_version: Int${US}offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyLifecycleParams version${US}declared applied parameters of the three pre-existing observers; the deployment supplies exactly these positions"
)

# ---------------------------------------------------------------------------
# Application-site census (#254 NOTE-007).
# ---------------------------------------------------------------------------
# A version remnant is one way an unchecked value reaches a deployment
# identity. The other is an application site nobody enumerated: a place that
# applies arguments to a blueprint program without going through the
# fail-closed constructor. The group census in ScriptAritySpec answers "is
# every live blueprint validator accounted for"; this answers "is every place
# that applies arguments accounted for", which no test running inside the nix
# sandbox can see.
#
# The scan is over executable lines only. Imports, export-list entries and type
# signatures mention these names without applying anything, and counting them
# would pad the census with rows that cannot fail informatively.
#
# Declared here, above the --self-test dispatch, so the self-test seeds these
# exact paths into its isolated roots and exercises this exact table.
site_patterns='applyDataArgs|applyProgram|mkAppliedArtifact|applyParams|Cek\.runProgram'

# path US pattern US class US exact-hits US rationale
#   identity — produces a published deployment identity; must be fail-closed
#   applier  — a production applier bound by the group census
#   oracle   — test-side recovery, publishes nothing
#   evidence — CEK execution for compiled-target proof, publishes nothing
#
# The hit count is EXACT, not a lower bound. A row that only required "at least
# one" would silently absorb a new call added to a file it already covers, so
# "a new application site fails" would be true across files and false within
# them. Changing a count is how a new site is admitted, and it forces someone
# to look at the rationale while doing it.
sites=(
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyDataArgs${US}identity${US}4${US}the single applier; reached only through mkAppliedArtifact and applyParams"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}mkAppliedArtifact${US}identity${US}8${US}the fail-closed constructor every published artifact is built through: its definition plus the seven artifacts derived through it"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyParams${US}applier${US}1${US}the legacy Cage applier; it bypasses mkAppliedArtifact because its only consumer is outside this slice's fence, so the group census drives this exact function and structurally recovers its two arguments"
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs${US}applyProgram${US}identity${US}1${US}the UPLC primitive, used only inside applyDataArgs"
    "offchain/e2e/CageTxBuilder.hs${US}applyParams${US}applier${US}1${US}the only consumer of the Cage applier; outside this slice's fence, and its arity is bound by the group census"
    "offchain/deployment-test/Cardano/KERI/Deployment/ScriptAritySpec.hs${US}applyProgram|mkAppliedArtifact|applyParams${US}oracle${US}4${US}the census oracle and its mutants; recovers and re-applies, publishes nothing"
    "offchain/blaster/KeriBlaster/S2Cek.lean${US}applyParams|Cek\.runProgram${US}evidence${US}2${US}the pinned CEK machine's own argument application"
    "offchain/blaster/KeriBlaster.lean${US}Cek\.runProgram${US}evidence${US}1${US}S2 reachability execution over the FROZEN baseline programs; a different artifact identity from the live groups, and it publishes none"
    "offchain/blaster/KeriBlaster/Migration.lean${US}Cek\.runProgram${US}evidence${US}2${US}migration compiled-target execution over the live blueprint; publishes no identity"
    "offchain/blaster/KeriBlaster/RegisterArity.lean${US}Cek\.runProgram${US}evidence${US}1${US}register compiled-target execution over the live blueprint; publishes no identity"
)

# ---------------------------------------------------------------------------
# Strip comments, keeping original line numbers.
# ---------------------------------------------------------------------------
code_lines() {
    local path=$1
    case "$path" in
        *.hs)
            awk '
                BEGIN { block = 0 }
                {
                    if (block) { if ($0 ~ /-\}/) block = 0; next }
                    if ($0 ~ /^[[:space:]]*\{-/) {
                        if ($0 !~ /-\}/) block = 1
                        next
                    }
                    if ($0 ~ /^[[:space:]]*--/) next
                    printf "%d:%s\n", NR, $0
                }
            ' "$path"
            ;;
        *.ak)
            awk '
                { if ($0 ~ /^[[:space:]]*\/\//) next; printf "%d:%s\n", NR, $0 }
            ' "$path"
            ;;
        *)
            awk '{ printf "%d:%s\n", NR, $0 }' "$path"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Isolated falsification. Seeds one mutation into a temporary copy and
# requires THIS script, unmodified, to reject it.
# ---------------------------------------------------------------------------
# Executable lines only: comments already gone, plus imports, export-list
# entries and type signatures, none of which apply an argument to anything.
#
# The list-entry exclusion REQUIRES a trailing comma. A bare identifier alone
# on a line is usually a real call whose arguments are on the following lines,
# which is what this formatter does to every multi-argument application; an
# exclusion that dropped those would hide most of the call sites it is meant to
# count. Over-counting is the safe direction here — an extra line has to be
# classified — so an unusual list entry without its comma costs a row, not a
# blind spot.
call_lines() {
    code_lines "$1" | awk -F: '
        {
            body = substr($0, index($0, ":") + 1)
            if (body ~ /^import /) next
            if (body ~ /::/) next
            if (body ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_'"'"']*,[[:space:]]*$/) next
            print
        }
    '
}

# Every Haskell and Lean source that could carry an application site. Uses the
# index when there is one, so untracked build output is never scanned, and
# falls back to the filesystem so an isolated self-test copy is scanned exactly
# the same way rather than silently scanning nothing.
list_sources() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git ls-files '*.hs' '*.lean'
    else
        find . -type f \( -name '*.hs' -o -name '*.lean' \) -printf '%P\n'
    fi | grep -v '^lean/' || true
}

site_paths() {
    local record field
    for record in "${sites[@]}"; do
        IFS="$US" read -r field _ _ _ <<<"$record"
        printf '%s\n' "$field"
    done | sort -u
}

consumer_paths() {
    local record field
    for record in "${retained[@]}"; do
        IFS="$US" read -r _ _ field _ _ <<<"$record"
        printf '%s\n' "$field"
    done | sort -u
}

seed_copy() {
    local target=$1 path
    while IFS= read -r path; do
        install -D "$repo_root/$path" "$target/$path"
    done < <(
        printf '%s\n' "${surfaces[@]}"
        consumer_paths
        site_paths
    )
}

self_test() {
    local workspace leg rc failures=0 output
    workspace=$(mktemp -d)

    run_leg() {
        local name=$1 expected_rc=$2 expected_text=$3 root=$4
        local leg_output leg_rc
        set +e
        leg_output=$(S254R_SWEEP_ROOT="$root" "$self" 2>&1)
        leg_rc=$?
        set -e
        printf 'S254R_SWEEP_SELFTEST %s_rc=%s\n' "$name" "$leg_rc"
        if [[ "$leg_rc" != "$expected_rc" ]]; then
            printf '  [leg] expected rc %s, got %s\n' "$expected_rc" "$leg_rc" >&2
            failures=$((failures + 1))
            return
        fi
        if [[ -n "$expected_text" ]] &&
            ! printf '%s\n' "$leg_output" | grep -qF -- "$expected_text"; then
            printf '  [leg] expected output to mention: %s\n' "$expected_text" >&2
            printf '%s\n' "$leg_output" | sed 's/^/  [child] /' >&2
            failures=$((failures + 1))
        fi
    }

    # Leg 0 — the unmutated copy passes. Without this the rejections below
    # would be indistinguishable from a scanner that rejects everything, and
    # in particular this is what shows the structural derivation check accepts
    # the VALID corrected call rather than merely noticing it is called.
    leg="$workspace/green"
    seed_copy "$leg"
    run_leg green 0 'PASS removed=3' "$leg"

    # Leg 1 — an unallowlisted version reference on an active surface.
    leg="$workspace/injected"
    seed_copy "$leg"
    printf '\nv1InjectedVersionRemnant :: Integer\nv1InjectedVersionRemnant = 1\n' \
        >>"$leg/offchain/deployment/Cardano/KERI/Deployment/Script.hs"
    run_leg injected 1 'unaccounted version references' "$leg"

    # Leg 2 — the cut register argument returns inside the derivation call.
    leg="$workspace/returned-cut"
    seed_copy "$leg"
    sed -i \
        's/^\( *\)( applyCheckpointParams$/\1( applyCheckpointParams\n\1    v1CheckpointVersion/' \
        "$leg/offchain/deployment/Cardano/KERI/Deployment/Script.hs"
    run_leg returned_cut 1 'the register derivation applies a version argument' "$leg"

    # Leg 3 — a retained row whose consumer has disappeared.
    leg="$workspace/stale-consumer"
    seed_copy "$leg"
    sed -i 's/"checkpointVersion":0,//g' "$leg/deploy/preprod/m1-manifest.json"
    run_leg stale_consumer 1 'has no live consumer' "$leg"

    # Leg 4 — an argument-application site nobody classified. Seeded into a
    # file that is swept but carries no site row, so it cannot be absorbed by
    # an existing pattern.
    leg="$workspace/unclassified-site"
    seed_copy "$leg"
    printf '\nunclassifiedApplication :: [Data] -> SBS.ShortByteString\nunclassifiedApplication plan = applyDataArgs plan mempty\n' \
        >>"$leg/offchain/deployment/Cardano/KERI/Deployment/Manifest.hs"
    run_leg unclassified_site 1 'unclassified application sites' "$leg"

    # Leg 5 — an ADDITIONAL call inside an already-classified file. This is the
    # case the previous "at least one hit" rule could not see: the new call
    # would have inherited the existing row's class and rationale in silence.
    leg="$workspace/absorbed-site"
    seed_copy "$leg"
    printf '\nabsorbedApplication :: [Data] -> SBS.ShortByteString -> SBS.ShortByteString\nabsorbedApplication plan program = applyDataArgs plan program\n' \
        >>"$leg/offchain/deployment/Cardano/KERI/Deployment/Script.hs"
    run_leg absorbed_site 1 'application-site count changed' "$leg"

    # Leg 6 — a classification row whose call site has gone. A stale site row
    # is a rule nobody is testing, exactly like a stale retained row.
    leg="$workspace/stale-site"
    seed_copy "$leg"
    sed -i 's/applyProgram/applyUplcProgram/g' \
        "$leg/offchain/deployment/Cardano/KERI/Deployment/Script.hs"
    run_leg stale_site 1 'stale application-site row' "$leg"

    # Leg 7 — a retained row that no longer matches anything.
    leg="$workspace/stale-row"
    seed_copy "$leg"
    sed -i 's/versionTag/programVersionField/g' \
        "$leg/offchain/deployment/Cardano/KERI/Deployment/Script.hs"
    run_leg stale_row 1 'stale allowlist entry' "$leg"

    rm -rf "$workspace"

    if (( failures == 0 )); then
        printf 'S254R_SWEEP_SELFTEST selftest=pass\n'
        return 0
    fi
    printf 'S254R_SWEEP_SELFTEST selftest=fail failures=%s\n' "$failures"
    return 1
}

if [[ "${1:-}" == "--self-test" ]]; then
    self_test
    exit $?
fi

cd "$repo_root"

for path in "${surfaces[@]}"; do
    test -f "$path" || fail "declared surface is missing: $path"
done

# ---------------------------------------------------------------------------
# Removal ledger.
# ---------------------------------------------------------------------------
removed=0
for record in "${removals[@]}"; do
    IFS="$US" read -r name path pattern extra <<<"$record"
    test -z "$extra" || fail "removal row has more than three fields: $name"
    test -n "$name" && test -n "$path" && test -n "$pattern" ||
        fail "removal row has fewer than three fields: $record"
    test -f "$path" || fail "removal ledger names a missing file: $path"
    if code_lines "$path" | cut -d: -f2- | grep -Eq -- "$pattern"; then
        fail "cut remnant has returned: $name matches '$pattern' in $path"
    fi
    printf 'S254-R version-remnant-sweep: CUT %s (%s)\n' "$name" "$path"
    removed=$((removed + 1))
done

# The derivation call is a separate cut from the applier's signature: the
# argument could be reintroduced at the call site alone. Inspected as a block,
# exactly as the immutable slice gate does, because merely proving that
# applyCheckpointParams is called would invert the assertion.
register_call=$(
    awk '
        /let appliedCheckpoint[[:space:]]*=/ { inside = 1 }
        inside { print }
        inside && /checkpointProgram/ { exit }
    ' offchain/deployment/Cardano/KERI/Deployment/Script.hs
)
test -n "$register_call" ||
    fail "the register derivation call could not be located in Script.hs"
if printf '%s\n' "$register_call" | grep -Eq -- 'v1CheckpointVersion|I version'; then
    fail "cut remnant has returned: the register derivation applies a version argument"
fi
printf 'S254-R version-remnant-sweep: CUT %s (%s)\n' \
    "register-derivation-version-argument" \
    "offchain/deployment/Cardano/KERI/Deployment/Script.hs"
removed=$((removed + 1))

# ---------------------------------------------------------------------------
# Allowlist: every row must match, and its consumer must exist.
# ---------------------------------------------------------------------------
covered=$(mktemp)
observed=$(mktemp)
uncovered=$(mktemp)
site_observed=""
site_covered=""
site_uncovered=""
trap 'rm -f "$covered" "$observed" "$uncovered" "$site_observed" "$site_covered" "$site_uncovered"' EXIT

kept=0
for record in "${retained[@]}"; do
    IFS="$US" read -r surface match_pattern consumer_path consumer_pattern \
        rationale extra <<<"$record"
    test -z "$extra" || fail "allowlist row has more than five fields: $surface"
    test -n "$surface" && test -n "$match_pattern" &&
        test -n "$consumer_path" && test -n "$consumer_pattern" &&
        test -n "$rationale" ||
        fail "allowlist row has fewer than five fields: $record"

    test -f "$surface" || fail "allowlist row names a missing surface: $surface"
    test -f "$consumer_path" ||
        fail "allowlist row for $surface names a missing consumer file: $consumer_path"

    hits=$(code_lines "$surface" | grep -Ec -- "$match_pattern" || true)
    test "$hits" -gt 0 ||
        fail "stale allowlist entry: '$match_pattern' matches nothing in $surface"

    grep -Eq -- "$consumer_pattern" "$consumer_path" ||
        fail "allowlist row for $surface has no live consumer: '$consumer_pattern' is absent from $consumer_path"

    code_lines "$surface" | grep -E -- "$match_pattern" | cut -d: -f1 |
        sed "s|^|$surface:|" >>"$covered"

    printf 'S254-R version-remnant-sweep: KEPT %s [%s] consumer=%s :: %s\n' \
        "$surface" "$match_pattern" "$consumer_path" "$rationale"
    kept=$((kept + 1))
done

# ---------------------------------------------------------------------------
# Coverage: no code mention of a version may be unaccounted for.
# ---------------------------------------------------------------------------
: >"$observed"
for path in "${surfaces[@]}"; do
    code_lines "$path" | grep -Ei -- 'version' | cut -d: -f1 |
        sed "s|^|$path:|" >>"$observed" || true
done

sort -u "$observed" -o "$observed"
sort -u "$covered" -o "$covered"
comm -23 "$observed" "$covered" >"$uncovered"

if [[ -s "$uncovered" ]]; then
    printf 'S254-R version-remnant-sweep: unaccounted version references:\n' >&2
    while IFS= read -r location; do
        path=${location%%:*}
        line=${location##*:}
        printf '  %s:%s: %s\n' \
            "$path" "$line" "$(sed -n "${line}p" "$path")" >&2
    done <"$uncovered"
    fail "every remnant must be cut or allowlisted with a concrete consumer"
fi

# ---------------------------------------------------------------------------
# Application-site census (#254 NOTE-007).
# ---------------------------------------------------------------------------
# A version remnant is one way an unchecked value reaches a deployment
# identity. The other is an application site nobody enumerated: a place that
# applies arguments to a blueprint program without going through the
# fail-closed constructor. The group census in ScriptAritySpec answers "is
# every live blueprint validator accounted for"; this answers "is every place
# that applies arguments accounted for", which no test running inside the nix
# sandbox can see.
#
site_observed=$(mktemp)
site_covered=$(mktemp)
site_uncovered=$(mktemp)
trap 'rm -f "$covered" "$observed" "$uncovered" "$site_observed" "$site_covered" "$site_uncovered"' EXIT

classified=0
for record in "${sites[@]}"; do
    IFS="$US" read -r path pattern class expected rationale extra <<<"$record"
    test -z "$extra" || fail "application-site row has more than five fields: $path"
    test -n "$path" && test -n "$pattern" && test -n "$class" &&
        test -n "$expected" && test -n "$rationale" ||
        fail "application-site row has fewer than five fields: $record"
    case "$class" in
        identity | applier | oracle | evidence) ;;
        *) fail "application-site row has an unknown class: $class" ;;
    esac
    case "$expected" in
        '' | *[!0-9]*) fail "application-site row has a non-numeric hit count: $expected" ;;
    esac
    test -f "$path" || fail "application-site row names a missing file: $path"

    hits=$(call_lines "$path" | grep -Ec -- "$pattern" || true)
    test "$hits" -gt 0 ||
        fail "stale application-site row: '$pattern' matches nothing in $path"
    test "$hits" -eq "$expected" ||
        fail "application-site count changed: '$pattern' in $path matches $hits executable lines, the row declares $expected; a new call site must be classified, not absorbed"

    call_lines "$path" | grep -E -- "$pattern" | cut -d: -f1 |
        sed "s|^|$path:|" >>"$site_covered"
    classified=$((classified + 1))
done

: >"$site_observed"
while IFS= read -r path; do
    call_lines "$path" | grep -E -- "$site_patterns" | cut -d: -f1 |
        sed "s|^|$path:|" >>"$site_observed" || true
done < <(list_sources)

sort -u "$site_observed" -o "$site_observed"
sort -u "$site_covered" -o "$site_covered"
comm -23 "$site_observed" "$site_covered" >"$site_uncovered"

if [[ -s "$site_uncovered" ]]; then
    printf 'S254-R version-remnant-sweep: unclassified application sites:\n' >&2
    while IFS= read -r location; do
        path=${location%%:*}
        line=${location##*:}
        printf '  %s:%s: %s\n' \
            "$path" "$line" "$(sed -n "${line}p" "$path")" >&2
    done <"$site_uncovered"
    fail "every argument-application site must carry a class and a rationale"
fi

printf 'S254-R version-remnant-sweep: SITES classified=%s\n' "$classified"

# ---------------------------------------------------------------------------
# Immutable deployed evidence: ADVISORY only, never a failure.
# ---------------------------------------------------------------------------
advisory=$(grep -rlEi -- 'version' deploy/preprod 2>/dev/null | wc -l | tr -d ' ')
printf 'S254-R version-remnant-sweep: ADVISORY deploy/preprod files carrying a version reference=%s (settled history; not rewritten by this repair)\n' \
    "$advisory"

printf 'S254-R version-remnant-sweep: PASS removed=%s kept=%s\n' \
    "$removed" "$kept"
