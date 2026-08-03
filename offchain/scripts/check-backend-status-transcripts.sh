#!/usr/bin/env bash
set -euo pipefail

readonly accepted_aid=EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi

usage() {
  cat <<'EOF'
Usage: check-backend-status-transcripts.sh --transcript FILE [--raw-dir DIR]

Validate the structure, provenance metadata, accepted AID, backend command
shapes, and result vocabulary in a three-backend status transcript.

When --raw-dir is supplied, also reconcile every raw-file SHA-256 against the
actual bytes below DIR and cross-check successful output's common-renderer
source marker. Without --raw-dir, validation is deterministic and checks only
the transcript-internal metadata; it does not read or reconcile raw captures.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

transcript=
raw_dir=
while (($# > 0)); do
  case $1 in
    --transcript)
      (($# >= 2)) || die '--transcript requires a file'
      transcript=$2
      shift 2
      ;;
    --raw-dir)
      (($# >= 2)) || die '--raw-dir requires a directory'
      raw_dir=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n $transcript ]] || die '--transcript is required'
[[ -f $transcript && ! -L $transcript ]] || die "transcript is not a regular file: $transcript"
if [[ -n $raw_dir ]]; then
  [[ -d $raw_dir ]] || die "raw directory does not exist: $raw_dir"
fi

declare -A values=()
declare -A seen_fields=()
declare -A global_values=()
declare -A seen_global_fields=()
record_count=0
line_number=0

while IFS= read -r line || [[ -n $line ]]; do
  line_number=$((line_number + 1))
  [[ $line != *$'\r'* ]] || die "unsafe transcript text at line $line_number: carriage return"
  [[ -n $line ]] || continue

  if [[ $line =~ ^record:\ ([1-9][0-9]*)$ ]]; then
    record_count=$((record_count + 1))
    [[ ${BASH_REMATCH[1]} -eq $record_count ]] ||
      die "record numbering must be contiguous from 1 at line $line_number"
    continue
  fi

  [[ $line =~ ^([a-z][a-z0-9-]*):\ (.*)$ ]] ||
    die "unsafe transcript text at line $line_number"
  field=${BASH_REMATCH[1]}
  value=${BASH_REMATCH[2]}
  if ((record_count == 0)); then
    case $field in
      evidence-version|source-commit|backend-code-commit|candidate-build-handoff-sha256|candidate-out-link|candidate-store-path|source-store|source-store-sha256-before|source-store-sha256-after|store-copy|store-copy-sha256-preopen|store-copy-sha256-postopen|local-as-of-source|endpoint-as-of-source|koios-as-of-source) ;;
      *) die "unsafe transcript header field at line $line_number: $field" ;;
    esac
    [[ -n $value ]] || die "missing $field"
    [[ -z ${seen_global_fields[$field]:-} ]] || die "duplicate transcript header $field"
    seen_global_fields[$field]=1
    global_values[$field]=$value
    continue
  fi
  case $field in
    backend|aid|utc|operator|host|pane|binary|binary-sha256|store|source|cwd|command|raw-file|raw-sha256|exit-status|result) ;;
    *) die "unsafe transcript field at line $line_number: $field" ;;
  esac
  [[ -n $value ]] || die "record $record_count: missing $field"
  key="$record_count|$field"
  [[ -z ${seen_fields[$key]:-} ]] || die "record $record_count: duplicate $field"
  seen_fields[$key]=1
  values[$key]=$value
done <"$transcript"

[[ $record_count -eq 3 ]] || die "expected exactly 3 records, found $record_count"

readonly required_global_fields=(
  evidence-version source-commit backend-code-commit
  candidate-build-handoff-sha256 candidate-out-link candidate-store-path
  source-store source-store-sha256-before source-store-sha256-after store-copy
  store-copy-sha256-preopen store-copy-sha256-postopen local-as-of-source
  endpoint-as-of-source koios-as-of-source
)
for field in "${required_global_fields[@]}"; do
  [[ -n ${global_values[$field]:-} ]] || die "missing $field"
done

