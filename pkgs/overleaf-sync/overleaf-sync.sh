#!/usr/bin/env bash

# Synchronization contract:
#
# - Run from the project root. `.overleafproject` must contain exactly one
#   24-character Overleaf project ID, and `.overleafignore` must exist.
# - `.overleafignore` is evaluated by Git itself and therefore supports the full
#   gitignore grammar, including `!` negation, anchored patterns, directory
#   patterns, and escapes. The two `.overleaf*` files and all `.git`/`.jj`
#   metadata are always local-only regardless of those rules.
# - Authentication uses `pass git.overleaf.com` through a temporary Git
#   credential helper. The password is never embedded in a URL or remote.
# - `push` replaces the remote tree with all files allowed by `.overleafignore`,
#   so local additions, changes, and deletions are mirrored. The subsequent
#   `git add` also honors the copied project `.gitignore` and the user's global
#   Git excludes, but not `.gitignore` files above the project root. Because the
#   old remote tree is removed first, newly ignored tracked files are deleted.
#   Local symlinks are dereferenced because their targets may live outside the
#   Overleaf project. The temporary commit is shown and pushed only after
#   confirmation; if there is no diff, nothing is committed or pushed.
# - `pull` requires Jujutsu. It applies non-ignored remote additions, changes,
#   and deletions in an isolated jj workspace while leaving ignored local files
#   untouched. If a remote regular file matches the resolved contents of an
#   existing local symlink, the symlink is preserved. If the contents differ,
#   the symlink is replaced by the remote regular file.
# - A pulled change is shown before integration. Confirmation rebases the
#   invoking working-copy change onto it; declining leaves the import as a
#   separate jj head. A no-op pull creates no change.
# - Temporary clones, matcher repositories, workspaces, and disposable jj
#   changes are cleaned up on both success and failure. Overleaf compilation is
#   never triggered or checked by this command.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: overleaf-sync <push|pull>

Synchronize the project in the current directory with Overleaf. The project
must contain .overleafproject and .overleafignore.
EOF
}

die() {
  printf 'overleaf-sync: %s\n' "$*" >&2
  exit 1
}

cleanup_temp_root=""
cleanup_repo_root=""
cleanup_workspace_name=""
cleanup_change=""

cleanup_temp() {
  if [[ -n "$cleanup_temp_root" ]]; then
    rm -rf -- "$cleanup_temp_root"
  fi
}

cleanup_pull() {
  if [[ -n "$cleanup_workspace_name" ]]; then
    jj -R "$cleanup_repo_root" workspace forget "$cleanup_workspace_name" >/dev/null 2>&1 || true
  fi
  if [[ -n "$cleanup_change" ]]; then
    jj -R "$cleanup_repo_root" abandon "$cleanup_change" >/dev/null 2>&1 || true
  fi
  cleanup_temp
}

