---
status: active
contract_ids: [DASHBOARD-SURFACE-011, PRIVACY-BOUNDARY-003, USAGE-ANALYTICS-012, REFRESH-COORDINATION-013]
supersedes: [004-menu-bar-only, 007-usage-analytics]
superseded_by: null
owner: project-maintainer
created_at: 2026-08-20
last_verified_commit: a3db739
---

# Native analytics dashboard and coordinated refresh

A compact status menu cannot legibly hold daily trends, coverage, ranges, and long model/client tables. Keep one persistent status item and one reusable native analytics window, with no Dock presence, notch overlay, or WebView.

`USAGE-ANALYTICS-012` defines a single trailing-365-day dataset projected into 7/30/90/365 views. Preserve missing, observed-zero, and activity-only dates as distinct states. Models report activity; clients report returned tokens. Compare periods only with at least 90% token coverage in both; a preceding-year comparison is unavailable. CSV requires an explicit user-selected destination.

`REFRESH-COORDINATION-013` owns coalescing, manual generation replacement, cancellation, and delayed scheduling after completion. Adaptive cadence uses only menu interaction, Low Power Mode, and thermal pressure. Analytics cadence stays independent from quota-only triggers.

Rejected directions: putting detailed charts into the menu, importing multi-provider/browser-cookie infrastructure, scanning sessions, embedding authenticated web pages, or treating absent token fields as zero. Each adds complexity or misrepresents available evidence. Widgets, local history, and multi-account support require separate decisions; explicit user controls are covered by decision 011.
