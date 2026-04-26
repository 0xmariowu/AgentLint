# AgentLint P0 Production Blocker Scan

Date: 2026-04-25

Repository: `0xmariowu/AgentLint`

Local path: `<repo-root>`

Current local branch during final scan: `fix/cn-en-yaml-comment`

Current local HEAD: `37b8534c66ab9cfec0d2dcbf8a9113974c055eb5`

Current `origin/main`: `2d29b5b9fc86ba6642a8d601e859c2995b98c1bf`

Baseline release tag: `v1.1.5` -> `0de092b16b5ecedaa750792f74ec020bc3d6624b`

Scope: P0 only. This document intentionally excludes P1/P2 quality issues unless they are needed to explain a P0 production blocker.

## P0 Definition Used

A finding is P0 only if it meets at least one of these conditions:

- A normal user follows the public install or Action docs and the first path fails.
- A released package or Action cannot deliver the current fixed product to users.
- A production safety gate can be bypassed or is not enforced.
- A setup command claims to install security controls but actually disables or omits them.
- A supported platform cannot run the installed CLI through the documented path.

## Executive Summary

The codebase is much healthier than the previous round: unit tests pass, npm pack is self-contained, the public `@v0` Action reference is gone, `gitleaks` finds no real leaks, and `.env.example` no longer contains token-shaped placeholders.

However, there are still P0 release and user-entry blockers:

- Current source contains post-`v1.1.5` fixes, but every version source still says `1.1.5`, and `agentlint-ai@1.1.5` is already published from the old commit.
- Remote `main` branch protection currently exposes no required status checks via GitHub API, despite `.github/branch-protection.yml` declaring required gates.
- `agentlint setup --lang ts --no-install` claims hooks are installed and sets `core.hooksPath=.husky`, but generates no `.husky` hook files.
- `INSTALL.md` gives a copy-paste GitHub Action snippet without `actions/checkout`, so users can scan an empty workspace.
- The npm global bin resolver still fails on environments without `readlink -f` when npm creates relative bin symlinks.
- `INSTALL.md` tells users to verify with `agentlint check --help`, but that command currently exits non-zero.
- `agentlint setup --no-install` can disable existing hooks before it writes any new `.husky` hooks (core hooksPath overwrite).
- `release.yml` can move `v1` from unprotected `v*` tag events that are not guaranteed to pass required checks first.
- `/al` session analysis performs weak project-path matching that can merge unrelated session logs and leak raw fragments into wrong project reports.
- `node src/reporter.js` blocks indefinitely in TTY mode when called without input.
- `npm install -g agentlint-ai` mutates `~/.claude` and installs plugin/command artifacts without a prominent opt-in notice in canonical quickstart docs.

## Verified Good Signals

These were checked locally before writing this report:

```bash
npm test
npm run lint:shell
npm pack --json --dry-run
bash scripts/sanitize.sh
gitleaks detect --source . --redact --no-banner --exit-code 1
git ls-files -z | xargs -0 detect-secrets scan --all-files
scripts/agentlint.sh check --project-dir . --fail-below 0
```

Results:

- `npm test` passed: scanner, CLI wrapper, registry consistency, surface sync, session, deep, scorer, plan-generator, reporter, fixer, HTML, basename, Action smoke, SARIF.
- `npm run lint:shell` passed.
- `npm pack --json --dry-run` produced a 97-file package containing `src/`, `standards/`, `commands/`, `templates/`, `postinstall.js`, `scripts/`, `.claude-plugin/`, `README.md`, `INSTALL.md`, and `LICENSE`.
- `gitleaks` scanned 435 commits and reported no leaks.
- Tracked-file `detect-secrets` findings are test fixtures / high-entropy corpus labels, not real credentials.
- Current self-scan returns `Score: 92/100 (core)`.
- Npm registry latest is `agentlint-ai@1.1.5`, and the `v1` tag exists.

These positives do not remove the P0 blockers below.

## P0-1. Current Fixed Source Cannot Be Published As-Is

Severity: P0 release blocker

Status: confirmed

### Evidence

Current branch is not at `v1.1.5`:

```bash
git rev-parse HEAD v1.1.5^{} v1^{}
```

