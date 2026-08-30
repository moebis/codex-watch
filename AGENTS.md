# Codex Watch maintenance guide

## Product boundary

Codex Watch is a standalone native macOS menu bar app with one user-opened native analytics window. It displays the remaining weekly ChatGPT Codex quota as a native adaptive pie-chart icon plus percentage, hides Codex Spark limits from the compact menu, prefers managed-auth Codex app-server account data, retains bounded same-host HTTPS for compatibility and richer analytics, and projects one bounded 365-day analytics response into 7/30/90/365-day views. Notifications, Launch at Login, diagnostics, and reset-credit use remain explicit user controls. It does not render a notch overlay or inspect Codex session or rollout logs.

## Required change harness

Before changing visible behavior, quota semantics, authentication, privacy, packaging, or release automation, read:

1. `ARCHITECTURE.md`
2. `docs/PROJECT_MEMORY.md`
3. `docs/agent-harness.md`
4. `docs/contracts/behavior-contracts.yaml`
5. Relevant active records in `docs/decisions/`

State what changes, what remains unchanged, what is out of scope, the risk level, and the verification plan before editing.

## Privacy boundary

- Never commit or print `CODEX_HOME/auth.json`, access tokens, Authorization headers, complete usage responses, prompts, or conversation metadata.
- Do not add session-log scanning, telemetry, automatic updates, or third-party network destinations without an explicit contract change and review.
- Keep authenticated analytics and profile statistics in process memory. The only analytics persistence allowed by the active contracts is a bounded Usage CSV written after the user chooses a destination.
- Keep the production network session ephemeral and restricted to HTTPS on the original host.
- Bound app-server JSONL lines while consuming them, discard child stderr, ignore thread-level account usage and identity fields, and launch only a known Codex executable without a shell.
- Keep notification copy and diagnostics free of quota values, account data, credentials, paths, and raw errors. Never spend a reset credit without confirmation and idempotent retry semantics.

## Validation

```sh
./scripts/check_contracts.sh
./scripts/test_release_scripts.sh
swift test
./scripts/verify.sh /private/tmp/codex-watch-verify
./scripts/release.sh /private/tmp/codex-watch-release
```

`./scripts/release.sh` is only for a distributable local artifact. A pushed version tag triggers the GitHub release workflow.

Build and sign outside File Provider or synced repository paths; injected Finder metadata invalidates strict signature verification.

For authentication, parsing, concurrency, task-lifecycle, or memory changes, also run complete strict-concurrency compilation with warnings as errors and the relevant AddressSanitizer or ThreadSanitizer suite.

Menu bar layout, dashboard rendering, notifications, Launch at Login, CSV save behavior, and first-launch Gatekeeper behavior require confirmation on a real Mac.

## Git and releases

- Preserve unrelated worktree changes.
- Work directly on `main`; do not create branches unless the user explicitly reverses this repository policy.
- Keep meaningful changes in intentional commits.
- Push or publish only when explicitly requested.
- Do not create or push a tag unless a GitHub Release is separately requested.
- Version tags must match `CFBundleShortVersionString` and use the form `vMAJOR.MINOR.PATCH`.

## Documentation hygiene

- Keep current authority compact. Durable structure belongs in `ARCHITECTURE.md`; durable handoff state belongs in `docs/PROJECT_MEMORY.md`; normative behavior belongs in active contracts and decisions.
- Do not add completed implementation plans or duplicate historical specifications. Git history is the release archive.
- Update version-specific verification guards whenever `Resources/Info.plist` changes.
