#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/deploy/preprod/witnesses.json"
compose="$repo_root/deploy/preprod/docker-compose.yaml"
witness_image="${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}"
kli_timeout="${KLI_TIMEOUT_SECONDS:-120}"

for command in curl docker jq timeout; do
  command -v "$command" >/dev/null || {
    echo "missing required command: $command" >&2
    exit 1
  }
done

jq -e '
  length == 3
  and ([.[].name] | sort == ["witness-1", "witness-2", "witness-3"])
  and ([.[].name] | unique | length == 3)
  and ([.[].aid] | unique | length == 3)
  and all(.[];
    (.aid | test("^B[A-Za-z0-9_-]{43}$"))
    and .oobi == (
      "https://" + .name + ".preprod.plutimus.com/oobi/"
      + .aid + "/controller"
    )
  )
' "$manifest" >/dev/null

compose_model="$(
  WITNESS_IMAGE="$witness_image" \
    docker compose --file "$compose" config --format json
)"

jq -e '
  (.services | keys == ["witness-1", "witness-2", "witness-3"])
  and (.volumes | keys == [
    "witness-1-data",
    "witness-2-data",
    "witness-3-data"
  ])
  and (.networks.web.external == true)
  and all(.services[];
    .restart == "unless-stopped"
    and .read_only == true
    and (.cap_drop | index("ALL"))
    and (.security_opt | index("no-new-privileges:true"))
    and (.healthcheck.test | length > 0)
  )
  and ([
    .services[].volumes[]
    | select(.type == "volume")
    | .source
  ] | sort == [
    "witness-1-data",
    "witness-2-data",
    "witness-3-data"
  ])
' <<<"$compose_model" >/dev/null

version_output="$(docker run --rm "$witness_image" version)"
printf '%s\n' "$version_output"
grep -Fxq "Library version: 1.3.5" <<<"$version_output"

mapfile -t witness_rows < <(jq -r '.[] | [.name, .aid, .oobi] | @tsv' "$manifest")

for row in "${witness_rows[@]}"; do
  IFS=$'\t' read -r name aid oobi <<<"$row"
  oobi_response="$(curl -fsS --max-time 15 "$oobi")"
  grep -Fq "\"i\":\"$aid\"" <<<"$oobi_response"
  grep -Fq "https://$name.preprod.plutimus.com/" <<<"$oobi_response"
  printf 'reachable: %s %s\n' "$name" "$aid"
done

run_label="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-${BASHPID}"
run_label="${run_label//[^A-Za-z0-9_.-]/-}"
client_volume="ckeri-preprod-acceptance-$run_label"

if docker volume inspect "$client_volume" >/dev/null 2>&1; then
  echo "refusing to reuse existing Docker volume: $client_volume" >&2
  exit 1
fi

docker volume create "$client_volume" >/dev/null
cleanup() {
  docker volume rm "$client_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_kli() {
  timeout "$kli_timeout" \
    docker run --rm \
      --volume "$client_volume:/var/lib/keri/.keri" \
      "$witness_image" "$@"
}

client_base="acceptance-$run_label"
run_kli init \
  --name alice \
  --base "$client_base" \
  --nopasscode

for row in "${witness_rows[@]}"; do
  IFS=$'\t' read -r name _aid oobi <<<"$row"
  run_kli oobi resolve \
    --name alice \
    --base "$client_base" \
    --oobi "$oobi" \
    --oobi-alias "$name"
done

incept_args=(
  incept
  --name alice
  --base "$client_base"
  --alias alice
  --transferable
  --icount 1
  --isith 1
  --ncount 1
  --nsith 1
  --toad 2
)

for row in "${witness_rows[@]}"; do
  IFS=$'\t' read -r _name aid _oobi <<<"$row"
  incept_args+=(--wits "$aid")
done

run_kli "${incept_args[@]}"

status_output="$(run_kli status --name alice --base "$client_base" --alias alice)"
printf '%s\n' "$status_output"

grep -Eq '^Count:[[:space:]]*3$' <<<"$status_output"
grep -Eq '^Receipts:[[:space:]]*3$' <<<"$status_output"
grep -Eq '^Threshold:[[:space:]]*2$' <<<"$status_output"

echo "PASS: clean kli client received 3 of 3 witness receipts at threshold 2"
