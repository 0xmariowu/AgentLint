#!/usr/bin/env bash
# setup-tag-protection.sh — apply or verify the tag-protection ruleset
# declared in .github/rulesets/tag-protection.yml against the live
# GitHub repository ruleset API.
#
# Usage:
#   bash scripts/setup-tag-protection.sh --apply [path/to/ruleset.yml]
#   bash scripts/setup-tag-protection.sh --verify [path/to/ruleset.yml]
#
# Requirements: gh CLI authenticated as repo admin (read for --verify,
# admin for --apply); python3 with PyYAML.
#
# Repo: this script targets `0xmariowu/AgentLint`. To target a different
# repo, set REPO=<owner>/<name>.

set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="apply"
CONFIG="${ROOT}/.github/rulesets/tag-protection.yml"
REPO="${REPO:-0xmariowu/AgentLint}"

case "${1:-}" in
  --verify)
    MODE="verify"
    CONFIG="${2:-$CONFIG}"
    ;;
  --apply)
    MODE="apply"
    CONFIG="${2:-$CONFIG}"
    ;;
  -*)
    echo "Usage: $0 [--apply|--verify] [path/to/ruleset.yml]" >&2
    exit 2
    ;;
  "")
    ;;
  *)
    CONFIG="$1"
    ;;
esac

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "ruleset config not found: $CONFIG" >&2; exit 1; }

payload="$(mktemp)"
actual="$(mktemp)"
trap 'rm -f "$payload" "$actual"' EXIT

# Convert the YAML config into the JSON shape GitHub's repo-rulesets API
# expects. PyYAML is required so we fail loud with a clear message instead
# of silently mis-parsing.
python3 - "$CONFIG" "$payload" <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    print('PyYAML is required (pip install pyyaml)', file=sys.stderr)
    sys.exit(1)

config_path, payload_path = sys.argv[1], sys.argv[2]
with open(config_path, encoding='utf-8') as f:
    cfg = yaml.safe_load(f)

required = ('name', 'target', 'enforcement', 'conditions', 'rules')
missing = [k for k in required if k not in cfg]
if missing:
    raise SystemExit(f'{config_path}: missing keys {missing}')

with open(payload_path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f)
PY

if [ "$MODE" = "verify" ]; then
  echo "Verifying tag ruleset on ${REPO} against ${CONFIG}" >&2
  gh api "repos/${REPO}/rulesets" > "$actual"
  python3 - "$CONFIG" "$payload" "$actual" <<'PY'
import json
import sys

config_path, expected_path, actual_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(expected_path, encoding='utf-8') as f:
    expected = json.load(f)
with open(actual_path, encoding='utf-8') as f:
    actual_list = json.load(f)

# Find the live ruleset by name; fall back to first tag-target ruleset.
matching = [r for r in actual_list if r.get('name') == expected['name']]
if not matching:
    matching = [r for r in actual_list if r.get('target') == 'tag']
if not matching:
    raise SystemExit(f'{config_path}: no tag ruleset named "{expected["name"]}" found on remote')

live = matching[0]
if live.get('enforcement') != expected.get('enforcement'):
    raise SystemExit(
        f'{config_path}: enforcement mismatch: expected {expected["enforcement"]}, '
        f'live {live.get("enforcement")}'
    )
if live.get('target') != 'tag':
    raise SystemExit(f'{config_path}: live ruleset target is {live.get("target")}, expected tag')

print(f'tag ruleset on remote matches: {live.get("name")} ({live.get("enforcement")})')
PY
else
  echo "Applying tag ruleset to ${REPO} from ${CONFIG}" >&2
  gh api \
    --method POST \
    "repos/${REPO}/rulesets" \
    --input "$payload"
fi
