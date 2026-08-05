root=$(jj root)
relative_dir=$(realpath --relative-to="$root" .)
invoking_change=$(jj -R "$root" log --no-graph -r @ -T change_id)
workspace_name="jjw-$(date +%s)-$$"
workspace_path="${TMPDIR:-/tmp}/jj-workspaces/$(basename "$root")/$workspace_name"

mkdir -p "$(dirname "$workspace_path")"
jj -R "$root" workspace add "$workspace_path" --name "$workspace_name"

shell_status=0
(
  cd "$workspace_path/$relative_dir"
  "${SHELL:-bash}" "$@"
) || shell_status=$?

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
  if read -r -p "Integrate changes into the invoking workspace? [y/N] " confirm \
    && [[ "$confirm" =~ ^[Yy]$ ]]; then
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
