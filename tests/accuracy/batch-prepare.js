#!/usr/bin/env node
'use strict';

// Generate DashScope batch JSONL for qwen-plus to label ALL 33 checks per repo.
// Cross-validates with deterministic labels for quality assurance.
//
// Usage: AL_CORPUS_DIR=/path/to/corpus/repos node batch-prepare.js
// Output: tests/accuracy/batch-input/batch_001.jsonl, batch_002.jsonl, ...

const fs = require('fs');
const path = require('path');

const CORPUS = process.env.AL_CORPUS_DIR;
if (!CORPUS) { process.stderr.write('ERROR: Set AL_CORPUS_DIR\n'); process.exit(1); }

const OUT_DIR = path.join(__dirname, 'batch-input');
const MAX_PER_FILE = 1000; // DashScope has file size limits, keep batches small
const MODEL = 'qwen-plus';

// Ensure output dir
fs.mkdirSync(OUT_DIR, { recursive: true });

function fileExists(p) { try { return fs.statSync(p).isFile(); } catch { return false; } }
function dirExists(p) { try { return fs.statSync(p).isDirectory(); } catch { return false; } }
function readFileTrunc(p, maxChars) {
  try {
    const content = fs.readFileSync(p, 'utf8');
    return content.length > maxChars ? content.slice(0, maxChars) + '\n[...truncated]' : content;
  } catch { return ''; }
}

const SYSTEM_PROMPT = `You are an expert code repository auditor for AI-friendliness.

Given a repository's key files, label each of the 33 checks as "pass", "fail", or "na" (not applicable).

Checks:
F1: Entry file exists (CLAUDE.md, AGENTS.md, or .cursorrules)
F2: Entry file has project description in first 10 lines
F3: Entry file has conditional loading guidance ("if modifying X, read Y")
F4: Entry file word count >= 100 words
F5: All markdown [link](path) references in entry file resolve (no broken links)
F6: Repo has README.md + entry file + CHANGELOG.md
F7: All @include directives in entry file resolve
I1: Entry file emphasis keywords (IMPORTANT/NEVER/MUST/CRITICAL) count <= 20
I2: Entry file has reasonable keyword density (not overly repetitive)
I3: Entry file has actionable rules with "Don't/Do not" + "Because:" pattern
I4: Entry file has action-oriented section headings (## Workflow, ## Rules, etc.)
I5: Entry file has no identity language ("You are a", "Act as a", etc.)
I6: Entry file has reasonable length (not too short, not too long for its project size)
I7: Entry file is under 40,000 characters
W1: Entry file documents build/test/run commands in code blocks
W2: CI workflows exist (.github/workflows/)
W3: Test files or test directories exist in the repo
W4: Linter/formatter configured (eslint, prettier, biome, ruff, etc.)
W5: No source files exceed 256 KB
W6: Pre-commit hook is fast (under 10 seconds)
C1: Entry file has structured sections with ## markdown headers
C2: Handoff/progress file exists (HANDOFF.md, PROGRESS.md, TODO.md)
C3: CHANGELOG.md exists with meaningful content
C4: Plans directory exists (docs/plans, .claude/plans, etc.)
C5: CLAUDE.local.md is not tracked in version control
S1: .env is listed in .gitignore (or no .env exists)
S2: GitHub Actions use SHA-pinned versions (@sha256 not @v4)
S3: Secret scanning configured (gitleaks or detect-secrets)
S4: SECURITY.md exists
S5: Workflow permissions are explicitly scoped (no top-level contents: write)
S6: No hardcoded secret patterns (API keys, private keys) in source
S7: No personal filesystem paths (/Users/ or /home/) in source
S8: No pull_request_target trigger in workflows

Rules:
- Base labels ONLY on the provided file contents
- If no entry file exists, entry-file-dependent checks (F2-F7, I1-I7, W1) are "na"
- For W5 (oversized files), W6 (hook speed): label "na" if insufficient data
- For S6, S7: label based on what you can see; "na" if no source files provided
- Output valid JSON array of 33 objects: {"check": "F1", "label": "pass|fail|na", "reason": "one sentence"}
- Be precise and conservative — when in doubt, label "fail" not "pass"`;

