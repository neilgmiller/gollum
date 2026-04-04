---
phase: 3
slug: configuration-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Minitest with custom context/test DSL |
| **Config file** | test/helper.rb |
| **Quick run command** | `rake test TEST=test/test_config_validation.rb` |
| **Full suite command** | `rake test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `rake test TEST=test/test_config_validation.rb`
- **After every plan wave:** Run `rake test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CONF-01 | integration | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | CONF-01 | integration | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | CONF-01 | integration | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-04 | 01 | 1 | CONF-02 | unit | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-05 | 01 | 1 | CONF-02 | unit | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-06 | 01 | 1 | CONF-02 | unit | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |
| 03-01-07 | 01 | 1 | N/A | unit | `rake test TEST=test/test_config_validation.rb` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_config_validation.rb` — stubs for CONF-01, CONF-02, and startup summary tests

*Existing infrastructure covers framework and fixtures — only the new test file is needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Startup summary visible in terminal | N/A | Visual formatting check | Run `bin/gollum` in development mode, verify feature summary displays with source attribution |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
