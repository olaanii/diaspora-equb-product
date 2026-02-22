# Payout Stream + Equb Charts Implementation Plan (Robust, MVP-to-Scale)

Date: 2026-02-22
Owner: Product + Frontend + Backend

## 1) Goals

1. Move winner-picking flow to Payout Stream and keep Pool Status focused on round closing.
2. Enforce traditional sequential progression:
   - close round N
   - pick winner for round N only
   - then round N+1 starts
3. Support season lifecycle:
   - one season ends when closed rounds == member count
   - allow optional parameter adjustment before season 2 starts.
4. Add Binance-style chart entry from home header chart icon (left of notification bell):
   - popular Equbs trend chart(s)
   - joined-pools progress chart(s)
   - filterable dashboard.

---

## 2) Scope

### In Scope
- UX relocation: winner button from Pool Status -> Payout Stream.
- Round-state machine and backend guards for one-round winner picking.
- Season completion and season rollover setup UX.
- New chart dashboard screen + route + app bar entry action.
- Filter system for charts (time range, pool type/status, token, joined-only/all).

### Out of Scope (this plan)
- Full analytics warehouse.
- Real-time websocket chart streaming (polling/cached API is enough for MVP).
- Advanced candlestick engine (line/area charts for MVP).

---

## 3) Current Code Anchors

- Home header chart icon (currently no action):
  - `frontend/lib/screens/home_screen.dart`
- Notification bell route nearby in header:
  - `frontend/lib/screens/home_screen.dart`
- Payout screen (target for winner-pick UX):
  - `frontend/lib/screens/payout_tracker_screen.dart`
- Pool status screen (remove winner-pick action, keep close-round):
  - `frontend/lib/screens/pool_status_screen.dart`
- Routing:
  - `frontend/lib/config/router.dart`
- Pool orchestration provider/services:
  - `frontend/lib/providers/pool_provider.dart`
  - backend pool endpoints under `backend/src/pools/*`

---

## 4) Product Behavior (Target)

## A. Round + Winner Flow (Traditional Sequential)

### A1. Pool Status Screen
- Keep only `Close Round` action (admin-only).
- Remove/disable auto winner-pick action from this screen.
- Show clear status chip:
  - `Round Open`
  - `Round Closed - Winner Pending`
  - `Winner Picked`

### A2. Payout Stream Screen
- Add `Pick Winner (Auto)` primary action (admin-only).
- Button enabled only when:
  - current round is closed,
  - winner for this round is not already picked,
  - season not completed.
- Action always applies to exactly one round: current closed round only.
- After success:
  - mark winner for that round,
  - advance pool to next round state.

### A3. Season Rules
- Season round count = `maxMembers` (or effective member count if business rule says so; choose one and lock in backend).
- Season completes when all required rounds are winner-picked.
- At completion:
  - show `Season Complete` state,
  - show `Configure Next Season` CTA.

### A4. Season 2 Setup (Post-Season Adjustment)
- Open setup form prefilled from previous season.
- Adjustable fields (final set by business policy):
  - contribution amount
  - token (if allowed)
  - payout split/upfront percent
  - cadence/schedule parameters.
- Confirm -> create season N+1 config and reactivate pool.

---

## B. Equb Charts Dashboard (Binance-style, app-header entry)

### B1. Navigation Entry
- Use existing chart icon in home header (`show_chart_rounded`) to open new route: `/equb-insights`.
- Placement remains in home app bar left of notification icon.

### B2. Dashboard Content (MVP)

#### Panel 1: Popular Equbs Trend
- Top pools by engagement volume (join activity + contribution activity).
- Chart type: line/area trend over time.
- Metric options toggle:
  - Join count
  - Contribution count
  - Total contributed amount

#### Panel 2: My Joined Equbs Progress
- Show user-joined pools only.
- Graph options:
  - Round completion percentage over time
  - Contribution completion ratio
  - Payout progress (released vs remaining)

#### Panel 3: Summary Cards
- Active pools count
- Pools ending soon
- Next winner pending count

### B3. Filter System
Global filter bar (sticky under app bar):
- Time range: `24H`, `7D`, `30D`, `90D`, `All`, `Custom`
- Scope: `Popular`, `Joined`, `Both`
- Token: `All`, `USDC`, `USDT`, `CTC`
- Pool status: `All`, `Open`, `Closed`, `Winner Pending`, `Completed`
- Sort metric: `Volume`, `Members`, `Progress`, `Recent Activity`

Persist filters per wallet:
- Key: `equb_insights_filters:<walletLower>`

---

## 5) Backend/Data Contract Plan

## A. Round State and Winner Picking

### A1. New/clarified pool state fields
- `currentRound`
- `currentRoundStatus` (`open|closed|winner_picked`)
- `currentRoundWinner`
- `seasonNumber`
- `seasonStatus` (`active|completed|config_pending`)
- `seasonTotalRounds`
- `seasonCompletedRounds`

### A2. Winner endpoint constraints
Winner-pick endpoint must reject invalid calls with explicit codes:
- `WINNER_BEFORE_CLOSE`
- `ROUND_ALREADY_PICKED`
- `SEASON_COMPLETE`
- `NOT_POOL_ADMIN`

