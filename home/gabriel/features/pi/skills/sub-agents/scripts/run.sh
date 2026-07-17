#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run.sh [OPTIONS] PROMPT_FILE...

Each prompt file starts one fresh `pi -p` process. --repeat N repeats a single
prompt N times.

options:
  --repeat N          repeat one prompt (default: 1)
  --concurrency N     maximum parallel agents (default: 4)
  --model MODEL       Pi model (default: gpt-5.6-luna)
  --tools LIST        comma-separated tool allowlist (default: no tools)
  --no-tools          explicitly disable every tool
  --system-prompt S   sub-agent system prompt
  --cwd DIR           working directory for agents (default: current directory)
  --output-dir DIR    write into DIR instead of a new temporary directory
  -h, --help          show this help

environment defaults: PI_SUBAGENT_MODEL, PI_SUBAGENT_CONCURRENCY
EOF
}

repeat=1
concurrency=${PI_SUBAGENT_CONCURRENCY:-4}
model=${PI_SUBAGENT_MODEL:-gpt-5.6-luna}
tools=
system_prompt='Complete the bounded task in the user prompt. Do not spawn sub-agents. Return only the requested deliverable.'
cwd=$PWD
output_dir=

while (($#)); do
  case $1 in
    --repeat)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      repeat=$2
      shift 2
      ;;
    --concurrency)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      concurrency=$2
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      model=$2
      shift 2
      ;;
    --tools)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      tools=$2
      shift 2
      ;;
    --no-tools)
      tools=
      shift
      ;;
    --system-prompt)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      system_prompt=$2
      shift 2
      ;;
    --cwd)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      cwd=$2
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      output_dir=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 1 ]] || { usage; exit 2; }
[[ $repeat =~ ^[1-9][0-9]*$ ]] || { echo "repeat must be a positive integer" >&2; exit 2; }
[[ $concurrency =~ ^[1-9][0-9]*$ ]] || { echo "concurrency must be a positive integer" >&2; exit 2; }
[[ -d $cwd ]] || { echo "working directory not found: $cwd" >&2; exit 2; }
if ((repeat > 1 && $# != 1)); then
  echo "--repeat requires exactly one prompt file" >&2
  exit 2
fi

prompts=()
for prompt in "$@"; do
  [[ -f $prompt ]] || { echo "prompt not found: $prompt" >&2; exit 2; }
  prompts+=("$(realpath "$prompt")")
done
if ((repeat > 1)); then
  prompt=${prompts[0]}
  prompts=()
  for ((i = 0; i < repeat; i++)); do
    prompts+=("$prompt")
  done
fi

if [[ -n $output_dir ]]; then
  mkdir -p -- "$output_dir"
  run_dir=$(realpath "$output_dir")
else
  run_dir=$(mktemp -d "${TMPDIR:-/tmp}/pi-sub-agents.XXXXXX")
fi

printf '%s\n' "$model" >"$run_dir/model.txt"
printf '%s\n' "$cwd" >"$run_dir/cwd.txt"
printf '%s\n' "${tools:-none}" >"$run_dir/tools.txt"
printf '%s\n' "$system_prompt" >"$run_dir/system-prompt.txt"

run_agent() {
  local i=$1
  local prompt_file=$2
  local copied_prompt="$run_dir/prompt-$i.md"
  local -a command=(
    pi --print --no-session --offline
    --no-skills --no-prompt-templates --no-context-files
    --system-prompt "$system_prompt"
    --model "$model"
  )

  cp -- "$prompt_file" "$copied_prompt"
  if [[ -n $tools ]]; then
    command+=(--tools "$tools")
  else
    command+=(--no-tools)
  fi
  command+=("$(cat "$copied_prompt")")

  (
    cd "$cwd"
    "${command[@]}"
  ) >"$run_dir/agent-$i.raw" 2>"$run_dir/agent-$i.stderr"
}

status=0
running=0
for i in "${!prompts[@]}"; do
  run_agent "$((i + 1))" "${prompts[$i]}" &
  running=$((running + 1))
  if ((running >= concurrency)); then
    if ! wait -n; then
      status=1
    fi
    running=$((running - 1))
  fi
done
while ((running > 0)); do
  if ! wait -n; then
    status=1
  fi
  running=$((running - 1))
done

printf 'outputs: %s\n' "$run_dir"
exit "$status"
