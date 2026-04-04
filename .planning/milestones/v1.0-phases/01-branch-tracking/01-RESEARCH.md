# Phase 1: Branch Tracking - Research

**Researched:** 2026-04-03
**Domain:** Dynamic git branch resolution in a Sinatra wiki application
**Confidence:** HIGH

## Summary

Phase 1 adds a `track_current_branch` option to Gollum that dynamically resolves HEAD on each request, passing the current branch (or detached SHA) as the `:ref` to `Gollum::Wiki.new`. The implementation touches three files: `bin/gollum` (CLI flag + validation), `lib/gollum/app.rb` (HEAD resolution in `wiki_new()` + dynamic editing toggle in `before` filter). No new dependencies are needed.

The existing architecture is well-suited for this change. `wiki_new()` already creates a fresh `Gollum::Wiki` per request at line 720, so injecting a dynamic `:ref` is a natural seam. The critical design constraint is thread safety: `settings.wiki_options` is shared mutable state, so `wiki_new()` must use `Hash#merge` (or `.dup`) to create a per-request copy rather than mutating the shared hash. The detached HEAD case requires special handling: serve the SHA (confirmed viable -- gollum-lib accepts SHAs for `:ref`), disable editing, and log a warning.

**Primary recommendation:** Modify `wiki_new()` to resolve HEAD via `File.read('.git/HEAD')` when `track_current_branch` is set, using `opts.merge(ref: resolved)` for thread safety. Add validation in `bin/gollum` AFTER config file loading (line 289+) to catch `--ref` + `track_current_branch` conflicts from any source.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Detached HEAD behavior: Serve the detached SHA, log a warning, disable editing dynamically, re-enable when HEAD reattaches
- Mutual exclusion UX: Short error with fix suggestion mentioning SOURCE of conflict (CLI vs config file). Only an explicitly-set --ref triggers conflict; the default ref ('master') does NOT conflict
- Startup/runtime feedback: Brief startup message confirming feature + current branch. Per-request logging only in verbose/development mode. Detached HEAD warning logged when detected

### Claude's Discretion
- HEAD resolution mechanism (File.read vs git symbolic-ref vs other)
- Exact warning/log message wording
- How to dynamically toggle allow_editing based on HEAD state
- Where to place the validation logic (before/after config file load -- though CONF-02 says after)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BRANCH-01 | User can set `wiki_options[:track_current_branch]` in config file or pass `--track-current-branch` CLI flag | CLI flag follows existing OptionParser pattern; config file works naturally via `wiki_options` hash convention |
| BRANCH-02 | When active, served branch resolves from HEAD on each request (no caching) | `wiki_new()` is called per-request; HEAD resolution via `File.read('.git/HEAD')` in that method gives per-request resolution |
| BRANCH-03 | If both `ref` and `track_current_branch` are set, exit with clear error | Validation runs after config file loading (line 289+); must distinguish explicitly-set `--ref` from default |
| BRANCH-04 | Detached HEAD handled gracefully | Parse `.git/HEAD` -- if no `ref:` prefix, it is a SHA; serve the SHA, disable editing, log warning |

</phase_requirements>

## Standard Stack

### Core (No New Dependencies)

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| Ruby | (project default, JRuby on default adapter) | Runtime | No version-specific features needed |
| OptionParser | stdlib | CLI flag parsing | Existing pattern in `bin/gollum` lines 23-203 |
| gollum-lib | ~> 6.0 (6.1.0) | Wiki core | `Gollum::Wiki.new(path, opts)` accepts `:ref` -- confirmed from `wiki_new()` at app.rb:720 |
| Sinatra | ~> 4.0 | Web framework | `Precious::App` with `settings`, `before` filter |
| Minitest | (bundled) | Test framework | Existing test suite uses minitest + shoulda + rack-test + mocha |

### Supporting (Already Present)

| Library | Purpose | Used For |
|---------|---------|----------|
| Rack::Test | HTTP testing | Simulating GET/POST requests in tests |
| Shoulda | Test DSL | `context`/`test` blocks in test files |
| Mocha | Mocking | `mocha/minitest` loaded in helper.rb |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `File.read('.git/HEAD')` | `git symbolic-ref --short HEAD` subprocess | Subprocess is ~5-10ms vs ~0.1ms for file read. File read is sufficient and faster. |
| `File.read('.git/HEAD')` | Rugged/RJGit API | Creates coupling to git adapter internals. Gollum uses rjgit on JRuby -- different API from rugged. |
| `Hash#merge` per request | Mutate `settings.wiki_options[:ref]` | Thread-unsafe. Concurrent requests would corrupt each other. |

