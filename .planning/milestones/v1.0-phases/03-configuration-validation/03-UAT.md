---
status: diagnosed
phase: 03-configuration-validation
source: [03-01-SUMMARY.md]
started: 2026-04-04T03:00:00Z
updated: 2026-04-04T03:25:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Config File track_current_branch Parity
expected: Create a config.rb with `Precious::App.settings.wiki_options[:track_current_branch] = true`. Start Gollum with `-c config.rb` (no `--track-current-branch` CLI flag). The wiki should serve the currently checked-out branch, same as if you had passed `--track-current-branch` on CLI.
result: pass

### 2. Config File local_git_user Parity
expected: Create a config.rb with `Precious::App.settings.wiki_options[:local_git_user] = true`. Start Gollum with `-c config.rb` (no `--local-git-user` CLI flag). Edit a page via the web UI. The commit author should be your local git config's user.name/user.email, same as if you had passed `--local-git-user` on CLI.
result: issue
reported: "Logs show 'Gollum running with local-git-user (WARNING: git config user.name/email not set -- will use Gollum defaults)' but user name & email are set in ~/.gitconfig"
severity: major

### 3. Both Features via Config File Only
expected: Create a config.rb setting both `track_current_branch` and `local_git_user` to true. Start Gollum with `-c config.rb` and no feature CLI flags. Both features should work: wiki serves checked-out branch AND commits use local git user.
result: issue
reported: "Same error as before, commit is made as anonymous user"
severity: major

### 4. Cross-Source Conflict: CLI ref + Config track_current_branch
expected: Create a config.rb with `Precious::App.settings.wiki_options[:track_current_branch] = true`. Start Gollum with `-c config.rb --ref main`. Gollum should exit with an error about `--ref` and `--track-current-branch` being mutually exclusive.
result: pass

### 5. Config-Only Conflict: ref + track_current_branch in Config
expected: Create a config.rb that sets both `wiki_options[:ref] = 'main'` and `wiki_options[:track_current_branch] = true`. Start Gollum with `-c config.rb` (no CLI flags). Gollum should exit with the mutual exclusion error, catching the conflict even though both came from the config file.
result: pass

### 6. Startup Summary in Development Mode
expected: Start Gollum in development mode with `--track-current-branch`. The startup output should include a summary line showing active features with source attribution, like `track-current-branch: ON (CLI)`.
result: pass

## Summary

total: 6
passed: 4
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "Config file local_git_user produces identical behavior to CLI flag — commit author uses local git config user.name/user.email"
  status: failed
  reason: "User reported: Logs show 'Gollum running with local-git-user (WARNING: git config user.name/email not set -- will use Gollum defaults)' but user name & email are set in ~/.gitconfig"
  severity: major
  test: 2
  root_cause: "git config calls in bin/gollum:321-322 and lib/gollum/app.rb:777-778 use --local flag, which only reads repo-level .git/config and ignores ~/.gitconfig (global). Most users set name/email globally."
  artifacts:
    - path: "bin/gollum"
      issue: "Lines 321-322: startup diagnostic git config calls use --local flag"
    - path: "lib/gollum/app.rb"
      issue: "Lines 777-778: resolve_local_git_user git config calls use --local flag"
  missing:
    - "Remove --local flag from all four git config invocations so git follows normal resolution order (local -> global -> system)"
  debug_session: ".planning/debug/local-git-user-config-file.md"

- truth: "Both features set via config file only — commits use local git user"
  status: failed
  reason: "User reported: Same error as before, commit is made as anonymous user"
  severity: major
  test: 3
  root_cause: "Same root cause as test 2 — --local flag on git config calls prevents reading ~/.gitconfig"
  artifacts:
    - path: "bin/gollum"
      issue: "Lines 321-322: startup diagnostic git config calls use --local flag"
    - path: "lib/gollum/app.rb"
      issue: "Lines 777-778: resolve_local_git_user git config calls use --local flag"
  missing:
    - "Remove --local flag from all four git config invocations"
  debug_session: ".planning/debug/local-git-user-config-file.md"
