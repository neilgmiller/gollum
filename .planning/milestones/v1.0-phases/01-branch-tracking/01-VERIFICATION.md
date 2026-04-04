---
phase: 01-branch-tracking
verified: 2026-04-03T15:10:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 01: Branch Tracking Verification Report

**Phase Goal:** Add `--track-current-branch` CLI flag with mutual exclusion validation, per-request HEAD resolution, detached-HEAD editing toggle, and startup confirmation.
**Verified:** 2026-04-03T15:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

All must-haves from both plan frontmatter blocks were evaluated.

**From Plan 01-01 (BRANCH-01, BRANCH-03):**

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | CLI flag `--track-current-branch` sets `wiki_options[:track_current_branch]` to true | VERIFIED | `bin/gollum` line 66-70: `opts.on('--track-current-branch', ...) { wiki_options[:track_current_branch] = true }` |
| 2  | Config file can set `wiki_options[:track_current_branch] = true` with same effect | VERIFIED | Validation reads from `wiki_options` after config reload at line 295; `cli_wiki_options` snapshot taken at line 287 before config load |
| 3  | Passing `--ref X` and `--track-current-branch` together causes exit with error | VERIFIED | `app.rb` line 88-97: `validate_wiki_options!` checks `wiki_options.key?(:ref)` and calls `Kernel.exit(1)` with error to `$stderr` |
| 4  | Default ref (no `--ref` passed) does NOT conflict with `--track-current-branch` | VERIFIED | Check is `wiki_options.key?(:ref)` (presence, not value); no `:ref` key means no conflict — test confirms this at test line 60-68 |
| 5  | Error message identifies source of each conflicting option (CLI vs config file) | VERIFIED | `app.rb` lines 90-94: `ref_source` and `tcb_source` computed from `cli_wiki_options` snapshot; messages include "CLI (--ref)" or "config file" |

**From Plan 01-02 (BRANCH-02, BRANCH-04):**

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 6  | When `track_current_branch` is enabled, wiki serves pages from whatever branch HEAD points to | VERIFIED | `app.rb` `wiki_new` lines 742-749: reads HEAD, merges `ref:` via `Hash#merge`, passes to `Gollum::Wiki.new` |
| 7  | Switching branches with `git checkout` changes which pages are served on next request | VERIFIED | `wiki_new` calls `resolve_current_branch` on every invocation (no caching); "follows branch switch" test confirms at test line 138-145 |
| 8  | Detached HEAD serves the detached SHA content | VERIFIED | `resolve_current_branch` returns `{ ref: head_content, detached: true }` when HEAD is not a `ref: refs/heads/` pointer; `wiki_new` passes that SHA as ref |
| 9  | Detached HEAD disables editing (POST returns 403) | VERIFIED | `before` filter lines 131-137: `resolved[:detached]` sets `@allow_editing = false`; line 178: `forbid unless @allow_editing || GET`; test confirms 403 at test line 184-185 |
| 10 | Re-attaching HEAD to a branch re-enables editing | VERIFIED | `@allow_editing` is recalculated on every request from current HEAD state; re-attach test confirms 303 at test line 196-198 |
| 11 | Startup message printed to stderr when `track_current_branch` is active | VERIFIED | `bin/gollum` lines 300-312: reads `.git/HEAD`, emits `"Gollum running with track-current-branch (currently on: #{current})"` to `$stderr` before server launch |

**Score: 11/11 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bin/gollum` | CLI flag registration, mutual exclusion validation, startup message | VERIFIED | Lines 66-70 (flag), 287 (snapshot), 289-298 (config load + validation call), 300-312 (startup message) |
| `lib/gollum/app.rb` | `validate_wiki_options!`, `resolve_current_branch`, modified `wiki_new`, modified `before` filter | VERIFIED | Lines 88-97 (validate), 128-137 (before), 742-763 (wiki_new + resolve_current_branch) |
| `test/test_branch_tracking.rb` | Tests for flag, mutual exclusion, HEAD resolution, detached HEAD editing | VERIFIED | 14 tests across 4 contexts; 30 assertions; 0 failures |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bin/gollum` (OptionParser) | `Precious::App.wiki_options` | `wiki_options[:track_current_branch] = true` in option block | WIRED | Line 69 sets value; line 285 passes to `App.set(:wiki_options, wiki_options)` |
| `bin/gollum` | `Precious::App.validate_wiki_options!` | Call after config file loading | WIRED | `cli_wiki_options` snapshot at line 287; `validate_wiki_options!` called at line 298 — after config reload at line 295 |
| `lib/gollum/app.rb` (`before` filter) | `resolve_current_branch` | Method call inside `track_current_branch` guard | WIRED | Lines 131-137: guard present, method called, result consumed to set `@allow_editing` |
| `lib/gollum/app.rb` (`wiki_new`) | `settings.wiki_options.merge(ref: resolved)` | `Hash#merge` for thread-safe ref injection | WIRED | Line 746: `opts = opts.merge(ref: resolved[:ref])` — new hash, no mutation of `settings.wiki_options` |
| `bin/gollum` | `$stderr.puts` (startup confirmation) | Conditional block before server launch | WIRED | Lines 300-312: guard on `wiki_options[:track_current_branch]`, reads `.git/HEAD`, emits to `$stderr` |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BRANCH-01 | 01-01 | CLI flag or config file sets `track_current_branch`; wiki serves currently checked-out branch | SATISFIED | Flag registered in OptionParser; config-file path tested via `validate_wiki_options!` receiving post-reload `wiki_options` |
| BRANCH-02 | 01-02 | Served branch resolves from HEAD on each request (no caching) | SATISFIED | `wiki_new` calls `resolve_current_branch` on every invocation; `File.read` called fresh each time |
| BRANCH-03 | 01-01 | Both `ref` and `track_current_branch` set causes exit with clear mutual-exclusion error | SATISFIED | `validate_wiki_options!` runs after config merge; error message names each option's source; `Kernel.exit(1)` |
| BRANCH-04 | 01-02 | Detached HEAD handled gracefully — falls back to detached SHA | SATISFIED | `resolve_current_branch` returns SHA when HEAD is not a branch ref; `wiki_new` uses that SHA; editing disabled via `@allow_editing = false` |

No orphaned requirements — all four BRANCH requirements for Phase 1 are claimed by plans and verified in code.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `bin/gollum` | 303 | `rescue nil` silences read error on `.git/HEAD` during startup message | Info | Startup message omitted if read fails; server still launches normally — acceptable fallback |

No blocker or warning anti-patterns found. The single `rescue nil` is in the startup message display path only, not in the request-handling path.

---

### Human Verification Required

None. All goal-critical behaviors are verifiable programmatically via tests and code inspection.

Items that could benefit from manual confirmation (not blocking):

1. **Test: `--track-current-branch` flag appears in `--help` output**
   Test: run `gollum --help`
   Expected: flag listed with its description text
   Why human: `--help` is a display concern not covered by automated tests

2. **Test: Startup message is visible in real terminal**
   Test: launch gollum with `--track-current-branch` in a git repo
   Expected: `Gollum running with track-current-branch (currently on: <branch>)` printed before server starts
   Why human: `$stderr` in bin/gollum is not covered by the test suite

---

### Gaps Summary

No gaps. All 11 observable truths verified, all 4 requirement IDs satisfied, all key links wired, and the test suite passes (14 tests, 30 assertions, 0 failures, 0 errors, 0 skips).

---

_Verified: 2026-04-03T15:10:00Z_
_Verifier: Claude (gsd-verifier)_
