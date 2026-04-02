---
date: 2026-04-03
project: harness-health
type: experience
tags: [harness-health, product, plugin, ai-friendly, meta-methods, evidence-based]
---

# Harness Health MVP — From Internal Tool to Product

## Done

- Created harness-health repo (public, MIT) with full pipeline
- Scanner: 20 mechanical checks across 4 dimensions (Findability, Instructions, Workability, Continuity), pure bash
- Scorer: weighted scoring, per-project breakdown, total /100
- Plan Generator: fix items with evidence, auto/assisted/guided types
- Fixer: execute selected fixes with backup
- Deep Analyzer: AI prompts for contradiction/dead-weight/vague rule detection
- Session Analyzer: reads ~/.claude/projects/ logs for repeated instructions, ignored rules, friction hotspots
- Reporter: terminal summary + markdown + JSONL output
- Skill definition: full interactive flow with AskUserQuestion module selection
- README with evidence table, scoring explanation, usage guide
- Evidence.json with citations for all 26 checks (Anthropic 265 versions, 6 academic papers, industry practice)

## Produced

- `github.com/0xmariowu/harness-health` — public repo, ~3,400 lines
- `internal-plan` — full product plan (v2)
- `~/.claude/commands/hh.md` — local /hh command (prototype)

## Discovered

- Anthropic's /insights command architecture (facet extraction → parallel AI analysis → HTML report) is a strong pattern for session-based analysis
- Session analyzer finds real signal (repeated instructions, potentially ignored rules) but also picks up system tag noise — needs filtering
- F5 (broken references) path extraction is the hardest check to get right — rule text fragments (.env*, __pycache__/) look like file paths
- Scorer total_score calculation needed normalization (score/max * weight * 100, not raw score * weight)
- plan-generator needed to handle scorer's flat project structure (not nested .dimensions)

## Pending

- F5 false positive filtering (project-f shows 128 — mostly rule text fragments)
- Session analyzer noise filtering (system tags, separator lines)
- Plugin packaging (claude plugin add)
- Actual /hh interactive test (need to verify AskUserQuestion flow end-to-end)
