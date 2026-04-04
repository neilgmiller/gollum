# Architecture Patterns

**Domain:** Gollum CLI enhancements (branch tracking + local git user)
**Researched:** 2026-04-02

## Recommended Architecture

Both features hook into the existing `wiki_options` hash pipeline. No new configuration mechanisms needed. The integration follows Gollum's established pattern: CLI flag sets a wiki_option, app.rb reads that option at the appropriate moment.

### Existing Data Flow (Baseline)

```
bin/gollum                        lib/gollum/app.rb                    gollum-lib
-----------                       -----------------                    ----------
OptionParser                      Precious::App
  |                                 |
  +--> wiki_options[:ref]           |
  |                                 |
  +--> App.set(:wiki_options, ...)  |
                                    |
                                    +-- wiki_new() [line 720-722]
                                    |     Gollum::Wiki.new(path, settings.wiki_options)
                                    |       --> wiki_options[:ref] becomes wiki.ref
                                    |
                                    +-- commit_options() [line 731-737]
                                          { message:, note:, name:, email: }
                                          --> author from session['gollum.author']
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `bin/gollum` (CLI) | Parse flags, populate `wiki_options`, validate mutual exclusion | `Precious::App` via `set()` |
| `Precious::App.before` filter | Read wiki_options per-request, set instance vars | `settings.wiki_options` |
| `wiki_new()` | Create Wiki instance with current options | `Gollum::Wiki.new()` in gollum-lib |
| `commit_options()` | Build commit hash with author details | `Gollum::Committer` in gollum-lib |
| `upload_file` handler | Separate author merge for file uploads | `session['gollum.author']` |

## Feature 1: --track-current-branch

### Integration Point

**Where:** `wiki_new()` method at `lib/gollum/app.rb` line 720-722.

Current code:
```ruby
def wiki_new
  Gollum::Wiki.new(settings.gollum_path, settings.wiki_options)
end
```

**Mechanism:** When `wiki_options[:track_current_branch]` is truthy, dynamically resolve HEAD before passing options to `Gollum::Wiki.new`. The `:ref` value in wiki_options gets overwritten per-request with the current branch.

### Data Flow

```
Request arrives
  |
  v
wiki_new() called
  |
  +-- Check settings.wiki_options[:track_current_branch]
  |     |
  |     +-- If true:
  |     |     resolve HEAD from git repo at settings.gollum_path
  |     |     e.g. File.read("#{gollum_path}/.git/HEAD") -> "ref: refs/heads/feature-x"
  |     |     extract branch name -> "feature-x"
  |     |     override :ref in a COPY of wiki_options (do not mutate shared hash)
  |     |
  |     +-- If false/nil:
  |           use wiki_options[:ref] as-is (existing behavior)
  |
  v
Gollum::Wiki.new(path, resolved_options)
```

### Exact Hook Location

**File:** `bin/gollum` -- add CLI flag (around line 63-65, near existing `--ref` flag)

```ruby
opts.on('--track-current-branch', 'Dynamically serve the currently checked out branch. Mutually exclusive with --ref.') do
  wiki_options[:track_current_branch] = true
end
```

**File:** `bin/gollum` -- add mutual exclusion check (after `opts.parse!` at line 212, before server launch)

```ruby
if wiki_options[:track_current_branch] && wiki_options[:ref]
  puts "Error: --track-current-branch and --ref are mutually exclusive."
  exit 1
end
```

**File:** `lib/gollum/app.rb` line 720-722 -- modify `wiki_new()`

```ruby
def wiki_new
  opts = settings.wiki_options
  if opts[:track_current_branch]
    opts = opts.merge(ref: resolve_current_branch)
  end
  Gollum::Wiki.new(settings.gollum_path, opts)
end
```

New private method (after line 737):

```ruby
def resolve_current_branch
  head_file = File.join(settings.gollum_path, '.git', 'HEAD')
  content = File.read(head_file).strip
  if content.start_with?('ref: refs/heads/')
    content.sub('ref: refs/heads/', '')
  else
    content  # detached HEAD -- return SHA
  end
