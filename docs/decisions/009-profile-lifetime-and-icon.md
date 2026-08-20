---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, DASHBOARD-SURFACE-011, PROFILE-LIFETIME-014]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-20
last_verified_commit: pending
---

# Add exact lifetime profile statistics and a visible status mark

## Context

The bounded 365-day aggregate endpoint cannot reproduce the exact lifetime total shown by Codex because older activity rows may omit token fields. The official Codex client obtains exact account totals, streaks, activity buckets, and invocation insights from a separate same-host profile route. The existing filled pie status symbol can also become low contrast while the status item is selected, and Spark-specific windows make the compact menu unnecessarily tall for a Codex-focused monitor.

## Decision

- Perform a bounded read-only GET of `/backend-api/wham/profiles/me` through the existing ephemeral, no-cookie, same-host HTTPS client.
- Decode only optional `stats` values needed for display. Ignore profile identity and editing fields, keep the validated result only in memory, and never estimate missing lifetime values.
- Refresh profile statistics only when the existing analytics cadence permits. Profile failure is independent from quota and bounded Usage analytics; preserve last-good in-memory values and mark the analytics surfaces stale.
- Add a separate Lifetime dashboard tab for the exact headline metrics, daily activity buckets, activity insights, and top Codex invocations. Keep bounded 7/30/90/365 projections and CSV export under Usage.
- Hide only `codex-spark` and `codex-spark-weekly` from the compact menu while preserving them in the decoded capability model.
- Replace the template pie symbol with a deterministic non-template colored monitoring mark so AppKit cannot recolor it to an illegible selected-state black. Keep the existing approved app artwork and verify every standard ICNS representation.

## Rejected alternatives

- **Add 30.3B as a manual baseline:** it would immediately drift and mix user input with server truth.
- **Infer lifetime usage from bounded daily analytics:** incomplete historical token fields make the result materially low.
- **Scan local sessions:** this changes the privacy and retention boundary while still missing remote work.
- **Embed or scrape the profile page:** browser state, HTML fragility, and cookies are unnecessary because a structured same-host response exists.

## Consequences

Codex Watch gains exact lifetime account metrics without reading conversation content or adding persistence. The internal profile route may change, so every field is optional and fail-closed. Lifetime daily buckets describe only the dates returned by the server and do not imply complete input/output, model, or client breakdowns. The Usage tab remains the authoritative surface for those bounded details.
