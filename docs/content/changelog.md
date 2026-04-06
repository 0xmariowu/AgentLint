---
title: Changelog
sidebar_position: 6
---

# Changelog

## v0.4.0 (2026-04-04)

33 checks. Two new safety checks, hardened dev workflow.

- New: S7 — detects personal filesystem paths in source files
- New: S8 — detects `pull_request_target` trigger in GitHub Actions workflows
- New: HTML report with before/after comparison when fixes are applied
- New: Segmented gauge visualization in HTML report
- New: Expandable dimension breakdowns with per-check detail
- New: Deep analyzer spawns AI subagents for contradiction and dead-weight detection
- New: Session analyzer reads Claude Code logs for recurring instruction gaps
- Changed: Report shows prioritized issues list instead of flat check output
- Changed: Fix plan groups items by fix type (guided, assisted, manual)
- Fixed: F5 correctly resolves relative paths in entry file references
- Fixed: W6 static analysis handles multi-line hook scripts
- CI: Added author email check, gitleaks, semgrep, trivy workflows
- CI: SHA-pinned all GitHub Actions

## v0.3.0 (2026-04-02)

31 checks across 5 dimensions. Major architecture upgrade.

- New: Fixer with guided, assisted, and manual fix modes
- New: Plan generator creates prioritized fix plans from scan results
- New: HTML reporter with gauge visualization
- New: S6 — detects hardcoded secrets (API keys, private keys)
- New: Evidence-based reference thresholds from Anthropic data
- Changed: Scanner outputs structured JSON per check
- Changed: Scorer supports 0-1, 0-10, and 0-100 input ranges
- Fixed: I6 entry file length scoring uses range instead of threshold

## v0.2.0 (2026-03-30)

First public release. 29 checks, 5 dimensions.

- Initial scanner with bash-based checks
- Node.js scorer with weighted dimensions
- Basic terminal output
- Claude Code plugin integration via `/al` command

## v0.1.0 (2026-03-28)

Internal prototype. 15 checks, proof of concept.