Observed:

```text
37b8534c66ab9cfec0d2dcbf8a9113974c055eb5
0de092b16b5ecedaa750792f74ec020bc3d6624b
0de092b16b5ecedaa750792f74ec020bc3d6624b
```

`origin/main` has 6 commits after `v1.1.5`; current local branch has 7 after `v1.1.5`.

```bash
git rev-list v1.1.5..HEAD --count
```

Observed:

```text
7
```

All version sources still say `1.1.5`:

```bash
node -e "const p=require('./package.json'); const m=require('./release-metadata.json'); const cp=require('./.claude-plugin/plugin.json'); const mp=require('./.claude-plugin/marketplace.json'); console.log({package:p.version, metadata:m.version, plugin:cp.version, marketplace:mp.metadata?.version, check_count:m.check_count});"
```

Observed:

```text
{
  package: '1.1.5',
  metadata: '1.1.5',
  plugin: '1.1.5',
  marketplace: '1.1.5',
  check_count: 58
}
```

Npm already has `1.1.5` published from the old release commit:

```bash
npm view agentlint-ai@1.1.5 dist.shasum dist.integrity gitHead
```

Observed:

```text
dist.shasum = '182985179c6ae6afd91e9d007f596c3d4ee59346'
dist.integrity = 'sha512-lK2YpoPPZPzeayNn/JOTQmjNn4LqiqzVlsI/Kjd3gMxBQPD8oBYXVrkUHgoS8pcuDkGJqk2YLAmhj6HA2W1PrA=='
gitHead = '0de092b16b5ecedaa750792f74ec020bc3d6624b'
```

Local dry-run package from the current tree has different contents:

```bash
npm pack --json --dry-run
```

Observed local package shasum:

```text
261faf59e4ce52876449db8e3a266c7f29ad2510
```

Publishing current tree as `1.1.5` is blocked:

```bash
npm publish --dry-run --json
```

Observed:

```text
You cannot publish over the previously published versions: 1.1.5.
```

### Impact

Users installing with the canonical command:

```bash
npm install -g agentlint-ai
```

receive the already-published package built from `0de092b`, not the current fixed source. GitHub Action users using `@v1` also resolve to the old `v1.1.5` commit:

```bash
git rev-parse v1^{}
```

returns:

```text
0de092b16b5ecedaa750792f74ec020bc3d6624b
```

This means several fixes merged after `v1.1.5` are present on `main` but not delivered through the public install paths.

### Required Fix

1. Bump every version source to the next unreleased version, likely `1.1.6`:
   - `package.json`
   - `.claude-plugin/plugin.json`
   - `.claude-plugin/marketplace.json`
   - `release-metadata.json`
   - README badges / release metadata if generated by `scripts/bump-version.sh`
2. Create a new release tag from the fixed commit:
   - `v1.1.6`
3. Publish `agentlint-ai@1.1.6`.
4. Force-update the moving major Action tag:
   - `v1` -> `v1.1.6` commit
5. Verify:

```bash
npm view agentlint-ai@1.1.6 gitHead
git ls-remote --tags origin v1 v1.1.6
npm install -g agentlint-ai
agentlint --version
```

Acceptance:

- `npm view agentlint-ai@1.1.6 gitHead` equals the release commit.
- `v1^{}` resolves to the same release commit.
- `npm install -g agentlint-ai` installs the fixed package.

## P0-2. Remote Main Branch Protection Does Not Enforce Required Gates

Severity: P0 production gate bypass

Status: confirmed from GitHub API

### Evidence

Local declared policy:

```yaml
required_status_checks:
  strict: true
  contexts:
    - lint (20)
    - lint (22)
    - test (20)
    - test (22)
    - scan
    - label
    - accuracy
    - npm-e2e
    - analyze
    - Semgrep
```

Location: `.github/branch-protection.yml`

Remote branch protection summary:

```bash
gh api repos/0xmariowu/AgentLint/branches/main --jq '.protection'
```

Observed:

```json
{"enabled":true,"required_status_checks":{"checks":[],"contexts":[],"enforcement_level":"non_admins"}}
```

Repository rulesets:

