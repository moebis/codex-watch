---
status: active
owner: project-maintainer
created_at: 2026-07-19
last_verified_commit: 018225f
---

# Codex Watch change harness

## Purpose

The harness protects the menu bar behavior, quota meaning, credential boundary, and release integrity. Passing compilation alone is not completion.

## Authority order

1. Active contracts in `docs/contracts/behavior-contracts.yaml`.
2. Active architecture decisions in `docs/decisions/`.
3. `ARCHITECTURE.md` and `docs/PROJECT_MEMORY.md`.
4. Tests and verification scripts.
5. Current implementation and configuration.
6. README and historical Git records.

## Risk levels

- **L0:** Documentation or comments only.
- **L1:** Local implementation with no user-visible or security effect.
- **L2:** Menu bar UI, quota semantics, settings, or packaging.
- **L3:** Authentication, privacy, external endpoints, signing, tagging, or public release.

For L1 and above, state the observable change, preserved contracts, excluded work, risk, and verification plan before editing.

## Implementation rules

1. Inspect the worktree before editing and preserve unrelated changes.
2. Add an outcome-oriented regression guard for a changed behavior.
3. Do not remove a valid regression test to accommodate a broken implementation.
4. Never log or persist tokens, Authorization headers, raw usage responses, prompts, or conversation metadata.
5. Do not restore notch windows or session-log monitoring without explicitly superseding the active contracts.
6. Do not add a new network host, dependency, telemetry, updater, or background persistence without L3 review.
7. Push, tag, or publish only when the user explicitly requests it.
8. Keep local and remote reads bounded while consuming bytes; metadata or `Content-Length` checks alone are not sufficient.
9. Keep filesystem work off the main actor and preserve explicit actor/sendability ownership.
10. Mark retained capability data stale whenever current authentication or refresh trust is lost.
11. Treat Codex app-server messages as untrusted bounded input, ignore private account fields, and keep the experimental-command compatibility fallback independent.
12. Require explicit user intent for notifications, Launch at Login, clipboard diagnostics, CSV export, and reset-credit consumption.

## Verification entry points

| Level | Command | Purpose |
|---|---|---|
| Contracts | `./scripts/check_contracts.sh` | Validate contract structure |
| Release scripts | `./scripts/test_release_scripts.sh` | Guard build count, isolated archive extraction, exact verification target, cleanup, and portable checksum output |
| Fast | `swift test` | Run deterministic tests |
| Full | `./scripts/verify.sh /private/tmp/codex-watch-verify` | Test, build, and inspect the app bundle outside synced storage |
| Release prerequisites | `./scripts/check_release.sh` | Contracts, release-script regressions, and strict-concurrency compilation before packaging |
| Release | `./scripts/release.sh /private/tmp/codex-watch-release` | Produce a verified ZIP and SHA-256 file outside synced storage |
| Concurrency | `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency -Xswiftc -warnings-as-errors` | Enforce actor and sendability boundaries |
| Memory | `swift test --sanitize=address` | Detect covered memory-safety failures |
| Races | `swift test --sanitize=thread` | Detect covered data races |

The menu bar icon, percentage spacing, dropdown behavior, and first-launch Gatekeeper flow still require validation on a real Mac.

File Provider and other sync services can reattach Finder metadata to a bundle after cleanup. Keep signing output outside those paths rather than weakening signature verification.

## Documentation lifecycle

Keep only current authority in the working tree. Consolidate durable lessons into architecture, project memory, active contracts, or active decisions, then remove completed plans and superseded design documents. Git history preserves historical implementation detail.
