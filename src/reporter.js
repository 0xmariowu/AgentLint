#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const evidencePath = path.join(__dirname, '..', 'standards', 'evidence.json');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function bar(score, max, width = 20) {
  const filled = Math.round((score / max) * width);
  return '\u2588'.repeat(filled) + '\u2591'.repeat(width - filled);
}

function generateTerminalSummary(scores) {
  const lines = [];
  lines.push('');
  lines.push(`\x1b[1m\u{1F3E5} Harness Health \u2014 Score: ${scores.total_score}/100\x1b[0m`);
  lines.push('');

  const dims = scores.dimensions || {};
  for (const [name, dim] of Object.entries(dims)) {
    const label = name.charAt(0).toUpperCase() + name.slice(1);
    const padded = label.padEnd(16);
    lines.push(`  ${padded} ${bar(dim.score, dim.max)}  ${dim.score}/${dim.max}`);
  }

  if (scores.by_project && Object.keys(scores.by_project).length > 1) {
    lines.push('');
    lines.push('  By Project:');
    const projects = Object.entries(scores.by_project)
      .map(([name, dims]) => {
        let total = 0, weightSum = 0;
        for (const dim of Object.values(dims)) {
          total += dim.score * dim.weight;
          weightSum += dim.weight;
        }
        const score = weightSum > 0 ? Math.round(total / weightSum) : 0;
        return { name, score };
      })
      .sort((a, b) => b.score - a.score);

    for (const p of projects) {
      const padded = p.name.padEnd(20);
      lines.push(`    ${padded} ${p.score.toString().padStart(3)}  ${bar(p.score, 10, 22)}`);
    }
  }

  lines.push('');
  return lines.join('\n');
}

function generateMarkdownReport(scores, plan, date) {
  const lines = [];
  lines.push(`# Harness Health Report \u2014 ${date}`);
  lines.push('');
  lines.push(`## Score: ${scores.total_score}/100`);
  lines.push('');

  const dims = scores.dimensions || {};
  lines.push('| Dimension | Score | Max |');
  lines.push('|-----------|-------|-----|');
  for (const [name, dim] of Object.entries(dims)) {
    lines.push(`| ${name} | ${dim.score} | ${dim.max} |`);
  }
  lines.push('');

  if (scores.by_project) {
    lines.push('## By Project');
    lines.push('');
    for (const [project, projectDims] of Object.entries(scores.by_project)) {
      lines.push(`### ${project}`);
      for (const [dimName, dim] of Object.entries(projectDims)) {
        lines.push(`**${dimName}**: ${dim.score}/${dim.max}`);
        for (const check of dim.checks || []) {
          const icon = check.score >= 0.8 ? '\u2713' : check.score >= 0.5 ? '\u26A0' : '\u2717';
          lines.push(`- ${icon} ${check.check_id}: ${check.name} \u2014 ${check.detail || ''}`);
        }
        lines.push('');
      }
    }
  }

  if (plan && plan.items && plan.items.length > 0) {
    lines.push('## Fix Plan');
    lines.push('');
    for (const item of plan.items) {
      lines.push(`- [ ] [${item.fix_type}] ${item.project}: ${item.description}`);
      if (item.evidence) {
        lines.push(`  > ${item.evidence.slice(0, 120)}...`);
      }
    }
    lines.push('');
  }

  return lines.join('\n');
}

function generateJsonl(scores, date) {
  const lines = [];
  for (const [project, projectDims] of Object.entries(scores.by_project || {})) {
    for (const [dimName, dim] of Object.entries(projectDims)) {
      for (const check of dim.checks || []) {
        lines.push(JSON.stringify({
          date,
          project,
          dimension: dimName,
          check_id: check.check_id,
          name: check.name,
          score: check.score,
          measured_value: check.measured_value,
          detail: check.detail,
        }));
      }
    }
  }
  return lines.join('\n') + '\n';
}

function main() {
  const args = process.argv.slice(2);
  const scoresFile = args.find(a => !a.startsWith('--'));
  const planFile = args.find((a, i) => args[i - 1] === '--plan');
  const outputDir = args.find((a, i) => args[i - 1] === '--output-dir') || null;
  const format = args.find((a, i) => args[i - 1] === '--format') || 'terminal';

  if (!scoresFile) {
    process.stderr.write('Usage: reporter.js <scores.json> [--plan plan.json] [--output-dir dir] [--format terminal|md|jsonl|all]\n');
    process.exit(1);
  }

  const scores = readJson(scoresFile);
  const plan = planFile ? readJson(planFile) : null;
  const date = new Date().toISOString().split('T')[0];

  if (format === 'terminal' || format === 'all') {
    process.stdout.write(generateTerminalSummary(scores));
  }

  if (outputDir || format === 'all' || format === 'md' || format === 'jsonl') {
    const dir = outputDir || '.';
    fs.mkdirSync(dir, { recursive: true });

    if (format === 'md' || format === 'all') {
      const md = generateMarkdownReport(scores, plan, date);
      const mdPath = path.join(dir, `hh-${date}.md`);
      fs.writeFileSync(mdPath, md);
      process.stderr.write(`Report: ${mdPath}\n`);
    }

    if (format === 'jsonl' || format === 'all') {
      const jsonl = generateJsonl(scores, date);
      const jsonlPath = path.join(dir, `hh-${date}.jsonl`);
      fs.writeFileSync(jsonlPath, jsonl);
      process.stderr.write(`Data: ${jsonlPath}\n`);
    }
  }
}

main();