```bash
gh api repos/0xmariowu/AgentLint/rulesets
gh api repos/0xmariowu/AgentLint/rules/branches/main
```

Observed:

```text
ruleset: copilot-code-review
branch rules: copilot_code_review only
```

The local verify helper also cannot validate live protection with the current credential:

```bash
bash scripts/setup-branch-protection.sh --verify
```

Observed:

```text
gh: Not Found (HTTP 404)
```

### Additional Local Policy Gaps

Even if `.github/branch-protection.yml` were applied as-is, it is still incomplete:

- `.github/workflows/test-required.yml` exposes job `check-test-pairing`, but that check is not in required contexts.
- `.github/workflows/gitleaks.yml` and `.github/workflows/trivy.yml` both use job name `scan`; the declared required context `scan` is ambiguous.

Evidence:

```bash
grep -n 'contexts:' -A12 .github/branch-protection.yml
grep -n 'name: test-required\|check-test-pairing' .github/workflows/test-required.yml
grep -n '  scan:' .github/workflows/gitleaks.yml .github/workflows/trivy.yml
```

### Impact

The repository can show passing optional checks but still have no enforced required checks on `main`. This allows:

- CI failures to be merged by maintainers with write/admin rights.
- Security scan failures to be ignored.
- Accuracy and npm e2e gates to be skipped.
- Test-pairing policy to be informational rather than blocking.

For a product that validates repository readiness and safety, unprotected release gates are a production-level contradiction.

### Required Fix

1. Convert the desired gate into a GitHub ruleset or branch protection setting that is actually enforced on `main`.
2. Use unique stable required check names:
   - `lint (20)`
   - `lint (22)`
   - `test (20)`
   - `test (22)`
   - `npm-e2e`
   - `accuracy`
   - `gitleaks`
   - `trivy`
   - `analyze`
   - `Semgrep`
   - `label`
   - `test-required` or `check-test-pairing`
3. Rename duplicated `scan` jobs or set explicit job `name:` values.
4. Add a scheduled / manual drift audit that fails if remote protection differs from `.github/branch-protection.yml`.
5. Ensure the token used by `scripts/setup-branch-protection.sh --verify` has permission to read branch protection; otherwise the verify command cannot be a reliable gate.
6. Convert release safety to enforceable rules:
   - Add a rule that requires checks on branch and tag flow for `v*` releases.
   - Require release-triggering commits to be ancestry of `origin/main`.
   - In `release.yml`, validate required checks for commit SHA before publish and before moving `v1`.

Acceptance:

```bash
gh api repos/0xmariowu/AgentLint/branches/main --jq '.protection.required_status_checks'
gh api repos/0xmariowu/AgentLint/rules/branches/main
```

must show required status checks or equivalent ruleset requirements for all critical gates.

### P0-2-tag (Round 2 finding 2026-04-26)

老板 2026-04-26 round 2 复核：远端 main required checks 已恢复（v1.1.6 修法的一部分），但 tag-side 防线仍缺。

复现命令:

```bash
unset GITHUB_TOKEN
gh api repos/0xmariowu/AgentLint/rulesets --jq '.[] | {name, target}'
```

观察:

```text
（无 target=tag 的 ruleset）
```

`.github/workflows/release.yml` 触发条件:

```yaml
on:
  push:
    tags:
      - 'v*'
```

但 release job 在 npm publish / GitHub Release / 移动 `v1` 之前**没**校验 (a) 该 SHA 是 `origin/main` 后代；(b) 该 SHA 的 required checks 全绿。

影响: 任何拥有 tag push 权限的主体可以从未经过 main required checks 的 commit（包括废弃分支、不通过 CI 的 commit）触发 v* tag → 自动 npm publish + GitHub Release + `v1` 漂移。

Required Fix:

