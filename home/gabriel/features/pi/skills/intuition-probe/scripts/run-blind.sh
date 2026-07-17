#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 FROZEN_PROMPT [COUNT]" >&2
  echo "optional env: PI_INTUITION_MODEL=gpt-5.6-luna, PI_INTUITION_CONCURRENCY=4" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
prompt_file=$(realpath "$1")
count=${2:-1}
concurrency=${PI_INTUITION_CONCURRENCY:-4}
model=${PI_INTUITION_MODEL:-gpt-5.6-luna}
[[ -f "$prompt_file" ]] || { echo "prompt not found: $prompt_file" >&2; exit 2; }
[[ "$count" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$concurrency" =~ ^[1-9][0-9]*$ ]] || usage

run_dir=$(mktemp -d "${TMPDIR:-/tmp}/pi-intuition-probe.XXXXXX")
cp -- "$prompt_file" "$run_dir/frozen-prompt.md"
printf '%s\n' "$model" > "$run_dir/model.txt"

run_probe() {
  local i=$1
  (
    cd "$run_dir"
    pi --print --no-session --offline \
      --no-tools --no-skills --no-prompt-templates --no-context-files \
      --system-prompt 'Follow the user prompt exactly. Return only the requested JSON. You have no tools and must not seek additional context.' \
      --model "$model" \
      "$(cat frozen-prompt.md)"
  ) > "$run_dir/probe-$i.raw" 2> "$run_dir/probe-$i.stderr"

  if jq -e 'select(.decision_points | type == "array")' "$run_dir/probe-$i.raw" > "$run_dir/probe-$i.json" 2>/dev/null; then
    printf 'probe %s: valid\n' "$i"
  else
    printf 'probe %s: invalid JSON (kept as .raw)\n' "$i" >&2
    return 1
  fi
}
export -f run_probe
export run_dir prompt_file model

status=0
running=0
for i in $(seq 1 "$count"); do
  run_probe "$i" &
  running=$((running + 1))
  if (( running >= concurrency )); then
    wait -n || status=1
    running=$((running - 1))
  fi
done
while (( running > 0 )); do
  wait -n || status=1
  running=$((running - 1))
done

printf 'outputs: %s\n' "$run_dir"
exit "$status"
