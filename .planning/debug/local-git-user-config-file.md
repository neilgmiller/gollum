---
status: diagnosed
trigger: "local_git_user works via CLI flag but fails when set via config file"
created: 2026-04-03T00:00:00Z
updated: 2026-04-03T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - both startup message and resolve_local_git_user use --local flag which only reads repo-level .git/config, not ~/.gitconfig
test: Compare git config flags used in bin/gollum and lib/gollum/app.rb
expecting: Both use --local which skips global/system config
next_action: Report diagnosis

## Symptoms

expected: When `local_git_user` is set via config file, Gollum should read user.name/email from git config (including ~/.gitconfig) and use them for commits
actual: Startup log shows "WARNING: git config user.name/email not set -- will use Gollum defaults" even though ~/.gitconfig has user.name and user.email set. Commits are made as anonymous user.
errors: "WARNING: git config user.name/email not set -- will use Gollum defaults"
reproduction: Set `Precious::App.settings.wiki_options[:local_git_user] = true` in config file, ensure user.name/email are in ~/.gitconfig but NOT in repo-local .git/config, start Gollum
started: Since local_git_user feature was implemented

## Eliminated

(none needed -- root cause found on first hypothesis)

## Evidence

- timestamp: 2026-04-03T00:00:00Z
  checked: bin/gollum lines 320-328 (startup message for local_git_user)
  found: |
    Uses `git -C <path> config --local --get user.name` and `git -C <path> config --local --get user.email`.
    The `--local` flag restricts git to ONLY read the repo-level .git/config file. It will NOT read
    ~/.gitconfig (global) or /etc/gitconfig (system). If user.name/email are set globally but not in
    the repo's local config, this returns empty strings, triggering the warning.
  implication: The startup warning is a false negative -- user.name/email ARE configured, just not at the --local level

- timestamp: 2026-04-03T00:00:00Z
  checked: lib/gollum/app.rb lines 775-784 (resolve_local_git_user method)
  found: |
    Same bug: uses `git -C <path> config --local --get user.name` and `--local --get user.email`.
    This is the method called in the `before` filter (line 144) to actually resolve the author for commits.
    Because --local skips global config, it returns nil when user.name/email are only in ~/.gitconfig,
    so the session['gollum.author'] is never set, and commits fall through to Gollum defaults.
  implication: This is why commits are made as anonymous -- resolve_local_git_user returns nil

- timestamp: 2026-04-03T00:00:00Z
  checked: How --local-git-user CLI flag path differs
  found: |
    The CLI flag sets wiki_options[:local_git_user] = true at line 75 of bin/gollum. Both paths
    (CLI and config file) end up with the same wiki_options hash and hit the same startup message
    code (lines 320-328) and the same resolve_local_git_user method (lines 775-784). The --local
    flag bug affects BOTH paths equally. If the CLI flag "works," it's because the test repo has
    user.name/email set in its local .git/config, OR the user is testing under different conditions.
    
    HOWEVER: if the user reports CLI works and config doesn't, the actual difference may be in
    testing conditions. Both code paths use identical --local flag logic. The bug is the same
    regardless of how the option is set.
  implication: The --local flag is the universal bug; it affects both CLI and config-file paths

## Resolution

root_cause: |
  Both `bin/gollum` (lines 321-322) and `lib/gollum/app.rb` (`resolve_local_git_user`, lines 777-778)
  use `git config --local --get` to read user.name and user.email. The `--local` flag restricts git
  to ONLY read the repository's `.git/config` file, ignoring `~/.gitconfig` (global) and
  `/etc/gitconfig` (system). When users have their name/email configured globally (the common case),
  `--local` returns empty strings, causing:
  
  1. A false warning at startup ("git config user.name/email not set")
  2. `resolve_local_git_user` returning nil, so commits use Gollum defaults instead of the real user
  
  The feature's name "local git user" means "use the LOCAL machine's git user" -- not "use the
  repo-local git config." The `--local` flag is semantically wrong for the feature's intent.

fix: |
  Remove the `--local` flag from all four `git config` calls (2 in bin/gollum, 2 in lib/gollum/app.rb).
  
  In `bin/gollum` lines 321-322, change:
    `git -C <path> config --local --get user.name`  -->  `git -C <path> config --get user.name`
    `git -C <path> config --local --get user.email`  -->  `git -C <path> config --get user.email`
  
  In `lib/gollum/app.rb` lines 777-778 (resolve_local_git_user), change:
    `git -C <path> config --local --get user.name`  -->  `git -C <path> config --get user.name`
    `git -C <path> config --local --get user.email`  -->  `git -C <path> config --get user.email`
  
  Without `--local`, git follows its normal resolution order: local -> global -> system.
  This means it will find user.name/email from ~/.gitconfig if not set in the repo's local config,
  which is the correct behavior for this feature.

verification: N/A (diagnosis only)
files_changed:
  - bin/gollum (lines 321-322)
  - lib/gollum/app.rb (lines 777-778, resolve_local_git_user method)
