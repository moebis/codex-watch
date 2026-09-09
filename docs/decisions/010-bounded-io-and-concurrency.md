---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, REFRESH-COORDINATION-013]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-23
last_verified_commit: a3db739
---

# Bounded credential I/O and explicit concurrency ownership

Metadata checks followed by unbounded reads leave a size-check/read race. Reading synchronously on the main actor also delays UI. Open the credential file once and enforce the one-mebibyte bound while consuming bytes, allowing only one extra detection byte.

Run credential I/O at utility priority through the sendable reader boundary. Keep AppKit owners and publication on the main actor; mark concurrent closures/results sendable according to ownership. Authentication failure makes retained Usage/Lifetime data stale even when those requests were skipped.

Retain Swift 5 language mode with complete strict-concurrency diagnostics for sensitive changes. A detached synchronous read cannot be interrupted mid-read, so bounded consumption and a minimal capture remain necessary. An entirely new refresh architecture is unnecessary; the generation coordinator already owns cancellation/publication.

Do not copy tokens into a second credential store or enable App Sandbox as a packaging toggle. Codex owns authentication, and sandboxing needs an explicit design for both the known child executable and optional credential-file compatibility path. See `PRIVACY-BOUNDARY-003` and `REFRESH-COORDINATION-013` for normative boundaries.
