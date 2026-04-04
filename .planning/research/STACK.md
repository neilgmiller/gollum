# Technology Stack

**Project:** Gollum CLI Enhancements (Branch Tracking + Local Git User)
**Researched:** 2026-04-02

## Recommended Stack

No new dependencies. Both features are implementable with what Gollum already has.

### Core: Existing Stack (No Changes)

| Technology | Version | Purpose | Notes |
|------------|---------|---------|-------|
| Ruby | (project default) | Runtime | No version-specific features needed |
| OptionParser | stdlib | CLI flag parsing | Already used in `bin/gollum` |
| gollum-lib | ~> 6.0 (6.1.0) | Wiki core, commit handling | `Gollum::Wiki.new(path, opts)` accepts `:ref` |
| Sinatra | (bundled) | Web framework | `Precious::App` hosts wiki |
| gollum-rjgit_adapter | ~> 2.0 | Git operations (JRuby) | Wraps JGit via rjgit |

### Feature 1: `--track-current-branch` (Dynamic HEAD Resolution)

**Approach: Read `.git/HEAD` directly via File I/O**

| Method | Where | Why |
|--------|-------|-----|
| `File.read(File.join(gollum_path, '.git', 'HEAD'))` | In `wiki_new` or a helper | Fastest, zero-dependency way to resolve current branch |
| Parse `ref: refs/heads/<branch>` format | Same | HEAD file is a symref in this format when on a branch |
| Inject resolved branch into `wiki_options[:ref]` | `wiki_new` method in `app.rb` | Per-request resolution via existing wiki creation path |

**How it works in detail:**

The `.git/HEAD` file contains either:
- `ref: refs/heads/some-branch\n` (when on a branch) -- parse out "some-branch"
- A raw 40-char SHA (detached HEAD) -- use as-is for the ref

```ruby
def resolve_current_branch(repo_path)
  head_path = File.join(repo_path, '.git', 'HEAD')
  content = File.read(head_path).strip
  if content.start_with?('ref: ')
    content.sub('ref: refs/heads/', '')
  else
    content  # detached HEAD, return SHA
  end
end
```

**Integration point:** The `wiki_new` method (line 720-721 in `app.rb`) creates a fresh `Gollum::Wiki` per request. When `--track-current-branch` is active, resolve HEAD and override `:ref` in the options hash before passing to `Gollum::Wiki.new`. This is the natural seam -- no architecture changes needed.

```ruby
def wiki_new
  opts = settings.wiki_options.dup
  if opts[:track_current_branch]
    opts[:ref] = resolve_current_branch(settings.gollum_path)
  end
  Gollum::Wiki.new(settings.gollum_path, opts)
end
```

**Why `.dup` the options:** Without `.dup`, modifying `:ref` on the shared `settings.wiki_options` hash would persist across requests and create thread-safety issues. Always duplicate before mutation.

**Confidence: HIGH** -- This is how git itself resolves HEAD. The `.git/HEAD` file format is stable across all git versions. gollum-lib's Wiki accepts `:ref` as an option and uses it to determine which branch to read pages from.

### Feature 2: `--local-git-user` (Git Config Author Injection)

**Approach: Shell out to `git config` per commit**

| Method | Where | Why |
|--------|-------|-----|
| `` `git config user.name` `` or `IO.popen` | In `commit_options` method | Reads the effective git config (global + local) |
| Inject `:name` and `:email` into commit options | `commit_options` in `app.rb` | Same keys that `session['gollum.author']` provides |

**How gollum-lib expects author info:**

From the existing `commit_options` method (lines 731-736 in `app.rb`) and the `Gollum::Committer` class, the options hash expects:
- `:name` -- String, author full name
- `:email` -- String, author email address
- `:message` -- String, commit message

The `session['gollum.author']` hash (set by Rack middleware like OmniAuth) provides `{ name: "...", email: "..." }`. The `--local-git-user` feature provides the same keys from a different source.

**Implementation:**

```ruby
def commit_options
  msg = (params[:message].nil? or params[:message].empty?) ? "[no message]" : params[:message]
  commit_options = { message: msg, note: session['gollum.note'] }
  
  author_parameters = session['gollum.author']
  
  if author_parameters.nil? && settings.wiki_options[:local_git_user]
    # Read git config fresh on each commit
    git_name = `git config user.name`.strip
    git_email = `git config user.email`.strip
    unless git_name.empty? && git_email.empty?
      author_parameters = { name: git_name, email: git_email }
    end
  end
  
  commit_options.merge! author_parameters unless author_parameters.nil?
  commit_options
end
```

**Key design decision: session author takes priority.** If Rack middleware (e.g., OmniAuth) has set `session['gollum.author']`, that should win over git config. The `--local-git-user` flag acts as a fallback for when no auth middleware is present (which is the typical local-use case). This matches the existing `unless author_parameters.nil?` guard.

**Why `git config` not `File.read`:** Git config has a cascade: system -> global -> local -> worktree. Parsing all of these manually is error-prone. `git config user.name` resolves the effective value correctly. The overhead of a subprocess per commit is negligible for a wiki with human-speed edits.

**Confidence: HIGH** -- `git config` is the canonical way to read effective git configuration. The `:name` and `:email` keys are confirmed from the existing `commit_options` method and comments in the source (lines 724-730).

### CLI Flag Registration

Both flags follow the existing OptionParser pattern in `bin/gollum`:

```ruby
opts.on('--track-current-branch', 'Dynamically serve the currently checked-out branch (resolves HEAD on each request).') do
  wiki_options[:track_current_branch] = true
end

opts.on('--local-git-user', 'Use git config user.name and user.email as commit author.') do
  wiki_options[:local_git_user] = true
end
```

**Mutual exclusivity check** (after `opts.parse!`):

```ruby
if wiki_options[:track_current_branch] && wiki_options[:ref]
  puts "Error: --track-current-branch and --ref are mutually exclusive."
  exit 1
end
```

**Confidence: HIGH** -- Directly follows the pattern of every other flag in `bin/gollum` (lines 48-201).

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| HEAD resolution | `File.read('.git/HEAD')` | `git rev-parse --abbrev-ref HEAD` via subprocess | Subprocess overhead on every HTTP request is wasteful; file read is ~0.1ms vs ~5-10ms for subprocess. Also avoids PATH dependency issues. |
| HEAD resolution | `File.read('.git/HEAD')` | Rugged/RJGit API via gollum-lib | gollum-lib abstracts the git adapter; reaching into adapter internals creates coupling. Also, Gollum on JRuby uses rjgit, not rugged -- different APIs. |
| HEAD resolution | `File.read('.git/HEAD')` | `git symbolic-ref HEAD` via subprocess | Same subprocess overhead concern. File read is simpler and equivalent. |
| Git user reading | `git config user.name` subprocess | Parse `~/.gitconfig` and `.git/config` manually | Would miss system config, conditional includes, and XDG config paths. `git config` handles all cascading correctly. |
| Git user reading | Per-commit resolution | Read once at startup | PROJECT.md explicitly requires fresh-read per commit to pick up config changes without restart. |
| Author injection | Modify `commit_options` method | Rack middleware | Over-engineered for a simple flag. The injection point already exists in `commit_options`. |
| Author fallback | Session author wins | Git config always wins | When auth middleware is present, the authenticated user identity should be authoritative. Git config is the fallback for local/unauthed use. |

## What NOT to Use

| Anti-Pattern | Why Avoid |
|--------------|-----------|
| `Rugged::Repository` directly | Gollum uses rjgit on JRuby (the default adapter per Gemfile.lock). Rugged is a C extension that doesn't exist on JRuby. Using rugged directly would break the app. |
| `gollum-lib` internal git adapter methods | The adapter layer (`gollum-rjgit_adapter`) is an internal abstraction. Reaching into `wiki.repo` for HEAD resolution couples to adapter internals. |
| `FileUtils` or `Pathname` for `.git/HEAD` | Overkill. `File.read` is sufficient for reading a single small file. |
| `Open3.capture3` for `git config` | Unnecessary complexity. Backtick or `IO.popen` is fine for a simple command that returns a single line. `Open3` is for when you need stderr separately. |
| `ENV['GIT_AUTHOR_NAME']` / `ENV['GIT_AUTHOR_EMAIL']` | These are transient process environment variables, not the user's configured identity. They override git config in surprising ways. |
| Caching resolved branch or user | Both PROJECT.md and the design require fresh resolution (branch per-request, user per-commit). Caching defeats the purpose. |
| Background threads or file watchers | Adds complexity and concurrency bugs for no benefit. Per-request/per-commit resolution is fast enough. |

## Edge Cases to Handle

| Edge Case | How to Handle |
|-----------|---------------|
| Detached HEAD | `.git/HEAD` contains raw SHA instead of `ref:` prefix. Use the SHA as ref -- gollum-lib accepts commit SHAs for `:ref`. |
| Bare repository (`--bare` flag) | HEAD file is at `<repo>/HEAD` not `<repo>/.git/HEAD`. Check `wiki_options[:repo_is_bare]` and adjust path. |
| `git config user.name` returns empty | Fall through to default gollum behavior (anonymous commit). Do not error. |
| `git config` not in PATH | Extremely unlikely in any environment running Gollum (which requires git). If it fails, let the backtick return empty string and fall through. |
| `.git` is a file (git worktree/submodule) | `.git` may contain `gitdir: /path/to/actual/git/dir`. For v1, this is acceptable to not support -- document as limitation. Workaround: use `git rev-parse --git-dir` if needed later. |
| Config file sets `track_current_branch` | Works naturally -- config file modifies `wiki_options` hash, same as CLI flag. No special handling needed. |

## Installation

No new dependencies to install. Both features use:
- Ruby stdlib (`File.read`, backtick operator)
- Existing gollum-lib APIs (`:ref` option, `:name`/`:email` commit options)
- Existing OptionParser patterns

## Sources

- `bin/gollum` lines 63-65: existing `--ref` flag pattern (LOCAL, HIGH confidence)
- `lib/gollum/app.rb` lines 720-721: `wiki_new` method creating `Gollum::Wiki.new` per request (LOCAL, HIGH confidence)
- `lib/gollum/app.rb` lines 724-736: `commit_options` method with author key documentation (LOCAL, HIGH confidence)
- `lib/gollum/app.rb` lines 279-281: `session['gollum.author']` usage for upload commits (LOCAL, HIGH confidence)
- `Gemfile.lock`: confirms gollum-lib 6.1.0, rjgit adapter (not rugged) (LOCAL, HIGH confidence)
- Git internals: `.git/HEAD` format is documented in `gitrepository-layout(5)` man page (TRAINING DATA, HIGH confidence -- this is core git, extremely stable)
- `git config` cascading: documented in `git-config(1)` man page (TRAINING DATA, HIGH confidence -- fundamental git feature)
