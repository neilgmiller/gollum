# Phase 3: Configuration Validation - Research

**Researched:** 2026-04-03
**Domain:** Ruby config file loading, wiki_options validation, Minitest testing
**Confidence:** HIGH

## Summary

Phase 3 is primarily a **testing and verification phase** with one small new feature (verbose-mode startup summary). The core functionality -- config file loading, wiki_options merging, mutual exclusion validation, and cli_wiki_options snapshot -- already exists and works. The job is to (1) prove via end-to-end tests that config file settings produce identical behavior to CLI flags, (2) prove that mutual exclusion catches conflicts from any source combination, and (3) add a verbose-mode startup summary showing active features with source attribution.

The existing test infrastructure uses Minitest with a custom `context/test` DSL (defined in `test/helper.rb`), Mocha for mocking, and Rack::Test for HTTP integration. Config file testing requires writing temporary `.rb` files, then exercising the real `require cfg` + `wiki_options = Precious::App.wiki_options` reload path from `bin/gollum`. The startup summary feature needs a mechanism to detect verbose mode -- `bin/gollum` currently has no `--verbose` flag, so the simplest approach is checking Sinatra's environment or adding an environment variable.

**Primary recommendation:** Write one new test file (`test/test_config_validation.rb`) covering config file parity and cross-source conflict detection using real temp config files, then add the verbose startup summary near `bin/gollum:306-328`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Keep validation focused on the two features we built (track_current_branch and local_git_user) -- no expanded scope
- CONF-02: The existing `validate_wiki_options!` already runs after config file loading. Phase 3 tests that this works correctly rather than rebuilding the logic
- No defensive validation (unknown keys, typo detection, type checking) -- beyond CONF-01/CONF-02 scope
- Use `cli_wiki_options` snapshot to detect cross-source conflicts -- this mechanism already exists from Phase 1
- Test that config-only conflicts (both ref and track_current_branch set in config.rb, no CLI) are caught by existing validation
- Config file overrides of CLI flags are acceptable as long as mutual exclusion is enforced
- Use real config file loading (write temp .rb files, require them, reload wiki_options) to prove the actual mechanism works end-to-end
- Feature parity matrix: for each feature, test that setting via config.rb produces same runtime behavior as the equivalent CLI flag
- Test both features set together via config.rb (no CLI flags)
- No simulation/mocking of config file loading -- test the real code path
- Add a verbose-mode-only startup summary showing active features and their source
- Format: "track-current-branch: ON (config file), local-git-user: ON (CLI)" -- include source attribution
- Only prints in verbose/debug mode -- silent in production and when no features are active
- Complements existing per-feature startup messages (those remain as-is)

### Claude's Discretion
- How to detect verbose mode in bin/gollum (environment variable, flag, or Sinatra setting)
- Exact placement of startup summary relative to existing feature startup messages
- Whether to use a single summary line or multiple lines for clarity
- Test file organization (single test file or split by concern)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONF-01 | Both options work identically whether set via config file or CLI flags | Config file parity testing pattern using temp .rb files + real require path; feature parity matrix tests |
| CONF-02 | Mutual exclusion validation runs after config file loading | validate_wiki_options! at bin/gollum:304 already runs post-config-load; tests prove CLI-vs-config and config-vs-config conflicts are caught |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| minitest | (bundled with Ruby) | Test framework | Already used by all Gollum tests |
| mocha | (in Gemfile) | Mocking (Kernel.exit stubs) | Already used in test_branch_tracking.rb |
| rack-test | (in Gemfile) | HTTP integration testing | Already used in all Gollum integration tests |
| shoulda | (in Gemfile) | Context/test DSL extensions | Already used via helper.rb |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tmpdir | (stdlib) | Temp directories for config files | Config file parity tests |
| tempfile | (stdlib) | Temp .rb config files | Writing test config files |
| fileutils | (stdlib) | Cleanup temp files | Test teardown |
| stringio | (stdlib) | Capture $stderr output | Startup message tests |

No new dependencies needed. Everything is already available in the project.

## Architecture Patterns

