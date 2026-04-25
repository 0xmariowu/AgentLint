#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-${ROOT}/.github/branch-protection.yml}"

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT

read -r repo branch < <(python3 - "$CONFIG" "$payload" <<'PY'
import json
import sys

config_path, payload_path = sys.argv[1], sys.argv[2]
repo = ''
branch = ''
strict = True
contexts = []
in_contexts = False

with open(config_path, encoding='utf-8') as f:
    for raw_line in f:
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if stripped.startswith('repository:'):
            repo = stripped.split(':', 1)[1].strip()
            in_contexts = False
        elif stripped.startswith('branch:'):
            branch = stripped.split(':', 1)[1].strip()
            in_contexts = False
        elif stripped.startswith('strict:'):
            strict = stripped.split(':', 1)[1].strip().lower() == 'true'
            in_contexts = False
        elif stripped == 'contexts:':
            in_contexts = True
        elif in_contexts and stripped.startswith('- '):
            contexts.append(stripped[2:].strip())
        elif not raw_line.startswith(' '):
            in_contexts = False

if not repo or not branch or not contexts:
    raise SystemExit(f'{config_path}: repository, branch, and contexts are required')

with open(payload_path, 'w', encoding='utf-8') as f:
    json.dump({'strict': strict, 'contexts': contexts}, f)

print(repo, branch)
PY
)

echo "Applying required status checks to ${repo}:${branch} from ${CONFIG}" >&2
gh api \
  --method PATCH \
  "repos/${repo}/branches/${branch}/protection/required_status_checks" \
  --input "$payload"