### A3. Idempotency
- Require idempotency key on winner-pick operation to prevent double execution.

## B. Insights endpoints

### B1. Popular Equbs series
`GET /analytics/equbs/popular-series`
Query:
- `fromTimestamp`, `toTimestamp`
- `token`
- `status`
- `metric` (`joins|contributions|amount`)
- `limit`

Response:
- `series`: [{ poolId, poolName, points: [{ts, value}] }]

### B2. Joined pools progress
`GET /analytics/equbs/joined-progress`
Query:
- `walletAddress`
- `fromTimestamp`, `toTimestamp`
- `token`
- `status`

Response:
- `pools`: [{ poolId, poolName, completionPct, roundsDone, roundsTotal, payoutReleased, payoutRemaining, points:[...] }]

### B3. Summary cards
`GET /analytics/equbs/summary`
Query:
- `walletAddress`
- `fromTimestamp`, `toTimestamp`
- `token`
- `status`

---

## 6) Frontend Architecture Plan

## A. New screen + route
- Add `EqubInsightsScreen`:
  - `frontend/lib/screens/equb_insights_screen.dart`
- Register route in:
  - `frontend/lib/config/router.dart`
- Wire home chart icon tap in:
  - `frontend/lib/screens/home_screen.dart`

## B. State management
- Add provider/controller:
  - `frontend/lib/providers/equb_insights_provider.dart`
- Responsibilities:
  - filter state
  - persisted filter load/save per wallet
  - fetch/caching for popular/joined/summary payloads
  - loading/error/empty states.

## C. Existing screen updates
- `pool_status_screen.dart`
  - remove winner-pick UI action
  - keep close-round UI and state hints.
- `payout_tracker_screen.dart`
  - add winner pick button + eligibility conditions
  - show round timeline state transitions
  - show season completion + next-season config CTA.

## D. Chart library
- Use existing approved Flutter chart package already in project if present; otherwise add one package only (e.g., `fl_chart`) for line/area chart rendering.

---

## 7) UX States and Edge Cases

## A. Winner flow edge cases
- Close-round tx mined but winner tx fails -> stay on `Winner Pending` with retry.
- Duplicate click -> backend idempotency + disabled loading state.
- Network error -> non-destructive retry with snackbar + inline error.

## B. Chart dashboard states
- Loading skeletons for 3 panels.
- Empty popular data -> message with filter reset button.
- Empty joined data -> guidance to join a pool.
- Partial failure: show available panels; only failed panel gets retry CTA.

## C. Filter behavior
- Filter change triggers debounced reload (250–400ms).
- Pull-to-refresh respects current filters.
- Quick `Reset Filters` action always available.

---

## 8) Delivery Phases

### Phase 1 — Winner flow relocation and guards
- Move button from Pool Status to Payout Stream.
- Backend one-round-only guard + explicit errors.
- Frontend eligibility logic + loading/error handling.

### Phase 2 — Season completion + season setup
- Add season status model and completion detection.
- Add season rollover setup UI and backend endpoint.

### Phase 3 — Equb insights route + basic charts
- Add `/equb-insights` route and home icon navigation.
- Implement Popular + Joined + Summary panels with default filters.

### Phase 4 — Filter persistence + performance
- Persist filters per wallet.
- API pagination/caching; optimize payload sizes.
- Improve skeletons, empty states, and retries.

### Phase 5 — Hardening
- Add tests, telemetry, and final UX polish.

---

## 9) Testing Plan

## Backend tests
- Winner pick valid only when round is closed.
- Winner cannot be picked twice for same round.
- Season completion transitions correctly.
- Next-season config writes validated parameters.

## Frontend tests
- Pool status screen shows close-round only.
- Payout screen enables/disables pick-winner correctly by state.
- Home chart icon opens insights route.
- Insights filters persist and restore by wallet.
- Panel-level loading/error/empty rendering.

## Integration checks
- Close round -> pick winner -> next round open sequence.
- End of season -> next-season setup -> season N+1 active.

---

## 10) Acceptance Criteria

1. Winner action is removed from Pool Status and available on Payout Stream only.
2. Winner can be picked exactly once per closed round and only in order.
3. Season completion state appears exactly at configured total rounds.
4. User can optionally adjust allowed parameters before starting next season.
5. Home header chart icon opens a working insights dashboard.
6. Dashboard shows popular Equb trends + joined-pool progress charts.
7. Filters work, persist per wallet, and are respected on refresh.

---

## 11) Risks and Mitigations

1. Race conditions in winner picking.
   - Mitigation: backend transaction lock + idempotency key.
2. Chart payload size/performance.
   - Mitigation: downsample server-side + range limits + cached responses.
3. Ambiguity in season round-count rule.
   - Mitigation: finalize one rule in backend contract and expose in UI labels.
4. User confusion around multiple states.
   - Mitigation: simple timeline labels and explicit CTA text.

---

## 12) Immediate Next Implementation Ticket Set

1. FE: Wire chart icon to `/equb-insights` placeholder screen.
2. FE: Remove winner button from pool status, add to payout tracker.
3. BE: Add round-sequencing guard and error codes.
4. FE: Add winner eligibility state mapper.
5. FE/BE: Add basic popular/joined analytics endpoints + render first charts.
