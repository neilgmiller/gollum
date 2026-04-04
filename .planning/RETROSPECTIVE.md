# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Gollum Configuration Enhancements

**Shipped:** 2026-04-04
**Phases:** 3 | **Plans:** 5

### What Was Built
- `--track-current-branch` — dynamic branch following via per-request HEAD resolution
- `--local-git-user` — per-commit git config resolution for web edit attribution
- Config file parity and cross-source mutual exclusion validation
- 37 new tests across 3 test files (201 total suite)

### What Worked
- Phase ordering (branch tracking → local git user → config validation) gave clean dependency chain
- Single integration point per phase kept plans small and focused
- Audit caught Nyquist compliance gap in Phase 03 before milestone completion
- Gap closure pattern (03-02) cleanly handled the `--local` flag bug found during UAT

### What Was Inefficient
- Phase 03 Plan 01 took 27min (5x other plans) due to Sinatra's hash-merging `set` method requiring Hash#replace workaround
- One-liner fields not populated in SUMMARY.md frontmatter — had to read full summaries for accomplishment extraction

### Patterns Established
- `cli_wiki_options` snapshot before config load for source attribution in error messages
- `Hash#replace` for Sinatra settings teardown in tests
- `GIT_CONFIG_GLOBAL` env var for git config test isolation
- Class-level validation methods on Precious::App for testability

### Key Lessons
1. UAT is essential even for "simple" phases — the `--local` flag bug in git config calls was invisible to unit tests
2. Config file testing requires `load` not `require` (Ruby caches `require`)
3. Per-request resolution (HEAD reads, git config calls) is simpler and more correct than caching with invalidation

### Cost Observations
- Model mix: primarily opus for execution and research
- Timeline: 2 days for full milestone (project init through audit)
- Notable: 5 plans averaged ~8min each, with Phase 03 Plan 01 as outlier

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 3 | 5 | Baseline — established GSD workflow for Gollum |

### Cumulative Quality

| Milestone | New Tests | Total Suite | Zero-Dep Additions |
|-----------|-----------|-------------|-------------------|
| v1.0 | 37 | 201 | 1 (shellwords) |

### Top Lessons (Verified Across Milestones)

1. UAT catches integration bugs that unit tests miss — always run UAT before milestone completion
2. Per-request resolution beats caching for correctness in request-scoped state
