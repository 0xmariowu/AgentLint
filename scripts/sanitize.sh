#!/usr/bin/env bash
# shellcheck disable=SC2059
# sanitize.sh — pre-release PII audit
# Usage: scripts/sanitize.sh [--repo <path>]
# Read-only: reports what needs cleaning, does NOT modify git history.
#
# Machine-hostname scan allowlist:
#   SANITIZE_ALLOWLIST_FILES contains tracked files whose hostname-looking text
#   is intentional documentation of the scanner patterns. Keep this path-based;
#   do not allowlist literal hostnames globally or real leaks in other files
#   will be hidden.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BOLD='\033[1m'; DIM='\033[0;90m'; NC='\033[0m'

REPO="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    -*)     printf "${RED}error:${NC} unknown flag: %s\n" "$1" >&2; exit 1 ;;
    *)      REPO="$1"; shift ;;
  esac
done

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
  printf "${RED}error:${NC} not a git repo: %s\n" "$REPO" >&2
  exit 1
}
REPO="$(cd "$REPO" && pwd)"
REPO_NAME="$(basename "$REPO")"
INTERNAL_CODENAMES_FILE="$REPO/.internal-codenames"

# Placeholder patterns that are intentional in this repo (README examples,
# evidence text, docker-e2e fixtures). Mirrors .husky/pre-commit.
PLACEHOLDER_FILTER='/Users/xxx|/home/xxx|/home/testuser|/Users/yourusername|/Users/example|/home/runner'

# File patterns that legitimately contain '.local' (config filenames, not
# hostnames). Mirrors agent-lint's tracked content.
LOCAL_FILE_ALLOWLIST='CLAUDE\.local\.md|\.env\.local|\.ship-boundary-deny\.local|CLAUDE\.LOCAL\.md'

SANITIZE_ALLOWLIST_FILES=(
  "templates/configs/privacy-taxonomy.md"
)

sanitize_is_allowlisted_file() {
  local file="$1"
  local allowlisted_file
  for allowlisted_file in "${SANITIZE_ALLOWLIST_FILES[@]}"; do
    [[ "$file" == "$allowlisted_file" ]] && return 0
  done
  return 1
}

printf "\n${BOLD}PII Audit: ${REPO_NAME}${NC}\n"
printf "${DIM}%s${NC}\n\n" "$REPO"

FAIL_COUNT=0
WARN_COUNT=0

fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; ((FAIL_COUNT++)) || true; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; ((WARN_COUNT++)) || true; }
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
info() { printf "${DIM}[INFO]${NC} %s\n" "$*"; }

# ── Audit 1: Non-noreply emails in git log ──────────────────────────────────

printf "${BOLD}1. Author email audit${NC}\n"
BAD_EMAILS=$(git -C "$REPO" log --all --format="%ae" | sort -u | grep -vE '@users\.noreply\.github\.com$|@github\.com$|^noreply@github\.com$' || true)

if [[ -n "$BAD_EMAILS" ]]; then
  fail "Non-noreply emails found in git history:"
  while IFS= read -r email; do
    COUNT=$(git -C "$REPO" log --all --format="%ae" | grep -c "^${email}$" || true)
    printf "       %s (%d commits)\n" "$email" "$COUNT"
  done <<< "$BAD_EMAILS"
else
  ok "All commit emails are noreply"
fi
echo

# Tracked files only — untracked test artifacts, coverage reports, and local
# scratch don't reach the public repo, so scanning them is noise.
TRACKED_FILES=$(git -C "$REPO" ls-files)

# ── Audit 2: Personal paths in tracked files ────────────────────────────────

printf "${BOLD}2. Personal paths in tracked files${NC}\n"
PATH_HITS=""
if [[ -n "$TRACKED_FILES" ]]; then
  PATH_HITS=$(printf '%s\n' "$TRACKED_FILES" \
    | xargs -I{} grep -nHE '/Users/[a-zA-Z0-9_]+/|/home/[a-z][a-z0-9_-]+/' "$REPO/{}" 2>/dev/null \
    | grep -vE "$PLACEHOLDER_FILTER" | head -20 || true)
