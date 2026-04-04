# Phase 2: Local Git User - Research

**Researched:** 2026-04-03
**Domain:** Git config reading, Sinatra session injection, commit author attribution
**Confidence:** HIGH

## Summary

Phase 2 adds `--local-git-user` / `wiki_options[:local_git_user]` to inject the developer's local git identity (user.name / user.email) as the commit author for web edits. The implementation strategy is well-defined by user decisions in CONTEXT.md: inject into `session['gollum.author']` via a `before` filter on write requests only, read git config fresh per write request using `git config --get` with `-C` scoped to the wiki repo path, and fall back to Gollum defaults when git config is incomplete.

Phase 1 established all the patterns this phase reuses: CLI flag registration in OptionParser, `before` filter logic in app.rb, `cli_wiki_options` snapshot for source attribution, startup messages in bin/gollum, and test structure using Minitest with Rack::Test. The touch points are: `bin/gollum` (CLI flag + startup message), `lib/gollum/app.rb` (before filter injection + helper method), and a new test file.

**Primary recommendation:** Inject local git user into `session['gollum.author']` in the existing `before` filter block (only on write requests when session author is absent). This single injection point covers all 6 commit paths without modifying `commit_options()` or `upload_file` handler.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Session author (`session['gollum.author']` from rack middleware like OmniAuth) takes priority over local git user
- When session author overrides local git user, log a generic per-request message: "local_git_user overridden by session author" -- no PII in logs
- Local git user is a fallback for when no auth middleware is present (typical local dev scenario)
- If git config user.name or user.email is unset/empty, warn and fall back to Gollum defaults -- no crash, no blocked commit
- All-or-nothing: both user.name AND user.email must be set. If either is missing, fall back entirely to Gollum defaults
- Fallback warning logged once at startup, not on every commit: "local-git-user active but git config user.name/email not set"
- Inject local git user into `session['gollum.author']` in a `before` filter -- covers all 6 commit paths with a single injection point
- Only resolve git user on write requests (POST/PUT/DELETE) -- avoid unnecessary shell-outs on read-heavy GET traffic
- Use `git config --get user.name` / `git config --get user.email` with `-C` flag scoped to wiki repo path -- respects full git config cascade (system > global > local)
- Use `Shellwords.escape` on repo path to prevent shell injection
- Show identity at boot: "Gollum running with local-git-user (currently: Neil Miller <neil@example.com>)"
- If git config is empty at boot, warn inline: "Gollum running with local-git-user (WARNING: git config user.name/email not set -- will use Gollum defaults)"
- Similar pattern to Phase 1's startup message for branch tracking

### Claude's Discretion
- Exact method name for the git config resolution helper (e.g., `resolve_local_git_user`)
- Whether to combine both git config calls into a single helper or keep separate
- Log level for the session-override message (info vs debug)
- Exact placement of the before filter relative to Phase 1's existing before filter logic

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| USER-01 | User can set `wiki_options[:local_git_user]` in config file or pass `--local-git-user` CLI flag to use local git config's user.name and user.email as commit author for web edits | CLI flag registration follows Phase 1 pattern (OptionParser block at bin/gollum:65-69). Config file support is automatic via wiki_options hash convention. Before filter injection covers all commit paths. |
| USER-02 | When `local_git_user` is active, git config is read fresh on each commit (not cached at startup) | Resolution happens in the `before` filter on each write request via `git config --get` shell-out. No caching. |
| USER-03 | If git config user.name or user.email is empty/unset, gollum falls back gracefully with a warning rather than crashing | All-or-nothing check: if either is empty, return nil from helper. Startup warning logged once. Gollum defaults handle the nil case naturally. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Ruby stdlib `Shellwords` | (stdlib) | Escape repo path for shell commands | Prevents injection; built-in, no dependency |
| `git` CLI | system | Read user.name/email via `git config --get` | Handles full git config cascade (system > global > local > worktree) correctly |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Minitest | 5.27.0 | Test framework | Already used by project (test/helper.rb) |
| Rack::Test | 0.6.3 | HTTP request testing | Already used by all app tests |
| Mocha | (bundled) | Mocking/stubbing | Already used in Phase 1 tests (Kernel.expects, .stubs) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `git config --get` shell-out | Parse `~/.gitconfig` directly | Shell-out respects full cascade; parsing only reads one level |
| `Shellwords.escape` | `Open3.capture2` with array args | Open3 avoids shell entirely but is heavier; Shellwords is simpler for this use case |
| Backticks for shell-out | `IO.popen` | Backticks are simpler and sufficient; both are used in the codebase |

