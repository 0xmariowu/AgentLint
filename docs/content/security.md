---
title: Security Policy
sidebar_position: 5
---

# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.4.x   | Yes       |
| 0.3.x   | Yes       |
| 0.2.x   | No        |

## Reporting a vulnerability

Please email **security@agentlint.app** instead of opening a public issue.

**Response time**: We aim to acknowledge within 48 hours and provide a fix or mitigation plan within 7 days.

## Scope

Security concerns include:

- Code execution vulnerabilities in the scanner or fixer
- Secret exposure through reports or logs
- Supply chain risks in dependencies or CI workflows
- Privilege escalation through fix operations

## Session analysis data

The optional session analyzer reads Claude Code session logs from `~/.claude/projects/`. This data never leaves your machine — it is processed locally and only the aggregated findings appear in the report.
