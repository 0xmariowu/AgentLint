#!/usr/bin/env bash
# P0-2-tag regression test: assert the structural gates added to
# .github/workflows/release.yml + .github/rulesets/tag-protection.yml are
# in place and ordered correctly. This is a static-shape test (parses the
# YAML) — it does NOT need GitHub credentials.

set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
RELEASE_YAML="$REPO_ROOT/.github/workflows/release.yml"
RULESET_YAML="$REPO_ROOT/.github/rulesets/tag-protection.yml"

[ -f "$RELEASE_YAML" ] || { echo "FAIL: $RELEASE_YAML not found" >&2; exit 1; }
[ -f "$RULESET_YAML" ] || { echo "FAIL: $RULESET_YAML not found" >&2; exit 1; }

failures=0
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "  PASS: $1"; }

# --- Test 1: tag-protection.yml shape ---
echo "case 1: tag-protection.yml has the expected shape"
python3 - "$RULESET_YAML" <<'PY' || exit 1
import sys
try:
    import yaml
except ImportError:
    print('PyYAML required for ruleset shape check', file=sys.stderr)
    sys.exit(1)

p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    d = yaml.safe_load(f)

errors = []
if d.get('target') != 'tag':
    errors.append(f"target is {d.get('target')!r}, expected 'tag'")
if d.get('enforcement') != 'active':
    errors.append(f"enforcement is {d.get('enforcement')!r}, expected 'active'")
includes = d.get('conditions', {}).get('ref_name', {}).get('include', [])
if not any('v*' in inc for inc in includes):
    errors.append(f'conditions.ref_name.include lacks a v* pattern: {includes!r}')
rule_types = sorted(r.get('type') for r in d.get('rules', []))
expected = sorted(['deletion', 'non_fast_forward'])
if rule_types != expected:
    errors.append(f"rules has {rule_types!r}, expected {expected!r}")

if errors:
    for e in errors:
        print(f'  FAIL: ruleset: {e}', file=sys.stderr)
    sys.exit(1)
print(f"  PASS: ruleset target=tag, enforcement=active, v* match, rules={rule_types}")
PY

# --- Test 2: release.yml structural gates ---
echo "case 2: release.yml ancestor check is in the publish job"
python3 - "$RELEASE_YAML" <<'PY' || true
import sys
try:
    import yaml
except ImportError:
    print('PyYAML required', file=sys.stderr)
    sys.exit(1)

p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    wf = yaml.safe_load(f)

# Expect a single job (release). Walk its steps and assert ordering.
jobs = wf.get('jobs') or {}
release_job = next(iter(jobs.values()), {})
steps = release_job.get('steps') or []

def find_step(predicate):
    for i, s in enumerate(steps):
        if predicate(s):
            return i
    return -1

idx_checkout = find_step(lambda s: 'actions/checkout' in (s.get('uses') or ''))
idx_ancestor = find_step(lambda s: 'merge-base --is-ancestor' in (s.get('run') or ''))
idx_checks  = find_step(lambda s: 'check-runs' in (s.get('run') or '') and '!= "success"' in (s.get('run') or ''))
idx_publish = find_step(lambda s: 'npm publish' in (s.get('run') or ''))

ok = True
def report(name, idx, msg):
    global ok
    if idx == -1:
        print(f'  FAIL: {name}: {msg}', file=sys.stderr)
        ok = False
    else:
        print(f'  PASS: {name} at step index {idx}')

report('actions/checkout step exists', idx_checkout, 'no checkout step found')
report('ancestor-check step exists',   idx_ancestor, 'no `git merge-base --is-ancestor` step')
report('Checks-API gate exists',       idx_checks,   'no check-runs gate that filters non-success conclusions')
report('npm publish step exists',      idx_publish,  'no `npm publish` step')

if idx_checkout >= 0 and idx_ancestor >= 0 and idx_ancestor < idx_checkout:
    print('  FAIL: ancestor check is BEFORE checkout (impossible — needs git history)', file=sys.stderr)
    ok = False
if idx_ancestor >= 0 and idx_publish >= 0 and idx_ancestor >= idx_publish:
    print('  FAIL: ancestor check runs AT OR AFTER npm publish (gate is too late)', file=sys.stderr)
    ok = False
if idx_checks >= 0 and idx_publish >= 0 and idx_checks >= idx_publish:
    print('  FAIL: Checks-API gate runs AT OR AFTER npm publish (gate is too late)', file=sys.stderr)
    ok = False

if not ok:
    sys.exit(1)
PY
case2_rc=$?
if [ "$case2_rc" -ne 0 ]; then
    fail "case 2 release.yml gate ordering"
fi

if [ "$failures" -eq 0 ]; then
    echo "OK: release-yaml gates contract holds (P0-2-tag)"
    exit 0
fi
echo "FAIL: $failures assertion(s) failed" >&2
exit 1
