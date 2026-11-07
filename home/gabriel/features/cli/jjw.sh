usage() {
  printf '%s\n' \
    'Usage: jjw [name] [-c command | -C | -R]' \
    '' \
    'Open an interactive shell in a temporary jj workspace, then forget/remove it.' \
    'Names default to a random adjective-animal pair (e.g. quiet-otter).' \
    '' \
    '  -c, --command COMMAND  Run a shell command instead; forget/remove on exit' \
    '  -C, --create          Print the absolute workspace path and retain it' \
    '  -R, --remove          Integrate and forget/remove a named workspace without prompting' \
    '  -h, --help             Show this help' \
    '' \
    'Names must match [a-z][a-z0-9-]*. Options may precede or follow the name.' \
    '--create, --command, and --remove are mutually exclusive.' \
    'Without a terminal, use --create or --command; changes stay separate.' \
    'Use jjw NAME --remove to integrate and clean up a retained workspace.'
}

fail() {
  printf 'jjw: %s\n' "$*" >&2
  exit 1
}

workspace_name=
command=
mode=shell
while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -c | --command)
      [[ "$mode" == shell ]] || fail '--command, --create, and --remove may only be specified once and are mutually exclusive'
      (($# >= 2)) || fail "$1 requires a command string"
      mode='command'
      command=$2
      shift 2
      ;;
    -C | --create | -R | --remove)
      [[ "$mode" == shell ]] || fail '--command, --create, and --remove may only be specified once and are mutually exclusive'
      case "$1" in
        -C | --create) mode=create ;;
        -R | --remove) mode=remove ;;
      esac
      shift
      ;;
    -*) fail "unknown option: $1" ;;
    *)
      [[ -z "$workspace_name" ]] || fail 'expected at most one workspace name'
      [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]] || fail 'names must match [a-z][a-z0-9-]*'
      workspace_name=$1
      shift
      ;;
  esac
done

if [[ "$mode" == remove && -z "$workspace_name" ]]; then
  fail '--remove requires a workspace name'
fi

if [[ "$mode" == shell ]] && [[ ! -t 0 ]]; then
  fail 'opening a shell requires a terminal; use --command or --create'
fi

root=$(jj root)
relative_dir=$(realpath --relative-to="$root" .)
invoking_change=$(jj -R "$root" log --no-graph -r @ -T change_id)
workspace_dir=$(realpath -m -- "${TMPDIR:-/tmp}/jj-workspaces/$(basename "$root")")
workspace_names=$(jj -R "$root" workspace list -T 'name ++ "\n"')

name_taken() {
  [[ -e "$workspace_dir/$1" || -L "$workspace_dir/$1" ||
    $'\n'"$workspace_names"$'\n' == *$'\n'"$1"$'\n'* ]]
}

if [[ "$mode" == remove ]]; then
  workspace_path=$(jj -R "$root" workspace root --name "$workspace_name")
  [[ "$workspace_path" != "$root" ]] || fail 'cannot remove the invoking workspace'
elif [[ -n "$workspace_name" ]]; then
  ! name_taken "$workspace_name" || fail "workspace name or path already exists: $workspace_name"
else
  adjectives=(bright calm clever copper cozy crisp daring gentle golden hazy jolly keen lively lucky mellow misty nimble quiet silver sleepy soft sunny swift wild)
  animals=(badger bat bear beetle bison crane deer falcon finch fox gecko hare heron lynx moth mouse newt otter owl panda raven seal toad wren)
  for ((attempt = 0; attempt < 100; attempt++)); do
    workspace_name="${adjectives[RANDOM % ${#adjectives[@]}]}-${animals[RANDOM % ${#animals[@]}]}"
    if ! name_taken "$workspace_name"; then
      break
    fi
  done
  ! name_taken "$workspace_name" || fail 'could not find an unused workspace name; specify one explicitly'
fi
shell_status=0
if [[ "$mode" != remove ]]; then
  workspace_path="$workspace_dir/$workspace_name"

  mkdir -p "$workspace_dir"
  jj -R "$root" workspace add "$workspace_path" --name "$workspace_name" >&2

  if [[ "$mode" == create ]]; then
    printf '%s\n' "$workspace_path"
    exit 0
  fi

  printf 'jjw: entering %s (%s)\n' "$workspace_name" "$workspace_path" >&2
  (
    cd "$workspace_path/$relative_dir" || exit 1
    if [[ "$mode" == command ]]; then
      "${SHELL:-bash}" -c "$command"
    else
      "${SHELL:-bash}" -i
    fi
  ) || shell_status=$?
fi

# Snapshot the workspace, then account for concurrent changes to the invoking workspace.
jj -R "$workspace_path" status >/dev/null
jj -R "$root" workspace update-stale
base=$(jj -R "$workspace_path" log --no-graph -r "fork_point($invoking_change | @)" -T commit_id)

if [[ -n "$(jj -R "$workspace_path" diff --from "$base" --to @ --summary)" ]]; then
  printf '\njjw: changes produced in %s:\n\n' "$workspace_name" >&2
  jj -R "$workspace_path" diff --from "$base" --to @

  imported_change=$(
    jj -R "$workspace_path" log --no-graph \
      -r 'heads(first_ancestors(@) & ~empty())' -T change_id
  )
  printf '\n' >&2
  if [[ "$mode" == remove ]] || { [[ -t 0 ]] &&
    read -r -p "Integrate changes into the invoking workspace? [y/N] " confirm &&
    [[ "$confirm" =~ ^[Yy]$ ]]; }; then
    jj -R "$root" rebase -s "$invoking_change" -d "$imported_change"
    result="integrated changes into the invoking workspace"
  else
    result="left change $imported_change separate for later review"
  fi
else
  result="removed workspace $workspace_name"
fi

if jj -R "$root" workspace forget "$workspace_name"; then
  rm -rf -- "$workspace_path"
  echo "jjw: $result" >&2
else
  echo "jjw: failed to forget workspace $workspace_name; keeping $workspace_path" >&2
fi

exit "$shell_status"
