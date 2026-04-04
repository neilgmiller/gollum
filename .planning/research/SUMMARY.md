# Project Research Summary

**Project:** Gollum CLI Enhancements — Branch Tracking + Local Git User
**Domain:** CLI feature additions to a git-backed Sinatra wiki
**Researched:** 2026-04-02
**Confidence:** HIGH

## Executive Summary

This project adds two independent, low-complexity CLI flags to an existing Ruby/Sinatra wiki application. Both features are well-defined, scope-limited, and fit naturally into Gollum's established patterns: all configuration flows through the `wiki_options` hash from `bin/gollum` (OptionParser) into `Precious::App` (Sinatra), and both features hook into exactly two existing methods (`wiki_new` and `commit_options`) that are already the canonical integration points for branch and author configuration. No new dependencies are needed. The entire implementation is approximately 45 lines of new Ruby code.

The recommended approach is sequential: implement `--track-current-branch` first (single integration point in `wiki_new`, easiest to verify visually by switching branches), then `--local-git-user` (two integration points: `commit_options` and the `upload_file` handler). The two features are independent — they can be toggled together or separately — and should be validated together in a final integration phase to catch edge cases like interaction with config file loading order.

The key risks are subtle concurrency and coverage issues rather than design complexity. Mutating the shared `settings.wiki_options` hash directly would create thread-safety bugs; the fix is to use `Hash#merge` for a per-request copy in `wiki_new`. The `upload_file` handler has its own inline author injection path that bypasses `commit_options`, meaning a naive implementation of `--local-git-user` would silently apply the wrong author to file uploads. Both risks have clear, documented preventions. The race condition between a user editing a page and a developer switching branches is a known, accepted limitation of the per-request resolution design and should be documented, not engineered around.

## Key Findings

### Recommended Stack

Both features are implementable using only the existing Gollum stack with Ruby stdlib. No gems need to be added or upgraded.

**Core technologies:**
- **Ruby stdlib (`File.read`, backtick operator):** HEAD resolution and git config shelling — zero-dependency, sufficient for both tasks
- **OptionParser (stdlib):** CLI flag registration — already used by every flag in `bin/gollum`, new flags follow identical pattern
- **gollum-lib 6.1.0:** Accepts `:ref` in `Wiki.new` options for branch selection; accepts `:name`/`:email` in commit options for author attribution — no version upgrade needed
- **Shellwords (stdlib):** Required for safely escaping the repo path when shelling out to `git config -C <path>`

For HEAD resolution, reading `.git/HEAD` directly via `File.read` is preferred over shelling out to `git symbolic-ref HEAD` — it is ~50x faster (~0.1ms vs ~5-10ms) and called on every HTTP request. For git user resolution, shelling out to `git config user.name` (per commit) is preferred over parsing gitconfig files manually, because `git config` handles the full cascade (system, global, local, conditional includes) correctly.

### Expected Features

**Must have (table stakes):**
- `--track-current-branch` resolves HEAD per request — the entire purpose of the flag
- `--ref` and `--track-current-branch` mutual exclusion with a clear error at startup — conflicting intents must be caught
- `--local-git-user` reads `user.name` and `user.email` fresh from git config per commit — not cached at startup
- Both flags work independently of each other — different use cases, no coupling
- Config file support (`wiki_options[:track_current_branch]` / `wiki_options[:local_git_user]`) — follows Gollum's existing convention
- Graceful fallback when git config user is absent — fall through to existing behavior, do not crash
- Warn at startup if `--track-current-branch` is combined with `--bare` — the feature is meaningless for bare repos

**Should have (competitive):**
- Startup validation warnings (branch being tracked, missing git user at boot) — aids debugging misconfiguration
- Session author takes priority over `--local-git-user` — correct layering when auth middleware (OmniAuth, omnigollum) is present

**Defer (v2+):**
- UI indicator showing current branch in the web interface — nice-to-have, explicitly out of MVP scope per PROJECT.md
- Integration tests with omnigollum — out of scope per PROJECT.md constraints

### Architecture Approach

