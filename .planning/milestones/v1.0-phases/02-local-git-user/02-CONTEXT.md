# Phase 2: Local Git User - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Web edits attributed to the developer's local git identity (user.name / user.email) read fresh from git config on each commit. Includes CLI flag `--local-git-user`, config file support via `wiki_options[:local_git_user]`, graceful fallback when git config is empty, and startup confirmation. Config file is the primary interface; CLI flag is convenience (same pattern as Phase 1).

</domain>

<decisions>
## Implementation Decisions

### Author priority
- Session author (`session['gollum.author']` from rack middleware like OmniAuth) takes priority over local git user
- When session author overrides local git user, log a generic per-request message: "local_git_user overridden by session author" — no PII in logs
- Local git user is a fallback for when no auth middleware is present (typical local dev scenario)

### Missing git config fallback
- If git config user.name or user.email is unset/empty, warn and fall back to Gollum defaults — no crash, no blocked commit
- All-or-nothing: both user.name AND user.email must be set. If either is missing, fall back entirely to Gollum defaults
- Fallback warning logged once at startup, not on every commit: "local-git-user active but git config user.name/email not set"

### Injection strategy
- Inject local git user into `session['gollum.author']` in a `before` filter — covers all 6 commit paths (commit_options() and upload_file handler) with a single injection point
- Only resolve git user on write requests (POST/PUT/DELETE) — avoid unnecessary shell-outs on read-heavy GET traffic
- Use `git config --get user.name` / `git config --get user.email` with `-C` flag scoped to wiki repo path — respects full git config cascade (system > global > local)
- Use `Shellwords.escape` on repo path to prevent shell injection

### Startup feedback
- Show identity at boot: "Gollum running with local-git-user (currently: Neil Miller <neil@example.com>)"
- If git config is empty at boot, warn inline: "Gollum running with local-git-user (WARNING: git config user.name/email not set — will use Gollum defaults)"
- Similar pattern to Phase 1's startup message for branch tracking

### Claude's Discretion
- Exact method name for the git config resolution helper (e.g., `resolve_local_git_user`)
- Whether to combine both git config calls into a single helper or keep separate
- Log level for the session-override message (info vs debug)
- Exact placement of the before filter relative to Phase 1's existing before filter logic

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — USER-01 through USER-03 define acceptance criteria for this phase

### Architecture context
- `.planning/PROJECT.md` — Architecture context: wiki_options pattern, config file loading, commit author injection
- `.planning/research/ARCHITECTURE.md` §Feature 2: --local-git-user — Detailed integration point analysis, pseudocode for commit_options and upload_file patching
- `.planning/research/PITFALLS.md` §Pitfall 1 and §Pitfall 5 — Upload handler bypass risk and empty git config handling

### Existing code (integration points)
- `bin/gollum` — CLI entry point, OptionParser, wiki_options hash, config file loading, startup messages
- `lib/gollum/app.rb` — `commit_options()` at line 772, `upload_file` handler at line 276, `before` filter, `wiki_new()`, `validate_wiki_options!`

### Prior phase context
- `.planning/phases/01-branch-tracking/01-CONTEXT.md` — Phase 1 decisions: before filter pattern for detached HEAD toggle, cli_wiki_options snapshot, startup message pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `before` filter in app.rb: Phase 1 added detached HEAD logic here — local git user injection follows the same pattern
- `cli_wiki_options` snapshot (bin/gollum): Captures CLI-specified options before config file override — reuse for source attribution in validation
- `validate_wiki_options!` (app.rb): Phase 1's validation class method — can be extended if needed

### Established Patterns
- `session['gollum.author']` hash: `{ name: "...", email: "..." }` — local git user must produce the same shape
- `wiki_options[:key]` for all config — `wiki_options[:local_git_user]` follows convention
- OptionParser block for CLI flags — same registration pattern as `--track-current-branch`
- Startup messages printed in bin/gollum after config loading — same location for local-git-user confirmation

### Integration Points
- `before` filter: Inject local git user into session when `local_git_user` enabled, session author absent, and request is a write
- `commit_options()` (line 772): Already reads `session['gollum.author']` — no change needed if before filter injects correctly
- `upload_file` handler (line 301): Already reads `session['gollum.author']` — no change needed if before filter injects correctly
- `bin/gollum` startup block: Add confirmation message after config loading, similar to branch tracking message

</code_context>

<specifics>
## Specific Ideas

- The before filter approach mirrors Phase 1's pattern — inject once, all paths pick it up
- Per-request override logging (not per-startup) because session state can change between requests
- All-or-nothing for git config completeness avoids partial/confusing commit authorship
- Startup message pattern matches Phase 1: "Gollum running with local-git-user (currently: ...)"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-local-git-user*
*Context gathered: 2026-04-03*
