---
status: current
owner: project-maintainer
last_verified_commit: a628a8c
current_release: 1.3.2
current_build: 22
---

# Codex Watch project memory

## Current state and routing

- Native Mac app; repository `https://github.com/moebis/codex-watch`, primary checkout on `main`. No project production server, database, Docker deployment, or automatic updater. See README for install commands and attribution.
- Version/build authority is `Resources/Info.plist` plus `scripts/verify_app.sh`. Version 1.3.2 (code `a628a8c`) passed 199 tests and signed universal bundle verification on 2026-09-05. The installed `/Applications/Codex Watch.app` remains 1.3.2 build 22 and was rechecked on 2026-09-09. Broader strict-concurrency and sanitizer checks passed for the preceding 1.3.1 runtime fixes; they were not repeated for display preferences or documentation.
- Native Computer Use timed out during the implementation. Spark-toggle appearance, notification delivery, Launch at Login, reset confirmation, dashboard geometry, CSV save, and Gatekeeper acceptance have no recorded visual confirmation. Do not substitute protocol tests for those checks.
- Start with `docs/agent-harness.md` for proportional verification; `ARCHITECTURE.md` owns structure. Active contracts own behavior, and `docs/decisions/README.md` routes to the relevant rationale. Do not reread every decision or rerun all gates for each task.

## Durable lessons from this thread

- **Pipe behavior needs a real child-process test.** POSIX reads consume short JSONL replies while stdout stays open. Foundation convenience reads may wait for a full buffer or EOF; in-memory transports missed that failure.
- **Capability and generation ownership matter.** Prefer managed app-server quota, with independent HTTPS fallback and richer analytics. Publish quota before slow analytics; authentication loss makes retained analytics stale even after quota-only refreshes. Share connection startup, revalidate accounts, and recover with the bounded retry cadence.
- **Spark is a display preference.** `showCodexSparkStats` defaults false; toggling rebuilds the menu without fetching. Match adjacent Codex/Spark words in IDs or titles, including versioned GPT names and duplicate suffixes, while preserving `Codex Sparkle`. Base-weekly quota never changes source because of this toggle. Native row labels append `remaining`.
- **Preserve quota and reset meaning.** Prefer the explicit base `codex` bucket, validate numeric strings in full, and retain notification threshold history through same-window corrections. Never infer lifetime totals from a bounded year or retry uncertain reset spending automatically.
- **Keep builds out of File Provider.** Synced paths can reattach Finder metadata and invalidate strict signatures. Use nonsynced scratch/output paths and inspect the exact installed or extracted bundle. App bundles do not back up user preferences or chosen CSV exports.

## Retention and efficient maintenance

Keep the installed app plus one latest verified rollback bundle in `~/Library/Application Support/Codex Watch/Backups`. On 2026-09-09 cleanup retained the 1.3.1 rollback and removed older backups and obsolete project build/temp artifacts. Inspect live inventory before future deletion; do not generalize this rule to unrelated projects, shared caches, Time Machine, credentials, or user exports.

No source or test behavior changed in that maintenance pass. The regressions remain useful; duplicated documentation and repeated verification instructions were the overhead. Inspect workflow triggers before every push and skip hosted CI when direct checks suffice. No version tag or GitHub Release was requested.
