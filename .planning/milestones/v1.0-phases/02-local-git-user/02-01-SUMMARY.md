---
phase: 02-local-git-user
plan: 01
subsystem: auth
tags: [git-config, sinatra, before-filter, cli, shellwords]

requires:
  - phase: 01-branch-tracking
    provides: before filter pattern, resolve_current_branch helper, CLI flag pattern, test infrastructure
provides:
  - resolve_local_git_user helper in app.rb
  - before filter session injection for write requests
  - --local-git-user CLI flag
  - startup message showing git identity
  - 10 tests covering USER-01, USER-02, USER-03
affects: [03-config-validation]

tech-stack:
  added: [shellwords]
  patterns: [local git config resolution via shell-out, session injection before filter]

key-files:
  created: [test/test_local_git_user.rb]
  modified: [lib/gollum/app.rb, bin/gollum]

key-decisions:
  - "Used --local flag with git config to read only repo-local config, not global/system"
  - "All-or-nothing fallback: both name and email must be present, otherwise nil"

patterns-established:
  - "Session injection pattern: before filter sets session['gollum.author'] on non-GET requests"
  - "Git config shell-out pattern: Shellwords.escape + backtick with git -C for repo-scoped commands"

requirements-completed: [USER-01, USER-02, USER-03]

duration: 5min
completed: 2026-04-03
---

# Phase 2 Plan 1: Local Git User Summary

**--local-git-user feature with before filter session injection, git config resolution helper, CLI flag, and startup message**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-03T17:07:13Z
- **Completed:** 2026-04-03T17:12:28Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Web edits and uploads attributed to local git config user.name/email when --local-git-user enabled
- Git config read fresh on each write request (no caching), supporting identity changes without restart
- Missing or partial git config falls back gracefully to Gollum defaults
- Session author from rack middleware takes priority over local git user
- CLI flag --local-git-user with startup message showing identity or warning

## Task Commits

Each task was committed atomically:

1. **Task 1: Before filter session injection and resolve_local_git_user helper** - `41500fff` (feat)
2. **Task 2: CLI flag registration and startup message** - `d536d107` (feat)

## Files Created/Modified
- `test/test_local_git_user.rb` - 10 tests covering all 3 requirements (USER-01, USER-02, USER-03)
- `lib/gollum/app.rb` - resolve_local_git_user helper + before filter session injection + require shellwords
- `bin/gollum` - --local-git-user CLI flag + startup message + require shellwords

## Decisions Made
- Used `--local` flag with `git config` to read only repo-local config, avoiding global/system config bleed-through. This ensures the feature reflects the repo's own identity, not the machine's global settings.
- All-or-nothing fallback: if either user.name or user.email is missing from local config, the helper returns nil and Gollum defaults are used (no partial author data).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used --local flag for git config reads**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Plan specified `git config --get` which reads all config levels (local, global, system). Tests failed because global git config was picked up when local config was unset.
- **Fix:** Changed to `git config --local --get` in both resolve_local_git_user helper and bin/gollum startup message
- **Files modified:** lib/gollum/app.rb, bin/gollum
- **Verification:** All 10 tests pass, including missing-config fallback tests
- **Committed in:** 41500fff (Task 1), d536d107 (Task 2)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential for correctness -- without --local flag, missing-config tests fail due to global git config bleed-through.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Local git user feature complete, ready for Phase 03 config validation
- wiki_options[:local_git_user] key established for config file support
- Pattern matches Phase 01's track_current_branch for validation integration

---
*Phase: 02-local-git-user*
*Completed: 2026-04-03*
