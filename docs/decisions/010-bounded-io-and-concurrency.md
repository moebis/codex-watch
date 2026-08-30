---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, REFRESH-COORDINATION-013]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-23
last_verified_commit: a3db739
---

# Bound credential I/O and make concurrency ownership explicit

## Context

The credential reader checked file metadata but then used an unbounded convenience read on the main actor. This left a size-check/read race and allowed slow local I/O to delay menu interaction. Strict Swift concurrency also exposed actor and sendability ownership that Swift 5 mode did not enforce. Authentication failure could preserve valid analytics and profile objects without marking them stale.

## Decision

- Open `auth.json` once, consume it in bounded chunks, stop after one mebibyte plus one detection byte, and reject oversized or invalid content.
- Perform the synchronous credential read from a utility-priority detached task through a sendable `CredentialsReading` boundary. Do not move AppKit or mutable controller state off the main actor.
- Keep lifecycle owners, AppKit presentation, and refresh publication main-actor isolated. Mark concurrent refresh closures, transport values, attempts, and results sendable where their ownership supports it.
- Treat retained Usage and Lifetime values as stale whenever authentication fails, even if those capability requests were not attempted in the failing refresh.
- Keep Swift 5 language mode for compatibility, but require complete strict-concurrency compilation with warnings as errors for concurrency-sensitive work.
- Do not enable App Sandbox until credential access is redesigned. The current app must read the existing Codex credential file outside its container.

## Rejected alternatives

- **Trust metadata size before `Data(contentsOf:)`:** the path can change between inspection and read, and the read still performs synchronous work on the caller.
- **Copy the token into Keychain:** Codex remains the source of truth, so a second credential store would not remove the original exposure and could drift.
- **Enable App Sandbox as a packaging toggle:** it would break the current authentication path without providing a replacement.
- **Rewrite refresh around a new concurrency architecture:** the existing coordinator already has correct generation, cancellation, and publication ownership; explicit annotations are sufficient.

## Consequences

Credential I/O no longer blocks the main actor and cannot allocate beyond its documented bound. Current Swift 5 builds preserve behavior while strict diagnostics guard Swift 6 migration readiness. A detached synchronous read is not interruptible mid-read, but its byte count is hard-bounded and it captures only a sendable reader. Sandboxing remains a visible product and security decision rather than an accidental build change.