load_project() {
  project_root="$(pwd -P)"
  project_file="$project_root/.overleafproject"
  ignore_file="$project_root/.overleafignore"

  [[ -f "$project_file" ]] || die "missing .overleafproject in $project_root"
  [[ -f "$ignore_file" ]] || die "missing .overleafignore in $project_root"

  mapfile -t project_lines < "$project_file"
  [[ ${#project_lines[@]} -eq 1 ]] || die ".overleafproject must contain exactly one project ID"
  project_id="${project_lines[0]}"
  [[ "$project_id" =~ ^[0-9a-f]{24}$ ]] || die ".overleafproject does not contain a valid project ID"
}

# Use Git itself as the matcher so .overleafignore has the complete gitignore
# grammar, including negation, anchored patterns, and escaped characters.
generate_manifest() {
  local source_root="$1"
  local matcher_dir="$2"
  local manifest="$3"
  local source_path relative status

  mkdir -p -- "$matcher_dir"
  git -C "$matcher_dir" init -q
  cp -- "$ignore_file" "$matcher_dir/.gitignore"
  : > "$manifest"

  while IFS= read -r -d '' source_path; do
    relative="${source_path#"$source_root"/}"

    # Synchronization metadata belongs only in the local project.
    case "$relative" in
      .overleafignore | .overleafproject) continue ;;
    esac

    if git -C "$matcher_dir" check-ignore --no-index -q -- "$relative"; then
      continue
    else
      status=$?
      [[ $status -eq 1 ]] || die "could not match .overleafignore against $relative"
    fi

    printf '%s\0' "$relative" >> "$manifest"
  done < <(
    find "$source_root" -mindepth 1 \
      \( -name .git -o -name .jj \) -prune -o \
      \( -type f -o -type l \) -print0
  )
}

# Expanded later by Git's credential-helper shell. It retrieves the password
# without placing it in a URL, process argument, or log.
# shellcheck disable=SC2016
credential_helper='!f() { test "$1" = get && printf "username=git\npassword=%s\n" "$(pass git.overleaf.com)"; }; f'
credential_args=(
  -c credential.https://git.overleaf.com.username=git
  -c credential.https://git.overleaf.com.helper="$credential_helper"
)

delete_missing_files() {
  local project_copy="$1"
  local remote_manifest="$2"
  local local_manifest="$3"
  local relative
  declare -A remote_files=()

  while IFS= read -r -d '' relative; do
    remote_files["$relative"]=1
  done < "$remote_manifest"

  while IFS= read -r -d '' relative; do
    if [[ ! ${remote_files["$relative"]+present} ]]; then
      rm -f -- "$project_copy/$relative"
    fi
  done < "$local_manifest"
}

filter_unchanged_symlinks() {
  local remote_root="$1"
  local project_copy="$2"
  local remote_manifest="$3"
  local copy_manifest="$4"
  local relative remote_path local_path

  : > "$copy_manifest"
  while IFS= read -r -d '' relative; do
    remote_path="$remote_root/$relative"
    local_path="$project_copy/$relative"

    if [[ -L "$local_path" && -f "$remote_path" && ! -L "$remote_path" ]] \
      && cmp -s -- "$remote_path" "$local_path"; then
      continue
    fi

    printf '%s\0' "$relative" >> "$copy_manifest"
  done < "$remote_manifest"
}

overleaf_git() {
  git "${credential_args[@]}" "$@"
}

clone_overleaf() {
  local destination="$1"
  overleaf_git clone "https://git@git.overleaf.com/$project_id" "$destination"
}

push_project() {
  local temp_root overleaf_dir matcher_dir manifest confirm
  temp_root="$(mktemp -d -t overleaf-sync.XXXXXXXX)"
  overleaf_dir="$temp_root/overleaf"
  matcher_dir="$temp_root/matcher"
  manifest="$temp_root/manifest"
  cleanup_temp_root="$temp_root"
  trap cleanup_temp EXIT

  generate_manifest "$project_root" "$matcher_dir" "$manifest"
  clone_overleaf "$overleaf_dir"

  git -C "$overleaf_dir" rm -rq --ignore-unmatch -- .
  # Dereference project symlinks: links to authoritative assets outside the
  # project tree would otherwise be broken in Overleaf.
  rsync -aL --from0 --files-from="$manifest" "$project_root/" "$overleaf_dir/"
  git -C "$overleaf_dir" add -A

  if git -C "$overleaf_dir" diff --cached --quiet; then
    printf 'Overleaf already matches the local project.\n'
    return
  fi

  git -C "$overleaf_dir" -c commit.gpgsign=false commit -m "sync from $(basename -- "$project_root")"
  git -C "$overleaf_dir" show

  read -r -p "Push to Overleaf? [y/N] " confirm || true
  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    overleaf_git -C "$overleaf_dir" push
  fi
}

pull_project() {
  local repo_root project_path project_name default_change
  local temp_root workspace_dir workspace_name overleaf_dir
  local remote_matcher local_matcher remote_manifest local_manifest copy_manifest project_copy
  local imported_change disposable_change confirm

  repo_root="$(jj root)" || die "pull requires a Jujutsu workspace"
  project_path="$(realpath --relative-to="$repo_root" "$project_root")"
  [[ "$project_path" != .. && "$project_path" != ../* ]] || die "project is outside its Jujutsu repository"
  project_name="$(basename -- "$project_root")"
  default_change="$(jj -R "$repo_root" log --no-graph -r @ -T 'change_id')"

  temp_root="$(mktemp -d -t overleaf-sync.XXXXXXXX)"
  workspace_dir="$temp_root/workspace"
  workspace_name="overleaf-sync-$(basename -- "$temp_root")"
  overleaf_dir="$temp_root/overleaf"
  remote_matcher="$temp_root/remote-matcher"
  local_matcher="$temp_root/local-matcher"
  remote_manifest="$temp_root/remote-manifest"
  local_manifest="$temp_root/local-manifest"
  copy_manifest="$temp_root/copy-manifest"
  project_copy="$workspace_dir/$project_path"
  cleanup_temp_root="$temp_root"
  cleanup_repo_root="$repo_root"
  cleanup_workspace_name="$workspace_name"
  cleanup_change=""
  trap cleanup_pull EXIT

  jj -R "$repo_root" workspace add --name "$workspace_name" "$workspace_dir"
  cleanup_change="$(jj -R "$workspace_dir" log --no-graph -r @ -T 'change_id')"

  clone_overleaf "$overleaf_dir"
  generate_manifest "$overleaf_dir" "$remote_matcher" "$remote_manifest"
  generate_manifest "$project_copy" "$local_matcher" "$local_manifest"
  delete_missing_files "$project_copy" "$remote_manifest" "$local_manifest"
  filter_unchanged_symlinks "$overleaf_dir" "$project_copy" "$remote_manifest" "$copy_manifest"
  rsync -a --from0 --files-from="$copy_manifest" "$overleaf_dir/" "$project_copy/"
  rm -rf -- "$overleaf_dir"

  if [[ "$(jj -R "$workspace_dir" log --no-graph -r @ -T 'empty')" == "true" ]]; then
    printf 'The local project already contains all Overleaf changes.\n'
    return
  fi

  jj -R "$workspace_dir" describe -m "chore($project_name): pull from overleaf"
  imported_change="$(jj -R "$workspace_dir" log --no-graph -r @ -T 'change_id')"

  # Leave the imported change as a durable head when the temporary workspace is
  # forgotten. The disposable child itself is abandoned by cleanup().
  jj -R "$workspace_dir" new
  disposable_change="$(jj -R "$workspace_dir" log --no-graph -r @ -T 'change_id')"
  cleanup_change="$disposable_change"

  jj -R "$workspace_dir" show "$imported_change"
  read -r -p "Integrate Overleaf change into the invoking workspace? [y/N] " confirm || true
  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    jj -R "$repo_root" rebase -s "$default_change" -d "$imported_change"
    printf '\nImported Overleaf change into the invoking workspace.\n'
  else
    printf '\nOverleaf import left as change %s for later review.\n' "$imported_change"
  fi
}

main() {
  [[ $# -eq 1 ]] || {
    usage >&2
    exit 2
  }

  case "$1" in
    push)
      load_project
      push_project
      ;;
    pull)
      load_project
      pull_project
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
