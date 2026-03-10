#!/usr/bin/env bash

chrome_state_dir() {
  printf '%s\n' "${CHROME_SESSION_DIR:-$HOME/.claude/chrome-sessions}"
}

chrome_sessions_dir() {
  printf '%s/sessions\n' "$(chrome_state_dir)"
}

chrome_aliases_dir() {
  printf '%s/aliases\n' "$(chrome_state_dir)"
}

chrome_debug_log() {
  printf '%s/debug.log\n' "$(chrome_state_dir)"
}

ensure_state_layout() {
  mkdir -p "$(chrome_sessions_dir)" "$(chrome_aliases_dir)"
}

now_iso8601() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

session_file_for_key() {
  printf '%s/%s.json\n' "$(chrome_sessions_dir)" "$1"
}

alias_file_for_sid() {
  printf '%s/%s\n' "$(chrome_aliases_dir)" "$1"
}

trim_whitespace() {
  awk '{$1=$1;print}'
}

generate_session_key() {
  printf 'chrome-%s\n' "$(
    uuidgen 2>/dev/null \
      || cat /proc/sys/kernel/random/uuid 2>/dev/null \
      || printf '%s-%s' "$$" "$(date +%s)"
  )"
}

safe_session_key() {
  if [ -n "${CHROME_SESSION_KEY:-}" ]; then
    printf '%s\n' "$CHROME_SESSION_KEY"
    return 0
  fi

  if [ -n "${1:-}" ] && [ "${1:-}" != "null" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  generate_session_key
}

write_alias() {
  local input_sid="$1"
  local session_key="$2"
  local alias_file
  local tmp

  if [ -z "$input_sid" ] || [ "$input_sid" = "null" ]; then
    return 0
  fi

  alias_file="$(alias_file_for_sid "$input_sid")"
  tmp="${alias_file}.$$"
  printf '%s\n' "$session_key" > "$tmp"
  mv "$tmp" "$alias_file"
}

resolve_session_file() {
  local input_sid="${1:-}"
  local session_key
  local file
  local alias_file
  local aliased_key

  ensure_state_layout

  session_key="$(safe_session_key "$input_sid")"
  file="$(session_file_for_key "$session_key")"
  if [ -f "$file" ] && [ -s "$file" ]; then
    printf '%s\n' "$file"
    return 0
  fi

  if [ -n "$input_sid" ] && [ "$input_sid" != "null" ]; then
    alias_file="$(alias_file_for_sid "$input_sid")"
    if [ -f "$alias_file" ] && [ -s "$alias_file" ]; then
      aliased_key="$(tr -d '[:space:]' < "$alias_file")"
      file="$(session_file_for_key "$aliased_key")"
      if [ -f "$file" ] && [ -s "$file" ]; then
        printf '%s\n' "$file"
        return 0
      fi
    fi

    file="$(session_file_for_key "$input_sid")"
    if [ -f "$file" ] && [ -s "$file" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  fi

  return 1
}

build_state_json() {
  local session_key="$1"
  local input_sid="$2"
  local status="$3"
  local tab_id="${4:-}"
  local last_tool="${5:-}"
  local last_error="${6:-}"
  local existing_created_at="${7:-}"
  local created_at

  if [ -n "$existing_created_at" ]; then
    created_at="$existing_created_at"
  else
    created_at="$(now_iso8601)"
  fi

  if [ -n "$tab_id" ] && [ "$tab_id" != "null" ]; then
    jq -n \
      --arg sessionKey "$session_key" \
      --arg inputSessionId "$input_sid" \
      --arg status "$status" \
      --arg lastToolName "$last_tool" \
      --arg lastError "$last_error" \
      --arg createdAt "$created_at" \
      --arg updatedAt "$(now_iso8601)" \
      --argjson tabId "$tab_id" \
      '{
        version: 1,
        sessionKey: $sessionKey,
        inputSessionId: $inputSessionId,
        status: $status,
        tabId: $tabId,
        createdAt: $createdAt,
        updatedAt: $updatedAt,
        lastToolName: $lastToolName,
        lastError: $lastError
      }'
  else
    jq -n \
      --arg sessionKey "$session_key" \
      --arg inputSessionId "$input_sid" \
      --arg status "$status" \
      --arg lastToolName "$last_tool" \
      --arg lastError "$last_error" \
      --arg createdAt "$created_at" \
      --arg updatedAt "$(now_iso8601)" \
      '{
        version: 1,
        sessionKey: $sessionKey,
        inputSessionId: $inputSessionId,
        status: $status,
        tabId: null,
        createdAt: $createdAt,
        updatedAt: $updatedAt,
        lastToolName: $lastToolName,
        lastError: $lastError
      }'
  fi
}

write_state_json() {
  local session_key="$1"
  local input_sid="$2"
  local json="$3"
  local file
  local tmp

  ensure_state_layout
  file="$(session_file_for_key "$session_key")"
  tmp="${file}.$$"
  printf '%s\n' "$json" > "$tmp"
  mv "$tmp" "$file"
  write_alias "$input_sid" "$session_key"
}

log_debug() {
  local message="$1"
  local log_file

  ensure_state_layout
  log_file="$(chrome_debug_log)"
  printf '[%s] %s\n' "$(now_iso8601)" "$message" >> "$log_file"
}

extract_tab_id() {
  local blob="$1"
  local tab_id=""
  local stripped=""

  tab_id="$(printf '%s' "$blob" | jq -r '.tabId // empty' 2>/dev/null || true)"
  if [ -z "$tab_id" ]; then
    tab_id="$(printf '%s' "$blob" | jq -r '.id // empty' 2>/dev/null || true)"
  fi
  if [ -z "$tab_id" ]; then
    tab_id="$(printf '%s' "$blob" | grep -oiE 'Tab ID[: ]+([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)"
  fi
  if [ -z "$tab_id" ]; then
    tab_id="$(printf '%s' "$blob" | grep -oE '"tabId"\s*:\s*([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)"
  fi
  if [ -z "$tab_id" ]; then
    tab_id="$(printf '%s' "$blob" | grep -oE '"id"\s*:\s*([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)"
  fi
  if [ -z "$tab_id" ]; then
    stripped="$(printf '%s' "$blob" | tr -d '[:space:]')"
    if [[ "$stripped" =~ ^[0-9]+$ ]]; then
      tab_id="$stripped"
    fi
  fi

  if [[ "$tab_id" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$tab_id"
    return 0
  fi

  return 1
}

is_stale_tab_error() {
  local blob

  blob="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$blob" | grep -Eq \
    'tab[^[:alnum:]]+not[^[:alnum:]]+found|no[^[:alnum:]]+tab[^[:alnum:]]+with[^[:alnum:]]+id|target[^[:alnum:]]+closed|session[^[:alnum:]]+closed|webview[^[:alnum:]]+not[^[:alnum:]]+found|frame[^[:alnum:]]+was[^[:alnum:]]+detached|browser[^[:alnum:]]+has[^[:alnum:]]+disconnected'
}

state_field() {
  local file="$1"
  local jq_expr="$2"

  jq -r "$jq_expr // empty" "$file"
}

prune_stale_state() {
  local state_dir

  state_dir="$(chrome_state_dir)"
  find "$state_dir" -type f -mtime +1 -delete 2>/dev/null || true
}