### Config File Loading Path (the critical path being tested)

```
bin/gollum flow:
1. OptionParser sets wiki_options hash from CLI flags
2. Precious::App.set(:wiki_options, wiki_options)     [line 291]
3. cli_wiki_options = wiki_options.dup                  [line 293]
4. require cfg (config file modifies App.wiki_options)  [line 295-299]
5. wiki_options = Precious::App.wiki_options (reload)   [line 301]
6. validate_wiki_options!(wiki_options, cli_wiki_options) [line 304]
7. Per-feature startup messages to $stderr               [line 306-328]
```

### Pattern: Real Config File Testing

**What:** Write a temp `.rb` file that modifies `Precious::App.settings.wiki_options`, then `require` it and verify behavior.
**When to use:** All CONF-01 and CONF-02 tests.
**Example:**
```ruby
# Write a temp config file
config_content = <<~RUBY
  Precious::App.settings.wiki_options[:track_current_branch] = true
RUBY
config_file = File.join(Dir.mktmpdir, 'test_config.rb')
File.write(config_file, config_content)

# Simulate the bin/gollum config loading path
Precious::App.set(:wiki_options, { allow_editing: true })
cli_wiki_options = Precious::App.wiki_options.dup
require config_file
wiki_options = Precious::App.wiki_options

# Now validate and/or test behavior
Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
assert_equal true, wiki_options[:track_current_branch]
```

### Pattern: Source Attribution Detection

**What:** Compare `cli_wiki_options` (snapshot before config load) with final `wiki_options` (after config load) to determine where each option came from.
**Example:**
```ruby
# CLI set track_current_branch, config file set ref
cli_wiki_options = { track_current_branch: true }
wiki_options = { track_current_branch: true, ref: 'main' }  # ref came from config

# validate_wiki_options! uses this to attribute sources:
ref_source = cli_wiki_options.key?(:ref) ? "CLI (--ref)" : "config file"
# => "config file"
```

### Pattern: Startup Summary (Verbose Mode)

**What:** After per-feature messages, print a summary showing all active features and their source.
**Recommended detection:** Use `ENV['GOLLUM_VERBOSE']` or check `Precious::App.environment == :development`. The environment approach requires no new flags and works naturally -- development mode is where debugging happens.

**Recommendation for verbose detection:** Check `Precious::App.environment == :development`. This is the cleanest approach because:
1. No new CLI flags needed
2. Sinatra already has this concept (`APP_ENV=development`)
3. Development mode is when users want verbose output
4. Already set at bin/gollum:289: `Precious::App.set(:environment, ENV.fetch('APP_ENV', :production).to_sym)`

**Example placement (after line 328 in bin/gollum):**
```ruby
if Precious::App.environment == :development
  features = []
  if wiki_options[:track_current_branch]
    src = cli_wiki_options.key?(:track_current_branch) ? "CLI" : "config file"
    features << "track-current-branch: ON (#{src})"
  end
  if wiki_options[:local_git_user]
    src = cli_wiki_options.key?(:local_git_user) ? "CLI" : "config file"
    features << "local-git-user: ON (#{src})"
  end
  unless features.empty?
    $stderr.puts "Active features: #{features.join(', ')}"
  end
end
```

### Anti-Patterns to Avoid
- **Mocking config file loading:** The user explicitly requires real `require` + reload -- no stubbing wiki_options directly for config parity tests
- **Testing validate_wiki_options! in isolation only:** That is already done in test_branch_tracking.rb. Phase 3 tests the full flow: config file sets options, validation catches conflicts
- **Modifying validate_wiki_options!:** The existing implementation is correct. Phase 3 proves it works, not rebuilds it

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config file loading simulation | Custom config parser | Real `require` + `Precious::App.wiki_options` reload | Must prove the actual code path works |
| Source attribution logic | New tracking mechanism | Existing `cli_wiki_options` snapshot comparison | Already built in Phase 1 |
| Mutual exclusion validation | New validation rules | Existing `validate_wiki_options!` | Already handles all cases correctly |
| Temp file management | Manual file tracking | `Dir.mktmpdir` + `FileUtils.rm_rf` in teardown | Ruby stdlib handles cleanup correctly |