Both features hook into the `wiki_options` hash pipeline without requiring new configuration mechanisms. `--track-current-branch` adds one private method (`resolve_current_branch`) and modifies `wiki_new` to call it when the flag is set, using `Hash#merge` to produce a per-request copy of the options hash rather than mutating shared state. `--local-git-user` adds one private method (`resolve_local_git_user`) and modifies two author-injection paths: `commit_options` (used by rename, edit, delete, create, revert) and the `upload_file` handler's inline session read.

**Major components and touch points:**
1. **`bin/gollum` (OptionParser)** — register both CLI flags; add mutual exclusion validation after both `opts.parse!` AND config file load
2. **`wiki_new()` in `app.rb` (line 720)** — per-request Wiki instantiation; add HEAD resolution here for `--track-current-branch`
3. **`commit_options()` in `app.rb` (line 731)** — shared commit hash builder; add git user injection here for `--local-git-user`
4. **`upload_file` handler in `app.rb` (line 279)** — standalone author merge; must ALSO add git user injection here (bypasses `commit_options`)

### Critical Pitfalls

1. **Upload handler bypasses `commit_options`** — `post '/upload_file'` reads `session['gollum.author']` directly instead of calling `commit_options()`. Implementing `--local-git-user` only in `commit_options` will silently leave uploads with wrong/empty author. Fix: modify both paths, or inject into session in a `before` filter.

2. **Mutating shared `settings.wiki_options`** — `settings.wiki_options` is shared across all concurrent requests. Assigning `settings.wiki_options[:ref] = resolved_branch` directly is thread-unsafe. Fix: use `opts = settings.wiki_options.merge(ref: branch)` in `wiki_new` to create a per-request copy.

3. **Detached HEAD breaks branch resolution** — `.git/HEAD` contains a raw SHA when HEAD is detached (after `git checkout <sha>` or during rebase). Passing a raw SHA as `:ref` to gollum-lib may produce undefined behavior. Fix: detect detached state explicitly and either error with a clear message or fall back to the configured default ref.

4. **Mutual exclusion validated too early** — If validation of `--track-current-branch` vs `--ref` runs only after `opts.parse!` but before config file loading, a config file that sets `:ref` will silently conflict. Fix: run mutual exclusion validation after the config file is loaded (line 289 in `bin/gollum`, where config file settings are re-read into `wiki_options`).

5. **Shell injection via unescaped repo path** — `git config -C <path>` without escaping will fail or behave incorrectly for repo paths containing spaces or special characters. Fix: use `Shellwords.escape(settings.gollum_path)` in the `resolve_local_git_user` method.

## Implications for Roadmap

Based on research, the two features map cleanly to two implementation phases plus a combined validation phase. All three phases have well-documented patterns and do not require additional research.

### Phase 1: --track-current-branch
**Rationale:** Single integration point (`wiki_new`), no author-handling complexity, easiest to verify visually. Sets the pattern for the second flag's implementation. Lower risk — bugs are visible (wrong content served) rather than silent (wrong git author).
**Delivers:** Dynamic branch tracking; wiki content follows `git checkout` without restarting Gollum.
**Addresses:** All `--track-current-branch` table stakes features from FEATURES.md.
**Avoids:** Pitfall 2 (detached HEAD — detect and error), Pitfall 7 (shared mutable state — use `Hash#merge` in `wiki_new`).
**Implementation touchpoints:** `bin/gollum` (flag + initial mutual exclusion check), `app.rb` `wiki_new` (HEAD resolution call), new `resolve_current_branch` private method.

### Phase 2: --local-git-user
**Rationale:** Slightly more complex due to two author injection paths. Must be implemented after Phase 1 to establish the overall code pattern, but has no dependency on Phase 1's code.
**Delivers:** Git commits made via web UI are attributed to the developer's configured git identity (`user.name` / `user.email`), matching terminal commits.
**Addresses:** All `--local-git-user` table stakes features and the session-author-priority differentiator from FEATURES.md.
**Avoids:** Pitfall 1 (upload handler — must modify both `commit_options` and `upload_file` handler), Pitfall 5 (empty/missing git config — validate non-empty, fall through gracefully), Pitfall 4 (shell injection — use `Shellwords.escape`).

