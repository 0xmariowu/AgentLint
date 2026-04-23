#!/usr/bin/env bash
# install-user.sh — AgentLint installer (curl-friendly)
# Usage: curl -fsSL https://raw.githubusercontent.com/0xmariowu/agent-lint/main/scripts/install-user.sh | bash
set -euo pipefail

G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
ok()   { printf "  ${G}✓${R} %s\n" "$1"; }
warn() { printf "  ${Y}!${R} %s\n" "$1"; }

# ── check node/npm ─────────────────────────────────────────────────────────────
if ! command -v npm &>/dev/null; then
  warn "npm not found. Install Node.js 20+ first: https://nodejs.org"
  exit 1
fi

NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ "${NODE_MAJOR:-0}" -lt 20 ]; then
  warn "Node.js 20+ required (found $(node --version 2>/dev/null || echo 'none'))"
  warn "Upgrade: https://nodejs.org"
  exit 1
fi

# ── install ─────────────────────────────────────────────────────────────────────
echo ""
echo "Installing agentlint-ai..."
npm install -g agentlint-ai --silent
ok "agentlint-ai installed"

# ── init (shows full UI + Claude Code plugin setup) ─────────────────────────────
echo ""
agentlint-ai init
