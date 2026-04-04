# Domain Pitfalls

**Domain:** CLI feature additions to a git-backed Sinatra wiki (dynamic branch tracking + local git user injection)
**Researched:** 2026-04-02

## Critical Pitfalls

Mistakes that cause rewrites, data corruption, or broken behavior.

### Pitfall 1: Upload handler has its own author injection path

**What goes wrong:** The `--local-git-user` feature gets wired into `commit_options()` (line 731) but the `upload_file` POST handler (line 254) does NOT use `commit_options()`. It manually reads `session['gollum.author']` and merges it into its own options hash (lines 279-281). If the local git user is only injected via `commit_options()`, uploads will silently use the wrong author (or no author).

**Why it happens:** The upload handler was written with a different commit flow -- it builds its own options hash instead of calling the shared `commit_options()` helper. It is easy to grep for `commit_options` and think you have found all commit paths, missing this one.

**Consequences:** Commits from file uploads get attributed to a different (or empty) author than page edits. Silent data inconsistency in git history.

**Prevention:** Audit every code path that creates a git commit. There are exactly 6 commit sites in `app.rb`:
1. `post '/rename/*'` -- line 317, uses `commit_options`
2. `post '/edit/*'` -- line 352, uses `commit_options`
3. `post '/delete/*'` -- line 371, uses `commit_options`
4. `post '/create'` -- line 408, uses `commit_options`
5. `post '/revert/*'` -- line 426, uses `commit_options`
6. `post '/upload_file'` -- line 279, uses **direct session access**

The `--local-git-user` implementation must handle all 6 paths. The cleanest approach: inject the local git user into `session['gollum.author']` in the `before` filter (which runs before every request), so both `commit_options()` and the upload handler's direct session read pick it up.

**Detection:** After implementation, upload a file and check `git log --format='%an <%ae>' -1` to verify the author matches page edit commits.

**Phase:** Must be addressed during the `--local-git-user` implementation phase.

### Pitfall 2: Detached HEAD breaks branch resolution

**What goes wrong:** `--track-current-branch` resolves HEAD to get the current branch. But HEAD can be detached (pointing to a commit SHA, not a branch). Reading a detached HEAD and passing it as `:ref` to gollum-lib may produce undefined behavior -- gollum-lib expects a branch name, not a raw SHA.

**Why it happens:** Developers commonly `git checkout <sha>` or `git rebase`, leaving HEAD detached. The feature silently resolves to a SHA instead of a branch name.

**Consequences:** Pages may render from an unexpected commit, or gollum-lib may error out trying to look up a ref that does not exist as a branch. Commits made through the wiki could land on an orphaned ref.

**Prevention:** When resolving HEAD, detect the detached state explicitly. In Ruby:
```ruby
ref = `git -C #{repo_path} symbolic-ref --short HEAD 2>/dev/null`.strip
if ref.empty?
  # HEAD is detached -- fall back to default behavior or error
