#!/usr/bin/env bash
# sandbox_setup.sh — E2B sandbox bootstrap for AgentLint tests
# Runs inside E2B sandbox (Ubuntu, user with sudo, Node 20 + git pre-installed).
# Installs jq and agentlint from the uploaded npm pack tarball.
# Sets up /tmp/agentlint-src as the canonical source path for scenario scripts.
set -uo pipefail

NODE_VERSION="${NODE_VERSION:-20}"
AGENTLINT_TAR="${AGENTLINT_TAR:-/tmp/agentlint.tar.gz}"
FROM_NPM="${FROM_NPM:-}"  # if set, install this package name from npm registry

echo "[setup] Node: $(node --version 2>/dev/null || echo missing), npm: $(npm --version 2>/dev/null || echo missing), git: $(git --version 2>/dev/null || echo missing)"

# Install jq (not in E2B base image)
if ! command -v jq &>/dev/null; then
  echo "[setup] Installing jq..."
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq 2>/dev/null || true
  sudo apt-get install -y -qq jq 2>/dev/null || true
fi
echo "[setup] jq: $(jq --version 2>/dev/null || echo missing)"

# Switch Node version if requested and different from installed
CURRENT_NODE="$(node -e 'process.version.slice(1).split(".")[0]' 2>/dev/null || echo 0)"
if [ "$CURRENT_NODE" != "$NODE_VERSION" ]; then
  echo "[setup] Switching to Node $NODE_VERSION (current: $CURRENT_NODE)..."
  export DEBIAN_FRONTEND=noninteractive
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo bash - 2>/dev/null || true
  sudo apt-get install -y nodejs 2>/dev/null || true
fi
echo "[setup] Node: $(node --version), npm: $(npm --version)"

# Install agentlint — either from npm registry or from uploaded tarball
rm -rf /tmp/agentlint-src 2>/dev/null || true

if [ -n "$FROM_NPM" ]; then
  echo "[setup] Installing $FROM_NPM from npm registry..."
  npm install -g "$FROM_NPM" --no-fund 2>&1 | tail -5 || true
  NPM_ROOT="$(npm root -g 2>/dev/null || echo /usr/lib/node_modules)"
  # agentlint-ai installs as agentlint-ai in node_modules
  INSTALL_DIR="$NPM_ROOT/agentlint-ai"
  [ -d "$INSTALL_DIR" ] || INSTALL_DIR="$NPM_ROOT/${FROM_NPM}"
  ln -s "$INSTALL_DIR" /tmp/agentlint-src
  echo "[setup] npm-mode: agentlint-src -> $INSTALL_DIR ($(ls /tmp/agentlint-src/src/ 2>/dev/null | wc -l) src files)"
else
  # Extract git archive tarball (flat, no subdirectory wrapper)
  echo "[setup] Extracting AgentLint tarball..."
  EXTRACT_DIR="/tmp/al-extract-$$"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$AGENTLINT_TAR" -C "$EXTRACT_DIR" 2>/dev/null || true

  # git archive: files extracted flat. npm pack: files under package/ subdir.
  if [ -d "$EXTRACT_DIR/package" ] && [ -f "$EXTRACT_DIR/package/package.json" ]; then
    INSTALL_DIR="$EXTRACT_DIR/package"
  else
    INSTALL_DIR="$EXTRACT_DIR"
  fi
  ln -s "$INSTALL_DIR" /tmp/agentlint-src
  echo "[setup] tarball-mode: agentlint-src -> $INSTALL_DIR ($(ls /tmp/agentlint-src/src/ 2>/dev/null | wc -l) src files)"

  # Install globally from tarball
  echo "[setup] Installing AgentLint globally from tarball..."
  cd "$INSTALL_DIR"
  npm install --silent --no-fund 2>/dev/null || true
  npm install -g . --silent --no-fund 2>/dev/null || true
fi

# Verify installation
echo "[setup] agentlint: $(agentlint --version 2>/dev/null || echo 'not found via PATH')"
echo "[setup] scanner: $(ls /tmp/agentlint-src/src/scanner.sh 2>/dev/null && echo OK || echo MISSING)"
echo "[setup] Bootstrap complete."