## Common Pitfalls

### Pitfall 1: Config File Require Caching
**What goes wrong:** Ruby's `require` only loads a file once. If you `require` the same temp config file path twice in different tests, the second load is a no-op.
**Why it happens:** Ruby caches required file paths in `$LOADED_FEATURES`.
**How to avoid:** Use unique file paths for each test (different tmpdir), or use `load` instead of `require`. Alternatively, remove the path from `$LOADED_FEATURES` after each test.
**Warning signs:** Tests pass individually but fail when run together; second test sees stale wiki_options.

### Pitfall 2: Wiki Options State Leaking Between Tests
**What goes wrong:** `Precious::App.wiki_options` is class-level state that persists across tests.
**Why it happens:** Minitest runs tests in the same process. `Precious::App.set(:wiki_options, ...)` is global.
**How to avoid:** Always reset wiki_options in teardown: `Precious::App.set(:wiki_options, { allow_editing: true })`. This pattern is already used in existing tests.
**Warning signs:** Tests pass in isolation, fail in full suite.

### Pitfall 3: Config File Path Must Be Absolute for require
**What goes wrong:** `require` with a relative path may not find the file, or may resolve relative to `$LOAD_PATH` entries.
**Why it happens:** Ruby `require` searches `$LOAD_PATH`; only `require` with absolute path or `./` prefix is deterministic.
**How to avoid:** Use `File.join(Dir.mktmpdir(...), 'config.rb')` which produces an absolute path. Or use `load` with an absolute path.

### Pitfall 4: $stderr Capture Interference
**What goes wrong:** Multiple features printing to `$stderr` in the same test makes assertions fragile.
**Why it happens:** Startup messages, validation errors, and the new summary all write to `$stderr`.
**How to avoid:** Use the `capture_stderr` pattern already established in test_branch_tracking.rb (swap `$stderr` with `StringIO.new`). Assert with `assert_match` for specific content rather than exact string equality.

## Code Examples

### Test: Config File Sets track_current_branch Identically to CLI
```ruby
test "config file track_current_branch produces same behavior as CLI flag" do
  # Config file approach
  config_content = <<~RUBY
    Precious::App.settings.wiki_options[:track_current_branch] = true
  RUBY
  config_file = File.join(@tmpdir, 'tcb_config.rb')
  File.write(config_file, config_content)

  Precious::App.set(:wiki_options, { allow_editing: true })
  cli_wiki_options = Precious::App.wiki_options.dup
  load config_file
  wiki_options = Precious::App.wiki_options

  assert_equal true, wiki_options[:track_current_branch]
  # Verify it works: GET a page, should resolve from HEAD
  get '/A'
  assert last_response.ok?
end
```

### Test: Cross-Source Conflict (CLI ref + Config track_current_branch)
```ruby
test "CLI ref conflicts with config file track_current_branch" do
  config_content = <<~RUBY
    Precious::App.settings.wiki_options[:track_current_branch] = true
  RUBY
  config_file = File.join(@tmpdir, 'conflict_config.rb')
  File.write(config_file, config_content)

  # Simulate CLI setting ref
  Precious::App.set(:wiki_options, { allow_editing: true, ref: 'main' })
  cli_wiki_options = Precious::App.wiki_options.dup
  load config_file
  wiki_options = Precious::App.wiki_options

  Kernel.expects(:exit).with(1).once
  err = capture_stderr do
    Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
  end
  assert_match(/mutually exclusive/, err)
  assert_match(/CLI \(--ref\)/, err)          # ref from CLI
  assert_match(/config file/, err)             # track_current_branch from config
end
```