[[ ${global_values[evidence-version]} == 1 ]] || die 'evidence-version must be 1'
[[ ${global_values[source-commit]} =~ ^[0-9a-f]{40}$ ]] || die 'invalid source-commit'
[[ ${global_values[backend-code-commit]} =~ ^[0-9a-f]{40}$ ]] || die 'invalid backend-code-commit'
[[ ${global_values[candidate-build-handoff-sha256]} =~ ^[0-9a-f]{64}$ ]] ||
  die 'invalid candidate-build-handoff-sha256'
[[ ${global_values[candidate-out-link]} == /code/tmp/cardano-keri-177/* ]] ||
  die 'candidate-out-link must be ticket-scoped under /code/tmp/cardano-keri-177'
[[ ${global_values[candidate-store-path]} =~ ^/nix/store/[^/]+-ckeri$ ]] ||
  die 'candidate-store-path must be a resolved Nix store ckeri package'
[[ ${global_values[source-store]} == /* && ${global_values[store-copy]} == /code/tmp/cardano-keri-177/* ]] ||
  die 'source-store and store-copy must be absolute ticket provenance paths'
for field in source-store-sha256-before source-store-sha256-after store-copy-sha256-preopen store-copy-sha256-postopen; do
  [[ ${global_values[$field]} =~ ^[0-9a-f]{64}$ ]] || die "invalid $field"
done
[[ ${global_values[source-store-sha256-before]} == "${global_values[source-store-sha256-after]}" ]] ||
  die 'source store hash changed after local capture'
[[ ${global_values[source-store-sha256-before]} == "${global_values[store-copy-sha256-preopen]}" ]] ||
  die 'store copy pre-open hash does not match source store'
[[ ${global_values[local-as-of-source]} == transactional-store-watermark ]] ||
  die 'local as_of_slot must name the transactional store watermark'
[[ ${global_values[endpoint-as-of-source]} == endpoint-response ]] ||
  die 'endpoint as_of_slot must name the endpoint response'
[[ ${global_values[koios-as-of-source]} == supporting-checkpoint-transaction-slot-compared-with-fresh-tip ]] ||
  die 'Koios as_of_slot must name supporting records compared with a fresh tip'

readonly required_fields=(
  backend aid utc operator host pane binary binary-sha256 store source cwd
  command raw-file raw-sha256 exit-status result
)

declare -A seen_backends=()
declare -A seen_raw_files=()
reference_binary_hash=

option_value() {
  local wanted=$1
  printf '%s' "${command_options[$wanted]:-}"
}

validate_command() {
  local record=$1 backend=$2 binary=$3 command=$4 store=$5 source=$6
  if [[ $command == *';'* || $command == *'&'* || $command == *'|'* ||
        $command == *'<'* || $command == *'>'* || $command == *'`'* ||
        $command == *'$('* || $command == *'\\'* || $command == *\"* ||
        $command == *\'* ]]; then
    die "record $record: unsafe command text"
  fi

  local -a words=()
  read -r -a words <<<"$command"
  ((${#words[@]} >= 4)) || die "record $record: invalid production command shape"
  [[ ${words[0]} == "$binary" && ${words[1]} == status ]] ||
    die "record $record: invalid production command shape"

  declare -gA command_options=()
  local index=2 option
  while ((index < ${#words[@]})); do
    option=${words[$index]}
    case $option in
      --aid|--backend|--store|--endpoint|--manifest|--board-manifest)
        ((index + 1 < ${#words[@]})) || die "record $record: invalid production command shape"
        [[ -z ${command_options[$option]:-} ]] || die "record $record: duplicate command option $option"
        command_options[$option]=${words[$((index + 1))]}
        index=$((index + 2))
        ;;
      *)
        die "record $record: invalid production command shape near $option"
        ;;
    esac
  done

  [[ $(option_value --aid) == "$accepted_aid" ]] ||
    die "record $record: invalid production command shape for --aid"
  if [[ -n $(option_value --manifest) && $(option_value --manifest) != /* ]]; then
    die "record $record: manifest path must be absolute"
  fi
  if [[ -n $(option_value --board-manifest) && $(option_value --board-manifest) != /* ]]; then
    die "record $record: board manifest path must be absolute"
  fi

  case $backend in
    local)
      [[ $(option_value --backend) == local ]] ||
        die "record $record: command backend does not match declared backend local"
      [[ -n $(option_value --store) && $(option_value --store) == "$store" && $store == /* ]] ||
        die "record $record: invalid production command shape: local requires matching absolute --store"
      [[ -z $(option_value --endpoint) ]] ||
        die "record $record: command backend does not match declared backend local"
      [[ $(option_value --manifest) == /* && $(option_value --board-manifest) == /* ]] ||
        die "record $record: invalid production command shape: local requires absolute manifest settings"
      ;;
    endpoint)
      [[ -z $(option_value --backend) ]] ||
        die "record $record: endpoint must use the exact shorthand command shape"
      [[ $(option_value --endpoint) == "$source" ]] ||
        die "record $record: invalid production command shape: endpoint requires matching --endpoint"
      [[ -z $(option_value --store) ]] ||
        die "record $record: command backend does not match declared backend endpoint"
      [[ -z $(option_value --manifest) && -z $(option_value --board-manifest) ]] ||
        die "record $record: endpoint shorthand must not supply manifests"
      ;;
    koios)
      [[ $(option_value --backend) == koios ]] ||
        die "record $record: command backend does not match declared backend koios"
      [[ -z $(option_value --store) && -z $(option_value --endpoint) ]] ||
        die "record $record: command backend does not match declared backend koios"
      [[ $(option_value --manifest) == /* && $(option_value --board-manifest) == /* ]] ||
        die "record $record: invalid production command shape: koios requires absolute manifest settings"
      ;;
  esac
}

validate_raw() {
  local record=$1 backend=$2 source=$3 raw_file=$4 expected_hash=$5 result=$6
  local raw_path="$raw_dir/$raw_file"
  [[ -f $raw_path && ! -L $raw_path ]] || die "record $record: missing raw file $raw_file"

  local actual_hash
  actual_hash=$(sha256sum "$raw_path" | awk '{print $1}')
  [[ $actual_hash == "$expected_hash" ]] || die "record $record: raw hash mismatch for $raw_file"

  local -a renderer_tokens=()
  local nonempty_lines
  nonempty_lines=$(awk 'NF { count++ } END { print count + 0 }' "$raw_path")
  read -r -a renderer_tokens <"$raw_path" || true

  if [[ $result == success ]]; then
    [[ $nonempty_lines -eq 1 ]] ||
      die "record $record: successful raw output must be exactly one non-empty renderer line"
    ((${#renderer_tokens[@]} >= 8)) ||
      die "record $record: successful raw output is not the renderer shape"
    [[ ${renderer_tokens[0]} == source && ${renderer_tokens[1]} == "$source" ]] ||
      die "record $record: raw source does not match backend $backend"
    [[ ${renderer_tokens[2]} == as_of_slot && ${renderer_tokens[3]} =~ ^[0-9]+$ ]] ||
      die "record $record: successful raw output lacks as_of_slot"
    [[ ${renderer_tokens[4]} == tip_lag_slots ]] ||
      die "record $record: successful raw output lacks tip_lag_slots"
    if [[ $backend == local ]]; then
      [[ ${renderer_tokens[5]} == unknown || ${renderer_tokens[5]} =~ ^[0-9]+$ ]] ||
        die "record $record: local tip_lag_slots must be non-negative or unknown"
    else
      [[ ${renderer_tokens[5]} =~ ^[0-9]+$ ]] ||
        die "record $record: successful raw output lacks numeric tip_lag_slots"
    fi
    [[ ${renderer_tokens[6]} == aid && ${renderer_tokens[7]} == "$accepted_aid" ]] ||
      die "record $record: raw AID does not match accepted AID"
  else
    [[ -s $raw_path ]] || die "record $record: fail-closed raw is empty"
    if ((${#renderer_tokens[@]} >= 8)) &&
      [[ ${renderer_tokens[0]} == source && ${renderer_tokens[2]} == as_of_slot &&
         ${renderer_tokens[3]} =~ ^[0-9]+$ && ${renderer_tokens[4]} == tip_lag_slots &&
         -n ${renderer_tokens[5]} && ${renderer_tokens[6]} == aid ]]; then
      die "record $record: fail-closed raw resembles successful renderer output"
    fi
  fi
}

for ((record = 1; record <= record_count; record++)); do
  for field in "${required_fields[@]}"; do
    [[ -n ${values[$record|$field]:-} ]] || die "record $record: missing $field"
  done

  backend=${values[$record|backend]}
  case $backend in
    local|endpoint|koios) ;;
    *) die "record $record: unknown backend $backend" ;;
  esac
  [[ -z ${seen_backends[$backend]:-} ]] || die 'expected exactly one record per backend'
  seen_backends[$backend]=1

  [[ ${values[$record|aid]} == "$accepted_aid" ]] ||
    die "record $record: AID is not the accepted AID $accepted_aid"
  [[ ${values[$record|utc]} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z$ ]] ||
    die "record $record: utc must be an RFC3339 UTC timestamp ending in Z"
  [[ ${values[$record|host]} =~ ^[A-Za-z0-9._-]+$ ]] || die "record $record: unsafe host"
  [[ ${values[$record|pane]} =~ ^%[0-9]+$ ]] || die "record $record: invalid pane"
  [[ ${values[$record|operator]} == 'paolino via cardano-keri#177 driver pane %5284' ]] ||
    die "record $record: operator identity does not match the accepted capture operator"
  [[ ${values[$record|binary]} == "${global_values[candidate-store-path]}/bin/ckeri" ]] ||
    die "record $record: binary does not match candidate-store-path"
  [[ ${values[$record|binary-sha256]} =~ ^[0-9a-f]{64}$ ]] ||
    die "record $record: invalid binary-sha256"
  if [[ -z $reference_binary_hash ]]; then
    reference_binary_hash=${values[$record|binary-sha256]}
  else
    [[ ${values[$record|binary-sha256]} == "$reference_binary_hash" ]] ||
      die "record $record: binary-sha256 differs across records"
  fi
  [[ ${values[$record|source]} != *$'\n'* ]] || die "record $record: unsafe source"
  [[ ${values[$record|cwd]} == /* ]] || die "record $record: cwd must be absolute"
  if [[ $backend == endpoint ]]; then
    [[ ${values[$record|cwd]} == /tmp ]] || die "record $record: endpoint cwd must be /tmp"
    [[ ${values[$record|source]} == https://ckeri.dev.plutimus.com ]] ||
      die "record $record: endpoint source must be https://ckeri.dev.plutimus.com"
  elif [[ $backend == local ]]; then
    [[ ${values[$record|source]} == local ]] || die "record $record: local source must be local"
    [[ ${values[$record|store]} == "${global_values[store-copy]}" ]] ||
      die "record $record: local store does not match the recorded ticket copy"
  else
    [[ ${values[$record|source]} == https://preprod.koios.rest/api/v1 ]] ||
      die "record $record: Koios source must be the released preprod default"
  fi

  raw_file=${values[$record|raw-file]}
  [[ $raw_file =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "record $record: unsafe raw-file"
  [[ -z ${seen_raw_files[$raw_file]:-} ]] || die "record $record: raw-file must be unique"
  seen_raw_files[$raw_file]=1
  [[ ${values[$record|raw-sha256]} =~ ^[0-9a-f]{64}$ ]] ||
    die "record $record: invalid raw-sha256"
  [[ ${values[$record|exit-status]} =~ ^[0-9]+$ ]] || die "record $record: invalid exit-status"
  result=${values[$record|result]}
  [[ $result == success || $result == fail-closed ]] ||
    die "record $record: result must be success or fail-closed"
  if [[ $result == success ]]; then
    [[ ${values[$record|exit-status]} -eq 0 ]] || die "record $record: success requires exit-status 0"
  else
    [[ ${values[$record|exit-status]} -ne 0 ]] || die "record $record: fail-closed requires non-zero exit-status"
  fi

  validate_command \
    "$record" \
    "$backend" \
    "${values[$record|binary]}" \
    "${values[$record|command]}" \
    "${values[$record|store]}" \
    "${values[$record|source]}"

  if [[ -n $raw_dir ]]; then
    validate_raw \
      "$record" \
      "$backend" \
      "${values[$record|source]}" \
      "$raw_file" \
      "${values[$record|raw-sha256]}" \
      "$result"
  fi
done

for backend in local endpoint koios; do
  [[ -n ${seen_backends[$backend]:-} ]] || die 'expected exactly one record per backend'
done

if [[ -n $raw_dir ]]; then
  printf 'OK: validated 3 backend status records with raw SHA-256/source reconciliation\n'
else
  printf 'OK: validated 3 backend status records (transcript metadata only; raw files not reconciled)\n'
fi
