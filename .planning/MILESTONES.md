# Milestones

## v1.0 Gollum Configuration Enhancements (Shipped: 2026-04-04)

**Phases completed:** 3 phases, 5 plans, 0 tasks

**Key accomplishments:**

- `--track-current-branch` CLI flag with mutual exclusion against `--ref`
- Per-request HEAD resolution for dynamic branch following without restart
- Detached HEAD detection with automatic read-only editing toggle
- `--local-git-user` CLI flag with per-commit git config resolution
- Config file parity — both features work identically via CLI or config file
- Cross-source mutual exclusion catches conflicts from any configuration source

**Stats:**
- Files modified: 5 (682 insertions, 3 deletions)
- Tests: 37 new tests (201 total suite)
- Timeline: 2 days (2026-04-03 → 2026-04-04)
- Git range: `feat(01-01)` → `feat(03-01)`

---