**Installation:**
```bash
# No new dependencies needed. Shellwords is Ruby stdlib.
require 'shellwords'
```

## Architecture Patterns

### Integration Points (3 files)

```
bin/gollum                          lib/gollum/app.rb
-----------                         -----------------
1. CLI flag registration            3. before filter: inject into session
   (OptionParser block)                (write requests only)
2. Startup message                  4. resolve_local_git_user helper
   (after config loading)              (private method, git config shell-out)
                                    
test/test_local_git_user.rb
---------------------------
5. Test file (new)
```

### Pattern 1: Before Filter Session Injection
**What:** Inject local git user into `session['gollum.author']` in the `before` block, so both `commit_options()` (line 772) and `upload_file` handler (line 301) pick it up without modification.
**When to use:** When `local_git_user` is enabled, session author is absent, and request is a write (POST/PUT/DELETE).
**Example:**
```ruby
# In the before do block, after the track_current_branch block (line 137):
if settings.wiki_options[:local_git_user] && !request.get?
  unless session['gollum.author']
    author = resolve_local_git_user
    if author
      session['gollum.author'] = author
    end
  else
    logger.info "local_git_user overridden by session author" if settings.logging?
  end
end
```

### Pattern 2: Git Config Resolution Helper
**What:** Private method that shells out to `git config --get` for user.name and user.email, returns `{ name: ..., email: ... }` or nil.
**When to use:** Called from before filter on write requests.
**Example:**
```ruby
# Source: CONTEXT.md decision + ARCHITECTURE.md pseudocode
def resolve_local_git_user
  path = Shellwords.escape(settings.gollum_path)
  name = `git -C #{path} config --get user.name`.strip
  email = `git -C #{path} config --get user.email`.strip
  if !name.empty? && !email.empty?
    { name: name, email: email }
  else
    nil
  end
end
```

### Pattern 3: CLI Flag + Startup Message (same as Phase 1)
**What:** Register `--local-git-user` in OptionParser, print confirmation at boot with current identity.
**Where:** `bin/gollum` -- flag near line 69 (after `--track-current-branch`), startup message after line 312 (after branch tracking message).
**Example:**
```ruby
# CLI flag (bin/gollum, in OptionParser block):
opts.on('--local-git-user',
  'Use local git config user.name/email as commit author.',
  'Read fresh on each commit. Falls back to defaults if unset.') do
  wiki_options[:local_git_user] = true
end

# Startup message (bin/gollum, after config loading + validation):
if wiki_options[:local_git_user]
  name = `git -C #{Shellwords.escape(gollum_path)} config --get user.name`.strip
  email = `git -C #{Shellwords.escape(gollum_path)} config --get user.email`.strip
  if !name.empty? && !email.empty?
    $stderr.puts "Gollum running with local-git-user (currently: #{name} <#{email}>)"
  else
    $stderr.puts "Gollum running with local-git-user (WARNING: git config user.name/email not set -- will use Gollum defaults)"
  end
