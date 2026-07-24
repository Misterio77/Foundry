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
[[ -f $prompt_file ]] || { echo "prompt not found: $prompt_file" >&2; exit 2; }
[[ $count =~ ^[1-9][0-9]*$ ]] || usage
[[ $concurrency =~ ^[1-9][0-9]*$ ]] || usage

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
sub_agent_runner=$(realpath "$script_dir/../../sub-agents/scripts/run.sh")
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/pi-intuition-probe.XXXXXX")
cp -- "$prompt_file" "$run_dir/frozen-prompt.md"

status=0
bash "$sub_agent_runner" \
  --repeat "$count" \
  --concurrency "$concurrency" \
  --model "$model" \
  --no-tools \
  --system-prompt 'Follow the user prompt exactly. Return only the requested JSON. You have no tools and must not seek additional context.' \
  --output-dir "$run_dir" \
  "$run_dir/frozen-prompt.md" || status=1

for i in $(seq 1 "$count"); do
  mv -- "$run_dir/agent-$i.raw" "$run_dir/probe-$i.raw"
  mv -- "$run_dir/agent-$i.stderr" "$run_dir/probe-$i.stderr"
  if jq -e 'select(.decision_points | type == "array")' \
    "$run_dir/probe-$i.raw" >"$run_dir/probe-$i.json" 2>/dev/null; then
    printf 'probe %s: valid\n' "$i"
  else
    printf 'probe %s: invalid JSON (kept as .raw)\n' "$i" >&2
    status=1
  fi
done

printf 'outputs: %s\n' "$run_dir"
exit "$status"
