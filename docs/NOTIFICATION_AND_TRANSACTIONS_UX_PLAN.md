# Notification + Transactions UX Plan (Binance-style, MVP-first)

Date: 2026-02-22

## Objectives

1. Notifications should feel professional and scannable:
   - Show only the most useful recent items by default.
   - Group repetitive messages into category summaries.
   - Keep full details accessible on tap.
2. Transactions page should match user preference:
   - Default active window = last 2 days.
   - User can filter history by token, direction, status, and custom date range.

---

## Scope Boundaries

- In scope:
  - Notification list presentation logic (grouping/summarization + sectioning + detail view continuity).
  - Transaction list filtering and preference persistence.
  - Minimal backend query extensions only where needed.
- Out of scope (for this plan):
  - Push notifications redesign.
  - New analytics dashboards.
  - Complex rule engines or AI classification.

---

## Area A — Binance-like Notification List

## A1. Product behavior

Default list behavior:
- Section 1: Critical alerts (ungrouped, always shown first).
- Section 2: Latest updates (most recent individual items, limited count).
- Section 3: Grouped summaries for repeated low-priority events.

Grouping rules (MVP):
- Group keys: `(type, poolId)` when poolId exists; otherwise `(type)`.
- Groupable types:
  - `round_closed`
  - `all_contributed`
  - `contribution_confirmed`
  - `pool_joined`
  - `pool_created`
- Never group critical types:
  - `default_triggered`
  - `collateral_slashed`
  - `stream_frozen`

Collapsed summary examples:
- "3 round updates in Pool #5"
- "5 contributions confirmed"

On tap behavior:
- Tap summary row -> opens grouped detail list (bottom sheet or dialog).
- Tap single row -> existing detail modal with full message (already implemented).

## A2. Data model additions (frontend-only first)

Add a derived view model in NotificationProvider layer:
- `NotificationListItem` union:
  - `single(notification)`
  - `group(groupKey, count, latestCreatedAt, sampleTitle, sampleBody, items)`

No backend schema change required for MVP grouping.

## A3. Rendering strategy

In notifications screen:
- Build `visibleItems` from provider-derived grouped list.
- Max initial single rows (non-critical): 12.
- Group repetitive remainder by rule.
- Keep unread badge semantics:
  - Group row is unread if any member unread.

## A4. Acceptance criteria

- Critical alerts are always visible individually.
- Repetitive informational events collapse into group rows.
- User can still read full individual message content from grouped detail.
- Unread count remains consistent before/after opening grouped summaries.

---

## Area B — Transactions by Customer Preference

## B1. Product behavior

Default for active users:
- Show transactions from last 2 days only.

User-controlled filters:
- Time range:
  - `2D` (default)
  - `7D`
  - `30D`
  - `All`
  - `Custom` (start/end date)
- Token: `All`, `USDC`, `USDT`, `CTC`
- Direction: `All`, `Sent`, `Received`
- Status: `All`, `Success`, `Failed`

Sorting:
- Newest first (existing behavior retained).

## B2. Preference persistence

Persist transaction filter preference locally per wallet:
- Storage key pattern: `tx_filters:<walletAddressLower>`
- Persist fields:
  - `rangePreset`
  - `token`
  - `direction`
  - `status`
  - `customFrom`
  - `customTo`

On wallet switch:
- Load that wallet’s last used filters.

## B3. Backend/API plan

Current endpoint:
- `/token/transactions` supports wallet + token + limit.

Recommended extension (Phase B2):
- Add optional query params:
  - `fromTimestamp`
  - `toTimestamp`
  - `direction`
  - `status`
  - `cursor` (future paging)

MVP fallback if backend change is deferred:
- Fetch current list as today.
- Apply date/direction/status filters client-side.
- Cap memory by existing `limit` and add “Load older” behavior later.

## B4. UI placement

Transactions screen toolbar:
- Add compact chip row under title:
  - Range chip (default `2D`)
  - Token chip
  - Direction chip
  - Status chip
  - “More filters” button for custom date

State ownership:
- Keep raw transactions in WalletProvider.
- Add computed `filteredTransactions` in screen/controller layer first.
- Move to provider once stable.

## B5. Acceptance criteria

- Default transaction view shows only last 2 days.
- User can change filters and immediately see list update.
- Preferences persist across app restarts per wallet.
- Pull-to-refresh respects active filters.

---

## Execution Plan (Phased)

### Phase 1 — Notifications grouping (frontend-only)
- Add grouped list view model in NotificationProvider.
- Implement grouped row rendering + grouped detail sheet/dialog.
- Add tests for grouping and unread consistency.

Status: Completed (2026-02-22)
- Added grouped notification view model and section builder (`critical`, `latest`, `grouped`).
- Notifications screen now renders sectioned list with grouped summary rows and grouped detail drilldown.
- Added provider test coverage for grouped display and unread semantics in grouped items.

### Phase 2 — Transactions default 2D + basic filters (frontend-only)
- Add filter state model + local persistence.
- Add range/token/direction/status UI chips.
- Apply client-side filtering to existing list.
- Add tests for default 2D behavior and persistence restore.

### Phase 3 — Backend filter support (optional but recommended)
- Extend `/token/transactions` query contract.
- Use server-side date/status filtering for scalability.
- Add backend tests for filter combinations.

Status: Completed (2026-02-22)
- Extended `/token/transactions` query contract with optional filters:
  - `fromTimestamp`, `toTimestamp`, `direction`, `status`, `cursor`.
- Implemented backend filtering logic (date range, token, direction, status) with newest-first ordering.
- Wired transactions screen/provider/api client to pass active filter state to backend while retaining UI behavior.
- Added backend tests for filter combinations in `backend/src/token/token.service.spec.ts`.

### Phase 4 — Polish + performance
- Add grouped notification summaries with better copy templates.
- Add optional pagination (`Load older`) in transactions.
- Validate empty/error/loading states for each filter state.

---

## Technical Notes for Current Codebase

- Notifications source:
  - `frontend/lib/providers/notification_provider.dart`
  - `frontend/lib/screens/notifications_screen.dart`
- Transactions source:
  - `frontend/lib/providers/wallet_provider.dart`
  - `frontend/lib/screens/transactions_screen.dart`
  - `frontend/lib/services/api_client.dart`

Suggested implementation order to minimize risk:
1. Notifications grouping view model + UI
2. Transactions 2D default + local preference persistence
3. Optional backend query extension

---

## Risks and Mitigations

1. Over-grouping can hide important context.
   - Mitigation: never group critical types; always expose detail drilldown.
2. Client-side filtering on limited list can miss older relevant records.
   - Mitigation: add server filters in Phase 3.
3. Preference complexity can confuse users.
   - Mitigation: clear defaults (`2D`, `All`, `All`, `All`) and one-tap reset.

---

## Definition of Done

- Notification screen presents mixed single + grouped items without losing detail visibility.
- Transaction screen defaults to 2-day history and supports user filters.
- Preferences persist per wallet and restore correctly.
- Core tests added for grouping logic, filter behavior, and persistence.