end
```

### Anti-Patterns to Avoid
- **Modifying commit_options() or upload_file handler directly:** The before-filter session injection approach is decided. Do NOT add conditional logic to commit_options() or upload_file -- it creates multiple injection points to maintain.
- **Caching git user at startup:** Per CONTEXT.md and USER-02, git config must be read fresh on each write request. Do not store the result in an instance variable or wiki_options.
- **Mutating session on GET requests:** Only inject on write requests (POST/PUT/DELETE) to avoid unnecessary shell-outs on read traffic.
- **Forgetting `require 'shellwords'`:** Shellwords is stdlib but must be explicitly required. Add to the requires at the top of app.rb.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Git config cascade resolution | Custom .gitconfig parser | `git config --get` with `-C` flag | Git handles system > global > local > worktree layering correctly |
| Shell argument escaping | Manual string escaping | `Shellwords.escape` | Handles all edge cases (spaces, quotes, special chars) |
| Author hash shape | New data structure | `{ name: ..., email: ... }` matching existing session format | `commit_options()` and upload_file already expect this shape |

**Key insight:** The entire feature piggybacks on existing `session['gollum.author']` infrastructure. No new commit-path code is needed if the before filter injects correctly.

## Common Pitfalls

### Pitfall 1: Upload Handler Bypass
**What goes wrong:** Implementing author injection in `commit_options()` only, missing the upload_file handler which reads `session['gollum.author']` directly.
**Why it happens:** `commit_options()` is the obvious commit path; `upload_file` has its own inline author merge (line 301-303).
**How to avoid:** The before-filter approach (decided in CONTEXT.md) eliminates this pitfall entirely -- session injection covers both paths.
**Warning signs:** Upload commits show no author or wrong author.

### Pitfall 2: Shellwords Not Required
**What goes wrong:** `NameError: uninitialized constant Shellwords` at runtime.
**Why it happens:** `Shellwords` is Ruby stdlib but not auto-loaded. The current app.rb does not require it.
**How to avoid:** Add `require 'shellwords'` at the top of `lib/gollum/app.rb`. Also needed in `bin/gollum` for the startup message.
**Warning signs:** First write request with local_git_user enabled crashes.

### Pitfall 3: git config --get Exit Code on Missing Config
**What goes wrong:** `git config --get user.name` returns exit code 1 and empty string when the key is not set. The backtick operator still returns empty string, but `$?` will be non-zero.
**Why it happens:** git config returns non-zero for missing keys, unlike most git commands.
**How to avoid:** Check for empty string (`name.empty?`), not exit code. The all-or-nothing approach (both must be non-empty) handles this correctly.
**Warning signs:** Unexpected nil returns from the helper.

### Pitfall 4: Session Persistence Across Requests
**What goes wrong:** The `before` filter sets `session['gollum.author']` on a POST request. Sinatra sessions persist across requests (cookie-based). A subsequent GET request might show the injected author in session state.
**Why it happens:** Rack sessions are persistent by default.
**How to avoid:** This is actually harmless -- the session author only affects commit paths (POST handlers). GET handlers never read `session['gollum.author']`. However, if you want to be clean, you could clear it after the request, but the CONTEXT.md design does not require this.
**Warning signs:** None practically, but worth noting for correctness.

### Pitfall 5: Bare Repo git config
**What goes wrong:** `git -C /path/to/bare/repo config --get user.name` works fine for bare repos because `-C` changes the working directory and git finds the config. This is NOT a pitfall -- `-C` handles bare repos correctly.
**How to avoid:** No special handling needed. The `-C` flag works for both bare and non-bare repos.

## Code Examples

### Complete before filter injection (verified against current app.rb line 128-179)
```ruby
# Add after the track_current_branch block (after line 137):
if settings.wiki_options[:local_git_user] && !request.get?
  if session['gollum.author']
    logger.info "local_git_user overridden by session author" if settings.logging?
  else
    author = resolve_local_git_user
    session['gollum.author'] = author if author
  end
end
```

### Complete resolve helper
```ruby
# Source: CONTEXT.md decisions
def resolve_local_git_user
  path = Shellwords.escape(settings.gollum_path)
  name = `git -C #{path} config --get user.name`.strip
  email = `git -C #{path} config --get user.email`.strip
  if !name.empty? && !email.empty?
    { name: name, email: email }
  else
    nil
  end
