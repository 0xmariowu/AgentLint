---
name: hh
description: "Run Harness Health diagnostic — check how AI-friendly your repos are, generate fix plan, execute fixes. Use when: user says /hh, 'check my repo', 'harness health', 'AI-friendly check', or wants to improve their CLAUDE.md / AGENTS.md."
---

# /hh — Harness Health

Diagnose, plan, fix. One command.

## Flow

### Step 1: Module Selection

Use AskUserQuestion to present:

```
Harness Health — which checks to run?

☑ Findability — can AI find what it needs?
☑ Instruction Quality — are your rules well-written?
☑ Workability — can AI build and test?
☑ Continuity — can next session pick up?
☐ AI Deep Analysis — find contradictions, dead weight, vague rules
☐ Session Analysis — discover issues from your usage history
```

Default: first 4 checked. Store selection.

### Step 2: Init (first run only)

If `~/.hh/config.json` doesn't exist:

```javascript
// Ask via AskUserQuestion:
// "Where are your projects? [~/Projects]:"
// Save to ~/.hh/config.json
{"projects_root": "~/Projects", "modules": ["findability", "instructions", "workability", "continuity"]}
```

### Step 3: Run Scanner

```bash
# Find the plugin's install directory
HH_DIR="$(dirname "$(which hh-scan 2>/dev/null || echo "$HOME/.claude/plugins/*/harness-health")")"

# If not installed as plugin, try common locations
for dir in "$HOME/.claude/plugins/"*/harness-health "$HOME/Projects/harness-health"; do
  [ -f "$dir/src/scanner.sh" ] && HH_DIR="$dir" && break
done

# Scan all projects (or use --project-dir for single)
bash "$HH_DIR/src/scanner.sh" > /tmp/hh-scan.jsonl
```

### Step 4: Run Scorer

```bash
node "$HH_DIR/src/scorer.js" /tmp/hh-scan.jsonl > /tmp/hh-scores.json
```

### Step 5: Present Scores

Read `/tmp/hh-scores.json` and present:

```
🏥 Harness Health — Score: 72/100

Findability     ████████░░  8/10
Instructions    █████████░  9/10
Workability     ██████░░░░  6/10
Continuity      ████░░░░░░  4/10

By Project:
  kalami          82  █████████████████░░░░
  autosearch      75  ███████████████░░░░░░
  atoms           71  ██████████████░░░░░░░
```

### Step 6: Run Plan Generator

```bash
node "$HH_DIR/src/plan-generator.js" /tmp/hh-scores.json > /tmp/hh-plan.json
```

### Step 7: Present Fix Plan + Ask What to Fix

Read `/tmp/hh-plan.json` and present fix items via AskUserQuestion:

```
📋 Fix Plan (8 items):

☐ 1. [auto] kalami: Remove 12 broken INDEX.jsonl references
     Evidence: 2026-04-01 audit found broken refs waste AI tokens
☐ 2. [assisted] harness-health: Generate CLAUDE.md from template
     Evidence: Anthropic auto-loads CLAUDE.md as entry point
☐ 3. [guided] kalami: Review IMPORTANT keyword usage (7 found, Anthropic uses 4)
     Evidence: Anthropic 265 versions: 12→4
☐ 4. [guided] autosearch: CLAUDE.md not updated in 45 days
     Evidence: Codified Context paper: stale content is #1 failure

Select items to fix:
```

Items labeled [auto] are executed automatically. [assisted] generates content for confirmation. [guided] shows advice only.

### Step 8: Execute Fixes

For selected items:

```bash
node "$HH_DIR/src/fixer.js" --items "1,2" --project-dir ~/Projects/kalami < /tmp/hh-plan.json
```

Present results: what was fixed, what was generated, what needs manual attention.

### Step 9: Verify

Re-run scanner + scorer on affected projects. Show score change:

```
🏥 Score: 72 → 85/100 (+13)
  Findability: 8 → 10 (+2)
  Instructions: 9 → 9 (=)
```

### Step 10: Save Report

```bash
mkdir -p ~/.hh/reports
cp /tmp/hh-scores.json ~/.hh/reports/$(date +%F).json
cp /tmp/hh-plan.json ~/.hh/reports/$(date +%F)-plan.json
```

## AI Deep Analysis (if selected)

After Step 5, before Step 6, run these checks on each project's entry file:

For each project that has an entry file, spawn a subagent (model: sonnet):

```
Read this file and answer three questions. Be strict — only flag clear issues.

1. CONTRADICTIONS: Are there rules that contradict each other? Quote both rules.
2. DEAD WEIGHT: Are there rules the AI model would follow without being told? 
   (e.g., "use descriptive variable names" — models already do this)
   Quote each dead-weight rule.
3. VAGUE RULES: Are there rules too abstract to act on — no clear decision boundary?
   (e.g., "follow best practices")
   Quote each vague rule.

File: {path}
```

Add results to the fix plan as `guided` items.

## Session Analysis (if selected)

After Step 5, scan `~/.claude/projects/` session logs:

1. **Repeated instructions**: Find user messages that appear in 2+ sessions with similar content. Use string similarity (substring matching is fine). Report as: "You told Claude '{instruction}' in {N} sessions — consider adding to CLAUDE.md."

2. **Friction signals**: Find sessions where user said "no", "wrong", "not that", "try again", "stop". Aggregate by project directory to find friction hotspots.

Add results to the fix plan:
- Repeated instructions → `assisted` type (generate CLAUDE.md rule)
- Friction hotspots → `guided` type (suggest investigation)

## Notes

- All temp files in /tmp/hh-* — cleaned up at end
- Reports saved to ~/.hh/reports/ for trend tracking
- If scanner fails: check that jq is installed
- If scorer fails: check Node.js version
