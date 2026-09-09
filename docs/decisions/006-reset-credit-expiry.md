---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, RESET-CREDITS-006, USER-CONTROLS-016]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-07-31
last_verified_commit: a3db739
---

# Reset-credit expiry and confirmed redemption

Quota resets and banked reset credits have independent lifetimes. Compatibility quota exposes credit counts; the separate same-host detail route supplies availability, plan support, grant, and expiry metadata.

Use the existing ephemeral HTTPS session and original host/port. Fetch details only for a positive count, with a five-second timeout. Display the earliest available credit expiry supported by the current plan. Show lifetime progress only when both exact timestamps are valid; missing details preserve quota/count without inventing expiry or duration.

Redemption is a separate confirmed app-server action under `RESET-CREDITS-006`. Keep one idempotency key across an uncertain retry, retain the pending request only in memory, and refetch quota after an exact outcome. Refresh must never spend a credit.

Do not reuse the weekly reset, assume a fixed credit lifetime, cache the private response, or redeem automatically. These alternatives either conflate different entitlements or bypass user intent. The detail route is internal, so optional failure must remain harmless.
