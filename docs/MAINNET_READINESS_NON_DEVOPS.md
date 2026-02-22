# Mainnet Readiness (Non-DevOps)

Date: 2026-02-22
Scope: Product, protocol, backend/frontend architecture requirements before mainnet launch.
Out of scope: Deployment pipeline, cloud infra, observability hosting, and other DevOps operations.

---

## P0 — Must Have Before Mainnet

### 1) Independent smart-contract security audit
- Complete third-party audit for all protocol contracts:
  - `EqubPool`, `PayoutStream`, `CollateralVault`, `CreditRegistry`, `IdentityRegistry`, `TierRegistry`.
- Resolve all High/Critical findings before go-live.
- Add invariant and fuzz testing for:
  - Round transitions,
  - Slashing correctness,
  - Payout correctness,
  - Tier/credit consistency,
  - Identity one-to-one constraints.

### 2) Finalize trust and custody model
- Remove or strictly constrain any backend path that can move/issue user-value in production mode without explicit user signing.
- Define and enforce clear on-chain/admin authorization boundaries.
- Document exactly which actor can do what (user wallet, backend service, protocol admin).

### 3) Protocol safety controls and governance rules
- Ensure emergency controls exist and are tested (pause/freeze scope and unpause flow).
- Ensure sensitive parameter changes are bounded and delayed (timelock/governance delay where applicable).
- Enforce immutable/locked settings for critical constants once production starts.

### 4) Real identity integration and lifecycle
- Replace mocked Fayda verification with production integration.
- Add revocation/appeal/dispute lifecycle behavior for identity edge cases.
- Ensure identity state changes cannot silently desync between off-chain records and on-chain binding.

### 5) On-chain truth and reconciliation guarantees
- Define canonical source of truth and finality policy (e.g., confirmation depth).
- Handle chain reorgs deterministically in indexer and DB projections.
- Add replay-safe idempotency for all state-changing event handlers.

---

## P1 — Strongly Recommended Before Mainnet

### 6) Economic and adversarial stress validation
- Simulate extreme default scenarios and cascading slashing behavior.
- Validate payout fairness and insolvency prevention under stress conditions.
- Validate tier/credit progression under malicious or edge-user behavior.

### 7) Authorization hardening across backend APIs
- Review every privileged endpoint for least-privilege access.
- Formalize role matrix for user/admin/system/indexer actions.
- Ensure all sensitive actions are auditable and non-repudiable.

### 8) Unified transaction state machine
- Standardize lifecycle states across app/backend/notifications:
  - `pending -> confirmed -> failed/reverted`.
- Remove ambiguous UX outcomes where blockchain state and UI state can diverge.
- Ensure retry/reconnect paths do not duplicate side effects.

---

## P2 — Quality, Compliance, and Operational Safety in Product Architecture

### 9) Immutable business audit trail
- Keep a tamper-evident event trail for:
  - Identity bind,
  - Pool create/join,
  - Contribution,
  - Default/slash,
  - Payout events.
- Support dispute reconstruction with deterministic event history.

### 10) Data minimization and privacy boundaries
- Minimize identity-linked stored data to required fields only.
- Define retention and deletion policy in code-level behavior.
- Keep strict separation between identity-sensitive data and protocol event data.

---

## Project-Specific Immediate Gaps (from current docs/state)

- `docs/mvp-checklist.md` still lists:
  - Fayda real integration (pending),
  - Smart contract security audit (pending).
- Terminal history indicates unresolved quality signals (`start:dev`, `flutter analyze`, and some test commands failing in certain contexts), which should be fully stabilized before a mainnet freeze.

---

## Suggested Go/No-Go Gate

Mainnet should be **No-Go** until all P0 items are complete and verified with evidence (test reports, audit report, signed-off architecture decisions).
