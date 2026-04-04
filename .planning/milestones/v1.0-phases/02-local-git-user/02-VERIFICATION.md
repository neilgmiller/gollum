---
phase: 02-local-git-user
verified: 2026-04-03T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run gollum with --local-git-user and make a web edit"
    expected: "Commit is attributed to the repo's local git config user.name and user.email"
    why_human: "Integration test requires a running Sinatra server and browser interaction"
  - test: "Run gollum with --local-git-user when git config user.name/email is unset"
    expected: "Startup message shows WARNING text, edit commits without crash using Gollum defaults"
    why_human: "Startup message goes to stderr and requires live server boot"
---

# Phase 2: Local Git User Verification Report

**Phase Goal:** Implement the --local-git-user flag so Gollum uses the local git user.name and user.email for wiki commits instead of hardcoded defaults.
**Verified:** 2026-04-03
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Web edit committed with local git config user.name/email as author | VERIFIED | Test at line 24 of test_local_git_user.rb POSTs to /gollum/create and asserts `git log -1 --format='%an <%ae>'` equals 'Test User <test@example.com>' |
| 2 | Upload committed with local git config user.name/email as author | VERIFIED | Test at line 31 POSTs to /gollum/upload_file and asserts same author line |
| 3 | Git config read fresh on each write request, not cached | VERIFIED | Test at line 42 changes git config between two POSTs and asserts second commit uses 'Changed User' |
| 4 | Missing git config falls back to Gollum defaults without crash | VERIFIED | Test at line 53 unsets both config values, asserts redirect succeeds and author is not 'Test User'; test at line 62 unsets email only (partial), same assertion |
| 5 | Session author from rack middleware overrides local git user | VERIFIED | Test at line 70 injects rack.session with gollum.author and asserts commit shows 'Session User'; before filter at app.rb:141 guards with `if session['gollum.author']` |
| 6 | Startup message shows current git identity or warning if missing | VERIFIED | bin/gollum:320-328 prints identity string or WARNING message to stderr when flag is set |
| 7 | CLI flag --local-git-user sets wiki_options[:local_git_user] | VERIFIED | bin/gollum:72-76 registers flag in OptionParser; test at line 115 directly asserts `wiki_options[:local_git_user] == true` |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/gollum/app.rb` | resolve_local_git_user helper + before filter session injection | VERIFIED | `def resolve_local_git_user` at line 775; before filter block at lines 140-147; `require 'shellwords'` at line 13 |
| `bin/gollum` | CLI flag + startup message | VERIFIED | `--local-git-user` flag at line 72; startup message block at lines 320-328; `require 'shellwords'` at line 10 |
| `test/test_local_git_user.rb` | 10 tests covering USER-01, USER-02, USER-03 | VERIFIED | 131 lines, 10 test blocks confirmed by `grep -c 'test "'` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| lib/gollum/app.rb (before filter) | session['gollum.author'] | resolve_local_git_user called on non-GET requests | WIRED | app.rb:140 checks `!request.get?`, calls `resolve_local_git_user` at :144, assigns result to `session['gollum.author']` at :145 |
| lib/gollum/app.rb (resolve_local_git_user) | git config --local --get | backtick shell-out with Shellwords.escape | WIRED | app.rb:776-778 — `path = Shellwords.escape(settings.gollum_path)` then backtick `git -C #{path} config --local --get user.name/email` (note: plan specified `--get`, implementation correctly uses `--local --get` per SUMMARY deviation) |
| bin/gollum | wiki_options[:local_git_user] | OptionParser block | WIRED | bin/gollum:72-76 — `opts.on('--local-git-user', ...)` block sets `wiki_options[:local_git_user] = true` |

**Note on key_link pattern deviation:** The PLAN specified the git config pattern as `git config --get user\.name`. The implementation uses `git config --local --get user\.name`. This is a documented, intentional deviation (SUMMARY.md "Deviations" section) — the `--local` flag prevents global/system config bleed-through and is essential for test correctness. The semantic intent of the key link is fully satisfied.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| USER-01 | 02-01-PLAN.md | User can set wiki_options[:local_git_user] or pass --local-git-user CLI flag to use local git config's user.name/email as commit author | SATISFIED | CLI flag at bin/gollum:72; before filter injects author via session at app.rb:140-147; 6 integration tests assert correct author attribution |
| USER-02 | 02-01-PLAN.md | When local_git_user is active, git config is read fresh on each commit (not cached at startup) | SATISFIED | resolve_local_git_user runs on every non-GET request (no caching); test at line 42 validates fresh-read behavior with config change between requests |
| USER-03 | 02-01-PLAN.md | If git config user.name or user.email is empty/unset, gollum falls back gracefully with a warning rather than crashing | SATISFIED | resolve_local_git_user returns nil when either value is empty (app.rb:779-783); before filter only assigns if author is non-nil (:145); tests at lines 53 and 62 verify no crash; startup warning at bin/gollum:326 |

No orphaned requirements: REQUIREMENTS.md maps only USER-01, USER-02, USER-03 to Phase 2, and all three are claimed and satisfied in 02-01-PLAN.md.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| bin/gollum | 284 | `# TODO: Remove RACK_ENV fallback once gollum-7 is released` | Info | Pre-existing TODO unrelated to this phase, not introduced by this work |

No anti-patterns introduced by this phase. No stubs, placeholder returns, or empty handlers found in the three modified files.

### Human Verification Required

#### 1. Live web edit attribution

**Test:** Start gollum with `gollum --local-git-user /path/to/wiki-repo` where the repo has local git config set. Make a page edit through the browser.
**Expected:** The resulting commit (verified via `git log -1 --format='%an <%ae>'`) shows the local git config identity, not the Gollum default ('Anonymous <anon@anon.org>' or similar).
**Why human:** Requires a running Sinatra server + browser; not covered by automated rack/test integration.

#### 2. Startup message visual check

**Test:** Start gollum with `--local-git-user` flag both when git config is set and when it is unset.
**Expected:** stderr shows `Gollum running with local-git-user (currently: Name <email>)` or `Gollum running with local-git-user (WARNING: git config user.name/email not set -- will use Gollum defaults)`.
**Why human:** Startup message writes to stderr during server boot; verifying the exact text requires live execution.

### Gaps Summary

No gaps found. All 7 observable truths verified, all 3 artifacts exist and are substantive and wired, all 3 key links confirmed, all 3 requirements satisfied. The single deviation from the plan (adding `--local` to the git config command) is documented in SUMMARY.md and improves correctness by preventing global config bleed-through.

---

_Verified: 2026-04-03_
_Verifier: Claude (gsd-verifier)_