### Phase 3: Integration and Validation
**Rationale:** Config file interaction and cross-flag scenarios require both features to be in place. Mutual exclusion validation must run after config file loading, which is only testable once both flags exist.
**Delivers:** Correct behavior for edge cases: both flags active together, config file conflict with `--ref`, `--bare` with `--track-current-branch`, empty git config environment.
**Avoids:** Pitfall 6 (config file override of mutual exclusion check), Pitfall 3 (race condition — document as accepted limitation, do not over-engineer).
**Test matrix:** `--track-current-branch` + `--ref` = error; `--track-current-branch` + `--bare` = warning/error; `--local-git-user` + session author = session wins; config file sets `:ref` + `--track-current-branch` = error; upload file with `--local-git-user` = correct author in git log.

### Phase Ordering Rationale

- Phase 1 before Phase 2 because single-integration-point features should establish the code pattern before multi-integration-point features follow it.
- Phase 3 requires both flags to exist in order to test cross-flag and config-file interactions.
- No external dependencies block any phase — all work is within `bin/gollum` and `lib/gollum/app.rb`.

### Research Flags

Phases with standard patterns (skip research-phase):
- **Phase 1:** Well-documented, single integration point, pattern directly visible in existing code (`--ref` flag in `bin/gollum`, `wiki_new` in `app.rb`).
- **Phase 2:** Both integration points identified and confirmed via code analysis. The `upload_file` handler bypass is a known pitfall with a clear fix.
- **Phase 3:** Validation logic follows existing OptionParser and config-load patterns.

No phase requires additional research before implementation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All findings from direct analysis of Gemfile.lock, `bin/gollum`, and `app.rb`. No external sources needed — the stack is fixed by the existing codebase. |
| Features | HIGH | Derived from PROJECT.md requirements + direct code reading of the existing `--ref` and session author patterns. Comparison with GitBook/Wiki.js is MEDIUM but irrelevant to implementation. |
| Architecture | HIGH | Integration points confirmed by reading exact line numbers in `bin/gollum` and `app.rb`. Both methods (`wiki_new`, `commit_options`) and the `upload_file` handler have been verified. |
| Pitfalls | HIGH | All critical pitfalls identified from direct code analysis. Concurrency pitfall (Pitfall 3/7) verified by reading Sinatra `settings` behavior. Upload handler bypass (Pitfall 1) confirmed by tracing all 6 commit paths. |

**Overall confidence:** HIGH

### Gaps to Address

- **`.git` file (worktree/submodule layout):** `.git` may be a file containing `gitdir: /path/to/actual/git/dir` rather than a directory. `File.read('.git/HEAD')` would read the gitdir pointer, not HEAD. This is documented as an accepted v1 limitation in STACK.md. If worktree support is needed, use `git rev-parse --git-dir` instead.
- **Bare repo + `--track-current-branch` behavior:** The correct response (error vs. warning vs. silent no-op) is not specified in PROJECT.md. Decide during Phase 1 implementation. Recommendation: error with clear message, as the feature is semantically undefined for bare repos.
- **`--local-git-user` + session author precedence in `upload_file`:** The `upload_file` handler's direct session read already ensures session wins when set. The gap is documenting this behavior. No code ambiguity.

## Sources

### Primary (HIGH confidence)

- `bin/gollum` (local) — CLI flag registration patterns, OptionParser usage, config file load sequence, mutual exclusion validation placement
- `lib/gollum/app.rb` (local) — `wiki_new` (line 720), `commit_options` (line 731), `upload_file` author merge (line 279), `before` filter (line 115), all 6 commit paths
- `Gemfile.lock` (local) — confirms gollum-lib 6.1.0, rjgit adapter (not rugged)
- `.planning/PROJECT.md` (local) — requirements, design decisions, accepted trade-offs
- `.planning/codebase/ARCHITECTURE.md` (local) — existing architecture analysis

### Secondary (MEDIUM confidence)

- `gitrepository-layout(5)` and `git-config(1)` man pages (training data) — `.git/HEAD` format, `git config` cascade behavior; extremely stable git internals, high practical confidence
- GitBook, Wiki.js, GitHub/GitLab wiki architectures (training data) — used only for competitive context in FEATURES.md; not load-bearing for implementation decisions

---
*Research completed: 2026-04-02*
*Ready for roadmap: yes*
