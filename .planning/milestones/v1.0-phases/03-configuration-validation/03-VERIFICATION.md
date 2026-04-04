---
phase: 03-configuration-validation
verified: 2026-04-04T00:00:00Z
status: passed
score: 10/10 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 7/7
  gaps_closed:
    - "Config file local_git_user produces identical behavior to CLI flag — commit author uses local git config user.name/user.email (including global ~/.gitconfig)"
    - "Both features set via config file only — commits use local git user from global config"
  gaps_remaining: []
  regressions: []
---

# Phase 3: Configuration Validation Verification Report

**Phase Goal:** Both options work identically whether set via config file or CLI, and mutual exclusion catches conflicts from any source
**Verified:** 2026-04-04
**Status:** passed
**Re-verification:** Yes — after gap closure (03-02 fixed --local flag bug found in UAT)

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                                              | Status     | Evidence                                                                                                                          |
|----|------------------------------------------------------------------------------------------------------------------------------------|------------|-----------------------------------------------------------------------------------------------------------------------------------|
| 1  | Setting track_current_branch via config file produces identical runtime behavior to --track-current-branch CLI flag                | VERIFIED   | test_config_validation.rb: "config file track_current_branch sets wiki_options identically to CLI" asserts wiki_options[:track_current_branch] == true, GET /A returns 200 |
| 2  | Setting local_git_user via config file produces identical runtime behavior to --local-git-user CLI flag                           | VERIFIED   | test_config_validation.rb: "config file local_git_user sets wiki_options identically to CLI" asserts wiki_options[:local_git_user] == true |
| 3  | Global git config (~~/.gitconfig) is resolved when no repo-local config exists (UAT gap — now fixed)                              | VERIFIED   | test_local_git_user.rb line 128: "reads global git config when no repo-local config is set" — sets GIT_CONFIG_GLOBAL to temp file with Global User identity, asserts resolve_local_git_user returns {name: 'Global User', email: 'global@example.com'} |
| 4  | Startup diagnostic correctly reports git user identity from global config                                                         | VERIFIED   | bin/gollum lines 321-322: git config calls use `--get` (no `--local`), so they resolve through local -> global -> system; grep confirms zero --local occurrences in git config calls |
| 5  | Mutual exclusion catches CLI ref + config file track_current_branch conflict                                                       | VERIFIED   | test_config_validation.rb: "CLI ref conflicts with config file track_current_branch" asserts /mutually exclusive/, /CLI \(--ref\)/, /config file/ |
| 6  | Mutual exclusion catches config file ref + CLI track_current_branch conflict                                                       | VERIFIED   | test_config_validation.rb: "config file ref conflicts with CLI track_current_branch" asserts /mutually exclusive/, /config file/ for ref, /CLI \(--track-current-branch\)/ for tcb |
| 7  | Mutual exclusion catches config-only ref + track_current_branch conflict                                                           | VERIFIED   | test_config_validation.rb: "both ref and track_current_branch in config file conflict" asserts /mutually exclusive/ |
| 8  | Both features set via config file only work correctly together                                                                     | VERIFIED   | test_config_validation.rb: "both features via config file only work together" asserts both true, empty stderr from validate_wiki_options! |
| 9  | Startup summary shows active features with source attribution in development mode                                                  | VERIFIED   | bin/gollum lines 330-342 contain startup summary block; "Active features:" present; development mode gate at line 331; tested by test_config_validation.rb |
| 10 | No regressions introduced by --local flag removal                                                                                  | VERIFIED   | Full suite: 201 tests, 582 assertions, 0 failures, 0 errors, 0 skips (one more test than previous 200 — the new regression test) |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact                          | Expected                                                              | Status   | Details                                                                                                       |
|-----------------------------------|-----------------------------------------------------------------------|----------|---------------------------------------------------------------------------------------------------------------|
| `test/test_config_validation.rb`  | Config file parity and cross-source conflict tests                    | VERIFIED | 280 lines, 12 tests, 35 assertions — all pass                                                                 |
| `bin/gollum`                      | Startup diagnostic git config calls without --local flag              | VERIFIED | Lines 321-322: `config --get user.name` / `config --get user.email` — no `--local` flag present              |
| `lib/gollum/app.rb`               | resolve_local_git_user without --local flag                           | VERIFIED | Lines 777-778: `config --get user.name` / `config --get user.email` — no `--local` flag present              |
| `test/test_local_git_user.rb`     | Regression test proving global-only git config is resolved            | VERIFIED | 169 lines; line 128: "reads global git config when no repo-local config is set"; uses GIT_CONFIG_GLOBAL isolation; 11 tests, 17 assertions — all pass |

### Key Link Verification

