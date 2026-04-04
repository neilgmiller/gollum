# Phase 3: Configuration Validation - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Ensure both `track_current_branch` and `local_git_user` work identically whether set via config file (`wiki_options[:key]`) or CLI flags (`--track-current-branch`, `--local-git-user`). Mutual exclusion validation must catch conflicts from any source (CLI, config file, or cross-source). Scope is limited to these two features — no new validation rules or expanded option checking.

</domain>

<decisions>
## Implementation Decisions

### Validation completeness
- Keep validation focused on the two features we built (track_current_branch and local_git_user) — no expanded scope
- CONF-02: The existing `validate_wiki_options!` already runs after config file loading. Phase 3 tests that this works correctly rather than rebuilding the logic
- No defensive validation (unknown keys, typo detection, type checking) — beyond CONF-01/CONF-02 scope

### Config file edge cases
- Use `cli_wiki_options` snapshot to detect cross-source conflicts (CLI flag vs config file setting) — this mechanism already exists from Phase 1
- Test that config-only conflicts (both ref and track_current_branch set in config.rb, no CLI) are caught by existing validation
- Config file overrides of CLI flags are acceptable as long as mutual exclusion is enforced

### Test strategy
- Use real config file loading (write temp .rb files, require them, reload wiki_options) to prove the actual mechanism works end-to-end
- Feature parity matrix: for each feature, test that setting via config.rb produces same runtime behavior as the equivalent CLI flag
- Test both features set together via config.rb (no CLI flags)
- No simulation/mocking of config file loading — test the real code path

### Startup summary
- Add a verbose-mode-only startup summary showing active features and their source
- Format: "track-current-branch: ON (config file), local-git-user: ON (CLI)" — include source attribution
- Only prints in verbose/debug mode — silent in production and when no features are active
- Complements existing per-feature startup messages (those remain as-is)

### Claude's Discretion
- How to detect verbose mode in bin/gollum (environment variable, flag, or Sinatra setting)
- Exact placement of startup summary relative to existing feature startup messages
- Whether to use a single summary line or multiple lines for clarity
- Test file organization (single test file or split by concern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — CONF-01 and CONF-02 define acceptance criteria for this phase

### Architecture context
- `.planning/PROJECT.md` — Config file loading at bin/gollum:282-288, wiki_options pattern, cli_wiki_options snapshot
- `bin/gollum` lines 282-328 — Config file require, wiki_options reload, validate_wiki_options! call, existing startup messages
- `lib/gollum/app.rb` lines 87-98 — validate_wiki_options! implementation with source attribution

### Prior phase context
- `.planning/phases/01-branch-tracking/01-CONTEXT.md` — cli_wiki_options snapshot pattern, validate_wiki_options! design, mutual exclusion UX decisions
- `.planning/phases/02-local-git-user/02-CONTEXT.md` — Session injection pattern, startup message pattern

### Existing tests
- `test/test_branch_tracking.rb` — Existing validate_wiki_options! unit tests (5 test cases for ref vs track_current_branch)
- `test/test_local_git_user.rb` — Existing local git user tests (10 test cases)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `validate_wiki_options!(wiki_options, cli_wiki_options)` (app.rb:89): Already validates ref vs track_current_branch with source attribution — extend or test as-is
- `cli_wiki_options = wiki_options.dup` (bin/gollum:293): Snapshot of CLI-only options before config file merge — key for source detection
- Config file loading block (bin/gollum:295-301): The actual require + reload mechanism that must be tested

### Established Patterns
- Config file loaded via `require cfg` then `wiki_options = Precious::App.wiki_options` reload
- `cli_wiki_options` compared to post-merge `wiki_options` to determine source
- Startup messages printed to `$stderr` after config loading, before server start

### Integration Points
- `bin/gollum:304` — validate_wiki_options! call (the critical post-config-load validation point)
- `bin/gollum:306-328` — Existing per-feature startup messages (new summary would live near here)
- `Precious::App.settings.wiki_options` — The merged options hash that config file modifies

</code_context>

<specifics>
## Specific Ideas

- This phase is primarily about testing and proving correctness rather than building new features — most code already works
- The startup summary in verbose mode is the one new user-facing feature (with source attribution per feature)
- Real config file loading in tests is essential — simulating it would miss the exact code path that CONF-01/CONF-02 care about

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-configuration-validation*
*Context gathered: 2026-04-03*