fi

if [[ -n "$PATH_HITS" ]]; then
  fail "Personal paths found in tracked files:"
  printf "%s\n" "$PATH_HITS" | while IFS= read -r line; do
    printf "       %s\n" "${line#"$REPO"/}"
  done
else
  ok "No personal paths in tracked files"
fi
echo

# ── Audit 3: Machine hostnames (.ts.net, .local) in tracked files ───────────

printf "${BOLD}3. Machine hostnames (Tailscale, mDNS) in tracked files${NC}\n"
HOST_HITS=""
if [[ -n "$TRACKED_FILES" ]]; then
  HOST_HITS=$(while IFS= read -r file; do
      [[ "$file" == *.gitleaks.toml ]] && continue
      sanitize_is_allowlisted_file "$file" && continue
      grep -nHE '[a-zA-Z0-9][a-zA-Z0-9-]*\.ts\.net|[a-zA-Z][a-zA-Z0-9-]*\.local\b' "$REPO/$file" 2>/dev/null || true
    done <<< "$TRACKED_FILES" \
    | grep -vE "$LOCAL_FILE_ALLOWLIST" | head -20 || true)
fi

if [[ -n "$HOST_HITS" ]]; then
  fail "Machine hostname references found:"
  printf "%s\n" "$HOST_HITS" | while IFS= read -r line; do
    printf "       %s\n" "${line#"$REPO"/}"
  done
else
  ok "No machine hostname references"
fi
echo

# ── Audit 4: PII in git history (last 50 commits) ───────────────────────────

printf "${BOLD}4. PII in git history (last 50 commits)${NC}\n"
HISTORY_HITS=""
while IFS= read -r sha; do
  DIFF_HITS=$(git -C "$REPO" show "$sha" 2>/dev/null \
    | grep -E '^\+.*/Users/[a-zA-Z0-9_]+/|^\+.*/home/[a-z][a-z0-9_-]+/|^\+.*\.ts\.net' \
    | grep -vE "$PLACEHOLDER_FILTER" \
    | head -3 || true)
  if [[ -n "$DIFF_HITS" ]]; then
    HISTORY_HITS+="  commit ${sha:0:7}:"$'\n'
    HISTORY_HITS+="$DIFF_HITS"$'\n'
  fi
done < <(git -C "$REPO" log --all --format="%H" -50 2>/dev/null)

if [[ -n "$HISTORY_HITS" ]]; then
  warn "PII found in recent git history (git-filter-repo needed to scrub):"
  printf "%s\n" "$HISTORY_HITS" | while IFS= read -r line; do
    printf "       %s\n" "$line"
  done
else
  ok "No PII in recent git history"
fi
echo

# ── Audit 5: Internal codenames in files ────────────────────────────────────

printf "${BOLD}5. Internal project codenames in tracked files${NC}\n"
if [[ -f "$INTERNAL_CODENAMES_FILE" ]]; then
  NAME_HITS=""
  if [[ -n "$TRACKED_FILES" ]]; then
    NAME_HITS=$(printf '%s\n' "$TRACKED_FILES" \
      | grep -vE '\.gitleaks\.toml$|\.internal-codenames$' \
      | xargs -I{} grep -nHE -f "$INTERNAL_CODENAMES_FILE" "$REPO/{}" 2>/dev/null \
      | head -20 || true)
  fi

  if [[ -n "$NAME_HITS" ]]; then
    warn "Internal project names found (review for public exposure):"
    printf "%s\n" "$NAME_HITS" | while IFS= read -r line; do
      printf "       %s\n" "${line#"$REPO"/}"
    done
  else
    ok "No internal project names found"
  fi
else
  info "Skipping: .internal-codenames not present (no codenames configured)"
fi
echo

# ── Audit 6: Internal codenames in commit messages ──────────────────────────