| From                             | To                               | Via                                               | Status   | Details                                                                                                         |
|----------------------------------|----------------------------------|---------------------------------------------------|----------|-----------------------------------------------------------------------------------------------------------------|
| `test/test_config_validation.rb` | `lib/gollum/app.rb`              | `validate_wiki_options!` calls                    | WIRED    | 7 call sites (lines 57, 69, 124, 138, 153, 164, 175) with real assertions on return values                     |
| `test/test_config_validation.rb` | `bin/gollum` config loading      | `simulate_config_load` helper                     | WIRED    | `load config_file` at lines 91 and 197; mirrors bin/gollum flow exactly                                        |
| `bin/gollum` startup summary     | `Precious::App.environment`      | development mode check                            | WIRED    | Line 331: `if Precious::App.environment == :development`                                                        |
| `lib/gollum/app.rb`              | `git config`                     | backtick shell call, normal resolution order      | WIRED    | Lines 777-778: `git -C #{path} config --get user.name/email` — no --local, git follows local->global->system   |
| `bin/gollum`                     | `git config`                     | backtick shell call, normal resolution order      | WIRED    | Lines 321-322: `git -C #{...} config --get user.name/email` — no --local, git follows local->global->system    |
| `test/test_local_git_user.rb`    | `resolve_local_git_user`         | `app_instance.send(:resolve_local_git_user)`      | WIRED    | Line 143: direct call with GIT_CONFIG_GLOBAL pointing to temp file containing Global User identity              |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                                               | Status    | Evidence                                                                                                                       |
|-------------|-------------|---------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------------------------|
| CONF-01     | 03-01-PLAN, 03-02-PLAN | Both options work identically whether set via config file or CLI flags                                     | SATISFIED | 4 config file parity tests in test_config_validation.rb; resolve_local_git_user now reads global config via --get (no --local); regression test in test_local_git_user.rb proves global resolution |
| CONF-02     | 03-01-PLAN  | Mutual exclusion validation runs after config file loading, not just after CLI parsing                                    | SATISFIED | 5 cross-source conflict tests in test_config_validation.rb cover all source combinations; validate_wiki_options! called with post-config-load wiki_options |

No orphaned requirements: REQUIREMENTS.md maps exactly CONF-01 and CONF-02 to Phase 3. Both claimed across 03-01-PLAN and 03-02-PLAN, both verified above.

### Anti-Patterns Found

| File         | Line | Pattern | Severity | Impact                                                                    |
|--------------|------|---------|----------|---------------------------------------------------------------------------|
| `bin/gollum` | 284  | TODO: Remove RACK_ENV fallback once gollum-7 is released | Info | Pre-existing, unrelated to phase 03; no action needed |

No TODO/FIXME/placeholder comments in phase 03 modified code paths. No stub implementations or empty handlers.

### Human Verification Required

None. The UAT gaps have been resolved by code changes (removing `--local` flag) with a regression test that programmatically proves global config is resolved. All behaviors are verified by unit assertions. The startup warning message change (now showing the correct identity from global config instead of the false "not set" warning) is a direct consequence of the code fix and confirmed by the test.

### Commits

All documented commits verified to exist in repository history:

**03-01 commits (unchanged from initial verification):**
- `de8b5a15` — test(03-01): add config validation test suite
- `a895ab60` — feat(03-01): add startup summary with source attribution in bin/gollum

**03-02 gap closure commits:**
- `955ca589` — fix(03-02): remove --local flag from git config calls
- `73ffab34` — test(03-02): add regression test for global git config resolution

### Test Results

- `ruby -Ilib -Itest test/test_local_git_user.rb`: 11 tests, 17 assertions, 0 failures, 0 errors, 0 skips
- `ruby -Ilib -Itest test/test_config_validation.rb`: 12 tests, 35 assertions, 0 failures, 0 errors, 0 skips
- `rake test` (full suite): 201 tests, 582 assertions, 0 failures, 0 errors, 0 skips

### Gap Closure Summary

The previous VERIFICATION.md was `passed` based on unit tests alone. UAT (03-UAT.md) then found 2 issues in tests 2 and 3:

- **Root cause:** `--local` flag on `git config` calls in `lib/gollum/app.rb:777-778` and `bin/gollum:321-322` restricted git config lookup to repo-level `.git/config` only, ignoring `~/.gitconfig` (global). Most users set `user.name`/`user.email` globally, not per-repo.
- **Fix (03-02):** Removed `--local` from all four git config invocations. Git now follows its normal resolution order: repo-local -> global -> system. The `-C` flag still scopes repo context correctly for the local config layer.
- **Regression protection:** Two existing tests that assumed repo-local-only lookup were updated to use `GIT_CONFIG_GLOBAL` env var pointing to an empty temp file (so they still test the fallback path without leaking the developer's real `~/.gitconfig`). A new regression test proves that global-only config IS resolved.

All 10 observable truths verified. Phase goal achieved.

---

_Verified: 2026-04-04_
_Verifier: Claude (gsd-verifier)_