### Test: Both Features via Config File Only
```ruby
test "both features set via config file work together" do
  config_content = <<~RUBY
    Precious::App.settings.wiki_options[:track_current_branch] = true
    Precious::App.settings.wiki_options[:local_git_user] = true
  RUBY
  config_file = File.join(@tmpdir, 'both_config.rb')
  File.write(config_file, config_content)

  Precious::App.set(:wiki_options, { allow_editing: true })
  cli_wiki_options = Precious::App.wiki_options.dup
  load config_file
  wiki_options = Precious::App.wiki_options

  assert_equal true, wiki_options[:track_current_branch]
  assert_equal true, wiki_options[:local_git_user]

  # No conflict -- should not exit
  err = capture_stderr do
    Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
  end
  assert_equal '', err
end
```

### Startup Summary Implementation
```ruby
# In bin/gollum, after line 328 (after existing per-feature messages)
if Precious::App.environment == :development
  features = []
  if wiki_options[:track_current_branch]
    src = cli_wiki_options.key?(:track_current_branch) ? "CLI" : "config file"
    features << "track-current-branch: ON (#{src})"
  end
  if wiki_options[:local_git_user]
    src = cli_wiki_options.key?(:local_git_user) ? "CLI" : "config file"
    features << "local-git-user: ON (#{src})"
  end
  $stderr.puts "Active features: #{features.join(', ')}" unless features.empty?
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Test config by stubbing wiki_options | Test with real config file require | Phase 3 decision | Proves actual code path works |
| No source attribution | cli_wiki_options snapshot comparison | Phase 1 | Enables cross-source conflict messages |

## Open Questions

1. **`load` vs `require` for test config files**
   - What we know: Ruby's `require` caches files; `load` always re-executes. `bin/gollum` uses `require cfg`.
   - What's unclear: Whether tests should use `load` (avoids caching) or `require` (matches production) with `$LOADED_FEATURES` cleanup.
   - Recommendation: Use `load` in tests for reliability. The difference between `load` and `require` is only caching -- the execution semantics are identical for this use case. Add a comment explaining why.

2. **Verbose mode detection mechanism**
   - What we know: No `--verbose` flag exists. Sinatra environment is set via `APP_ENV` (defaults to `:production`).
   - What's unclear: Whether users would prefer `GOLLUM_VERBOSE=1` env var or `APP_ENV=development`.
   - Recommendation: Use `Precious::App.environment == :development` -- it requires no new flags, works naturally, and the startup summary is useful info during development. Document this in the startup summary code comment.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Minitest with custom context/test DSL |
| Config file | test/helper.rb |
| Quick run command | `rake test TEST=test/test_config_validation.rb` |
| Full suite command | `rake test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONF-01 | Config file track_current_branch == CLI behavior | integration | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| CONF-01 | Config file local_git_user == CLI behavior | integration | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| CONF-01 | Both features via config file only | integration | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| CONF-02 | CLI ref + config track_current_branch conflict | unit | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| CONF-02 | Config ref + CLI track_current_branch conflict | unit | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| CONF-02 | Both ref + track_current_branch in config file conflict | unit | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |
| N/A | Startup summary in development mode | unit | `rake test TEST=test/test_config_validation.rb` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `rake test TEST=test/test_config_validation.rb`
- **Per wave merge:** `rake test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_config_validation.rb` -- all CONF-01 and CONF-02 tests (new file)
- No framework install needed -- Minitest and all dependencies already present

## Sources

### Primary (HIGH confidence)
- `bin/gollum` lines 282-328 -- actual config loading, validation, and startup message code
- `lib/gollum/app.rb` lines 87-98 -- validate_wiki_options! implementation
- `test/helper.rb` -- test framework setup, context/test DSL, capture_stderr helper
- `test/test_branch_tracking.rb` -- existing validation test patterns (5 mutual exclusion tests)
- `test/test_local_git_user.rb` -- existing local_git_user test patterns (10 tests)

### Secondary (MEDIUM confidence)
- Ruby `require` vs `load` semantics -- well-documented Ruby stdlib behavior

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already in use, no new dependencies
- Architecture: HIGH -- code paths are well-understood from Phase 1 and 2 implementation
- Pitfalls: HIGH -- based on direct code inspection of require caching and state management
- Test patterns: HIGH -- directly derived from existing test files in the project

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- no external dependencies or fast-moving APIs)