**Installation:** No new packages needed.

## Architecture Patterns

### Integration Points

```
bin/gollum (3 changes)
├── OptionParser block (~line 65)     # Add --track-current-branch flag
├── After config file load (~line 289) # Mutual exclusion validation
└── Before server launch              # Startup confirmation message

lib/gollum/app.rb (3 changes)
├── before filter (~line 115)          # Dynamic allow_editing toggle for detached HEAD
├── wiki_new() (~line 720)            # HEAD resolution + ref injection
└── New private method                 # resolve_current_branch helper
```

### Pattern 1: Per-Request HEAD Resolution in wiki_new()

**What:** Resolve `.git/HEAD` inside `wiki_new()`, merge result into a copy of `wiki_options`.
**When:** Every HTTP request when `track_current_branch` is enabled.
**Why this location:** `wiki_new()` is already called per-request and creates a fresh `Gollum::Wiki`. It is the natural seam for injecting dynamic state.

```ruby
# Source: existing wiki_new at app.rb:720, modified
def wiki_new
  opts = settings.wiki_options
  if opts[:track_current_branch]
    resolved = resolve_current_branch
    opts = opts.merge(ref: resolved[:ref])
    # Store detached state for before filter to use
    Thread.current[:gollum_head_detached] = resolved[:detached]
  end
  Gollum::Wiki.new(settings.gollum_path, opts)
end
```

**Key detail:** Use `opts.merge()` (returns new hash), NOT `opts[:ref] = ...` (mutates shared hash). This is the most critical correctness constraint.

### Pattern 2: HEAD File Parsing

**What:** Read `.git/HEAD` to determine current branch or detached SHA.
**Format:** The file contains either `ref: refs/heads/<branch>\n` or a 40-char SHA.

```ruby
def resolve_current_branch
  git_dir = settings.wiki_options[:repo_is_bare] ?
    settings.gollum_path :
    File.join(settings.gollum_path, '.git')
  head_path = File.join(git_dir, 'HEAD')
  content = File.read(head_path).strip

  if content.start_with?('ref: refs/heads/')
    { ref: content.sub('ref: refs/heads/', ''), detached: false }
  else
    { ref: content, detached: true }  # SHA for detached HEAD
  end
end
```

**Confidence: HIGH** -- `.git/HEAD` format is a core git invariant documented in `gitrepository-layout(5)`.

### Pattern 3: Dynamic Editing Toggle via before Filter

**What:** When HEAD is detached and `track_current_branch` is active, override `@allow_editing` to `false` in the `before` filter.
**When:** Every request, after `wiki_new()` has resolved HEAD state.

The challenge: `@allow_editing` is set in the `before` filter (line 116), but HEAD resolution happens in `wiki_new()` (line 720), which is called AFTER the `before` filter by individual route handlers.

**Two viable approaches:**

**Approach A (Recommended): Resolve HEAD in the before filter too.**
Add HEAD resolution to the `before` filter to set `@allow_editing`. This means resolving HEAD twice per request (once in `before`, once in `wiki_new()`), but the cost is negligible (~0.1ms file read).

```ruby
before do
  @allow_editing = settings.wiki_options.fetch(:allow_editing, true)

  if settings.wiki_options[:track_current_branch]
    resolved = resolve_current_branch
    if resolved[:detached]
      @allow_editing = false
      # Store for wiki_new to use
      Thread.current[:gollum_head_resolved] = resolved
    end
  end
  # ... rest of existing before filter
end
```

**Approach B: Cache resolution in Thread.current.**
Resolve once in `before` filter, store in `Thread.current`, reuse in `wiki_new()`. Avoids double file read but adds thread-local state management.

**Recommendation:** Approach B is cleaner. Resolve HEAD once in `before` when `track_current_branch` is true, store in `Thread.current[:gollum_head_resolved]`, use in both `before` (for editing toggle) and `wiki_new()` (for ref injection). Clear it at the end of the before filter cycle.

### Pattern 4: Distinguishing Explicit --ref from Default

**What:** The CONTEXT.md specifies that only an explicitly-set `--ref` conflicts with `track_current_branch`. The default ref value ('master') does NOT conflict.
**How:** Track whether `--ref` was explicitly passed.

