# Notification Reliability Hardening Plan

Date: 2026-02-22
Goal: Deliver robust, near-real-time, user-trustworthy notifications for all app transactions and risk events (Binance-style reliability baseline).

---

## 1) Current Implementation Audit (What exists)

### Backend
- Notification persistence + SSE stream endpoint exists.
- Event-driven emits already implemented for major pool/indexer events.
- Additional service-level emits implemented for transfer/withdraw/faucet/collateral/wallet-bind/pool-created.
- Idempotency support exists in notifications service.

### Frontend
- `NotificationProvider` consumes SSE and updates list/unread state.
- Polling fallback exists.
- Fast-sync hooks are triggered after key transaction actions.
- Notifications screen supports unread/mark-read/refresh flows.

---

## 2) Root Cause Identified

Primary delivery gap was wallet-address matching fragility:
- Notification ownership/filtering used case-sensitive comparisons in persistence lookups and SSE filtering.
- Wallet values can appear in mixed-case (checksum vs lowercase), causing:
  - Empty notification list despite existing records,
  - SSE events silently filtered out.

---

## 3) Improvements Implemented Now

### Backend fixes
- Normalized wallet address handling in notifications service (`trim + lowercase`) during create/query/update.
- Made wallet lookups case-insensitive for:
  - list (`findForWallet`),
  - unread count,
  - mark single read,
  - mark all read.
- Normalized SSE stream wallet filter in controller.

### Frontend fixes
- Strengthened polling fallback to refresh notification list (not only unread count).
- Added immediate sync pulse when SSE reconnect is scheduled (recovery path).
- Hardened SSE stream decoding path in API client.
- Added cursor-based incremental sync merge path in `NotificationProvider`.

### Delivery guarantee additions
- Added replay-safe incremental endpoint (`GET /notifications/incremental`) with cursor (`afterCreatedAt`, `afterId`).
- Added deterministic ordering contract (`createdAt ASC`, then `id ASC`) for incremental fetch.

---

## 4) Robustness Plan (Next Phases)

## Phase A — Delivery Guarantees
- Add a monotonic cursor/watermark model (`lastSeenCreatedAt` or server cursor) so reconnect cannot miss events.
- Support SSE `Last-Event-ID` style replay semantics (or equivalent API cursor endpoint).
- Add backend-side pagination consistency contract (`createdAt + id` tie-break ordering).

## Phase B — Event Taxonomy Completeness
- Define canonical transaction-notification matrix for every user action:
  - `pending_submitted`, `confirmed`, `failed/reverted` where applicable.
- Ensure each API + on-chain flow emits deterministic user-facing outcomes.
- Add strict schema for metadata fields (`txHash`, `poolId`, `round`, `token`, `amount`, `status`).

Status: Completed (finalized)
- Metadata contract standardized with lifecycle fields:
  - `status` (`pending | confirmed | failed`),
  - `kind` (`transaction | risk | system`),
  - normalized `walletAddress`, `notificationType`.
- Default lifecycle mapping now applied centrally in backend notification service.
- Notification UI now renders lifecycle status chips (`PENDING`, `CONFIRMED`, `FAILED`).
- Extended icon/color mapping for additional transaction notification types.
- Endpoint-level failure enrichment added for server-side transaction operations:
  - transfer/withdraw build failures,
  - faucet mint failures,
  - collateral release failures,
  - pool creation tx revert failures.

## Phase C — Idempotency and Ordering Hardening
- Introduce deterministic idempotency keys across all emitters using canonical format.
- Add guardrails for duplicate creation under retries/reorg reprocessing.
- Add ordering tests for rapid multi-event bursts.

Status: Completed (finalized)
- Canonical idempotency normalization enforced (case-insensitive key normalization).
- Duplicate guardrail strengthened to match by wallet + type + idempotency key (not title/body-sensitive).
- Added backend tests for:
  - case-insensitive dedupe,
  - burst event ordering,
  - incremental cursor pagination ordering behavior.

## Phase D — UX Trust Layer
- Distinguish informational updates from critical alerts.
- Add in-notification status chips (`Pending`, `Confirmed`, `Failed`) for transaction-originated notifications.
- Ensure unread badge/list remains correct after app resume/background transitions.

Status: Completed (finalized)
- Notification list now explicitly differentiates non-transaction alerts as `ALERT` (risk) vs `INFO` (system).
- Transaction status chips are rendered only for transaction-originated notifications.
- App lifecycle handling added for notifications: background transitions pause SSE/polling and app resume triggers immediate incremental sync + unread refresh.

## Phase E — Test Coverage Expansion
- Backend tests:
  - case-insensitive ownership lookup,
  - idempotency under duplicate replay,
  - stream-filter correctness.
- Frontend tests:
  - SSE reconnect recovery,
  - polling fallback coherence,
  - unread/list consistency under mixed event timing.

Status: Completed (finalized)
- Backend notification regression suite now covers:
  - case-insensitive ownership lookup for list/unread/read mutations,
  - stream filter correctness at controller SSE layer,
  - idempotency and ordering behavior from previous phases.
- Frontend notification provider suite now covers:
  - reconnect recovery with new stream session,
  - mixed SSE + incremental timing without duplicate list entries,
  - unread/list convergence through resume/background transitions.

---

## 5) Acceptance Criteria

- A notification created for a wallet is always visible regardless of wallet string casing.
- SSE disconnection/reconnect does not cause long-lived missing notifications.
- Notification list and unread count converge to the same truth within fallback polling window.
- Critical events are surfaced once, without spam.
- Duplicate retries/reindex runs do not create duplicate user notifications.

---

## 6) Recommended Execution Order

1. Case-insensitive ownership + SSE filtering (completed).
2. Fallback polling/list sync hardening (completed).
3. Cursor-based replay-safe fetch contract (completed).
4. Full event taxonomy contract (`pending/confirmed/failed`) (completed).
5. Expanded automated test suite and regression gate (completed; backend and frontend notification reliability regressions added).
