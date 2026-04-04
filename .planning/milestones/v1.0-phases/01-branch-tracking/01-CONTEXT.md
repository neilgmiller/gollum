# Phase 1: Branch Tracking - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Dynamic branch resolution from HEAD on each request when `track_current_branch` is enabled. Includes mutual exclusion against `--ref`, detached HEAD handling, and disabling edits on detached HEAD. Config file is the primary interface; CLI flag is convenience.

</domain>

<decisions>
## Implementation Decisions

### Detached HEAD behavior
- Serve the detached SHA — wiki keeps working, pinned to that commit
- Log a warning when detached HEAD is detected (e.g., "HEAD is detached, serving commit abc1234")
- Disable editing entirely when HEAD is detached (set allow_editing to false dynamically) — prevents dangling commits
- Re-enable editing automatically when HEAD reattaches to a branch
- This is in-scope for Phase 1, not deferred

### Mutual exclusion UX
- Short error message with fix suggestion: "Error: --ref and --track-current-branch are mutually exclusive. Use one or the other."
- Error message should mention the SOURCE of the conflict (CLI vs config file) — e.g., "--track-current-branch (CLI) conflicts with ref set in config file"
- Only an explicitly-set --ref triggers the conflict — the default ref value ('master') does NOT conflict with track-current-branch; it gets silently overridden

### Startup/runtime feedback
- Brief startup message confirming feature is active and showing current branch (e.g., "Gollum running with track-current-branch (currently on: main)")
- Per-request branch logging only in verbose/development mode — silent in production
- Detached HEAD warning logged when detected (see above)

### Claude's Discretion
- HEAD resolution mechanism (File.read vs git symbolic-ref vs other)
- Exact warning/log message wording
- How to dynamically toggle allow_editing based on HEAD state
- Where to place the validation logic (before/after config file load — though CONF-02 says after)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Branch tracking implementation
- `.planning/REQUIREMENTS.md` — BRANCH-01 through BRANCH-04 define the acceptance criteria
- `.planning/PROJECT.md` — Architecture context: wiki_new(), config file loading at bin/gollum:282-288, wiki_options pattern

### Existing code (integration points)
- `bin/gollum` — CLI entry point, OptionParser, wiki_options hash, config file loading (lines 282-288)
- `lib/gollum/app.rb` — `wiki_new()` at line 720 (creates Wiki with wiki_options), `commit_options()` at line 731

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `wiki_options` hash: All config flows through this — new option follows the same pattern
- `wiki_new()` method (app.rb:720): Creates `Gollum::Wiki.new(path, wiki_options)` per request — this is where HEAD resolution would inject the dynamic ref
- OptionParser block (bin/gollum:23-68): Established pattern for adding CLI flags

### Established Patterns
- Config options set as `wiki_options[:key]` in both CLI parsing and config file
- Config file loaded via `require` at bin/gollum:282-288, then wiki_options reloaded from app settings
- `settings.wiki_options` accessed in app.rb for runtime behavior

### Integration Points
- `wiki_new()` — must resolve HEAD and pass dynamic ref to `Gollum::Wiki.new`
- Config file loading block (bin/gollum:282-288) — validation must run AFTER this
- `allow_editing` in wiki_options — can be toggled dynamically based on HEAD state

</code_context>

<specifics>
## Specific Ideas

- Editing on detached HEAD is a footgun — user specifically flagged that commits shouldn't be allowed on detached HEAD to prevent dangling commits
- Error messages should mention the source of the conflict (CLI vs config file) to help users who forget what their config file sets

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-branch-tracking*
*Context gathered: 2026-04-03*
