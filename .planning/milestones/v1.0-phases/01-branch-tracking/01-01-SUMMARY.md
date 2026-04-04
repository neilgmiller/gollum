---
phase: 01-branch-tracking
plan: 01
subsystem: cli
tags: [optparse, sinatra, cli-flags, validation, mutual-exclusion]

# Dependency graph
requires: []
provides:
  - "--track-current-branch CLI flag registration in OptionParser"
  - "Precious::App.validate_wiki_options! class method for mutual exclusion"
  - "cli_wiki_options snapshot pattern for source attribution"
  - "Test scaffold for branch tracking feature"
affects: [01-branch-tracking]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLI snapshot before config merge for source attribution"
    - "Class-level validation method on Precious::App for testability"

key-files:
  created:
    - test/test_branch_tracking.rb
  modified:
    - bin/gollum
    - lib/gollum/app.rb

key-decisions:
  - "Validation method on Precious::App class (not inline in bin/gollum) for testability"
  - "Use Kernel.exit(1) in validation method so tests can stub it with Mocha"
  - "Test default-absent behavior on plain hash rather than Sinatra class setting to avoid test ordering issues"

patterns-established:
  - "validate_wiki_options! pattern: class method accepting wiki_options and cli_wiki_options for conflict detection"
  - "capture_stderr helper in tests for validating error output"

requirements-completed: [BRANCH-01, BRANCH-03]

# Metrics
duration: 4min
completed: 2026-04-03
---

# Phase 01 Plan 01: CLI Flag and Mutual Exclusion Summary

**--track-current-branch CLI flag with mutual exclusion validation against --ref, source-attributed error messages, and 7-test scaffold**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-03T14:47:24Z
- **Completed:** 2026-04-03T14:51:17Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- Registered --track-current-branch flag in OptionParser that sets wiki_options[:track_current_branch] = true
- Added Precious::App.validate_wiki_options! class method that detects --ref / --track-current-branch conflicts
- Validation runs after config file loading and attributes conflict source (CLI vs config file) in error messages
- Created test scaffold with 7 tests covering flag registration, mutual exclusion, default non-conflict, and source attribution

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Test scaffold** - `246bdcf3` (test)
2. **Task 1 (GREEN): CLI flag + validation** - `2a338b4c` (feat)

_Note: TDD task with RED/GREEN commits_

## Files Created/Modified
- `bin/gollum` - Added --track-current-branch flag, cli_wiki_options snapshot, validation call
- `lib/gollum/app.rb` - Added validate_wiki_options! class method with source attribution
- `test/test_branch_tracking.rb` - 7 tests for flag, mutual exclusion, source attribution

## Decisions Made
- Placed validation method on Precious::App class rather than inline in bin/gollum script, enabling direct unit testing without subprocess execution
- Used Kernel.exit(1) rather than raise, matching existing gollum error patterns, while allowing Mocha stubs in tests
- Tested default-absent behavior on plain hash to avoid Sinatra class-level setting contamination between test contexts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Sinatra class-level `set(:wiki_options, ...)` persists across test contexts in random execution order, causing the "default does not include track_current_branch" test to see stale state. Fixed by testing the hash property directly rather than through Sinatra's accessor.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- CLI flag and validation foundation complete for Plan 02 (runtime HEAD resolution)
- validate_wiki_options! pattern established for any future option conflict detection
- Test scaffold ready to extend with runtime behavior tests

---
*Phase: 01-branch-tracking*
*Completed: 2026-04-03*