```ruby
# In OptionParser block:
opts.on('-r', '--ref [REF]', 'Specify the branch to serve.') do |ref|
  wiki_options[:ref] = ref
  wiki_options[:ref_explicitly_set] = true  # Track explicit usage
end

# In validation (after config file load):
if wiki_options[:track_current_branch] && wiki_options[:ref_explicitly_set]
  # Determine source for helpful error message
  # ...
  exit 1
end
```

**Alternative:** Check if `:ref` key exists in the hash (since the default 'master' is NOT pre-set in the `wiki_options` hash -- confirmed from bin/gollum line 16-19 where `wiki_options` is initialized with only `:allow_uploads` and `:allow_editing`). This means `wiki_options.key?(:ref)` is true ONLY if `--ref` was explicitly passed on CLI or set in config file. This is simpler and already works.

### Pattern 5: Error Message with Source Attribution

**What:** When `--ref` and `track_current_branch` conflict, tell the user WHERE each was set.
**How:** Track provenance. After config file loading, if both are set, determine which came from CLI vs config file.

```ruby
# After config file load (line 289+):
if wiki_options[:track_current_branch] && wiki_options.key?(:ref)
  # Determine sources
  sources = []
  # If --track-current-branch was in original CLI wiki_options, it's from CLI
  # If :ref was in original CLI wiki_options, it's from CLI; otherwise config file
  $stderr.puts "Error: --track-current-branch conflicts with ref. Use one or the other."
  $stderr.puts "  (track_current_branch source: #{tcb_source}, ref source: #{ref_source})"
  exit 1
end
```

**Implementation detail:** Save a snapshot of `wiki_options` before config file loading to compare afterward. If a key existed before config file load, it came from CLI; if it appeared after, it came from the config file.

### Anti-Patterns to Avoid

- **Mutating `settings.wiki_options[:ref]`:** Thread-unsafe. Always use `Hash#merge` to create per-request copy.
- **Resolving HEAD at startup only:** Defeats the purpose. Must resolve per-request.
- **Caching HEAD resolution:** The requirement explicitly says no caching.
- **Using `Rugged::Repository` directly:** Gollum on JRuby uses rjgit, not rugged. Direct rugged calls would break.
- **Validating mutual exclusion before config file load:** Config file can set `:ref`, so validation must run after line 289 in bin/gollum.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HEAD resolution | Custom git library wrapper | `File.read('.git/HEAD')` + string parsing | 2 lines of code, stable format since git 1.0 |
| Thread-safe option passing | Mutex/lock around wiki_options | `Hash#merge` returning new hash | Immutable-style approach is simpler and correct |
| CLI flag parsing | Custom argument parsing | `OptionParser` (already used) | Existing pattern, handles help text, error messages |
| Config file validation | Custom config parser | Snapshot-and-compare pattern | Config file is `require`d Ruby -- just compare wiki_options before/after |

## Common Pitfalls

### Pitfall 1: Mutating Shared wiki_options Hash
**What goes wrong:** `settings.wiki_options[:ref] = resolved_branch` directly mutates the shared hash. In threaded servers, concurrent requests corrupt each other.
**Why it happens:** `settings.wiki_options` looks like a local variable but is shared across all requests.
**How to avoid:** Always use `opts = settings.wiki_options.merge(ref: branch)` in `wiki_new()`.
**Warning signs:** Branch flickering under concurrent load; test passes in single-threaded mode but fails with threads.

### Pitfall 2: Validation Runs Too Early
**What goes wrong:** Mutual exclusion check runs after `opts.parse!` but before config file loading. A config.rb that sets `:ref` silently conflicts with `--track-current-branch` from CLI.
**Why it happens:** The config file is loaded at line 282-289, after option parsing at line 207.
**How to avoid:** Place validation AFTER line 289 (`wiki_options = Precious::App.wiki_options`).
**Warning signs:** No error when config.rb sets `:ref` and CLI passes `--track-current-branch`.

### Pitfall 3: Default --ref Treated as Explicit
**What goes wrong:** The default ref ('master') triggers the mutual exclusion error even though no explicit `--ref` was passed.
**Why it happens:** Checking `wiki_options[:ref]` without distinguishing explicit from default.
**How to avoid:** Check `wiki_options.key?(:ref)` -- the default 'master' is NOT pre-set in the wiki_options hash (confirmed: bin/gollum:16-19 initializes only `:allow_uploads` and `:allow_editing`). The `:ref` key only exists if explicitly set.
**Warning signs:** `--track-current-branch` fails even without `--ref`.

