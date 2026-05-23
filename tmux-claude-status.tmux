#!/usr/bin/env bash
# tmux-claude-status TPM plugin entry point.
# Replaces #{claude_status} placeholder in window-status-format strings
# with the actual #() call to claude-status.sh.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$CURRENT_DIR/scripts/claude-status.sh"
PLACEHOLDER="#{claude_status}"
CALL="#($CURRENT_DIR/scripts/claude-status.sh '#{session_name}:#{window_index}')"

replace_placeholder() {
  local option="$1"
  local current
  current="$(tmux show-option -gv "$option" 2>/dev/null)"
  if echo "$current" | grep -qF "$PLACEHOLDER"; then
    local replaced="${current//$PLACEHOLDER/$CALL}"
    tmux set-option -g "$option" "$replaced"
  fi
}

chmod +x "$SCRIPT"
replace_placeholder "window-status-format"
replace_placeholder "window-status-current-format"
