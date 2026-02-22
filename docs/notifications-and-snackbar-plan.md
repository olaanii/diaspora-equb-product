# Notifications + Snackbar UX Implementation Plan

Date: 2026-02-22

## Goal
Implement a robust end-to-end notification system and a consistent, polished snackbar UX for all success, error, warning, and info messages across the app.

---

## Plan A — Robust Notification System (Backend + UI)

### Current Baseline (already implemented)
- Backend notifications module exists (`/notifications`, unread count, mark-read, mark-all-read, SSE stream).
- Notification creation already happens for major indexer-driven events (join, contribution confirmed, round closed, payout, default, slashing, stream frozen, all contributed).
- Frontend notification list and unread badge exist.
- Frontend currently uses polling; SSE stream is not yet consumed by UI.

### Gaps to close
- No frontend SSE subscription yet.
- Notification lifecycle is not fully tied to auth/login/logout transitions.
- Not all transaction paths emit explicit user-facing notifications yet.
- Type/icon mapping on UI is incomplete for some types (e.g., `all_contributed`).
- Post-transaction refresh flows focus on balances/tx, not notifications.

### Implementation phases

#### Phase 1: Notification Contract + Coverage Matrix
- Define notification taxonomy for every in-app transaction:
  - create pool, join pool, contribute, close round, schedule payout,
  - trigger default, collateral deposit/release, identity bind,
  - transfer/withdraw, faucet, payout/credit updates.
- Standardize payload fields:
  - `type`, `title`, `body`, `metadata` (`txHash`, `poolId`, `round`, `token`, `amount`, etc.).

#### Phase 2: Backend Emission Hardening
- Add a notification factory/helper for consistent message construction.
- Add idempotency key strategy to avoid duplicate notifications during reindex/retry.
- Extend missing emitters in indexer/services for uncovered transaction categories.
- Ensure warnings/errors in emit path are logged without breaking core flow.

#### Phase 3: Frontend Realtime + Fallback
- Add SSE client in `NotificationProvider` for `/notifications/stream`.
- Keep polling as fallback/recovery.
- On incoming event:
  - prepend notification to list,
  - increment unread count,
  - refresh badge immediately.

#### Phase 4: Auth Lifecycle Wiring
- Start notifications stream/polling on successful login and auto-login restore.
- Stop stream/polling and clear in-memory notification state on logout.
- Reconnect stream with backoff when connection drops.

#### Phase 5: Transaction UX Integration
- After successful user transaction submission, trigger fast notification sync until confirmation is indexed.
- Optionally show local pending state and reconcile when backend notification arrives.

#### Phase 6: Validation + Observability
- Add backend tests for notification dedupe/idempotency and event coverage.
- Add frontend tests for unread count, mark-read flows, stream reconnect, logout cleanup.
- Add structured logs/metrics for emit success/failure and stream health.

---

## Plan B — Global Snackbar Plan (Alert/Error/Success/Info)

### Goal
Create one unified snackbar system so all user messages are consistent, non-spammy, and visually polished.

### Implementation phases

#### Phase 1: Centralized Snackbar Service
- Create an `AppSnackbarService` with one API for all message types:
  - `success`, `error`, `warning`, `info`.
- Wire global `ScaffoldMessenger` key in app root so snackbars can be shown from providers/services safely.

#### Phase 2: Message Model + Theming
- Define a message model with:
  - `type`, `title`, `message`, `duration`, optional action (`label`, callback), optional `dedupeKey`.
- Use existing theme tokens/components only (no new hard-coded design primitives).
- Standardize iconography and layout by message type.

#### Phase 3: Anti-Spam Controls
- Add queueing behavior for sequential messages.
- Add dedupe window (same `dedupeKey` within short TTL should be ignored/coalesced).
- Prevent repeated retries/background polling from flooding users.

#### Phase 4: Provider-Level Integration
- Replace ad-hoc snackbars in key providers/screens with centralized service:
  - auth, pools, wallet, collateral, notifications.
- Use rules:
  - success for user-initiated completion,
  - error for failures/rejections,
  - warning for risk/required action,
  - info for neutral progress.

#### Phase 5: Notification-Snackbar Bridge
- For critical incoming notifications (`default_triggered`, `collateral_slashed`, `stream_frozen`), show high-priority warning snackbar once.
- For non-critical notifications, update badge/list without intrusive popups.

#### Phase 6: Test + Polish
- Unit test snackbar dedupe + queue behavior.
- Validate UX on rapid transaction flows.
- Ensure no snackbar is shown after route disposal/context loss.

---

## Combined Execution Order (Recommended)
1. Backend notification coverage + idempotency foundation.
2. Frontend notification realtime (SSE) + auth lifecycle.
3. Global snackbar service + provider integration.
4. Critical notification-to-snackbar bridge.
5. Tests + end-to-end validation pass.

## Acceptance Criteria
- Users receive timely notification entries for all important in-app transaction outcomes.
- Unread badge updates reliably in near real-time.
- Snackbar visuals/messages are consistent app-wide.
- Duplicate/retry floods are suppressed.
- Login/logout cleanly starts/stops notification streams.
- Core notification and snackbar flows are covered by automated tests.