function assembleContext(repoDir) {
  const parts = [];

  // Meta
  const metaPath = path.join(repoDir, '_meta.json');
  if (fileExists(metaPath)) {
    const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    parts.push(`## Repository: ${meta.owner || ''}/${meta.repo || ''}`);
    parts.push(`Language: ${meta.lang || '?'} | Stars: ${meta.stars || 0}`);
  }

  // CLAUDE.md
  const claudePath = path.join(repoDir, 'CLAUDE.md');
  if (fileExists(claudePath)) {
    parts.push(`\n## CLAUDE.md\n\`\`\`\n${readFileTrunc(claudePath, 8000)}\n\`\`\``);
  }

  // AGENTS.md
  const agentsPath = path.join(repoDir, 'AGENTS.md');
  if (fileExists(agentsPath)) {
    parts.push(`\n## AGENTS.md\n\`\`\`\n${readFileTrunc(agentsPath, 4000)}\n\`\`\``);
  }

  // root-tree.txt
  const treePath = path.join(repoDir, 'root-tree.txt');
  if (fileExists(treePath)) {
    parts.push(`\n## Directory tree (root level)\n\`\`\`\n${readFileTrunc(treePath, 3000)}\n\`\`\``);
  }

  // Workflows
  const wfDir = path.join(repoDir, 'workflows');
  if (dirExists(wfDir)) {
    const wfFiles = fs.readdirSync(wfDir).filter(f => f.endsWith('.yml') || f.endsWith('.yaml')).slice(0, 5);
    for (const wf of wfFiles) {
      parts.push(`\n## Workflow: ${wf}\n\`\`\`yaml\n${readFileTrunc(path.join(wfDir, wf), 2000)}\n\`\`\``);
    }
  }

  // Build configs
  for (const cfg of ['package.json', 'go.mod', 'pyproject.toml', 'Cargo.toml']) {
    const cfgPath = path.join(repoDir, cfg);
    if (fileExists(cfgPath)) {
      parts.push(`\n## ${cfg}\n\`\`\`\n${readFileTrunc(cfgPath, 1500)}\n\`\`\``);
    }
  }

  // Rules
  const rulesDir = path.join(repoDir, 'rules');
  if (dirExists(rulesDir)) {
    const ruleFiles = fs.readdirSync(rulesDir).slice(0, 5);
    if (ruleFiles.length > 0) {
      parts.push(`\n## .claude/rules/ (${ruleFiles.length} files)`);
      for (const rf of ruleFiles) {
        parts.push(`### ${rf}\n\`\`\`\n${readFileTrunc(path.join(rulesDir, rf), 500)}\n\`\`\``);
      }
    }
  }

  // settings.json
  const settingsPath = path.join(repoDir, 'settings.json');
  if (fileExists(settingsPath)) {
    parts.push(`\n## .claude/settings.json\n\`\`\`json\n${readFileTrunc(settingsPath, 1000)}\n\`\`\``);
  }

  return parts.join('\n');
}

function buildRequest(repoName, context) {
  return {
    custom_id: repoName,
    method: 'POST',
    url: '/v1/chat/completions',
    body: {
      model: MODEL,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: `Label all 33 checks for this repository.\n\n${context}\n\nOutput a JSON array of 33 objects: [{"check": "F1", "label": "pass|fail|na", "reason": "..."}]` },
      ],
      temperature: 0,
      max_tokens: 2000,
    },
  };
}

// Main
const repoDirs = fs.readdirSync(CORPUS)
  .filter(d => {
    if (d.startsWith('_') || d.startsWith('.')) return false;
    return dirExists(path.join(CORPUS, d)) && fileExists(path.join(CORPUS, d, '_meta.json'));
  })
  .sort();

process.stderr.write(`Preparing batch for ${repoDirs.length} repos...\n`);

let fileIdx = 1;
let lineCount = 0;
let fd = null;
let totalTokensEst = 0;

function openNextFile() {
  if (fd !== null) fs.closeSync(fd);
  const fname = `batch_${String(fileIdx).padStart(3, '0')}.jsonl`;
  fd = fs.openSync(path.join(OUT_DIR, fname), 'w');
  fileIdx++;
  lineCount = 0;
  process.stderr.write(`  Writing ${fname}...\n`);
}

openNextFile();

for (const repoName of repoDirs) {
  const repoDir = path.join(CORPUS, repoName);
  const context = assembleContext(repoDir);
  const request = buildRequest(repoName, context);

  const line = JSON.stringify(request) + '\n';
  totalTokensEst += Math.ceil(context.length / 4) + 1000; // rough estimate

  fs.writeSync(fd, line);
  lineCount++;

  if (lineCount >= MAX_PER_FILE) {
    openNextFile();
  }
}

if (fd !== null) fs.closeSync(fd);

const totalFiles = fileIdx - 1 + (lineCount > 0 ? 0 : -1);
const costEst = (totalTokensEst / 1000000 * 0.8 + (repoDirs.length * 1500 / 1000000) * 2.0).toFixed(1);
process.stderr.write(`\nDone: ${repoDirs.length} requests across ${fileIdx - 1} file(s)\n`);
process.stderr.write(`Estimated tokens: ~${(totalTokensEst / 1000000).toFixed(1)}M input + ~${(repoDirs.length * 1500 / 1000000).toFixed(1)}M output\n`);
process.stderr.write(`Estimated cost: ~¥${costEst} (qwen-plus standard pricing)\n`);
process.stderr.write(`Output: ${OUT_DIR}/\n`);
