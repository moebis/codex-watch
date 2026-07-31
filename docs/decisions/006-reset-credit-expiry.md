---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, RESET-CREDITS-006]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-07-31
last_verified_commit: pending
---

# Read reset-credit expiry from the same ChatGPT host

## Context

The existing usage response exposes only reset-credit counts. It does not include the per-credit expiry needed to warn when a banked reset will disappear. ChatGPT exposes those details from a separate read-only path on the same authenticated host.

## Decision

- Request reset-credit details only when the usage response reports a positive available count.
- Use the existing ephemeral authenticated session and require the detail URL to use HTTPS with the same host and port as the usage URL.
- Decode only availability, plan support, grant, and expiry metadata needed for display.
- Show the earliest expiry among available credits supported by the current plan in the user's local time zone, and visualize remaining lifetime as `(expires_at - now) / (expires_at - granted_at)` when both timestamps are valid.
- Treat the detail request as best-effort with a five-second request timeout. A failure preserves weekly quota and reset-credit count without inventing an expiry.

## Rejected alternatives

- **Reuse the weekly quota reset:** banked reset credits have independent expiry semantics.
- **Assume a fixed lifetime from grant date:** promotions can use different expiry policies.
- **Persist the detail response:** the menu can derive its display in memory and does not need private account data on disk.
- **Add redemption:** consuming a reset is a separate state-changing product and security decision.

## Consequences

Each refresh with a positive reset-credit count makes one additional read-only request to the existing ChatGPT host. The detail path is not a public API, so the app must continue to degrade safely if its response or availability changes. Missing or invalid grant metadata leaves the expiry text visible but hides its progress bar rather than assuming a lifetime.