end
```
Decide on a policy: either (a) fall back to the configured `--ref` default, (b) fall back to "master"/"main", or (c) refuse to start with a clear error message. Option (c) is safest.

**Detection:** Test with `git checkout --detach` before starting gollum.

**Phase:** Must be addressed during the `--track-current-branch` implementation phase.

### Pitfall 3: Race condition between branch switch and wiki commit

**What goes wrong:** User is viewing a page on branch A. They start editing. Meanwhile, the developer switches to branch B in the terminal. The wiki save resolves HEAD (now branch B) and commits the edit to branch B instead of branch A where the user was reading.

**Why it happens:** HEAD is resolved per-request. The read request and write request may resolve to different branches if the underlying repo changes between requests.

**Consequences:** Page edits land on the wrong branch. The user sees a "success" but their edit is invisible on the branch they were reading from. This is a silent data placement error.

**Prevention:** This is an inherent trade-off of the per-request resolution design. Mitigations:
1. **Document it clearly** -- this is expected behavior for the feature. The wiki follows HEAD, and HEAD can change between requests.
2. **Do NOT try to fix this with locking** -- file locks on HEAD would break the developer's git workflow, defeating the feature's purpose.
3. **Consider showing the current branch in the UI** (even though UI changes are out of scope for MVP) so users see which branch they are committing to.

The PROJECT.md explicitly states "resolve on each request is sufficient" and "no background polling," so this trade-off is accepted by design. The key pitfall is trying to over-engineer a solution (locking, caching the branch per session) that creates worse problems.

**Detection:** This is a known limitation, not a bug. Ensure documentation mentions it.

**Phase:** Documentation phase. No code fix needed, but must be explicitly acknowledged.

## Moderate Pitfalls

### Pitfall 4: Mutually exclusive flag validation happens too late

**What goes wrong:** `--track-current-branch` and `--ref` are declared mutually exclusive, but if validation happens after both values are stored in `wiki_options`, the later flag silently overwrites the earlier one (OptionParser processes flags in order). The user gets no error -- just unexpected behavior.

**Prevention:** Validate mutual exclusivity immediately after `opts.parse!` completes (around line 212 in `bin/gollum`), before the wiki boots:
```ruby
if wiki_options[:track_current_branch] && wiki_options[:ref]
  puts "Error: --track-current-branch and --ref are mutually exclusive."
  exit 1
end
```
Do NOT validate inside each option's block -- both blocks run during parsing, so the second one does not know if the first was set yet (OptionParser processes left-to-right but does not guarantee ordering with config file interaction).

**Detection:** Test: `gollum --ref master --track-current-branch` should print an error and exit 1.

**Phase:** CLI flag implementation phase.

### Pitfall 5: `git config` shelling out fails in bare repos or non-standard layouts

**What goes wrong:** `--local-git-user` reads `git config user.name` and `git config user.email` by shelling out to `git`. But:
- Bare repos (`--bare` flag) have no working directory, so `git config` must be run with `--git-dir` pointing to the right location.
- If the repo was cloned with a non-standard config location, `git config` may return empty strings.
- Docker deployments often have no local git config at all.

**Why it happens:** `git config user.name` reads from the repo's `.git/config`, then `~/.gitconfig`, then system config. In Docker containers or CI, none of these may have user info set.

**Consequences:** Empty author name/email in commits. Git may reject commits with empty author fields depending on the adapter (rugged vs rjgit behavior differs).

**Prevention:**
1. Always pass `--git-dir` or `-C <repo_path>` when shelling out to git, using the same `gollum_path` the wiki uses.
2. Validate that the returned values are non-empty. If empty, either:
   - Fall back to gollum-lib's default author behavior (let it handle the missing author).
   - Log a warning at startup: "Warning: --local-git-user is set but git config user.name/user.email are not configured in <path>."
3. Handle the bare repo case explicitly -- bare repos store config in `<repo>/config` not `<repo>/.git/config`.

**Detection:** Test with `--bare` flag. Test in a Docker container with no git config.

**Phase:** `--local-git-user` implementation phase.

### Pitfall 6: Config file can override wiki_options after flag processing

**What goes wrong:** The config file (loaded via `-c` / `--config`) runs `require cfg` which can modify `Precious::App.wiki_options` arbitrarily (line 282-289 in `bin/gollum`). If a config file sets `:ref`, it could conflict with `--track-current-branch`. If it sets author info, it could conflict with `--local-git-user`. The flags and config file interact in non-obvious ways.

**Why it happens:** The config file is loaded AFTER CLI option parsing, and its changes are re-read into `wiki_options` (line 289: `wiki_options = Precious::App.wiki_options`). This means config file settings win over CLI flags.

**Prevention:**
1. Run mutual exclusivity validation AFTER the config file is loaded (not just after `opts.parse!`).
2. Document that config file settings override CLI flags (this is existing behavior for all options, not new).
3. Consider: if `--track-current-branch` is set via CLI but config file sets `:ref`, should that be an error? Decide and document the precedence rule.

**Detection:** Test with a config.rb that sets `wiki_options[:ref] = 'develop'` combined with `--track-current-branch`.

**Phase:** CLI flag implementation phase (validation logic).

### Pitfall 7: wiki_new() creates a new Wiki instance per request -- ref must be dynamic

**What goes wrong:** The developer assumes `:ref` in `wiki_options` is read once at boot. But `wiki_new()` (line 720) creates `Gollum::Wiki.new(settings.gollum_path, settings.wiki_options)` on every request. This is actually helpful for `--track-current-branch` -- it means the ref is re-read per request IF `wiki_options[:ref]` is updated before each call.

The pitfall: naively setting `wiki_options[:ref]` to the resolved HEAD at startup instead of resolving it dynamically per request. Since `wiki_options` is stored in Sinatra `settings`, it is shared mutable state across all requests.

**Prevention:** The cleanest approach for `--track-current-branch`: instead of mutating `wiki_options[:ref]` (shared state, thread-unsafe), override `wiki_new()` to resolve HEAD at call time:
```ruby
def wiki_new
  opts = settings.wiki_options.dup
  if opts[:track_current_branch]
    opts[:ref] = resolve_current_branch(settings.gollum_path)
  end
  Gollum::Wiki.new(settings.gollum_path, opts)
