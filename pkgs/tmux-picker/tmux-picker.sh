#!/usr/bin/env bash
set -euo pipefail

declare -A remote_target
entries="new session"

while IFS= read -r s; do
  [ -n "$s" ] && entries+=$'\n'"$s"
done < <(tmux list-sessions -F '#S' 2>/dev/null | grep -v '^_view_' || true)

# Only query existing SSH masters; opening the picker must never dial out.
shopt -s nullglob
for sock in "$HOME"/.ssh/master-*; do
  [ -S "$sock" ] || continue
  target="${sock##*/}"
  target="${target#master-}"
  target="${target%:*}"
  label="${target#*@}"
  label="${label%%.*}"
  ssh -O check "$target" 2>/dev/null || continue
  remote_target["$label: new session"]="$target"
  entries+=$'\n'"$label: new session"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    key="$label: $s"
    remote_target["$key"]="$target"
    entries+=$'\n'"$key"
  done < <(timeout 3 ssh "$target" "tmux list-sessions -F '#S'" 2>/dev/null | grep -v '^_view_' || true)
done

choice=$(printf '%s\n' "$entries" | wofi -S dmenu --cache-file /dev/null -p 'tmux session')
case "$choice" in
  "") exit 0 ;;
  "new session") exec handlr launch x-scheme-handler/terminal -- -e tmux new-session ;;
esac

if [ -n "${remote_target[$choice]:-}" ]; then
  target="${remote_target[$choice]}"
  session="${choice#*: }"
  if [ "$session" = "new session" ]; then
    exec handlr launch x-scheme-handler/terminal -- -e ssh -t "$target" tmux new-session
  fi
  exec handlr launch x-scheme-handler/terminal -- -e \
    ssh -t "$target" \
    "tmux new-session -t \"$session\" -s \"_view_${session}_$RANDOM\" \; set-option @base \"$session\" \; set-option destroy-unattached on"
elif tmux has-session -t "$choice" 2>/dev/null; then
  # Grouped views share windows, not the selected window, and vanish on close.
  exec handlr launch x-scheme-handler/terminal -- -e tmux \
    new-session -t "$choice" -s "_view_${choice}_$RANDOM" \; \
    set-option @base "$choice" \; \
    set-option destroy-unattached on
else
  exec handlr launch x-scheme-handler/terminal -- -e tmux new-session -s "$choice"
fi
