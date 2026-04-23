#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION="${NODE_VERSION:-20}"
AGENTLINT_TAR="${AGENTLINT_TAR:-/tmp/agentlint.tar.gz}"

echo "[setup] Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq curl git jq python3 python3-pip 2>/dev/null || true

echo "[setup] Installing Node.js $NODE_VERSION..."
# Try nvm first, fall back to NodeSource
if ! command -v node &>/dev/null || [ "$(node -e 'process.version.slice(1).split(".")[0]')" != "$NODE_VERSION" ]; then
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - 2>/dev/null
  apt-get install -y nodejs 2>/dev/null
fi

echo "[setup] Node: $(node --version), npm: $(npm --version)"

echo "[setup] Installing AgentLint from tarball..."
mkdir -p /tmp/agentlint-src
tar -xzf "$AGENTLINT_TAR" -C /tmp/agentlint-src --strip-components=1 2>/dev/null \
  || tar -xzf "$AGENTLINT_TAR" -C /tmp/agentlint-src

cd /tmp/agentlint-src
npm install --silent 2>/dev/null || true
npm install -g . --silent 2>/dev/null || npm install -g /tmp/agentlint-src --silent

echo "[setup] AgentLint: $(agentlint --version 2>/dev/null || echo 'installed but --version not found')"
echo "[setup] Bootstrap complete."
