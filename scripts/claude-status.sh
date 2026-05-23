#!/usr/bin/env bash
# Outputs Claude Code status icons for panes in a given tmux window.
# Usage: claude-status.sh <session:window>
#
# Reads ~/.claude/sessions/<pid>.json for active sessions and their status,
# then maps each session PID to a tmux pane via PPID chain.

WINDOW_TARGET="$1"
[ -z "$WINDOW_TARGET" ] && exit 0

get_tmux_option() {
  local option="$1"
  local default="$2"
  local value
  value="$(tmux show-option -gqv "$option" 2>/dev/null)"
  [ -z "$value" ] && echo "$default" || echo "$value"
}

CLAUDE_STATUS_ICON="$(get_tmux_option "@claude_status_icon" "C")"
CLAUDE_STATUS_SPACE="$(get_tmux_option "@claude_status_space" " ")"

CLAUDE_STATUS_CACHE_FILE="$(get_tmux_option "@claude_status_cache_file" "/tmp/tmux-claude-status-${USER}")"
CLAUDE_STATUS_CACHE_TTL="$(get_tmux_option "@claude_status_cache_ttl" "5")"
CLAUDE_STATUS_SESSIONS_DIR="$(get_tmux_option "@claude_status_sessions_dir" "${HOME}/.claude/sessions")"

CLAUDE_STATUS_COLOR_BUSY="$(get_tmux_option "@claude_status_color_busy" "#ff79c6")"
CLAUDE_STATUS_COLOR_IDLE="$(get_tmux_option "@claude_status_color_idle" "#6272a4")"
CLAUDE_STATUS_COLOR_WAITING="$(get_tmux_option "@claude_status_color_waiting" "#f1fa8c")"
CLAUDE_STATUS_COLOR_SHELL="$(get_tmux_option "@claude_status_color_shell" "#bd93f9")"

needs_refresh=1
if [ -f "$CLAUDE_STATUS_CACHE_FILE" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$CLAUDE_STATUS_CACHE_FILE" 2>/dev/null || stat -c %Y "$CLAUDE_STATUS_CACHE_FILE" 2>/dev/null || echo 0)
  if [ $((now - mtime)) -lt "$CLAUDE_STATUS_CACHE_TTL" ]; then
    needs_refresh=0
  fi
fi

if [ "$needs_refresh" -eq 1 ]; then
  tmp="${CLAUDE_STATUS_CACHE_FILE}.$$"

  # Build pane_pid -> window_target map, and parent lookup in one awk pass
  {
    tmux list-panes -a -F 'PANE #{session_name}:#{window_index} #{pane_index} #{pane_pid}' 2>/dev/null
    echo "ENDPANES"
    ps -eo pid=,ppid= 2>/dev/null
  } | awk -v sessions_dir="$CLAUDE_STATUS_SESSIONS_DIR" '
    /^PANE / { pane_win[$4] = $2; pane_idx[$4] = $3; next }
    /^ENDPANES$/ { next }
    { parent[$1+0] = $2+0 }
    END {
      # For each session file, walk up PPID chain to find owning pane
      cmd = "ls " sessions_dir "/*.json 2>/dev/null"
      while ((cmd | getline f) > 0) {
        # Extract PID from filename
        n = split(f, parts, "/")
        gsub(/\.json$/, "", parts[n])
        pid = parts[n] + 0
        if (pid == 0) continue
        if (!(pid in parent)) continue

        # Skip non-interactive sessions (subagents, etc.)
        getline content < f
        close(f)
        if (content !~ /"kind"[ \t]*:[ \t]*"interactive"/) continue
        if (content !~ /"entrypoint"[ \t]*:[ \t]*"cli"/) continue

        # Extract status
        status = "idle"
        if (match(content, /"status"[ \t]*:[ \t]*"[^"]*"/)) {
          s = substr(content, RSTART, RLENGTH)
          gsub(/.*"status"[ \t]*:[ \t]*"/, "", s)
          gsub(/"$/, "", s)
          status = s
        }

        # Walk up parent chain
        cur = pid
        for (i = 0; i < 50; i++) {
          if (cur in pane_win) {
            print pane_win[cur] " " pane_idx[cur] " " status
            break
          }
          if (!(cur in parent) || parent[cur] == cur || cur <= 1) break
          cur = parent[cur]
        }
      }
      close(cmd)
    }
  ' | sort -k1,1 -k2,2n >"$tmp"

  mv -f "$tmp" "$CLAUDE_STATUS_CACHE_FILE" 2>/dev/null
fi

if [ -f "$CLAUDE_STATUS_CACHE_FILE" ]; then
  output=""
  while IFS=' ' read -r wt _pane_idx status; do
    [ "$wt" != "$WINDOW_TARGET" ] && continue
    if [ "$status" = "busy" ]; then
      output="${output}#[fg=${CLAUDE_STATUS_COLOR_BUSY}]${CLAUDE_STATUS_ICON}"
    elif [ "$status" = "waiting" ]; then
      output="${output}#[fg=${CLAUDE_STATUS_COLOR_WAITING}]${CLAUDE_STATUS_ICON}"
    elif [ "$status" = "shell" ]; then
      output="${output}#[fg=${CLAUDE_STATUS_COLOR_SHELL}]${CLAUDE_STATUS_ICON}"
    else
      output="${output}#[fg=${CLAUDE_STATUS_COLOR_IDLE}]${CLAUDE_STATUS_ICON}"
    fi
  done <"$CLAUDE_STATUS_CACHE_FILE"
  if [ -n "$output" ]; then
    printf '%s%s#[fg=default]' "$CLAUDE_STATUS_SPACE" "$output"
  fi
fi