end
```

### Critical Design Decision: Do Not Mutate Shared Hash

`settings.wiki_options` is a shared object across all requests. The `wiki_new()` method MUST use `opts.merge()` (which returns a new hash) rather than `opts[:ref] = ...` (which would mutate the shared hash and cause race conditions with concurrent requests in threaded servers).

## Feature 2: --local-git-user

### Integration Points

There are TWO author injection paths that must both be handled:

**Path 1: `commit_options()` at `lib/gollum/app.rb` line 731-737**
Used by: rename (line 317), edit (line 352), delete (line 371), create (line 408), revert (line 426).

Current code:
```ruby
def commit_options
  msg               = (params[:message].nil? or params[:message].empty?) ? "[no message]" : params[:message]
  commit_options    = { message: msg, note: session['gollum.note'] }
  author_parameters = session['gollum.author']
  commit_options.merge! author_parameters unless author_parameters.nil?
  commit_options
end
```

**Path 2: `upload_file` handler at `lib/gollum/app.rb` lines 276-282**
Directly reads `session['gollum.author']` and merges into options hash.

Current code:
```ruby
options = { :message => "Uploaded file to #{reponame}" }
options[:parent] = wiki.repo.head.commit if wiki.repo.head
author  = session['gollum.author']
unless author.nil?
  options.merge! author
end
```

### Data Flow

```
Request arrives (POST edit/create/delete/revert/upload)
  |
  v
commit_options() called  [or upload_file inline author merge]
  |
  +-- Check settings.wiki_options[:local_git_user]
  |     |
  |     +-- If true AND session['gollum.author'] is nil:
  |     |     read git config user.name from repo
  |     |     read git config user.email from repo
  |     |     inject { name: ..., email: ... } into commit hash
  |     |
  |     +-- If true AND session['gollum.author'] exists:
  |     |     session author takes precedence (middleware-set author wins)
  |     |
  |     +-- If false/nil:
  |           existing behavior unchanged
  |
  v
Gollum::Committer.new(wiki, commit_hash_with_author)
```

### Exact Hook Location

**File:** `bin/gollum` -- add CLI flag (near line 65, after --ref or after --track-current-branch)

```ruby
opts.on('--local-git-user', 'Use local git config user.name and user.email as the commit author for web edits.') do
  wiki_options[:local_git_user] = true
end
```

**File:** `lib/gollum/app.rb` -- modify `commit_options()` at line 731

```ruby
def commit_options
  msg               = (params[:message].nil? or params[:message].empty?) ? "[no message]" : params[:message]
  commit_options    = { message: msg, note: session['gollum.note'] }
  author_parameters = session['gollum.author']
  if author_parameters.nil? && settings.wiki_options[:local_git_user]
    author_parameters = resolve_local_git_user
  end
  commit_options.merge! author_parameters unless author_parameters.nil?
  commit_options
end
```

**File:** `lib/gollum/app.rb` -- modify `upload_file` handler around line 279

```ruby
author = session['gollum.author']
if author.nil? && settings.wiki_options[:local_git_user]
  author = resolve_local_git_user
end
unless author.nil?
  options.merge! author
end
```

**File:** `lib/gollum/app.rb` -- new private method (alongside resolve_current_branch)

```ruby
def resolve_local_git_user
  name = `git -C #{Shellwords.escape(settings.gollum_path)} config user.name`.strip
  email = `git -C #{Shellwords.escape(settings.gollum_path)} config user.email`.strip
  if !name.empty? && !email.empty?
    { name: name, email: email }
  else
    nil
  end
end
```

### Design Decision: Session Author Takes Precedence

When `session['gollum.author']` is set (by Rack middleware like OmniAuth), it should override local git user. The local git user is a fallback for when no authentication middleware is configured, which is the common single-user local development scenario.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Mutating settings.wiki_options
**What:** Assigning `settings.wiki_options[:ref] = resolved_branch` directly
**Why bad:** Shared mutable state across all concurrent requests. A request resolving branch "A" could corrupt another request mid-flight. The `before` filter already does this for `:base_path` (line 133) which is safe because it's constant, but dynamic branch resolution is not.
**Instead:** Use `Hash#merge` to create a per-request copy in `wiki_new()`.

