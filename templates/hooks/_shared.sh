#!/usr/bin/env bash
# _shared.sh — Shared helpers for project hooks
# Source this file at the top of your hook scripts:
#   source "$(dirname "$0")/_shared.sh"

# fail_with_help — structured hook error (what / rule / fix / see)
# Usage: fail_with_help "what went wrong" "which rule" "how to fix" ["docs link"]
fail_with_help() {
  local what="$1"
  local rule="$2"
  local fix="$3"
  local see="${4:-}"

  printf 'error: %s\n' "$what" >&2
  printf '  Rule: %s\n' "$rule" >&2
  printf '  Fix:  %s\n' "$fix" >&2
  [ -n "$see" ] && printf '  See:  %s\n' "$see" >&2
  exit 1
}
