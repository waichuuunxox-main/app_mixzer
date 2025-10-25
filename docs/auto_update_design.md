# Auto-update design for app_mixzer

Purpose

- Provide a secure, resilient, and user-friendly mechanism to automatically fetch an up-to-date remote "kworb" JSON (ranking list), enrich each entry with iTunes metadata, and display it progressively in the UI.

Goals

- Always prefer secure remote data (HTTPS), but fall back to local `docs/kworb_top10.json` on failures.
- Avoid blocking the UI: render a minimal list immediately and enrich items in the background with controlled concurrency.
- Minimize repeated external calls: cache iTunes metadata with TTL.
- Keep the user informed: show source (remote/local), progress, and last-updated time.
- Be safe: validate remote content size and basic schema; limit max entries to a reasonable cap.

Key components

1. RankingService
- `loadRemoteKworb(from:url)`
  - Downloads remote JSON via HTTPS only.
  - Enforces size limits (default 2MB) and decodes into `[KworbEntry]`.
  - Throws meaningful errors for missing/invalid data.

- `loadRanking(remoteURL: URL?, maxConcurrency: Int, topN: Int?)`
  - Accepts an optional remote URL (falls back to local).
  - Returns final `[RankingItem]` after enrichment.
  - Posts `Notification.Name.appMixzerDidEnrichItem` for each item as it becomes enriched so the UI can update incrementally.
  - Processes items in batches to control concurrency (default 6 concurrent queries).

2. MetadataCache (actor)
- In-memory cache keyed by normalized `title::artist`.
- TTL default 24 hours.
- Reduces duplicate iTunes calls when the same title/artist appears repeatedly.

3. ViewModel (RankingsViewModel)
- Reads `remoteKworbURL` from `UserDefaults` (AppStorage in Settings).
- Loads an immediate minimal list (rank/title/artist) for instant UI rendering.
- Registers a selector-based observer for `appMixzerDidEnrichItem` (main actor) to update items as enriched entries arrive.
- Exposes `sourceDescription`, `lastUpdated`, and `isEnriching` for the UI.
- Responds to `appMixzerRequestRefresh` notifications (manually triggered in Settings or toolbar) to force an immediate refresh.

4. Settings UI
- Controls:
  - `remoteKworbURL` (text field)
  - `autoUpdateEnabled` toggle
  - `autoUpdateIntervalSeconds` selection (1h/6h/24h)
  - `Fetch now` button (posts `appMixzerRequestRefresh`)

5. Safety & Limits
- Only HTTPS URLs allowed.
- Max file size default 2MB; configurable when calling the API.
- Basic schema verification (must decode into `KworbEntry`).
- Max entries cap when loading large lists (e.g., topN default nil, but UI and settings can impose limits).

Concurrency & retry

- The enrichment phase uses batch processing. Each batch size equals the configured `maxConcurrency`, e.g., 6.
- Individual iTunes queries implement caller-side retry with exponential backoff (recommended, currently minimal retry behavior is applied via callers).
- MetadataCache reduces pressure from duplicate queries.

UX behaviour

- On app launch (or manual Fetch):
  1. Try to load remote kworb (if configured). If remote fails, fallback to local.
  2. Render minimal list immediately.
  3. Start background enrichment, updating list entries as metadata arrives (artwork, preview, collection, releaseDate).
  4. When enrichment completes, update `lastUpdated` and display "remote" as the source (or "local" on fallback).

Testing

- Unit tests should cover:
  - Remote download success and failure (timeout, non-HTTPS, over-size).
  - MetadataCache expiry and hit/miss.
  - loadRanking incremental behaviour with a mocked URLSession.

Deployment notes

- Because iTunes Search API is public, the app must be conservative about request volume. Large lists (top100+) should be enriched in the background and optionally paused or rate-limited.
- Consider server-side aggregation if extremely large or frequent updates are required.

----

This document is intentionally concise; implementation details exist in `Sources/app_mixzer/RankingService.swift`, `Sources/app_mixzer/MetadataCache.swift`, and `Sources/app_mixzer/RankingsView.swift` (ViewModel changes). If you want, I can expand the document with sequence diagrams and concrete failure-trace examples.
