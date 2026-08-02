#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --no-loss BIN | --no-leak BIN | --self-test" >&2
  exit 2
}

fail() {
  echo "follower-capability check failed: $*" >&2
  exit 1
}

capture_help() {
  local binary=$1
  shift
  local output

  if ! output=$("$binary" "$@" --help 2>&1); then
    fail "could not read help for: $binary $*"
  fi
  printf '%s\n' "$output"
}

has_top_level_command() {
  local command_name=$1
  grep -Eq "^[[:space:]]{0,8}${command_name}([[:space:]]|$)"
}

require_help_option() {
  local command_name=$1
  local help_text=$2
  local option_name=$3

  grep -Fq -- "$option_name" <<<"$help_text" \
    || fail "retained command '$command_name' help is missing $option_name"
}

check_no_loss() {
  local binary=$1
  [[ -x "$binary" ]] || fail "binary is not executable: $binary"

  local top_help command_name command_help
  top_help=$(capture_help "$binary")

  for command_name in status list checkpoint payer; do
    has_top_level_command "$command_name" <<<"$top_help" \
      || fail "packaged ckeri is missing retained top-level capability '$command_name'"
    command_help=$(capture_help "$binary" "$command_name")
    require_help_option "$command_name" "$command_help" "--backend"
    require_help_option "$command_name" "$command_help" "CKERI_BACKEND"
    require_help_option "$command_name" "$command_help" "${command_name}.backend"
    case "$command_name" in
      status|checkpoint)
        require_help_option "$command_name" "$command_help" "--aid"
        require_help_option "$command_name" "$command_help" "CKERI_AID"
        require_help_option "$command_name" "$command_help" "${command_name}.aid"
        ;;
      payer)
        require_help_option "$command_name" "$command_help" "--address"
        require_help_option "$command_name" "$command_help" "CKERI_ADDRESS"
        require_help_option "$command_name" "$command_help" "payer.address"
        ;;
    esac
  done
}

check_no_leak() {
  local binary=$1
  [[ -x "$binary" ]] || fail "binary is not executable: $binary"

  local top_help combined command_name command_help
  top_help=$(capture_help "$binary")
  combined=$top_help

  for command_name in status list checkpoint payer; do
    if has_top_level_command "$command_name" <<<"$top_help"; then
      command_help=$(capture_help "$binary" "$command_name")
      combined+=$'\n'
      combined+=$command_help
    fi
  done

  for command_name in help quit; do
    if has_top_level_command "$command_name" <<<"$top_help"; then
      fail "excluded REPL affordance leaked as top-level command '$command_name'"
    fi
  done

  grep -Eiq 'ckeri>|(^|[[:space:]])verbs:|(^|[^[:alnum:]_])(completion|history)([^[:alnum:]_]|$)|progress([[:space:]_-]+(loop|frame|framing)|:)' <<<"$combined" \
    && fail "forbidden REPL prompt/completion/history/progress framing leaked into packaged help"

  return 0
}

write_fake() {
  local path=$1
  local top_commands=$2
  local extra=${3:-}

  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf 'top_commands=%q\n' "$top_commands"
    printf 'extra=%q\n' "$extra"
    cat <<'FAKE'
case "${1:-}" in
  --help|-h)
    printf 'Usage: ckeri COMMAND\nCommands:\n%s\n%s\n' "$top_commands" "$extra"
    ;;
  status|checkpoint)
    printf 'Usage: ckeri %s --aid AID --backend BACKEND\nenv: CKERI_AID\nenv: CKERI_BACKEND\nconfig: %s.aid %s.backend\n' "$1" "$1" "$1"
    ;;
  list)
    printf 'Usage: ckeri list --backend BACKEND\nenv: CKERI_BACKEND\nconfig: list.backend\n'
    ;;
  payer)
    printf 'Usage: ckeri payer --address ADDRESS --backend BACKEND\nenv: CKERI_ADDRESS\nenv: CKERI_BACKEND\nconfig: payer.address payer.backend\n'
    ;;
  *)
    exit 2
    ;;
esac
FAKE
  } >"$path"
  chmod 755 "$path"
}

expect_failure() {
  local expected=$1
  shift
  local output

  if output=$("$@" 2>&1); then
    fail "negative control unexpectedly passed: $*"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "negative control did not report '$expected': $output"
}

self_test_fixture_dir=

cleanup_self_test() {
  if [[ -n "$self_test_fixture_dir" && -d "$self_test_fixture_dir" ]]; then
    rm -rf -- "$self_test_fixture_dir"
  fi
}

self_test() {
  local good loss leak
  self_test_fixture_dir=$(mktemp -d)
  trap cleanup_self_test EXIT
  good="$self_test_fixture_dir/good-ckeri"
  loss="$self_test_fixture_dir/loss-ckeri"
  leak="$self_test_fixture_dir/leak-ckeri"

  write_fake "$good" $'  status  status\n  list  list\n  checkpoint  checkpoint\n  payer  payer'
  write_fake "$loss" $'  status  status\n  list  list\n  checkpoint  checkpoint'
  write_fake "$leak" $'  status  status\n  list  list\n  checkpoint  checkpoint\n  payer  payer\n  help  shell help\n  quit  quit shell' 'ckeri> verbs: completion history progress:'

  check_no_loss "$good"
  check_no_leak "$good"
  expect_failure "missing retained top-level capability 'payer'" "$0" --no-loss "$loss"
  expect_failure "excluded REPL affordance leaked as top-level command 'help'" "$0" --no-leak "$leak"
  echo "follower-capability self-test: PASS (no-loss and no-leak controls both rejected their mutation)"
}

case "${1:-}" in
  --no-loss)
    [[ $# -eq 2 ]] || usage
    check_no_loss "$2"
    ;;
  --no-leak)
    [[ $# -eq 2 ]] || usage
    check_no_leak "$2"
    ;;
  --self-test)
    [[ $# -eq 1 ]] || usage
    self_test
    ;;
  *)
    usage
    ;;
esac