### Pitfall 4: Detached HEAD Without Editing Disable
**What goes wrong:** Wiki allows edits on a detached HEAD, creating commits on an orphaned/dangling ref.
**Why it happens:** Editing toggle (`@allow_editing`) is set in `before` filter from static config, not dynamically from HEAD state.
**How to avoid:** In `before` filter, when `track_current_branch` is active and HEAD is detached, force `@allow_editing = false`.
**Warning signs:** User edits a page while HEAD is detached; commit is invisible after switching back to a branch.

### Pitfall 5: `.git` is a File (Worktree/Submodule)
**What goes wrong:** In git worktrees or submodules, `.git` is a file containing `gitdir: /path/to/actual/git/dir`, not a directory.
**Why it happens:** Non-standard git layouts.
**How to avoid:** For v1, document as a known limitation. The fix would be to check if `.git` is a file and follow the `gitdir:` pointer. This is v2 scope (BRANCH-06).
**Warning signs:** `File.read('.git/HEAD')` raises an error because `.git/HEAD` doesn't exist (`.git` is a file, not a directory).

## Code Examples

### Example 1: CLI Flag Registration

```ruby
# In bin/gollum OptionParser block, after --ref flag (~line 65):
opts.on('--track-current-branch',
  'Dynamically serve the currently checked-out branch.',
  'Resolves HEAD on each request. Mutually exclusive with --ref.') do
  wiki_options[:track_current_branch] = true
end
```

### Example 2: Mutual Exclusion Validation (After Config File Load)

```ruby
# In bin/gollum, after line 289 (wiki_options = Precious::App.wiki_options):
if wiki_options[:track_current_branch] && wiki_options.key?(:ref)
  ref_source = cli_wiki_options.key?(:ref) ? "CLI (--ref)" : "config file"
  tcb_source = cli_wiki_options.key?(:track_current_branch) ? "CLI (--track-current-branch)" : "config file"
  $stderr.puts "Error: --ref and --track-current-branch are mutually exclusive. Use one or the other."
  $stderr.puts "  --track-current-branch set via: #{tcb_source}"
  $stderr.puts "  --ref set via: #{ref_source}"
  exit 1
end
```

### Example 3: HEAD Resolution Helper

```ruby
# In lib/gollum/app.rb, private method:
def resolve_current_branch
  git_dir = settings.wiki_options[:repo_is_bare] ?
    settings.gollum_path :
    File.join(settings.gollum_path, '.git')
  content = File.read(File.join(git_dir, 'HEAD')).strip

  if content.start_with?('ref: refs/heads/')
    { ref: content.sub('ref: refs/heads/', ''), detached: false }
  else
    { ref: content, detached: true }
  end
end
```

### Example 4: Modified wiki_new with Thread-Local Caching

```ruby
def wiki_new
  opts = settings.wiki_options
  if opts[:track_current_branch]
    resolved = Thread.current[:gollum_head_resolved] || resolve_current_branch
    opts = opts.merge(ref: resolved[:ref])
  end
  Gollum::Wiki.new(settings.gollum_path, opts)
end
```

### Example 5: Before Filter with Dynamic Editing Toggle

```ruby
before do
  @allow_editing = settings.wiki_options.fetch(:allow_editing, true)

  if settings.wiki_options[:track_current_branch]
    resolved = resolve_current_branch
    Thread.current[:gollum_head_resolved] = resolved
    if resolved[:detached]
      @allow_editing = false
      logger.warn "HEAD is detached at #{resolved[:ref][0..6]}, editing disabled"
    end
  end

  # ... rest of existing before filter unchanged
end
```

### Example 6: Test Pattern (Following Existing Convention)