### Anti-Pattern 2: Reading git user at startup
**What:** Resolving `git config user.name` once in `bin/gollum` and storing in wiki_options
**Why bad:** User may change their git config while Gollum is running. The project requirement explicitly calls for per-commit resolution.
**Instead:** Resolve in `commit_options()` on each commit.

### Anti-Pattern 3: Single author injection point
**What:** Only modifying `commit_options()` and forgetting `upload_file`
**Why bad:** File uploads would still show no author. The `upload_file` POST handler (line 254-295) has its own inline author merge that bypasses `commit_options()`.
**Instead:** Modify both paths, or extract shared author resolution into a helper called by both.

### Anti-Pattern 4: Using IO.popen or backticks without path escaping
**What:** Running `git config` without escaping the repo path
**Why bad:** Paths with spaces or special characters would break
**Instead:** Use `Shellwords.escape()` for the path argument

## Patterns to Follow

### Pattern 1: Wiki Options Hash Convention
**What:** All configuration flows through `wiki_options` hash from CLI to app
**When:** Adding any new configurable behavior
**Example:** See existing `wiki_options[:css]`, `wiki_options[:allow_uploads]`, `wiki_options[:ref]`

### Pattern 2: Per-Request Wiki Instance
**What:** `wiki_new()` creates a fresh `Gollum::Wiki` on every request
**When:** This is the existing pattern -- branch resolution hooks into it naturally
**Why it matters:** No cached wiki state means dynamic branch resolution "just works" by modifying the options passed to each new Wiki instance.

### Pattern 3: Graceful Degradation
**What:** Features fail silently when conditions aren't met
**When:** Always -- e.g., if HEAD file can't be read, fall back to default ref; if git user is empty, commit without author (existing behavior)

## Suggested Build Order

### Phase 1: --track-current-branch (simpler, fewer touch points)

1. Add CLI flag to `bin/gollum` OptionParser
2. Add mutual exclusion validation after `opts.parse!`
3. Add `resolve_current_branch` private method to `Precious::App`
4. Modify `wiki_new()` to use it
5. Test: start with `--track-current-branch`, switch branches, verify wiki serves new branch content

**Rationale:** Single integration point (`wiki_new`), no author-handling complexity, easy to verify visually.

### Phase 2: --local-git-user (more touch points, needs careful testing)

1. Add CLI flag to `bin/gollum` OptionParser
2. Add `resolve_local_git_user` private method to `Precious::App`
3. Modify `commit_options()` to use it
4. Modify `upload_file` handler to use it
5. Test: edit a page via web UI, check git log for correct author; upload a file, check git log

**Rationale:** Two separate author injection paths need modification. The `upload_file` handler is easy to miss. Testing requires actual commits.

### Phase 3: Integration testing

1. Test both flags together
2. Test `--track-current-branch` with `--ref` produces clear error
3. Test `--local-git-user` with session author (session wins)
4. Test config file access (`Precious::App.wiki_options[:track_current_branch] = true`)

## Scalability Considerations

| Concern | At 1 user (local) | At 10 users (team) | At 100+ users (org) |
|---------|-------------------|--------------------|--------------------|
| Branch resolution | File read per request (~0.1ms) | Same, negligible | Same, negligible |
| Git user resolution | Shell out per commit (~5ms) | Same per commit | N/A -- would use auth middleware instead |
| Concurrency safety | N/A | Hash#merge ensures isolation | Same |

Both features are designed for the local/small-team use case. At scale, organizations would use Rack authentication middleware for author identity and explicit branch pinning via `--ref`.

## Sources

- `bin/gollum` -- CLI entry point, OptionParser configuration (lines 1-301)
- `lib/gollum/app.rb` -- Sinatra application, `wiki_new()` (line 720-722), `commit_options()` (line 731-737), `upload_file` author merge (line 279-282), `before` filter (line 115-157)
- `.planning/codebase/ARCHITECTURE.md` -- Existing architecture analysis
- `.planning/PROJECT.md` -- Project requirements and constraints

---

*Architecture analysis: 2026-04-02*
