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

# Resolve every ruleset id whose summary `name` matches `expected_name`.
# Prints one id per line. Uses jq's --arg so a config name containing
# quotes / backslashes can't break the filter or be injected into a
# different ruleset selection.
expected_name=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['name'])" "$payload")
matching_ids=$(gh api "repos/${REPO}/rulesets" \
  | jq -r --arg name "$expected_name" '.[] | select(.name == $name) | .id')
matching_count=0
if [ -n "$matching_ids" ]; then
  matching_count=$(printf '%s\n' "$matching_ids" | wc -l | tr -d ' ')
fi

if [ "$MODE" = "verify" ]; then
  echo "Verifying tag ruleset on ${REPO} against ${CONFIG}" >&2
  # The list endpoint `repos/.../rulesets` returns summaries WITHOUT
  # `conditions` / `rules` / `bypass_actors`, so the matcher below would
  # report false drift on those fields if we only fetched the list. Two
  # steps: count names in the list (catches duplicates), then GET each
  # match's detail. We pass an array of detail objects to the matcher so
  # the existing list-shaped contract still works AND the duplicate guard
  # at `len(matching) > 1` keeps firing.
  if [ "$matching_count" -eq 0 ]; then
    echo "${CONFIG}: no tag ruleset named \"${expected_name}\" found on remote" >&2
    exit 1
  fi
  {
    printf '['
    first=1
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      gh api "repos/${REPO}/rulesets/${id}"
    done <<< "$matching_ids"
    printf ']'
  } > "$actual"
  python3 - "$CONFIG" "$payload" "$actual" <<'PY'
import json
import sys

config_path, expected_path, actual_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(expected_path, encoding='utf-8') as f:
    expected = json.load(f)
with open(actual_path, encoding='utf-8') as f:
    actual_list = json.load(f)

matching = [r for r in actual_list if r.get('name') == expected['name']]
if not matching:
    raise SystemExit(f'{config_path}: no tag ruleset named "{expected["name"]}" found on remote')
if len(matching) > 1:
    raise SystemExit(f'{config_path}: {len(matching)} live rulesets named "{expected["name"]}" — duplicate; clean up via UI')

live = matching[0]
errors = []
if live.get('enforcement') != expected.get('enforcement'):
    errors.append(f'enforcement: expected {expected["enforcement"]}, live {live.get("enforcement")}')
if live.get('target') != expected.get('target'):
    errors.append(f'target: expected {expected["target"]}, live {live.get("target")}')

# Conditions: ref_name.include must be a superset/equal — GitHub may
# normalize patterns, but the configured match must remain.
exp_inc = sorted(expected.get('conditions', {}).get('ref_name', {}).get('include', []))
liv_inc = sorted((live.get('conditions') or {}).get('ref_name', {}).get('include', []))
if not all(any(p == lp or p in lp for lp in liv_inc) for p in exp_inc):
    errors.append(f'conditions.ref_name.include: expected superset of {exp_inc}, live {liv_inc}')

# Rule types must include each expected one (live may have extra rules).
exp_rules = sorted(r.get('type') for r in expected.get('rules', []))
liv_rules = sorted(r.get('type') for r in (live.get('rules') or []))
missing_rules = [r for r in exp_rules if r not in liv_rules]
if missing_rules:
    errors.append(f'rules: live missing required types {missing_rules}')

# bypass_actors must match exactly. The earlier draft of this ruleset
# was rejected by the API specifically because of broken bypass_actor
# entries, so this assertion is the canary that catches a regression
# where someone re-adds bad entries (or the live ruleset gets manually
# edited via the UI).
def _norm_bypass(items):
    return sorted(
        (i.get('actor_id'), i.get('actor_type'), i.get('bypass_mode'))
        for i in (items or [])
    )

exp_bypass = _norm_bypass(expected.get('bypass_actors', []))
liv_bypass = _norm_bypass(live.get('bypass_actors', []))
if exp_bypass != liv_bypass:
    errors.append(f'bypass_actors: expected {exp_bypass}, live {liv_bypass}')

if errors:
    print(f'{config_path}: live ruleset drift — ' + '; '.join(errors), file=sys.stderr)
    sys.exit(1)

print(f'tag ruleset on remote matches: {live.get("name")} ({live.get("enforcement")})')
PY
else
  # PR #209 review fix: --apply must be idempotent. Re-running should
  # update the existing ruleset instead of POSTing a duplicate (which
  # leaves the live API with two rulesets of the same name and makes
  # --verify pick an arbitrary one).
  echo "Applying tag ruleset to ${REPO} from ${CONFIG}" >&2
  if [ "$matching_count" -gt 1 ]; then
    echo "${CONFIG}: ${matching_count} live rulesets named \"${expected_name}\" — duplicate; clean up via UI before re-applying" >&2
    exit 1
  fi
  if [ "$matching_count" -eq 1 ]; then
    existing_id=$(printf '%s\n' "$matching_ids" | head -1)
    echo "Updating existing ruleset id=${existing_id}" >&2
    gh api --method PUT "repos/${REPO}/rulesets/${existing_id}" --input "$payload"
  else
    echo "Creating new ruleset" >&2
    gh api --method POST "repos/${REPO}/rulesets" --input "$payload"
  fi
fi