1. 加 `.github/rulesets/tag-protection.yml` (`target: tag`, `enforcement: active`, `conditions.ref_name.include: ['refs/tags/v*']`, `rules: [{ type: deletion }, { type: non_fast_forward }]`); 老板 + GitHub Actions bot 进 bypass actors。
2. release.yml 的 publish job 起手第一个 step 加 `git fetch origin main && git merge-base --is-ancestor "$GITHUB_SHA" origin/main || exit 1`。
3. ancestor check 之后、npm publish 之前加 Checks API gate: `gh api repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/check-runs --jq '[.check_runs[] | select(.conclusion!="success")] | length' | grep -q '^0$'`，非零 → exit 1。
4. 加 `scripts/setup-tag-protection.sh --apply` / `--verify`（仿 `setup-branch-protection.sh` 模式）一次性把 ruleset 推到远端。

Acceptance:

```bash
gh api repos/0xmariowu/AgentLint/rulesets --jq '.[] | select(.target=="tag") | {name, enforcement}'
grep -q "merge-base --is-ancestor" .github/workflows/release.yml
grep -q "check-runs" .github/workflows/release.yml
```

三条都必须返回非空 / exit 0。

## P0-3. `agentlint setup` Claims Git Hooks Are Installed But Generates Empty `.husky`

Severity: P0 safety gate bypass

Status: confirmed

### Evidence

Setup code copies from a directory that does not exist:

```bash
nl -ba scripts/setup.sh | sed -n '620,645p'
find templates/hooks -maxdepth 3 -type f -print
```

Relevant code:

```bash
for hook in "$TEMPLATE_DIR/hooks/husky/"*; do
  [ -f "$hook" ] || continue
  hook_name="$(basename "$hook")"
  copy_template "$hook" "$PROJECT/.husky/$hook_name" ".husky/$hook_name"
  chmod +x "$PROJECT/.husky/$hook_name"
done
```

Actual template files:

```text
templates/hooks/committer
templates/hooks/commit-msg
templates/hooks/_shared-push.sh
templates/hooks/_shared.sh
```

There is no `templates/hooks/husky/` directory.

