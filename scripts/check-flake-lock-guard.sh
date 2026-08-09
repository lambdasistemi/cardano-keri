#!/usr/bin/env bash
# #259 S259-1 — STANDING repository-CI contract: the primary offchain flake's
# declared inputs and every gate-path evaluation of it are guarded, without
# ever rewriting the committed lock.
#
# ── OUTPUT CONTRACT (stable repository interface; consumers may parse this) ──
#
# EXIT CODES — the authoritative verdict, and the ONLY thing a consumer needs:
#   0  every direct offchain/flake.nix input reconciles against a present
#      offchain/flake.lock node using a SUPPORTED declaration spelling, every
#      direct primary-offchain invocation this script classified in
#      `justfile` and `.github/workflows/ci.yml` carries
#      `--no-write-lock-file`, both files call this script as EXECUTABLE
#      text, and `justfile`'s `ci` recipe still calls
#      `--assert-lock-unchanged` (GREEN)
#   1  an unreconciled or unsupported-spelling input, an unguarded or
#      unclassified invocation, a lost or commented-out caller, a
#      zero-population classification, or a failed self-test leg (RED)
#   2  usage error or evaluation could not complete (malformed JSON, missing
#      file, missing `jq`) — GATE-INCOMPLETE, never treat as a pass
#   any other code is an ERROR and must be treated as RED, never as a pass.
#
# A second mode, `--assert-lock-unchanged`, is INV-259-ASSERT's actual
# mechanism (0 = lock unchanged from its committed blob, 1 = it drifted) —
# `justfile`'s `ci` recipe calls it as the shared post-dependency check, so
# the property proved by this script's own self-test is the exact code path
# `just ci` runs, not a copy of it.
#
# MACHINE-READABLE LINES — `CFLG_RESULT <key>=<value>`, one key per line,
# recognised ONLY at the START of a line, each key emitted AT MOST ONCE per
# run in normal mode.
#
#   normal mode:  declared_inputs, locked_root_entries, unsupported_declarations,
#                 unreconciled_inputs, justfile_invocations, justfile_unguarded,
#                 workflow_invocations, workflow_unguarded, caller_justfile,
#                 caller_workflow, caller_assert, onchain_flake_pair,
#                 result=pass|fail
#   --self-test:  selftest=pass|fail; one `<seed>_rc` key per seeded negative
#                 control leg (green_rc, incomplete_lock_rc,
#                 unlocked_quoted_input_rc, unsupported_declaration_rc,
#                 unguarded_invocation_rc, continued_unguarded_command_rc,
#                 missing_caller_rc, commented_caller_justfile_rc,
#                 commented_caller_workflow_rc, missing_assert_caller_rc,
#                 assert_mechanism_green_rc, assert_mechanism_red_rc,
#                 zero_population_rc, onchain_pair_present_rc) — the exit
#                 code of that leg — plus `failures` (count of misbehaving
#                 legs) when selftest=fail.
#
# Population scope (INV-259-NOWRITE): a direct primary-offchain invocation is
# a `nix build|run|develop|shell|flake` command that evaluates
# `offchain/flake.nix` itself — via `cd offchain &&`, a bare `cd offchain`
# recipe-body/step line, or an explicit `./offchain#`/`../offchain#`/
# `path:./offchain#` reference. A `github:`- or `nixpkgs#`-rooted reference,
# or any invocation whose only working directory is `onchain/` or
# `spikes/*`, is a remote shell or auxiliary flake and is OUT of this
# population (brief: "remote shells and auxiliary flakes are not this
# population"). Backslash-continued physical lines (justfile) and YAML
# block-scalar continuations (workflow, already handled) are joined into one
# logical command before classification; a joined command containing the
# bare word `nix` that does not resolve to a recognized subcommand is
# UNCLASSIFIABLE (fails closed), not silently dropped — except the
# `command -v nix` existence-probe idiom, which is excluded on that one
# narrow, well-known shape.
#
# --self-test falsifies the checker on a SYNTHETIC fixture under a temporary
# root (the real worktree is only ever read in normal mode): it seeds an
# incomplete-lock node deletion, a valid-syntax quoted-but-unlocked input, an
# unsupported declaration spelling, a stripped `--no-write-lock-file`, a
# valid line-continuation that drops the guard flag, a fully removed
# guard-caller line, an independently commented-out justfile caller, an
# independently commented-out workflow caller, a removed
# `--assert-lock-unchanged` caller, an emptied invocation population, and an
# added `onchain/flake.nix` (advisory value control) — and requires the real
# checker to reject each for the stated reason; the unmodified fixture must
# pass (GREEN leg). `--assert-lock-unchanged` itself is separately proved
# able to both pass and fail against a real (non-fixture) temporary git
# repository, since its mechanism is git-diff-based, not fixture-shaped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
usage: check-flake-lock-guard.sh [--repo-root <dir>] [--self-test]
       check-flake-lock-guard.sh [--repo-root <dir>] --assert-lock-unchanged

  --repo-root <dir>          repository root containing offchain/flake.nix,
                             offchain/flake.lock, justfile, and
                             .github/workflows/ci.yml (default: parent of
                             this script's directory)
  --self-test                seeded RED/GREEN falsification on a synthetic
                             fixture under a temporary root only
  --assert-lock-unchanged    INV-259-ASSERT: fail if offchain/flake.lock
                             differs from its committed blob (the shared
                             post-dependency check `just ci`'s body calls)
EOF
}

fail() { echo "check-flake-lock-guard: FAIL: $*" >&2; exit 1; }
incomplete() { echo "check-flake-lock-guard: GATE-INCOMPLETE: $*" >&2; exit 2; }

REPO_ROOT=""
SELF_TEST=0
ASSERT_LOCK_UNCHANGED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) [ $# -ge 2 ] || { usage >&2; exit 2; }; REPO_ROOT=$2; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --assert-lock-unchanged) ASSERT_LOCK_UNCHANGED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -d "$REPO_ROOT" ] || incomplete "repo root '$REPO_ROOT' is not a directory"

command -v jq >/dev/null 2>&1 || incomplete "jq is required"

NIX_REL="offchain/flake.nix"
LOCK_REL="offchain/flake.lock"
JUST_REL="justfile"
CI_REL=".github/workflows/ci.yml"

# Audit finding (submission 1, INV-259-PARITY): an unanchored `grep -q` for
# the script's own name treats a COMMENTED-OUT caller line as a live one —
# `# ./scripts/check-flake-lock-guard.sh` still contains the substring.
# Require a non-comment line that contains it: strip full-line comments (a
# `#`-leading trimmed line — true for both justfile and YAML) and, on the
# remaining lines, reject a match preceded by a `#` on the same line (an
# inline trailing comment). Neither language's syntax for this specific
# invocation shape needs a literal `#` before the match otherwise.
has_executable_caller() { # <file> <needle> -> return 0 if a non-comment line contains <needle>
  local file=$1 needle=$2 line trimmed before
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ "$trimmed" == \#* ]] && continue
    [[ "$trimmed" == *"$needle"* ]] || continue
    before="${trimmed%%"$needle"*}"
    [[ "$before" == *"#"* ]] && continue
    return 0
  done < "$file"
  return 1
}

# ─────────────────────────── declared/locked reconciliation ────────────────
#
# Extract the direct input names from offchain/flake.nix's `inputs = { ... }`
# block (nix-formatted, 2-space top-level indent: `  inputs = {` opens,
# `  };` at the same indent closes). A top-level entry is one at brace/paren/
# bracket depth 1 relative to that opening `{`, recognized as either a bare
# identifier (`name.attr =` / `name = {`) or a quoted identifier
# (`"name".attr =` / `"name" = {`) — nix permits both spellings for an
# attribute name. A multi-line value (`name.url =\n  "...";`) is tracked via
# an "awaiting `;`" flag so its continuation line is never mistaken for a
# second top-level entry. Depth is computed from `{([`/`])}` counts with
# double-quoted substrings blanked first, so a URL can never perturb it. This
# is a positional/indentation parse, not a `nix eval`: the guard is a static
# shell control and must never itself invoke Nix (a Nix evaluation costs the
# ticket's build budget; this check must not).
#
# Audit finding (submission 1, DATA-INV-259-01): the prior single-regex,
# no-depth-tracking parser silently skipped a quoted key entirely (a new
# unlocked input went undetected) — enumerate every *supported* spelling and
# FAIL CLOSED on anything else, rather than silently omitting it.
extract_declared_inputs() { # <nix-file> -> TSV: name status(ok|unsupported) per top-level entry
  local file=$1 in_block=0 depth=0 pending=0 line trimmed stripped opens closes delta ends_semicolon
  local closer_re='^[]})][;]?$'
  local bare_re='^([A-Za-z_][A-Za-z0-9_-]*)([.]|[[:space:]]*=)'
  local quoted_re='^"([A-Za-z_][A-Za-z0-9_-]*)"([.]|[[:space:]]*=)'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 0 ]; then
      [[ "$line" =~ ^[[:space:]]{2}inputs[[:space:]]*=[[:space:]]*\{[[:space:]]*$ ]] && { in_block=1; depth=1; pending=0; }
      continue
    fi
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$trimmed" ] && continue
    [[ "$trimmed" == \#* ]] && continue
    stripped="$(printf '%s' "$line" | sed -E 's/"[^"]*"/""/g')"
    opens=$(printf '%s' "$stripped" | tr -dc '{([' | wc -c)
    closes=$(printf '%s' "$stripped" | tr -dc '])}' | wc -c)
    delta=$((opens - closes))
    ends_semicolon=0
    [[ "$(printf '%s' "$trimmed" | sed -E 's/"[^"]*"/""/g')" == *\; ]] && ends_semicolon=1

    if [[ "$trimmed" =~ $closer_re ]]; then
      depth=$((depth + delta))
      pending=0
      [ "$depth" -le 0 ] && in_block=0
      continue
    fi

    if [ "$depth" -eq 1 ] && [ "$pending" -eq 0 ]; then
      if [[ "$trimmed" =~ $bare_re ]]; then
        printf '%s\tok\n' "${BASH_REMATCH[1]}"
      elif [[ "$trimmed" =~ $quoted_re ]]; then
        printf '%s\tok\n' "${BASH_REMATCH[1]}"
      else
        printf '%s\tunsupported\n' "$trimmed"
      fi
      [ "$ends_semicolon" -eq 0 ] && pending=1
    fi

    depth=$((depth + delta))
    if [ "$depth" -le 0 ]; then in_block=0; continue; fi
    [ "$depth" -eq 1 ] && [ "$ends_semicolon" -eq 1 ] && pending=0
  done < "$file"
}

# Resolve every root-node input spec (a plain node-id string, or a `follows`
# path array relative to the lock root) to its final node id, and report
# whether that id is present in `.nodes`. `follows` paths can themselves
# terminate in a nested `follows` array (e.g. leanNixpkgs -> [leanBlaster,
# nixpkgs] where leanBlaster's own `nixpkgs` input is itself a 3-element
# path) — `resolve` recurses on that case.
reconcile_inputs() { # <nix-file> <lock-file> -> emits TSV: name spec resolved present declared
  local nix_file=$1 lock_file=$2
  jq -e . "$lock_file" >/dev/null 2>&1 || incomplete "$LOCK_REL is not valid JSON"
  local declared_json
  declared_json=$(extract_declared_inputs "$nix_file" | awk -F'\t' '$2 == "ok" { print $1 }' | jq -R . | jq -s .)
  jq -r --argjson declared "$declared_json" '
    def resolve($nodes; $root):
      . as $path
      | reduce $path[] as $seg ($root;
          ($nodes[.].inputs[$seg]) as $next
          | if ($next|type) == "string" then $next
            else ($next | resolve($nodes; $root))
            end
        );
    ($declared) as $decl
    | (.root) as $root
    | (.nodes) as $nodes
    | ($nodes[$root].inputs // {}) as $locked
    | ( [$decl[] , ($locked|keys[])] | unique ) as $allnames
    | $allnames[] as $name
    | ($decl | index($name) != null) as $isdeclared
    | ($locked | has($name)) as $islocked
    | ( if $islocked then $locked[$name] else null end ) as $spec
    | ( if $islocked then
          (if ($spec|type)=="string" then $spec else ($spec|resolve($nodes;$root)) end)
        else null end
      ) as $resolved
    | ( if $resolved == null then false else ($nodes|has($resolved)) end ) as $present
    | [$name, ($spec // "" | tostring), ($resolved // ""), $present, $isdeclared, $islocked]
    | @tsv
  ' "$lock_file"
}

# ─────────────────────────── invocation classification: justfile ───────────
#
# Per-line state machine over `justfile`, with backslash-continued physical
# lines joined into one logical command before classification. A column-0,
# non-comment line always resets the current recipe's tracked cwd (a new
# recipe body starts). Within a recipe body, a bare `cd offchain` (or
# `cd onchain`/`cd <dir>`) line sets the cwd for subsequent bare invocations
# in a `#!/usr/bin/env bash` script-body recipe (justfile runs each such body
# as ONE shell, so `cd` persists across its lines); a same-line
# `cd <dir> && nix ...` only affects that one command. See the
# population-scope note above the file header.
#
# Audit finding (submission 1, INV-259-NOWRITE): a `nix \`-continued command
# whose subcommand word landed on the NEXT physical line was invisible to a
# same-physical-line-only regex — it vanished from the population entirely
# rather than failing closed. Physical lines ending in `\` are now joined
# into one logical command (mirrors `just`'s own line-continuation, and the
# ci.yml literal-block joining below) before the nix-invocation check runs;
# a joined line containing the bare word `nix` that does NOT resolve to one
# of the five recognized subcommands is reported UNCLASSIFIABLE (fails
# closed) rather than silently dropped. `command -v <name>` is excluded from
# that bare-word scan on this one narrow, well-known idiom — `nix` there is
# an ARGUMENT being probed for existence, never a command being invoked, and
# six real recipes use exactly this idiom for a restricted-PATH control.
classify_justfile() { # <justfile> -> emits TSV per classified invocation: population lineno guarded line
  local file=$1 cwd="" lineno=0 line trimmed pop same_line_cd_dir
  local cont_buf="" cont_start=0

  classify_joined() { # <joined-text> <start-lineno>
    local joined=$1 startline=$2
    [ -z "$joined" ] && return 0
    [[ "$joined" == *nix* ]] || return 0
    local probe_stripped
    probe_stripped="$(printf '%s' "$joined" | sed -E 's/command[[:space:]]+-v[[:space:]]+[A-Za-z0-9_-]+/command -v PROBE/g')"
    [[ "$probe_stripped" =~ (^|[^A-Za-z0-9_])nix($|[^A-Za-z0-9_]) ]] || return 0
    local jtrimmed
    jtrimmed="$(printf '%s' "$joined" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if ! [[ "$joined" =~ nix[[:space:]]+(build|run|develop|shell|flake)([^A-Za-z0-9_]|$) ]]; then
      printf '%s\t%s\t%s\t%s\n' "unknown" "$startline" "0" "$jtrimmed"
      return 0
    fi
    local pop="unknown" same_line_cd_dir=""
    if [[ "$jtrimmed" =~ ^cd\ ([A-Za-z0-9_./-]+)\ \&\&\ nix\  ]]; then
      same_line_cd_dir="${BASH_REMATCH[1]}"
    fi
    if [[ "$joined" == *"github:"* ]]; then
      pop="remote"
    elif [[ "$joined" == *"nixpkgs#"* ]]; then
      pop="remote"
    elif [[ "$joined" == *"./offchain#"* || "$joined" == *"path:./offchain#"* \
        || "$joined" == *"path:../offchain#"* || "$joined" == *"../offchain#"* ]]; then
      pop="offchain"
    elif [[ "$same_line_cd_dir" == "offchain" ]]; then
      pop="offchain"
    elif [[ -n "$same_line_cd_dir" ]]; then
      pop="auxiliary"
    elif [[ "$cwd" == "offchain" ]]; then
      pop="offchain"
    elif [[ "$cwd" == other:* ]]; then
      pop="auxiliary"
    fi
    if [[ "$pop" == "offchain" || "$pop" == "unknown" ]]; then
      local guarded=0
      [[ "$joined" == *"--no-write-lock-file"* ]] && guarded=1
      printf '%s\t%s\t%s\t%s\n' "$pop" "$startline" "$guarded" "$jtrimmed"
    fi
  }

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ -z "$cont_buf" ]; then
      if [[ "$line" =~ ^[^[:space:]#] ]]; then
        cwd=""
        continue
      fi
      trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ "$trimmed" == \#* ]] && continue
      if [[ "$trimmed" == "cd offchain" ]]; then cwd="offchain"; continue; fi
      if [[ "$trimmed" =~ ^cd\ ([A-Za-z0-9_./-]+)$ ]]; then cwd="other:${BASH_REMATCH[1]}"; continue; fi
      cont_start=$lineno
    fi
    if [[ "$line" == *\\ ]]; then
      cont_buf="${cont_buf:+$cont_buf }${line%\\}"
      continue
    fi
    cont_buf="${cont_buf:+$cont_buf }${line}"
    classify_joined "$cont_buf" "$cont_start"
    cont_buf=""
  done < "$file"
  [ -n "$cont_buf" ] && classify_joined "$cont_buf" "$cont_start"
}

# ────────────────────── invocation classification: ci.yml ──────────────────
#
# YAML `run:` values need block-scalar-aware joining before classification,
# or a token split across lines (e.g. `nixpkgs#jq` on its own continuation
# line of a literal `nix shell \` command) is invisible to a per-physical-
# -line scan, and — more dangerously — a single `run: |` step can hold TWO
# unrelated commands (e.g. `nix build ./offchain#ckeri` then a separate
# `nix shell nixpkgs#... --command ...`), so flattening the whole step into
# one string would let the remote command's `nixpkgs#` token mis-classify
# the real offchain invocation as excluded. Literal (`|`) blocks: a content
# line at the block's own base indent starts a NEW logical command; a more
# deeply indented line continues the previous one (mirrors how these
# workflow steps use trailing `\` shell continuation). Folded (`>`) blocks:
# every content line joins into exactly ONE command regardless of indent
# (YAML folding semantics) — this repo's only folded, in-population step
# (`build-gate`'s `nix build --quiet .#checks... .#packages...`) is exactly
# that shape.
classify_workflow() { # <ci.yml> -> emits TSV per classified invocation: population lineno guarded cmd
  local file=$1 cwd="" lineno=0 line trimmed ind content
  local in_run=0 run_indent=-1 run_style="" base_indent=-1 cmd_buf="" cmd_start=0

  indent_of() { local s=$1 n=0; while [[ "${s:$n:1}" == " " ]]; do n=$((n + 1)); done; echo "$n"; }

  emit_if_offchain_or_unknown() { # <buf> <startline>
    local buf=$1 startline=$2 pop="unknown" guarded=0
    [[ -z "$buf" ]] && return 0
    [[ "$buf" == *nix* ]] || return 0
    local probe_stripped
    probe_stripped="$(printf '%s' "$buf" | sed -E 's/command[[:space:]]+-v[[:space:]]+[A-Za-z0-9_-]+/command -v PROBE/g')"
    [[ "$probe_stripped" =~ (^|[^A-Za-z0-9_])nix($|[^A-Za-z0-9_]) ]] || return 0
    if ! [[ "$buf" =~ nix[[:space:]]+(build|run|develop|shell|flake)([^A-Za-z0-9_]|$) ]]; then
      printf '%s\t%s\t%s\t%s\n' "unknown" "$startline" "0" "$buf"
      return 0
    fi
    if [[ "$buf" == *"github:"* ]]; then
      pop="remote"
    elif [[ "$buf" == *"nixpkgs#"* ]]; then
      pop="remote"
    elif [[ "$buf" == *"./offchain#"* || "$buf" == *"path:./offchain#"* || "$buf" == *"../offchain#"* ]]; then
      pop="offchain"
    elif [[ "$cwd" == "offchain" ]]; then
      pop="offchain"
    elif [[ -n "$cwd" ]]; then
      pop="auxiliary"
    fi
    if [[ "$pop" == "offchain" || "$pop" == "unknown" ]]; then
      [[ "$buf" == *"--no-write-lock-file"* ]] && guarded=1
      printf '%s\t%s\t%s\t%s\n' "$pop" "$startline" "$guarded" "$buf"
    fi
  }
  finalize_cmd() { [[ -n "$cmd_buf" ]] && emit_if_offchain_or_unknown "$cmd_buf" "$cmd_start"; cmd_buf=""; }

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    ind=$(indent_of "$line")
    content="${line:$ind}"

    if [[ $in_run -eq 1 ]]; then
      if [[ -z "$content" ]]; then continue; fi
      if [[ $ind -le $run_indent ]]; then
        finalize_cmd
        in_run=0
        # fall through: this line is handled as an ordinary line below
      else
        if [[ "$run_style" == "folded" ]]; then
          [[ -z "$cmd_buf" ]] && cmd_start=$lineno
          cmd_buf="${cmd_buf:+$cmd_buf }${content%\\}"
        else
          [[ $base_indent -eq -1 ]] && base_indent=$ind
          if [[ $ind -eq $base_indent ]]; then
            finalize_cmd
            cmd_start=$lineno
            cmd_buf="${content%\\}"
          else
            cmd_buf="${cmd_buf:+$cmd_buf }${content%\\}"
          fi
        fi
        continue
      fi
    fi

    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ "$trimmed" =~ ^-\ (name:|uses:) ]]; then cwd=""; continue; fi
    if [[ "$line" =~ ^[a-zA-Z0-9_-]+:$ ]]; then cwd=""; continue; fi
    if [[ "$trimmed" =~ ^working-directory:\ (.+)$ ]]; then cwd="${BASH_REMATCH[1]}"; continue; fi
    [[ "$trimmed" == \#* ]] && continue
    if [[ "$trimmed" =~ ^run:\ *(.*)$ ]]; then
      local tail="${BASH_REMATCH[1]}"
      run_indent=$ind
      base_indent=-1
      cmd_buf=""
      case "$tail" in
        '|' | '|-' | '|+') in_run=1; run_style="literal" ;;
        '>' | '>-' | '>+') in_run=1; run_style="folded" ;;
        '') in_run=0 ;;
        *) emit_if_offchain_or_unknown "$tail" "$lineno" ;;
      esac
      continue
    fi
  done < "$file"
  [[ $in_run -eq 1 ]] && finalize_cmd
  return 0
}

# ──────────────────────────────── normal mode ───────────────────────────────

normal_mode() {
  local nix_file="$REPO_ROOT/$NIX_REL" lock_file="$REPO_ROOT/$LOCK_REL"
  local just_file="$REPO_ROOT/$JUST_REL" ci_file="$REPO_ROOT/$CI_REL"
  [ -r "$nix_file" ] || incomplete "cannot read $NIX_REL from repo root '$REPO_ROOT'"
  [ -r "$lock_file" ] || incomplete "cannot read $LOCK_REL from repo root '$REPO_ROOT'"
  [ -r "$just_file" ] || incomplete "cannot read $JUST_REL from repo root '$REPO_ROOT'"
  [ -r "$ci_file" ] || incomplete "cannot read $CI_REL from repo root '$REPO_ROOT'"

  local ok=1

  # --- DATA-INV-259-01: declared/locked reconciliation ---
  local unsupported_count=0 uname ustatus
  while IFS=$'\t' read -r uname ustatus; do
    if [ "$ustatus" = "unsupported" ]; then
      unsupported_count=$((unsupported_count + 1))
      ok=0
      echo "check-flake-lock-guard: unsupported declaration form in $NIX_REL: $uname" >&2
    fi
  done < <(extract_declared_inputs "$nix_file")
  echo "CFLG_RESULT unsupported_declarations=$unsupported_count"

  local declared_count=0 locked_count=0 unreconciled=0 row name spec resolved present isdeclared islocked
  while IFS=$'\t' read -r name spec resolved present isdeclared islocked; do
    [ "$isdeclared" = "true" ] && declared_count=$((declared_count + 1))
    [ "$islocked" = "true" ] && locked_count=$((locked_count + 1))
    if [ "$isdeclared" != "true" ] || [ "$islocked" != "true" ] || [ "$present" != "true" ]; then
      unreconciled=$((unreconciled + 1))
      ok=0
      echo "check-flake-lock-guard: unreconciled input '$name' (declared=$isdeclared locked=$islocked resolved-present=$present spec='$spec')" >&2
    fi
  done < <(reconcile_inputs "$nix_file" "$lock_file")
  [ "$declared_count" -gt 0 ] || { ok=0; echo "check-flake-lock-guard: zero declared inputs extracted from $NIX_REL — parser or population fault" >&2; }
  echo "CFLG_RESULT declared_inputs=$declared_count"
  echo "CFLG_RESULT locked_root_entries=$locked_count"
  echo "CFLG_RESULT unreconciled_inputs=$unreconciled"

  # --- INV-259-NOWRITE: justfile invocations ---
  local jf_total=0 jf_unguarded=0 pop lineno guarded rest
  while IFS=$'\t' read -r pop lineno guarded rest; do
    if [ "$pop" = "unknown" ]; then
      ok=0
      echo "check-flake-lock-guard: $JUST_REL:$lineno unclassifiable primary-offchain-shaped invocation: $rest" >&2
      continue
    fi
    jf_total=$((jf_total + 1))
    if [ "$guarded" != "1" ]; then
      jf_unguarded=$((jf_unguarded + 1))
      ok=0
      echo "check-flake-lock-guard: $JUST_REL:$lineno missing --no-write-lock-file: $rest" >&2
    fi
  done < <(classify_justfile "$just_file")
  [ "$jf_total" -gt 0 ] || { ok=0; echo "check-flake-lock-guard: zero primary-offchain invocations classified in $JUST_REL — GATE-INCOMPLETE-shaped, refusing to pass vacuously" >&2; }
  echo "CFLG_RESULT justfile_invocations=$jf_total"
  echo "CFLG_RESULT justfile_unguarded=$jf_unguarded"

  # --- INV-259-NOWRITE: ci.yml invocations ---
  local wf_total=0 wf_unguarded=0
  while IFS=$'\t' read -r pop lineno guarded rest; do
    if [ "$pop" = "unknown" ]; then
      ok=0
      echo "check-flake-lock-guard: $CI_REL:$lineno unclassifiable primary-offchain-shaped invocation: $rest" >&2
      continue
    fi
    wf_total=$((wf_total + 1))
    if [ "$guarded" != "1" ]; then
      wf_unguarded=$((wf_unguarded + 1))
      ok=0
      echo "check-flake-lock-guard: $CI_REL:$lineno missing --no-write-lock-file: $rest" >&2
    fi
  done < <(classify_workflow "$ci_file")
  [ "$wf_total" -gt 0 ] || { ok=0; echo "check-flake-lock-guard: zero primary-offchain invocations classified in $CI_REL — GATE-INCOMPLETE-shaped, refusing to pass vacuously" >&2; }
  echo "CFLG_RESULT workflow_invocations=$wf_total"
  echo "CFLG_RESULT workflow_unguarded=$wf_unguarded"

  # --- INV-259-PARITY: both files must call this guard, as executable text ---
  local caller_justfile=0 caller_workflow=0
  has_executable_caller "$just_file" 'check-flake-lock-guard.sh' && caller_justfile=1
  has_executable_caller "$ci_file" 'check-flake-lock-guard.sh' && caller_workflow=1
  [ "$caller_justfile" -eq 1 ] || { ok=0; echo "check-flake-lock-guard: $JUST_REL no longer calls check-flake-lock-guard.sh (as executable text)" >&2; }
  [ "$caller_workflow" -eq 1 ] || { ok=0; echo "check-flake-lock-guard: $CI_REL no longer calls check-flake-lock-guard.sh (as executable text)" >&2; }
  echo "CFLG_RESULT caller_justfile=$caller_justfile"
  echo "CFLG_RESULT caller_workflow=$caller_workflow"

  # --- INV-259-ASSERT: `just ci` must still call the post-dependency
  # lock-unchanged assertion (this script's --assert-lock-unchanged mode).
  # Audit finding (submission 1): the assertion existed and ran in the
  # audited candidate, but nothing constrained its CONTINUED presence — a
  # deleted assertion block survived at exit 0. This is the presence half of
  # the fix; --assert-lock-unchanged's own self-test leg (below) proves the
  # mechanism it calls can actually fail.
  local caller_assert=0
  has_executable_caller "$just_file" '--assert-lock-unchanged' && caller_assert=1
  [ "$caller_assert" -eq 1 ] || { ok=0; echo "check-flake-lock-guard: $JUST_REL's ci recipe no longer calls check-flake-lock-guard.sh --assert-lock-unchanged" >&2; }
  echo "CFLG_RESULT caller_assert=$caller_assert"

  # --- INV-259-SWEEP (advisory): onchain/ has no flake/lock pair ---
  local onchain_pair="absent"
  if [ -e "$REPO_ROOT/onchain/flake.nix" ] || [ -e "$REPO_ROOT/onchain/flake.lock" ]; then
    onchain_pair="present"
    echo "check-flake-lock-guard: ADVISORY: onchain/flake.nix or onchain/flake.lock now exists; INV-259-SWEEP's base assumption (no onchain flake/lock pair) no longer holds — re-scope if onchain gains its own flake" >&2
  fi
  echo "CFLG_RESULT onchain_flake_pair=$onchain_pair"

  if [ "$ok" -eq 1 ]; then
    echo "CFLG_RESULT result=pass"
    echo "check-flake-lock-guard: PASS — $declared_count/$declared_count inputs reconciled (0 unsupported), $jf_total/$jf_total justfile invocations guarded, $wf_total/$wf_total workflow invocations guarded, both callers and the assert-caller present"
    return 0
  else
    echo "CFLG_RESULT result=fail"
    return 1
  fi
}

# ─────────────────────────────── self-test mode ─────────────────────────────
#
# Synthetic fixture, not the real worktree: at RED time (before the justfile
# and workflow are guarded) the real files legitimately fail this checker, so
# copying them would not exercise the negative-control CLASSES this step
# owns. A small, fully-compliant fixture lets every leg assert a NAMED
# failure reason, not just "some nonzero exit".

FIXTURE_NIX='{
  inputs = {
    flakeA.url = "github:example/flakeA";
    flakeB.follows = "flakeA/nixpkgs";
  };
  outputs = { self, flakeA, flakeB, ... }: { };
}
'

FIXTURE_LOCK='{
  "nodes": {
    "flakeA": {
      "inputs": { "nixpkgs": "nixpkgs_a" },
      "locked": { "type": "github", "owner": "example", "repo": "flakeA", "rev": "0000000000000000000000000000000000000000" },
      "original": { "type": "github", "owner": "example", "repo": "flakeA" }
    },
    "nixpkgs_a": {
      "locked": { "type": "github", "owner": "example", "repo": "nixpkgs", "rev": "1111111111111111111111111111111111111111" },
      "original": { "type": "github", "owner": "example", "repo": "nixpkgs" }
    },
    "root": {
      "inputs": { "flakeA": "flakeA", "flakeB": ["flakeA", "nixpkgs"] }
    }
  },
  "root": "root",
  "version": 7
}
'

FIXTURE_JUSTFILE='check-flake-lock-guard:
    ./scripts/check-flake-lock-guard.sh

build-offchain:
    cd offchain && nix build --quiet --no-write-lock-file .#foo

ci: check-flake-lock-guard build-offchain
    ./scripts/check-flake-lock-guard.sh --assert-lock-unchanged
'

FIXTURE_CI='jobs:
  flake-lock-guard:
    steps:
      - name: guard
        run: bash scripts/check-flake-lock-guard.sh
  offchain:
    steps:
      - name: build
        working-directory: offchain
        run: nix build --quiet --no-write-lock-file .#foo
'

write_fixture() { # <root>
  local root=$1
  mkdir -p "$root/offchain" "$root/.github/workflows" "$root/scripts"
  printf '%s' "$FIXTURE_NIX" > "$root/$NIX_REL"
  printf '%s' "$FIXTURE_LOCK" > "$root/$LOCK_REL"
  printf '%s' "$FIXTURE_JUSTFILE" > "$root/$JUST_REL"
  printf '%s' "$FIXTURE_CI" > "$root/$CI_REL"
}

SEED_LEG_FAILURES=0

run_seed_leg() { # <key> <label> <expected-diagnostic-substring> <mutator-fn-or-empty>
  local key=$1 label=$2 expect=$3 mut=${4:-} root out rc
  root=$(mktemp -d "${TMPDIR:-/tmp}/flake-lock-guard-seed-$key.XXXXXXXX") \
    || fail "COULD-NOT-EVALUATE: $label: mktemp failed"
  write_fixture "$root" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: could not build the fixture"; }
  if [ -n "$mut" ]; then
    "$mut" "$root" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: the seed mutator failed, so the control never ran"; }
  fi
  set +e
  out=$("$SELF" --repo-root "$root" 2>&1); rc=$?
  set -e
  rm -rf "$root"
  if [ -n "$expect" ]; then
    if [ "$rc" -eq 1 ] && [[ $out == *"$expect"* ]]; then
      echo "$label: exit $rc (required 1), expected diagnostic present"
    else
      SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
      echo "$label: FAIL — exit $rc (required 1) and/or missing diagnostic '$expect'" >&2
      printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
    fi
  else
    if [ "$rc" -eq 0 ]; then
      echo "$label: exit $rc (required 0)"
    else
      SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
      echo "$label: FAIL — exit $rc (required 0)" >&2
      printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
    fi
  fi
  echo "CFLG_RESULT ${key}_rc=$rc"
}

mut_incomplete_lock() { # <root> — delete the flakeA lock NODE (root.inputs still names it), mirrors the required deployPreprod mutation
  local root=$1
  jq 'del(.nodes.flakeA)' "$root/$LOCK_REL" > "$root/$LOCK_REL.tmp" && mv "$root/$LOCK_REL.tmp" "$root/$LOCK_REL"
}

# Audit finding (submission 1, DATA-INV-259-01): a QUOTED declared input
# (valid nix syntax the prior parser never recognized) with no lock entry
# was invisible rather than reported unreconciled. Add one — same lock file,
# so the ONLY defect is the missing lock entry for a name that IS enumerated.
mut_unlocked_quoted_input() { # <root>
  local root=$1
  sed -i '/^  inputs = {$/a\    "flakeC".url = "github:example/flakeC";' "$root/$NIX_REL"
}

# A quoted key containing a character (space) outside the supported
# identifier charset: legal nix, unsupported by this parser's two enumerated
# spellings — must fail closed, not silently vanish a third way.
mut_unsupported_declaration() { # <root>
  local root=$1
  sed -i '/^  inputs = {$/a\    "my weird name".url = "github:example/weird";' "$root/$NIX_REL"
}

mut_unguarded_invocation() { # <root> — strip --no-write-lock-file from the one justfile invocation
  local root=$1
  sed -i 's/ --no-write-lock-file//' "$root/$JUST_REL"
}

# Audit finding (submission 1, INV-259-NOWRITE): a `nix \`-continued command
# whose SUBCOMMAND WORD lands on the next physical line, with the guard flag
# dropped in the same edit — a realistic "someone reformatted this and
# forgot the flag" continuation, deliberately NOT the exact bytes of the
# frozen seed instrument (which inserts a literal stray "+" token): the
# property this owns is "joined logical commands are classified", not
# "this one seeded string is recognized", so the control uses independently
# constructed continuation syntax.
mut_continued_unguarded_command() { # <root>
  local root=$1
  perl -0pi -e 's/cd offchain && nix build --quiet --no-write-lock-file \.#foo/cd offchain && nix \\\n        build --quiet .#foo/' "$root/$JUST_REL" 2>/dev/null \
    || sed -i 's|cd offchain && nix build --quiet --no-write-lock-file \.#foo|cd offchain \&\& nix \\\n        build --quiet .#foo|' "$root/$JUST_REL"
}

# Audit finding (submission 1, INV-259-PARITY): commenting out an executable
# caller line (text retained) survived. Each caller commented independently.
mut_commented_caller_justfile() { # <root> — comment out every justfile line invoking the script (bare call and --assert-lock-unchanged alike), isolating "no live caller_justfile" from "assert caller specifically missing" (mut_missing_assert_caller, below)
  local root=$1
  sed -i 's|^\([[:space:]]*\)\(\./scripts/check-flake-lock-guard\.sh.*\)$|\1# \2|' "$root/$JUST_REL"
}

mut_commented_caller_workflow() { # <root>
  local root=$1
  sed -i 's|^        run: bash scripts/check-flake-lock-guard\.sh$|        # run: bash scripts/check-flake-lock-guard.sh|' "$root/$CI_REL"
}

# Audit finding (submission 1, INV-259-ASSERT): the assertion existed in the
# audited candidate but nothing constrained its continued presence. Remove
# only the --assert-lock-unchanged call from `ci`, leaving the guard caller.
mut_missing_assert_caller() { # <root>
  local root=$1
  sed -i '/--assert-lock-unchanged/d' "$root/$JUST_REL"
}

mut_missing_caller() { # <root> — remove the guard-calling recipe/step from BOTH files
  local root=$1
  printf 'build-offchain:\n    cd offchain && nix build --quiet --no-write-lock-file .#foo\n' > "$root/$JUST_REL"
  printf 'jobs:\n  offchain:\n    steps:\n      - name: build\n        working-directory: offchain\n        run: nix build --quiet --no-write-lock-file .#foo\n' > "$root/$CI_REL"
}

mut_zero_population() { # <root> — replace the only offchain invocation in both files with a non-nix command
  local root=$1
  printf 'check-flake-lock-guard:\n    ./scripts/check-flake-lock-guard.sh\n\nbuild-offchain:\n    cd offchain && echo noop\n' > "$root/$JUST_REL"
  printf 'jobs:\n  flake-lock-guard:\n    steps:\n      - name: guard\n        run: bash scripts/check-flake-lock-guard.sh\n  offchain:\n    steps:\n      - name: build\n        working-directory: offchain\n        run: echo noop\n' > "$root/$CI_REL"
}

mut_onchain_pair_present() { # <root> — advisory value control: onchain/ gains a flake.nix
  local root=$1
  mkdir -p "$root/onchain"
  printf '%s\n' '{ outputs = _: {}; }' > "$root/onchain/flake.nix"
}

# `--assert-lock-unchanged`'s own mechanism (git-diff-based) is not
# fixture-shaped — proved separately against a real temporary git repo:
# GREEN (unchanged tracked lock) must exit 0, RED (dirtied tracked lock)
# must exit 1. `-c commit.gpgsign=false` per this repo's seed-commit
# convention, so a signing agent can never wedge this self-test.
run_assert_mechanism_legs() {
  local root rc_green rc_red out
  root=$(mktemp -d "${TMPDIR:-/tmp}/flake-lock-guard-assert.XXXXXXXX") \
    || fail "COULD-NOT-EVALUATE: assert-mechanism legs: mktemp failed"
  git -C "$root" init -q
  git -C "$root" -c user.email=t@t -c user.name=t config commit.gpgsign false
  mkdir -p "$root/offchain"
  printf '{"a":1}\n' > "$root/$LOCK_REL"
  git -C "$root" add "$LOCK_REL"
  git -C "$root" -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -q -m seed

  set +e
  out=$("$SELF" --repo-root "$root" --assert-lock-unchanged 2>&1); rc_green=$?
  set -e
  if [ "$rc_green" -eq 0 ]; then
    echo "assert-mechanism GREEN leg (unchanged lock): exit $rc_green (required 0)"
  else
    SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
    echo "assert-mechanism GREEN leg (unchanged lock): FAIL — exit $rc_green (required 0)" >&2
    printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
  fi
  echo "CFLG_RESULT assert_mechanism_green_rc=$rc_green"

  printf '{"a":2}\n' > "$root/$LOCK_REL"
  set +e
  out=$("$SELF" --repo-root "$root" --assert-lock-unchanged 2>&1); rc_red=$?
  set -e
  if [ "$rc_red" -eq 1 ] && [[ $out == *"INV-259-ASSERT violated"* ]]; then
    echo "assert-mechanism RED leg (dirtied lock): exit $rc_red (required 1), expected diagnostic present"
  else
    SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
    echo "assert-mechanism RED leg (dirtied lock): FAIL — exit $rc_red (required 1) and/or missing diagnostic" >&2
    printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
  fi
  echo "CFLG_RESULT assert_mechanism_red_rc=$rc_red"
  rm -rf "$root"
}

# INV-259-SWEEP is ADVISORY: presence must be reported, never treated as
# blocking. A dedicated check (not run_seed_leg, whose contract is pass/fail
# on exit code) since this leg requires exit 0 AND a specific value.
run_onchain_pair_leg() {
  local root out rc
  root=$(mktemp -d "${TMPDIR:-/tmp}/flake-lock-guard-seed-onchain.XXXXXXXX") \
    || fail "COULD-NOT-EVALUATE: onchain-pair-present leg: mktemp failed"
  write_fixture "$root" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: onchain-pair-present leg: could not build the fixture"; }
  mut_onchain_pair_present "$root" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: onchain-pair-present leg: mutator failed"; }
  set +e
  out=$("$SELF" --repo-root "$root" 2>&1); rc=$?
  set -e
  rm -rf "$root"
  if [ "$rc" -eq 0 ] && [[ $out == *"CFLG_RESULT onchain_flake_pair=present"* ]]; then
    echo "onchain-pair-present leg (advisory value control): exit $rc (required 0), onchain_flake_pair=present reported"
  else
    SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
    echo "onchain-pair-present leg (advisory value control): FAIL — exit $rc (required 0) and/or onchain_flake_pair not reported present" >&2
    printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
  fi
  echo "CFLG_RESULT onchain_pair_present_rc=$rc"
}

self_test_mode() {
  echo "self-test: seeding GREEN control plus negative/value controls on a synthetic fixture (temporary roots only)"

  run_seed_leg green "GREEN leg (unmodified fixture)" "" ""
  run_seed_leg incomplete_lock "RED leg (incomplete lock)" \
    "unreconciled input 'flakeA'" mut_incomplete_lock
  run_seed_leg unlocked_quoted_input "RED leg (valid quoted syntax, unlocked)" \
    "unreconciled input 'flakeC'" mut_unlocked_quoted_input
  run_seed_leg unsupported_declaration "RED leg (unsupported declaration spelling)" \
    "unsupported declaration form" mut_unsupported_declaration
  run_seed_leg unguarded_invocation "RED leg (unguarded invocation)" \
    "missing --no-write-lock-file" mut_unguarded_invocation
  run_seed_leg continued_unguarded_command "RED leg (continuation drops guard flag)" \
    "missing --no-write-lock-file" mut_continued_unguarded_command
  run_seed_leg commented_caller_justfile "RED leg (justfile caller commented out)" \
    "$JUST_REL no longer calls check-flake-lock-guard.sh" mut_commented_caller_justfile
  run_seed_leg commented_caller_workflow "RED leg (workflow caller commented out)" \
    "$CI_REL no longer calls check-flake-lock-guard.sh" mut_commented_caller_workflow
  run_seed_leg missing_assert_caller "RED leg (assert caller removed from ci)" \
    "no longer calls check-flake-lock-guard.sh --assert-lock-unchanged" mut_missing_assert_caller
  run_seed_leg missing_caller "RED leg (missing caller)" \
    "no longer calls check-flake-lock-guard.sh" mut_missing_caller
  run_seed_leg zero_population "RED leg (zero population)" \
    "GATE-INCOMPLETE-shaped, refusing to pass vacuously" mut_zero_population

  run_assert_mechanism_legs
  run_onchain_pair_leg

  if [ "$SEED_LEG_FAILURES" -eq 0 ]; then
    echo "CFLG_RESULT selftest=pass"
    echo "self-test: PASS — all seeded legs failed/passed for their stated reason"
    return 0
  else
    echo "CFLG_RESULT selftest=fail"
    echo "CFLG_RESULT failures=$SEED_LEG_FAILURES"
    echo "self-test: FAIL — $SEED_LEG_FAILURES leg(s) did not fail/pass for the stated reason" >&2
    return 1
  fi
}

# ───────────────────────── --assert-lock-unchanged mode ─────────────────────
#
# INV-259-ASSERT's actual mechanism: `offchain/flake.lock` must be
# byte-identical to its committed blob. `just ci`'s body calls this instead
# of inlining the check, so the ONE property proof below (self-test, pure
# git, no Nix) exercises the exact code `just ci` runs — not a copy of it.
assert_lock_unchanged_mode() {
  local lock_file="$REPO_ROOT/$LOCK_REL"
  [ -r "$lock_file" ] || incomplete "cannot read $LOCK_REL from repo root '$REPO_ROOT'"
  local rc
  set +e
  ( cd "$REPO_ROOT" && git diff --exit-code -- "$LOCK_REL" )
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "check-flake-lock-guard: $LOCK_REL unchanged (INV-259-ASSERT)"
    return 0
  fi
  echo "check-flake-lock-guard: FAIL: $LOCK_REL changed — INV-259-ASSERT violated (diff above)" >&2
  return 1
}

if [ "$ASSERT_LOCK_UNCHANGED" -eq 1 ]; then
  assert_lock_unchanged_mode
elif [ "$SELF_TEST" -eq 1 ]; then
  self_test_mode
else
  normal_mode
fi
