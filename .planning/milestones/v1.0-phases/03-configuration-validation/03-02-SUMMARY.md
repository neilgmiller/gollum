---
phase: 03-configuration-validation
plan: 02
subsystem: auth
tags: [git-config, local-git-user, global-config, fallback]

# Dependency graph
requires:
  - phase: 02-local-git-user
    provides: local_git_user feature with git config integration
  - phase: 03-01
    provides: config validation tests and UAT diagnosis of --local flag bug
provides:
  - git config resolution using normal order (local -> global -> system)
  - regression test proving global-only config is resolved
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GIT_CONFIG_GLOBAL env var for test isolation from real user config"

key-files:
  created: []
  modified:
    - bin/gollum
    - lib/gollum/app.rb
    - test/test_local_git_user.rb

key-decisions:
  - "Used GIT_CONFIG_GLOBAL env var to isolate tests from real global git config"

patterns-established:
  - "GIT_CONFIG_GLOBAL isolation: tests that need empty git identity use a temp empty file as GIT_CONFIG_GLOBAL"

requirements-completed: [CONF-01]

# Metrics
duration: 2min
completed: 2026-04-04
---

# Phase 03 Plan 02: Gap Closure Summary

**Removed --local flag from git config calls so resolve_local_git_user falls through to global/system config**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-04T16:24:32Z
- **Completed:** 2026-04-04T16:26:43Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Removed 4 `--local` flags from git config calls (2 in bin/gollum, 2 in lib/gollum/app.rb)
- Added regression test proving global-only git config is resolved by resolve_local_git_user
- Fixed 2 existing tests that were leaking real global git config after --local removal

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove --local flag from git config calls** - `955ca589` (fix)
2. **Task 2: Add regression test for global-only git config resolution** - `73ffab34` (test)

## Files Created/Modified
- `bin/gollum` - Removed --local from startup diagnostic git config calls
- `lib/gollum/app.rb` - Removed --local from resolve_local_git_user git config calls
- `test/test_local_git_user.rb` - Added global config test, fixed test isolation with GIT_CONFIG_GLOBAL

## Decisions Made
- Used GIT_CONFIG_GLOBAL env var to isolate tests from real ~/.gitconfig -- this lets tests control global config without touching the developer's actual config file

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed existing tests leaking real global git config**
- **Found during:** Task 2 (regression test)
- **Issue:** After removing --local, two existing tests ("returns nil when empty" and "partial config fallback") started reading the developer's real ~/.gitconfig, causing false failures
- **Fix:** Wrapped those tests with GIT_CONFIG_GLOBAL pointing to an empty temp file to isolate from real global config
- **Files modified:** test/test_local_git_user.rb
- **Verification:** All 11 tests pass, 12 config validation tests pass
- **Committed in:** 73ffab34 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary correction -- removing --local inherently changes test behavior when developer has global git config. No scope creep.

## Issues Encountered
None beyond the deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three phases complete: branch tracking, local git user, and configuration validation
- All 23 tests pass (11 local_git_user + 12 config_validation)
- The --local flag bug from UAT is fully resolved

---
## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 03-configuration-validation*
*Completed: 2026-04-04*