```ruby
# test/test_branch_tracking.rb
require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

context "Branch tracking" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    @wiki = Gollum::Wiki.new(@path)
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, {
      allow_editing: true,
      track_current_branch: true
    })
  end

  teardown do
    Precious::App.set(:wiki_options, {allow_editing: true})
    FileUtils.rm_rf(@path)
  end

  test "serves pages from current branch" do
    # Create a branch with different content
    system("git -C #{@path} checkout -b test-branch 2>/dev/null")
    @wiki = Gollum::Wiki.new(@path, ref: 'test-branch')
    @wiki.write_page('BranchPage', :markdown, 'branch content', commit_details)

    get '/BranchPage'
    assert last_response.ok?
    assert_match /branch content/, last_response.body
  end

  def app
    Precious::App
  end
end
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Static `--ref` at startup | Dynamic HEAD resolution per request | Wiki follows `git checkout` without restart |
| No editing control for HEAD state | Dynamic `allow_editing` based on detached HEAD | Prevents dangling commits |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Minitest (bundled) + Shoulda context DSL + Mocha mocking |
| Config file | `test/helper.rb` (custom context/test DSL, cloned_testpath helper) |
| Quick run command | `ruby -Itest test/test_branch_tracking.rb` |
| Full suite command | `rake test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BRANCH-01 | CLI flag sets `track_current_branch` in wiki_options | unit | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-01 | Config file sets `track_current_branch` (same effect) | unit | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-02 | Pages served from HEAD-resolved branch per request | integration | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-03 | --ref + track_current_branch exits with error | unit | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-03 | Default ref does NOT conflict | unit | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-04 | Detached HEAD serves SHA content | integration | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-04 | Detached HEAD disables editing | integration | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |
| BRANCH-04 | Re-attaching HEAD re-enables editing | integration | `ruby -Itest test/test_branch_tracking.rb` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `ruby -Itest test/test_branch_tracking.rb`
- **Per wave merge:** `rake test` (full suite to ensure no regressions)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_branch_tracking.rb` -- covers BRANCH-01 through BRANCH-04
- [ ] Test repo with multiple branches (may need to create branches in `cloned_testpath` during setup)
- [ ] No new framework install needed -- minitest/shoulda/rack-test already configured

## Open Questions

1. **Thread.current cleanup**
   - What we know: Using `Thread.current[:gollum_head_resolved]` to cache HEAD resolution per request works but requires cleanup.
   - What's unclear: Whether Sinatra guarantees that `after` filters always run (even on errors) for cleanup. In production Puma with threads, stale thread-local data could leak between requests if not cleaned.
   - Recommendation: Use `ensure` block or simply resolve HEAD twice (once in `before`, once in `wiki_new`) -- the file read is ~0.1ms and correctness trumps optimization.

2. **Bare repo HEAD path**
   - What we know: Bare repos store HEAD at `<repo>/HEAD` not `<repo>/.git/HEAD`. The code can check `wiki_options[:repo_is_bare]` to adjust the path.
   - What's unclear: Whether bare repos with `--track-current-branch` is a v1 requirement. BRANCH-05 (bare repo support) is explicitly v2.
   - Recommendation: Handle it defensively in `resolve_current_branch` since it is a one-line check, but do not write tests for it in Phase 1.

3. **Startup message mechanism**
   - What we know: User wants a brief startup message like "Gollum running with track-current-branch (currently on: main)".
   - What's unclear: Where exactly to place this. `bin/gollum` has no logging framework -- it uses `puts` for output. The message needs to run after validation but before server launch.
   - Recommendation: Use `$stderr.puts` or `puts` right before `Precious::App.run!` (line 294) or `Rackup::Server.new` (line 299). Keep it simple.

## Sources

### Primary (HIGH confidence)
- `bin/gollum` -- CLI entry point, OptionParser (lines 1-301). Directly read and analyzed.
- `lib/gollum/app.rb` -- Sinatra app, `wiki_new()` (line 720), `before` filter (line 115-157), `commit_options()` (line 731). Directly read and analyzed.
- `test/helper.rb` -- Test framework setup, `cloned_testpath` helper. Directly read.
- `test/test_allow_editing.rb` -- Pattern for wiki_options-based feature tests. Directly read.
- `test/test_app.rb` -- Main test file, Rack::Test patterns. Directly read.
- `.planning/research/ARCHITECTURE.md` -- Prior architecture research. Directly read.
- `.planning/research/PITFALLS.md` -- Prior pitfall analysis. Directly read.
- `.planning/research/STACK.md` -- Prior stack research. Directly read.

### Secondary (MEDIUM confidence)
- `.git/HEAD` file format -- documented in `gitrepository-layout(5)`. Core git invariant, extremely stable across all versions.

### Tertiary (LOW confidence)
- Thread.current behavior in Sinatra/Puma -- based on general Ruby/Rack knowledge. Should be verified if thread-local caching approach is used.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all integration points verified from source
- Architecture: HIGH -- `wiki_new()` seam confirmed, `Hash#merge` pattern well-understood
- Pitfalls: HIGH -- all identified from direct code analysis of the actual files
- Test patterns: HIGH -- existing test conventions confirmed from test/helper.rb and test files
- Thread safety: MEDIUM -- general Ruby knowledge, not verified against Gollum's specific server configuration

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable codebase, no upstream changes expected on feature branch)
