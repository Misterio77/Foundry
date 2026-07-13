root=$(jj root) || {
  echo "piw: not in a jj repository" >&2
  exit 1
}
invoking_change=$(jj -R "$root" log --no-graph -r @ -T change_id)
invoking_commit=$(jj -R "$root" log --no-graph -r @ -T commit_id)

workspace_name="pi-$(date +%s)-$$"

workspace_base="${TMPDIR:-/tmp}/pi-jj-workspaces/$(basename "$root")"
workspace_path="$workspace_base/$workspace_name"

if [[ -e "$workspace_path" ]]; then
  echo "piw: workspace path already exists: $workspace_path" >&2
  exit 1
fi

mkdir -p "$workspace_base"
jj -R "$root" workspace add "$workspace_path" --name "$workspace_name"

echo "piw: workspace $workspace_name ready at $workspace_path" >&2

set +e
(
  cd "$workspace_path"
  pi "$@"
)
pi_status=$?
set -e

# Explicitly snapshot Pi's changes before detaching them from the workspace.
jj -R "$workspace_path" status >/dev/null
# Pi may have rewritten shared repository state while this workspace was idle.
jj -R "$root" workspace update-stale

workspace_has_changes=false
if [[ -n "$(jj -R "$workspace_path" diff --from "$invoking_commit" --to @ --summary)" ]]; then
  workspace_has_changes=true
fi

integrate=false
if [[ "$workspace_has_changes" == true ]]; then
  printf '\npiw: changes produced in %s:\n\n' "$workspace_name" >&2
  jj -R "$workspace_path" diff --from "$invoking_commit" --to @

  printf '\n' >&2
  if read -r -p "Integrate changes into the invoking workspace? [y/N] " confirm; then
    [[ "$confirm" =~ ^[Yy]$ ]] && integrate=true
  fi

  imported_change=$(jj -R "$workspace_path" log --no-graph -r @ -T change_id)
  # Move the workspace onto a disposable child so its change remains a head.
  jj -R "$workspace_path" new

  if [[ "$integrate" == true ]]; then
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
  echo "piw: $result" >&2
else
  echo "piw: failed to forget workspace $workspace_name; keeping $workspace_path" >&2
fi

exit "$pi_status"