end
```
This avoids mutating shared state and is thread-safe.

**Detection:** Run gollum, switch branches in the terminal, reload the wiki page. If it still shows the old branch's content, the ref was cached at startup.

**Phase:** `--track-current-branch` implementation phase. This is an architectural decision that must be right from the start.

## Minor Pitfalls

### Pitfall 8: `git symbolic-ref` is a subprocess call on every request

**What goes wrong:** Resolving HEAD via `git symbolic-ref` shells out to git on every HTTP request. This adds latency (typically 5-15ms per call) and creates a subprocess per request.

**Prevention:** This is acceptable for a local development wiki (not a production service). The PROJECT.md explicitly says "resolve on each request is sufficient." Do not prematurely optimize with caching or file watching -- that adds complexity for negligible gain in this use case.

If performance becomes an issue later, reading `.git/HEAD` directly as a file (it is a plaintext symref like `ref: refs/heads/main`) is faster than shelling out, but introduces coupling to git internals.

**Detection:** Not a problem unless someone reports latency. Benchmark if concerned.

**Phase:** Not applicable for MVP. Optimization candidate only if needed.

### Pitfall 9: Flag naming collision with future gollum releases

**What goes wrong:** Upstream gollum may add flags with the same names (`--track-current-branch`, `--local-git-user`), or add their own branch/author features with different semantics.

**Prevention:** The PROJECT.md states "changes are on a feature branch, not targeting upstream merge." This limits exposure. If upstream merge is ever desired, check for conflicts at that time.

**Detection:** Before any upstream merge attempt, diff against latest upstream `bin/gollum`.

**Phase:** Not applicable unless upstream merge is pursued.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| `--track-current-branch` implementation | Detached HEAD (Pitfall 2) | Detect and handle explicitly with clear error |
| `--track-current-branch` implementation | Shared mutable state (Pitfall 7) | Override `wiki_new()` with per-request resolution, do not mutate `settings.wiki_options` |
| `--local-git-user` implementation | Missing upload handler (Pitfall 1) | Inject author in `before` filter via session, not just `commit_options()` |
| `--local-git-user` implementation | Empty git config (Pitfall 5) | Validate non-empty, warn at startup, handle bare repos |
| CLI validation | Late validation (Pitfall 4) | Validate after both CLI parse AND config file load |
| CLI validation | Config file override (Pitfall 6) | Validate mutual exclusivity after config file is applied |
| Testing/QA | Race condition (Pitfall 3) | Document as known limitation, do not over-engineer |

## Sources

- Direct code analysis of `bin/gollum` (CLI entry point, option parsing)
- Direct code analysis of `lib/gollum/app.rb` (Sinatra app, commit paths, wiki_new)
- `.planning/PROJECT.md` (requirements, constraints, design decisions)
- `.planning/codebase/ARCHITECTURE.md` (state management, request flow)
- `.planning/codebase/INTEGRATIONS.md` (git adapter details, deployment contexts)

---

*Pitfall analysis: 2026-04-02*