printf "${BOLD}6. Internal project codenames in commit messages${NC}\n"
if [[ -f "$INTERNAL_CODENAMES_FILE" ]]; then
  MSG_HITS=$(git -C "$REPO" log --all --format="%H %s" | grep -iE -f "$INTERNAL_CODENAMES_FILE" | head -10 || true)

  if [[ -n "$MSG_HITS" ]]; then
    warn "Internal project names in commit messages:"
    printf "%s\n" "$MSG_HITS" | while IFS= read -r line; do
      printf "       %s\n" "$line"
    done
  else
    ok "No internal project names in commit messages"
  fi
else
  info "Skipping: .internal-codenames not present"
fi
echo

# ── Audit 7: Personal paths in commit messages ──────────────────────────────

printf "${BOLD}7. Personal paths in commit messages (last 200)${NC}\n"
MSG_PII=$(git -C "$REPO" log --all --format='%H %B' -200 2>/dev/null \
  | grep -nE '/Users/[a-zA-Z0-9_]+/|/home/[a-z][a-z0-9_-]+/|[a-zA-Z0-9][a-zA-Z0-9-]*\.ts\.net' \
  | grep -vE "$PLACEHOLDER_FILTER" \
  | head -10 || true)

if [[ -n "$MSG_PII" ]]; then
  warn "Personal paths or hostnames in commit messages:"
  printf "%s\n" "$MSG_PII" | while IFS= read -r line; do
    printf "       %s\n" "$line"
  done
else
  ok "No personal paths or hostnames in commit messages"
fi
echo

# ── Audit 8: Internal codenames in branch names ─────────────────────────────

printf "${BOLD}8. Internal project codenames in branch names${NC}\n"
if [[ -f "$INTERNAL_CODENAMES_FILE" ]]; then
  BRANCH_HITS=$(git -C "$REPO" branch -a --format='%(refname:short)' | grep -iE -f "$INTERNAL_CODENAMES_FILE" | head -10 || true)

  if [[ -n "$BRANCH_HITS" ]]; then
    warn "Internal project names in branch names:"
    printf "%s\n" "$BRANCH_HITS" | while IFS= read -r line; do
      printf "       %s\n" "$line"
    done
  else
    ok "No internal project names in branch names"
  fi
else
  info "Skipping: .internal-codenames not present"
fi
echo

# ── Summary ─────────────────────────────────────────────────────────────────

printf "${BOLD}Summary:${NC} "
if [[ $FAIL_COUNT -eq 0 && $WARN_COUNT -eq 0 ]]; then
  printf "${GREEN}Clean${NC}\n"
elif [[ $FAIL_COUNT -eq 0 ]]; then
  printf "${YELLOW}%d warning(s)${NC}\n" "$WARN_COUNT"
else
  printf "${RED}%d failure(s)${NC}, ${YELLOW}%d warning(s)${NC}\n" "$FAIL_COUNT" "$WARN_COUNT"
fi

# ── Remediation hints ───────────────────────────────────────────────────────

if [[ $FAIL_COUNT -gt 0 || $WARN_COUNT -gt 0 ]]; then
  printf "\n${BOLD}Next steps:${NC}\n"

  if [[ -n "$BAD_EMAILS" ]]; then
    printf "\n  Email rewrite (all commits → noreply):\n"
    printf "    git-filter-repo --email-callback 'return b\"<ID>+<handle>@users.noreply.github.com\"'\n"
  fi

  if [[ -n "$PATH_HITS" || -n "$HOST_HITS" ]]; then
    printf "\n  Replace personal paths/hostnames with \$HOME, env vars, or repo-relative paths.\n"
    printf "  For git history scrub: git-filter-repo --replace-text <mapping-file>\n"
  fi

  printf "\n  ${DIM}After git history rewrite: force push + inform collaborators to re-clone.${NC}\n"
fi

printf "\n"
exit $((FAIL_COUNT > 0 ? 1 : 0))
