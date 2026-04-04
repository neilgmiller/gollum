# Feature Landscape

**Domain:** Git-backed wiki CLI enhancements (branch tracking + local user attribution)
**Researched:** 2026-04-02

## Table Stakes

Features users expect when these flags exist. Missing = feature feels broken or incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `--track-current-branch` resolves HEAD per request | The entire purpose of the flag; user switches branches and wiki follows | Low | Read `HEAD` symref, extract branch name, pass as `:ref` |
| `--ref` and `--track-current-branch` mutual exclusion | Conflicting intent -- one says "pin to X", the other says "follow HEAD" | Low | Validate at parse time, `abort` with clear message |
| `--local-git-user` reads `user.name` and `user.email` from local git config | The entire purpose of the flag; wiki edits attributed to the local developer | Low | Shell out to `git config user.name` / `git config user.email` or read `.git/config` |
| Fresh read on each operation (not cached at startup) | Users change branches and git config without restarting Gollum; stale data defeats the purpose | Low | Branch: resolve per request. User: resolve per commit. No caching. |
| Both flags work independently | Different use cases -- a team wiki may want branch tracking without overriding author; a solo dev may want local user without branch tracking | Low | Independent `wiki_options` keys, no coupling |
| Config file support (`wiki_options` hash) | Gollum's existing pattern -- every CLI flag has a `wiki_options` equivalent for `config.rb` | Low | `wiki_options[:track_current_branch]` and `wiki_options[:local_git_user]` |
| Graceful fallback when git config user is absent | `git config user.name` can be unset; should not crash the wiki | Low | Fall back to existing behavior (session author or Gollum defaults) with a warning |
| Works with bare repos (when applicable) | Gollum supports `--bare`; `--track-current-branch` is meaningless for bare repos since HEAD doesn't shift the same way | Low | Error or warn if `--track-current-branch` used with `--bare` |

## Differentiators

Features that go beyond what users explicitly asked for but add real value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Log/display which branch is being served | When `--track-current-branch` is active, show current branch in server output or a subtle UI indicator | Low | Logging on each request: `Serving branch: feature-xyz`. Could also expose via `wiki.ref` in templates. |
| `--local-git-user` overrides only when session author is absent | Respects rack middleware auth (omnigollum, etc.) when present, falls back to local git user otherwise | Medium | Priority: session `gollum.author` > `--local-git-user` > Gollum defaults. This is the correct layering. |
| Startup validation warnings | Warn at boot: "track-current-branch active, will follow HEAD" or "local-git-user active but git user.name not set" | Low | Good UX, helps debug misconfiguration |

## Anti-Features

Features to explicitly NOT build. Each has come up in similar tools but would be wrong here.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Background polling / file-watching for branch changes | Adds threads, complexity, race conditions, and Gollum already creates a fresh `Wiki.new` per request | Resolve HEAD per request in `wiki_new()` -- simple, always correct |
| Caching git user at startup | Defeats the purpose if user changes `git config` mid-session | Read fresh on each commit via `git config` subprocess call |
| Bundling both features into a single `--local-dev-mode` flag | They serve different purposes; a team wiki might want branch tracking without overriding the (authenticated) author | Keep as two independent, composable flags |
| Web UI for switching branches | Scope creep; Gollum has an existing `--ref` for this; the new flag is about *automatic* tracking | CLI/config only, no UI changes |
| Web UI for changing commit author | Author attribution should come from git config or auth middleware, not manual entry | Rely on `session['gollum.author']` chain |
| Multi-branch simultaneous serving | Serving multiple branches at once (e.g., branch picker dropdown) is a fundamentally different feature with major architecture implications | Single branch at a time, determined by HEAD |
| Reading `.gitconfig` directly instead of `git config` command | Parsing gitconfig files (includes, conditional includes, system/global/local layering) is complex and fragile | Use `git config --get` which handles all layering correctly |
| Persisting branch/user choice across restarts | These are runtime behaviors, not stored state | Flags are evaluated fresh each time |

## Feature Dependencies

```
--track-current-branch
  --> requires: HEAD symref resolution (read .git/HEAD or `git symbolic-ref HEAD`)
  --> conflicts with: --ref (mutual exclusion at parse time)
  --> interacts with: --bare (should error/warn)
  --> uses: wiki_options[:ref] (sets it dynamically per request)

--local-git-user
  --> requires: git config user.name + user.email resolution
  --> interacts with: session['gollum.author'] (session takes priority if present)
  --> uses: commit_options() method (injects author when session author absent)

No dependency between the two flags -- fully independent.
```

## How Similar Tools Handle This

### Gollum (current behavior)
- `--ref` pins to a single branch at startup; no dynamic tracking
- Author comes from rack session (`session['gollum.author']`), populated by middleware like omnigollum
- No built-in way to use local git identity for web edits
- `wiki_new()` creates a fresh `Gollum::Wiki` per request but always with the same static `:ref`

### GitBook (legacy self-hosted)
- Served from a single branch, typically `master`/`main`
- No dynamic branch tracking feature
- Author tied to the git push identity, not a web UI concept

### Wiki.js
- Database-backed, syncs to git as a storage backend
- Branch is configured once in admin settings
- Author comes from the authenticated web user, mapped to git committer

### GitHub/GitLab Wikis
- Single branch (`main` or legacy `master`), no branch switching
- Author always the authenticated platform user
- No concept of "local git user" since everything is web-based

### Key Insight
No major git-backed wiki tool offers dynamic branch tracking or local git user injection. These are genuinely developer-workflow features that only matter for locally-run Gollum instances. This is a differentiating capability for Gollum's "personal dev wiki" use case.

## MVP Recommendation

Prioritize (both are low complexity, both are the stated project scope):

1. **`--track-current-branch` flag** - Core implementation: resolve HEAD in `wiki_new()`, set `:ref` dynamically. Mutual exclusion with `--ref`. Warn on `--bare`.
2. **`--local-git-user` flag** - Core implementation: read `git config user.name`/`user.email` in `commit_options()`, inject when session author absent.
3. **Startup validation** - Warnings for misconfiguration (both flags active with conflicting options, missing git user, etc.)

Defer:
- UI indicators for current branch: nice-to-have but not essential for the CLI-focused feature
- Integration tests with omnigollum: out of scope per PROJECT.md constraints

## Complexity Assessment

Both features are **low complexity** additions to an existing, well-structured codebase:

- `--track-current-branch`: ~20 lines of code. Add CLI flag, modify `wiki_new()` to resolve HEAD when flag is set, add mutual exclusion check.
- `--local-git-user`: ~25 lines of code. Add CLI flag, modify `commit_options()` to shell out to `git config` when flag is set and session author is nil.
- Testing: Gollum has a Rack::Test-based test suite (`test/test_app.rb`). Both features are testable by setting `wiki_options` and verifying behavior.

## Sources

- Gollum codebase: `bin/gollum` (CLI flag patterns), `lib/gollum/app.rb` (wiki_new, commit_options)
- Training data knowledge of GitBook, Wiki.js, GitHub/GitLab wiki architectures (MEDIUM confidence -- general patterns well-established but specific version details may be stale)