Reproduction:

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/proj"
git -C "$tmp/proj" init --initial-branch=main >/dev/null 2>&1 || git -C "$tmp/proj" init >/dev/null
bash scripts/setup.sh --lang ts --visibility public --no-install "$tmp/proj"
git -C "$tmp/proj" config core.hooksPath
find "$tmp/proj/.husky" -maxdepth 2 -type f -print 2>/dev/null | sort
```

Observed:

```text
exit=0
.husky
```

No hook files are generated.

But setup output claims:

```text
hooks activated via core.hooksPath (--no-install; run 'npm install' to complete setup)
pre-commit hook (author whitelist + PII scan + secrets + codenames + lint)
pre-push hook (rebase + test)
commit-msg hook (conventional commit format)
direct git commit is blocked by the installed pre-commit hook
```

### Impact

This is more severe than a missing feature:

- The user believes PII/secrets/commit-message gates are active.
- `core.hooksPath=.husky` redirects Git away from default `.git/hooks`.
- In existing repos, this can disable previously working local hooks.
- The setup command's security story becomes false at the exact point where users rely on it.

### Required Fix

1. Add real hook templates:
   - `templates/hooks/husky/pre-commit`
   - `templates/hooks/husky/pre-push`
   - `templates/hooks/husky/commit-msg`
2. Or change `scripts/setup.sh` to copy the existing hook templates into `.husky/` correctly.
3. Fail closed if `LANG != python` and zero hook files were copied.
4. Update tests to assert:

```bash
agentlint setup --lang ts --no-install <repo>
test -x <repo>/.husky/pre-commit
test -x <repo>/.husky/pre-push
test -x <repo>/.husky/commit-msg
git -C <repo> config core.hooksPath
```

5. Add a negative test proving setup never reports installed hooks unless those files exist and are executable.
6. Add a pre-install `--no-install` safety gate:
   - Do not set `core.hooksPath` when `.husky` copy is skipped or empty.
   - If `.git/hooks` already has scripts or `core.hooksPath` is already set, prefer preserving current hooks or requiring explicit `--force`.
   - Fail with a clear error if this would disable existing hooks.

Acceptance:

- Setup output matches actual files.
- `git commit` in the generated repo triggers `.husky/pre-commit`.
- `git commit -m bad` triggers `.husky/commit-msg` or equivalent commitlint flow.

## P0-3-followup. `agentlint setup --no-install` Overwrites Existing `core.hooksPath`

Severity: P0 supply-chain / safety gate bypass

Status: confirmed by 老板 round 2 复现 2026-04-26 — v1.1.6 修法回归

### Background

P0-3 修法（v1.1.6 ship）让 `.husky/` 真正生成了三个 AgentLint hooks（pre-commit / pre-push / commit-msg），不再是"空 hooks"老问题。但同一波修法引入了新缺口：在已有 `core.hooksPath` 配置或既有 `.git/hooks/*` executable 的仓库里跑 `agentlint setup --no-install`，会**静默覆盖**用户已有的 hook 配置。

### Evidence

代码位置:

- `scripts/setup.sh:799` — 写 `git config core.hooksPath .husky` 之前未检测既有值
- `scripts/setup.sh:804` — 复制 `.husky/*` 之前未检测既有 `.git/hooks/pre-commit` 等可执行 hook
- `scripts/setup.sh:814` — 写完之后无确认 / 无回滚

复现:

```bash
tmp=$(mktemp -d)
cd "$tmp"
git init -q
mkdir -p .custom-hooks
cat > .custom-hooks/pre-commit <<'EOF'
#!/bin/bash
echo "ORG-LEVEL SECURITY HOOK" >&2
exit 0
EOF
chmod +x .custom-hooks/pre-commit
git config core.hooksPath .custom-hooks
echo "before: $(git config core.hooksPath)"

agentlint setup --lang ts --no-install "$tmp"

echo "after: $(git config core.hooksPath)"
```

观察:

```text
before: .custom-hooks
after:  .husky
```

`.custom-hooks/pre-commit` 的组织级安全 / 合规检查被静默禁用，没有任何提示。

### Impact

在已有仓库（含组织模板、合规 hook、自定义发布检查）跑 `agentlint setup` 会:

- 静默禁用既有 `core.hooksPath` 指向的 hook 链
- 跳过组织级 SAST / secret-scan / commit-msg 强制
- 不显示 warning / 不要求 `--force` 确认 / 不留可追溯日志

这把 P0-3 从"空 hooks"问题升级成了"覆盖既有 hooks"问题 —— blast radius 反而更大。

### Required Fix

1. 在写 `core.hooksPath=.husky` 之前检测：(a) `git config core.hooksPath` 已设置且不等于 `.husky` → fail closed；(b) `.git/hooks/` 下有任何 executable file 且不是 husky placeholder → fail closed。
2. 失败时 stderr 提示用户用 `--force` 显式覆盖，或者手动 merge 既有 hook 链。
3. 加 `--force` CLI flag（默认 false）显式 opt-in 覆盖。
4. 加 integration test 覆盖三种 fixture：(a) 既有 `core.hooksPath`；(b) 既有 `.git/hooks/pre-commit` executable；(c) `--force` 显式跑通。

Acceptance:

```bash
tmp=$(mktemp -d) && cd "$tmp" && git init -q && git config core.hooksPath .custom-hooks
agentlint setup --lang ts --no-install "$tmp"
test $? -ne 0 && [ "$(git config core.hooksPath)" = ".custom-hooks" ]
```

必须 exit 非 0 且 `core.hooksPath` 保持原值。

## P0-4. Canonical INSTALL GitHub Action Snippet Misses Checkout

Severity: P0 first-use Action blocker

Status: confirmed

### Evidence

`INSTALL.md` is explicitly the canonical install reference for AI coding agents.

Location: `INSTALL.md`

Current snippet:

```yaml
- uses: 0xmariowu/AgentLint@v1
  with:
    fail-below: 80
```

There is no:

```yaml
- uses: actions/checkout@...
```

The Action itself scans `project-dir: '.'`:

```yaml
inputs:
  project-dir:
    default: '.'
```

and runs:

```bash
bash "${AL_ACTION_PATH}/src/scanner.sh" --project-dir "${AL_PROJECT_DIR}" > "${RUNNER_TEMP}/al-scan.jsonl"
```

Without checkout, the runner workspace is not the user's repository.

Reproduction of the empty workspace effect:

```bash
tmp=$(mktemp -d)
bash src/scanner.sh --project-dir "$tmp" > "$tmp/scan.jsonl" 2> "$tmp/scan.err"
node src/scorer.js "$tmp/scan.jsonl" | jq '.total_score'
cat "$tmp/scan.err"
```

Observed from agent reproduction:

```text
total_score: 35
warning: not a git repository
```

### Impact

Users who copy the canonical install snippet will either:

- fail immediately with `fail-below: 80`, or
- scan an empty workspace and get a meaningless report if they remove the threshold.

This is a first-use failure in a public install document.

### Required Fix

Replace the snippet with a complete copy-paste workflow:

```yaml
name: AgentLint

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  agentlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: 0xmariowu/AgentLint@v1
        with:
          fail-below: 80
```

Also consider Action-side protection:

- If `project-dir` is `.` and no `.git` exists, fail with a clear message:
  - "Repository not checked out. Add actions/checkout before AgentLint."
- If non-git scanning is intentionally allowed, require an explicit `allow-non-git: true`.

Acceptance:

- `INSTALL.md` and `docs/content/intro.md` both include checkout in Action examples.
- A test asserts public docs Action snippets include `actions/checkout`.
- Composite Action smoke test covers the no-checkout failure message.

## P0-5. Global CLI Can Fail On Platforms Without `readlink -f`

Severity: P0 supported-platform install blocker

Status: confirmed with simulated BSD-style `readlink`. **Round 2 verified 2026-04-26** by 老板 against current 1.1.7 tarball — symptom unchanged, no v1.1.6/v1.1.7 修法 landed yet。

老板 round 2 复现命令:

```bash
# 模拟 BSD/macOS readlink 不支持 -f
tmp=$(mktemp -d)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/readlink" <<'EOF'
#!/bin/bash
[[ "$1" == "-f" ]] && { echo "readlink: illegal option -- f" >&2; exit 1; }
exec /usr/bin/readlink "$@"
EOF
chmod +x "$tmp/bin/readlink"
PATH="$tmp/bin:$PATH" agentlint --version
```

观察:

```text
cd: ../lib/node_modules/agentlint-ai/scripts: No such file or directory
```

CLI 入口完全失败 — 在公开安装路径 `npm install -g agentlint-ai` 之后，BSD/minimal 环境下用户根本进不去。

### Evidence

Location:

- `scripts/agentlint.sh`
- `src/scanner.sh`

Current resolver:

```bash
_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
```

If `readlink -f` is unavailable, fallback `readlink` returns npm's relative symlink target, commonly:

```text
../lib/node_modules/agentlint-ai/scripts/agentlint.sh
```

That relative path is then resolved relative to the caller's current directory, not relative to the symlink directory.

Reproduction:

```bash
tmp=$(mktemp -d)
npm pack --pack-destination "$tmp" >/tmp/al-readlink-pack-name.txt
npm install -g --ignore-scripts "$tmp/$(cat /tmp/al-readlink-pack-name.txt)" --prefix "$tmp/prefix" --cache "$tmp/cache"
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/readlink" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-f" ]; then
  exit 1
fi
/usr/bin/readlink "$@"
SH
chmod +x "$tmp/fakebin/readlink"
cd /tmp
PATH="$tmp/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" "$tmp/prefix/bin/agentlint" --version
```

Observed:

```text
exit=1
.../prefix/bin/agentlint: line 16: cd: ../lib/node_modules/agentlint-ai/scripts: No such file or directory
```

### Impact

The docs say macOS works out of the box. This is only safe on systems where `readlink -f` exists. On BSD-style environments or minimal containers where it does not, the installed global CLI can fail before printing a version.

The direct repo script works, but the documented user path is global npm install.

### Required Fix

Implement a portable symlink resolver in both entry scripts:

- `scripts/agentlint.sh`
- `src/scanner.sh`

Required behavior:

- Resolve symlink chains.
- If `readlink "$path"` returns a relative target, join it against `dirname "$path"`.
- Avoid relying on GNU-only `readlink -f`.

Example algorithm:

```bash
resolve_self() {
  local source="$1"
  while [ -L "$source" ]; do
    local dir
    dir="$(CDPATH='' cd -- "$(dirname -- "$source")" && pwd)"
    local target
    target="$(readlink "$source")"
    case "$target" in
      /*) source="$target" ;;
      *) source="$dir/$target" ;;
    esac
  done
  CDPATH='' cd -- "$(dirname -- "$source")" && pwd
}
```

Add tests:

- Install tarball into temporary `--prefix`.
- Put a fake `readlink` before `/usr/bin` that rejects `-f`.
- Run:

```bash
agentlint --version
agentlint check --project-dir <repo> --fail-below 0
al-scan --project-dir <repo>
```

Acceptance:

- All three commands pass without `readlink -f`.

## P0-6. Canonical Install Verification Command Fails

Severity: P0 first-use install verification failure

Status: confirmed

### Evidence

`INSTALL.md` says:

```bash
agentlint --version
agentlint check --help
```

Location: `INSTALL.md`

Reproduction against locally packed tarball:

```bash
tmp=$(mktemp -d)
npm pack --pack-destination "$tmp" >/tmp/al-help-pack-name.txt
npm install -g --ignore-scripts "$tmp/$(cat /tmp/al-help-pack-name.txt)" --prefix "$tmp/prefix" --cache "$tmp/cache"
PATH="$tmp/prefix/bin:$PATH" agentlint check --help
```

Observed:

```text
exit=1
agentlint: scanner produced no output
```

### Impact

The canonical install doc tells users and AI agents to run a command that fails immediately after successful install. This creates a false install failure and breaks the "read once, act" contract of `INSTALL.md`.

### Required Fix

Choose one:

- Documentation-only:

```bash
agentlint --version
agentlint help
```

- Product fix:
  - Make `agentlint check --help` and `agentlint check -h` print check-specific help and exit `0`.

The product fix is better because many CLI users expect subcommand help.

Acceptance:

```bash
agentlint check --help
echo $?
```

returns:

```text
0
```

and prints check usage.

## P0-7. Reporter Hangs in TTY When No Input Is Provided

Severity: P0 CLI usability blocker

Status: confirmed

### Evidence

File: [src/reporter.js](src/reporter.js:948)

When no scores file is provided, the reporter reads stdin directly:

```bash
const scoresText = fs.readFileSync(0, 'utf8');
```

In TTY mode, this blocks indefinitely rather than emitting usage.

### Impact

`agentlint report` paths that rely on this entry point can appear hung in terminals and automation wrappers.

### Required Fix

1. If no file argument is provided and stdin is a TTY, print usage and exit `1`.
2. Keep stdin reads for non-TTY or explicit `-` input modes only.

## P0-8. `/al` Session Analysis Can Cross-Attribute Unrelated Sessions

Severity: P0 data integrity and privacy leakage blocker

Status: confirmed. **Round 2 verified 2026-04-26** by 老板 — symptom unchanged on current 1.1.7 tarball; `projects/app` 短项目名被 `sessions/other-application` substring 命中，无关日志归到 app + 生成 SS1/SS4 score=0；开启 `--include-raw-snippets` 时跨项目 prompt 片段泄漏。

### Evidence

精确行号 (round 2 reverified 2026-04-26):

- [src/session-analyzer.js:341-342](src/session-analyzer.js#L341-L342) — `alias.includes(sessionKey) || sessionKey.includes(alias)` substring 匹配是 cross-attribution 的根源
- [src/session-analyzer.js:912](src/session-analyzer.js#L912) — alias 映射弱，未 normalize realpath / Claude session 编码路径
- [src/session-analyzer.js:936](src/session-analyzer.js#L936) — `--include-raw-snippets` 路径下 unmatched session 的 prompt 也会被一并输出

### Impact

Unrelated project sessions can be scored into the wrong project's SS1/SS4 checks, and `--include-raw-snippets` can leak unrelated content.

### Required Fix

1. Replace alias substring matching with strict path/identity matching and full alias normalization.
2. Only include `projectMapping == null` sessions behind explicit opt-in.
3. Suppress raw snippets for unmatched sessions unless explicitly requested.

## P0-9. Canonical Install Side Effects Are Not Upfront-Disclosed

Severity: P0 security/compliance blocker

Status: confirmed

### Evidence

- `npm install -g agentlint-ai` executes `postinstall` in [package.json](package.json:58).
- [postinstall.js](postinstall.js:121) invokes `scripts/install.sh`.
- [scripts/install.sh](scripts/install.sh:36) writes to `~/.claude` and registers `/al` command artifacts.

### Impact

The quickstart install path mutates user home and calls into Claude tooling without explicit, prominent opt-in.

### Required Fix

1. Clarify side effects at the top of `INSTALL.md` and linked docs.
2. Provide a documented `--ignore-scripts` bootstrap flow plus explicit `agentlint init` command path.
3. Add a no-side-effect mode in install flow where appropriate.

## Not P0 After This Scan

These were checked and should not be treated as P0 in this report:

- No real tracked secrets were found by `gitleaks`.
- Npm package does not include `.env`, `.npmrc`, `node_modules`, coverage, or local accuracy batch caches.
- Remaining stale references in `docs/content/changelog.md` are historical changelog content, not active quickstart instructions.
- `detect-secrets` tracked-file hits are test fixtures / corpus labels; they should be allowlisted or documented, but they are not confirmed real credentials.
- `node`/`jq` dependency diagnostics may still produce low-fidelity errors; this should be normalized but does not currently block a sane default install.

## Fix Order

1. Restore actual releaseability:
   - bump to `1.1.6`
   - tag and publish
   - move `v1`
   - verify npm `gitHead`
2. Add release safety checks for tag-based release path:
   - enforce required checks and branch ancestry for publish and `v1` move.
   - apply ruleset/branch-policy validation for `v*` tags.
3. Enforce remote branch protection / ruleset required checks.
4. Fix `agentlint setup` hook generation and `--no-install` hook override behavior; add fail-closed regression tests.
5. Fix canonical install docs:
   - Action snippet includes checkout
   - verify command uses valid help path
6. Add dependency diagnostics for missing `node`/`jq` before scanner execution paths.
7. Fix portable symlink resolution for npm global bin aliases.

## Final Acceptance Gate

Before calling this production-ready, the following must all pass:

```bash
npm test
npm run lint:shell
bash scripts/sanitize.sh
gitleaks detect --source . --redact --no-banner --exit-code 1
npm pack --json --dry-run
npm publish --dry-run --json
```

For a new release version, `npm publish --dry-run --json` must not fail with "previously published versions".

Remote checks:

```bash
npm view agentlint-ai@<new-version> gitHead
git ls-remote --tags origin v1 v<new-version>
gh api repos/0xmariowu/AgentLint/branches/main --jq '.protection.required_status_checks'
gh api repos/0xmariowu/AgentLint/rules/branches/main
gh api repos/0xmariowu/AgentLint/rulesets
```

Generated-project smoke:

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/proj"
git -C "$tmp/proj" init --initial-branch=main
agentlint setup --lang ts --visibility public --no-install "$tmp/proj"
test -x "$tmp/proj/.husky/pre-commit"
test -x "$tmp/proj/.husky/pre-push"
test -x "$tmp/proj/.husky/commit-msg"
```

Install smoke:

```bash
tmp=$(mktemp -d)
npm pack --pack-destination "$tmp"
npm install -g "$tmp"/agentlint-ai-*.tgz --prefix "$tmp/prefix" --ignore-scripts
PATH="$tmp/prefix/bin:$PATH" agentlint --version
PATH="$tmp/prefix/bin:$PATH" agentlint check --help
PATH="$tmp/prefix/bin:$PATH" agentlint check --project-dir <repo-root> --fail-below 0
printf 'score\n' | node src/reporter.js
```

Portable symlink smoke:

```bash
tmp=$(mktemp -d)
npm pack --pack-destination "$tmp"
npm install -g --ignore-scripts "$tmp"/agentlint-ai-*.tgz --prefix "$tmp/prefix"
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/readlink" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "-f" ] && exit 1
/usr/bin/readlink "$@"
SH
chmod +x "$tmp/fakebin/readlink"
PATH="$tmp/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" "$tmp/prefix/bin/agentlint" --version
```

All commands above must pass before this should be treated as production-grade for broad users.