end
```

### Session author hash shape (verified from test/test_app.rb line 645)
```ruby
# This is the exact shape expected by commit_options() and upload_file:
{ :name => 'ghi', :email => 'jkl' }
# Note: uses symbol keys, not string keys
```

### Test pattern (following Phase 1's test_branch_tracking.rb structure)
```ruby
context "Local git user" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, { allow_editing: true, local_git_user: true })
    # Set git user in the cloned repo
    system("git -C #{@path} config user.name 'Test User'")
    system("git -C #{@path} config user.email 'test@example.com'")
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "web edit uses local git user" do
    post '/gollum/create', content: 'test', format: 'markdown',
         message: 'test commit', page: 'LocalUserTest'
    # Verify commit author
    author = `git -C #{@path} log -1 --format='%an <%ae>'`.strip
    assert_equal 'Test User <test@example.com>', author
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Modify commit_options() + upload_file separately | Inject into session via before filter | Decided in CONTEXT.md | Single injection point, no changes to existing commit paths |
| Read git config at startup | Read fresh on each write request | USER-02 requirement | Picks up config changes without restart |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Minitest 5.27.0 + Shoulda-style context/test DSL |
| Config file | test/helper.rb (loaded by all test files) |
| Quick run command | `ruby test/test_local_git_user.rb` |
| Full suite command | `rake test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| USER-01 | local_git_user option available in wiki_options | unit | `ruby test/test_local_git_user.rb -n test_local_git_user_option_is_available` | Wave 0 |
| USER-01 | CLI flag sets wiki_options[:local_git_user] | unit | `ruby test/test_local_git_user.rb -n test_cli_flag_sets_option` | Wave 0 |
| USER-01 | Web edit uses local git user as commit author | integration | `ruby test/test_local_git_user.rb -n test_web_edit_uses_local_git_user` | Wave 0 |
| USER-01 | Upload uses local git user as commit author | integration | `ruby test/test_local_git_user.rb -n test_upload_uses_local_git_user` | Wave 0 |
| USER-02 | Git config read fresh on each commit (not cached) | integration | `ruby test/test_local_git_user.rb -n test_git_config_read_fresh` | Wave 0 |
| USER-03 | Missing git config falls back gracefully | unit | `ruby test/test_local_git_user.rb -n test_missing_git_config_falls_back` | Wave 0 |
| USER-03 | Partial git config (name only) falls back | unit | `ruby test/test_local_git_user.rb -n test_partial_config_falls_back` | Wave 0 |
| (bonus) | Session author overrides local git user | integration | `ruby test/test_local_git_user.rb -n test_session_author_takes_priority` | Wave 0 |

### Sampling Rate
- **Per task commit:** `ruby test/test_local_git_user.rb`
- **Per wave merge:** `rake test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_local_git_user.rb` -- covers USER-01, USER-02, USER-03
- [ ] No framework install needed -- Minitest + Rack::Test already in place

## Open Questions

1. **Write request detection method**
   - What we know: CONTEXT.md says "Only resolve git user on write requests (POST/PUT/DELETE)"
   - What's unclear: Sinatra's `request.get?` is the cleanest check (returns true for GET, false for POST/PUT/DELETE). Alternatively `!request.safe?` or checking `request.request_method`.
   - Recommendation: Use `!request.get?` -- simple, clear, and HEAD requests (also safe) are extremely rare for Gollum.

2. **Logger availability in before filter**
   - What we know: Phase 1 uses `logger.warn` with `settings.logging?` guard (line 135). The override message should use same pattern.
   - What's unclear: Whether `logger.info` or `logger.debug` is better for the session-override message.
   - Recommendation: Use `logger.info` -- it is operationally useful to know when override happens, not debug-level noise.

## Sources

### Primary (HIGH confidence)
- `lib/gollum/app.rb` -- Direct code analysis of before filter (line 128-179), commit_options (line 772-778), upload_file (line 276-309), wiki_new (line 742-749), resolve_current_branch (line 751-763)
- `bin/gollum` -- Direct code analysis of OptionParser (line 22-208), config loading (line 289-296), validation (line 298), startup messages (line 300-312)
- `test/test_branch_tracking.rb` -- Phase 1 test patterns (context/setup/teardown structure, cloned_testpath, Rack::Test usage)
- `test/test_app.rb:642-657` -- Session author hash shape verification (`{ :name => 'ghi', :email => 'jkl' }`)
- `test/helper.rb` -- Test infrastructure (Minitest + Shoulda DSL, cloned_testpath helper, commit_details helper)

### Secondary (MEDIUM confidence)
- `.planning/phases/02-local-git-user/02-CONTEXT.md` -- All user decisions (locked)
- `.planning/research/ARCHITECTURE.md` -- Feature 2 integration point analysis
- `.planning/research/PITFALLS.md` -- Pitfall 1 (upload handler) and Pitfall 5 (empty git config)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all stdlib/existing
- Architecture: HIGH -- pattern directly mirrors Phase 1, decisions locked in CONTEXT.md, code verified against current source
- Pitfalls: HIGH -- all known pitfalls from prior research verified against actual code; before-filter approach eliminates the riskiest one (upload handler bypass)

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable codebase, no upstream changes expected on feature branch)
