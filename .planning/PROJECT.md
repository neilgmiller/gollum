# Gollum Configuration Enhancements: Branch Tracking & Local Git User

## What This Is

Two new independent configuration options for Gollum wiki, usable both as CLI flags and as `wiki_options` keys in the config file (`-c config.rb`). `track_current_branch` dynamically serves pages from whatever branch is currently checked out (resolving HEAD on each request). `local_git_user` uses the local git config's user.name/user.email as the commit author for web edits (read on each commit). The config file is the primary interface — CLI flags are a convenience layer on top.

## Core Value

The wiki should seamlessly follow the developer's local git workflow — serving the branch they're working on and attributing edits to them — without manual reconfiguration.

## Requirements

### Validated

<!-- Existing capabilities inferred from codebase -->

- ✓ CLI option parsing via OptionParser with server and wiki option hashes — existing
- ✓ `-r, --ref [REF]` flag to serve a fixed branch (default: master) — existing
- ✓ Commit author injection via `session['gollum.author']` from rack middleware — existing
- ✓ Config file support via `require`d Ruby file that can modify wiki_options — existing
- ✓ Wiki instance created per-request via `wiki_new()` — existing
- ✓ `wiki_options[:track_current_branch]` config option that resolves HEAD on each request — Validated in Phase 01: branch-tracking
- ✓ `--track-current-branch` CLI flag exposed for convenience — Validated in Phase 01: branch-tracking
- ✓ `track_current_branch` and `ref` are mutually exclusive with clear error message — Validated in Phase 01: branch-tracking
- ✓ Detached HEAD served as read-only (editing disabled) — Validated in Phase 01: branch-tracking
- ✓ `wiki_options[:local_git_user]` config option that reads git config user.name and user.email on each commit — Validated in Phase 02: local-git-user
- ✓ `--local-git-user` CLI flag exposed for convenience — Validated in Phase 02: local-git-user
- ✓ Both options work independently (can use either or both) — Validated in Phase 02: local-git-user
- ✓ Config file settings produce identical behavior to CLI flags for both features — Validated in Phase 03: configuration-validation
- ✓ Mutual exclusion catches conflicts from any source (CLI, config, or mixed) — Validated in Phase 03: configuration-validation
- ✓ Verbose startup summary shows active features with source attribution — Validated in Phase 03: configuration-validation

### Active

*All requirements validated — no active requirements remaining.*

### Out of Scope

- Background polling/watching for branch changes — resolve on each request is sufficient
- Reading git user at startup and caching — always read fresh on each commit
- Bundling both features into a single flag — they serve different purposes
- New web UI elements for these features — CLI/config only

## Context

- Gollum is a Sinatra-based wiki backed by git, using gollum-lib for core operations
- **Config file** (`-c config.rb`): Ruby file `require`d after `Precious::App.set(:wiki_options, ...)` at `bin/gollum:282-288`. It can read/modify `Precious::App.settings.wiki_options` freely. This is the primary way power users configure Gollum, and the primary interface for these new options. Example:
  ```ruby
  # config.rb
  Precious::App.settings.wiki_options[:track_current_branch] = true
  Precious::App.settings.wiki_options[:local_git_user] = true
  ```
- CLI entry point: `bin/gollum` — OptionParser defines flags, stores in `wiki_options` hash. CLI flags are a convenience wrapper that set the same `wiki_options` keys.
- App: `lib/gollum/app.rb` — `wiki_new()` creates `Gollum::Wiki.new(path, wiki_options)` per request
- Branch ref: `wiki_options[:ref]` passed to gollum-lib, used in `wiki.ref` throughout app
- Author: `commit_options()` method merges `session['gollum.author']` into commit params
- Validation must run **after** config file loading since the config file can set these options too

## Constraints

- **Compatibility**: Must not break existing `-r, --ref` behavior when new flags aren't used
- **Architecture**: Use existing wiki_options hash pattern — no new configuration mechanisms
- **Dependencies**: No new gem dependencies — use Ruby's built-in git config reading or shell out to `git config`
- **Upstream**: Changes are on a feature branch, not targeting upstream merge

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Resolve HEAD per-request, not poll | Simple, always correct, no background threads | ✓ Implemented |
| Read git user per-commit, not cached | Picks up config changes without restart | ✓ Implemented |
| Error on --ref + --track-current-branch | Mutually exclusive by design, clear over clever | ✓ Implemented |
| Independent flags, not bundled | Different use cases, composable | ✓ Implemented |
| Flag names: --track-current-branch, --local-git-user | User-specified naming preference | ✓ Implemented |
| Remove --local from git config calls | Users set identity in ~/.gitconfig (global), not per-repo | ✓ Fixed in gap closure 03-02 |

---
*Last updated: 2026-04-04 after v1.0 milestone*
