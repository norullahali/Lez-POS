# B29 Review Pass — Supplier Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-15  
**Mode:** READ-ONLY review (no code/test/schema changes)  
**References:** `docs/b29_design_review.md`, `docs/b29_implementation_report.md`  
**Baseline:** `b6db87d49f1c49d051ac7587ee128609f22625e0`, schema **51**

---

## 1. Review Scope

Verify B29 Option C implementation against approved design: fingerprint, sticky map, submit-time UUID, lifecycle, tests, backend boundary, encoding, and regression. Source code is authoritative; the implementation report is corroborating evidence only.

---

## 2. Actual Implementation Verification

| Artifact | Verified |
|----------|----------|
| `supplier_refund_settlement_intent_fingerprint.dart` | Present; SHA-256 over canonical JSON |
| `supplier_refund_settlement_idempotency.dart` | Present; `prepareSettlementKey` / `clearSettlementKey` |
| `supplier_refund_settlement_provider.dart` | `init()` no UUID; no `idempotencyKey` on `UiState`; submit-time binding |
| Dialog | Unchanged (still `init` / `reset` on close) |
| B28 customer provider | Same ordering and lifecycle pattern |

---

## 3. Fingerprint Contract Result

**PASS** — aligned with `SupplierRefundSettlementService._fingerprintMatches`.

| Field | Service | UI (`submit`) |
|-------|---------|---------------|
| `supplierId` | int equality | Same `current.supplierId` passed to `compute` and `settleCredit` |
| `amount` | ±0.0001 | Same `parsedAmount` double passed to `compute` and `settleCredit` (hash uses 6dp `_round` only inside fingerprint JSON) |
| `returnId` | nullable equality | Same `current.returnId` |
| `note` | `(note ?? '').trim()` | `noteForService = trim empty ? null : trim`; fingerprint uses `noteForService` → same normalization as service |

Excluded from fingerprint: `supplierName`, `availableCredit`, `returnLabel`, `amountText` (only parsed value matters).

**6dp collision note (OPTIONAL):** Two amounts that differ within service tolerance but differ beyond 6dp rounding could theoretically hash differently while still matching on replay with the *same* key; B28 accepts the same pattern. Not a B29-specific drift.

No fingerprint **BLOCKER** identified.

---

## 4. Key Lifecycle Result

**PASS** — matches approved design.

- **`init()`:** No UUID (lines 146–152).
- **`reset()`:** `state = null` only; `settlementIdempotency` map untouched (lines 155–158).
- **`submit()`:** Validation before `prepareSettlementKey` (lines 192–210); fingerprint + key at 212–224; service call 227–233.
- **Success:** `clearSettlementKey` after successful `await settleCredit` (236), before invalidates (238–239).
- **Failure / conflict:** Catch paths do not clear or rotate UUID (246–265).
- **No** `finally` clear, **no** hidden UUID in dialog, **no** key in `UiState`.

---

## 5. Post-Commit Ambiguity Result

**Partial PASS — test gap (SHOULD-FIX).**

**Code behavior:** After `settleCredit` succeeds, the notifier **always** clears the sticky slot (236) before UI refresh. That matches B28 and the approved design (“success/replay clears binding”). Sticky map **does** survive `reset()` while a binding remains (T9, T10 pre-commit failure path).

**Primary discovery scenario (K1 committed → UI loss → reopen → same key → replay):**

- **Protected when:** Key still in map (service failed before/during commit, or user retries before success handler clears).
- **T10** proves: failed first `submit` (no commit) → key retained → `reset()`/`init()` → same fingerprint → same key → second submit → **one REFUND**. Good UI/notifier proof for **failure retention + reopen**, not post-commit success.
- **T14** proves: manual sticky map + service replay → one REFUND. It does **not** exercise the notifier after a **successful** commit followed by `reset()`/reopen without clearing the map (notifier would have cleared on success).

**Ordering edge (SHOULD-FIX, B28 parity):** If `invalidateSupplierRefundDisplays` throws after `clearSettlementKey`, generic catch shows failure but key is already cleared → user could retry same intent with a **new** UUID → potential second REFUND. Same order as B28 customer provider.

No evidence that B29 reintroduces the pre-B29 “new UUID every `init()`” bug.

---

## 6. Intent Isolation Result

**PASS** — covered in code and tests.

- T2 supplierId; T3 amount; T5/T15 returnId null vs concrete; T6 note trim vs material change.
- Aggregate vs return-linked: separate fingerprint slots (T15).

---

## 7. Concurrency / Generation Result

**PASS** — unchanged guards.

- `isSubmitting` early return (184).
- `_submitGeneration` checked after await (234, 247, 256).
- **T16** (notifier): Completer gate — second `submit()` false, one service call.
- **T16** (service group): concurrent same-key → one REFUND (SR pattern).

B29 does not mint a second key on double-submit while first is in flight.

---

## 8. Success / Failure / Conflict Result

**PASS** with noted edge above.

- Success/replay: clear after await (236).
- `SupplierRefundSettlementException`: retain key, no rotation.
- **Gap:** No notifier integration test asserting `idempotencyKeyConflict` retains key (T13 tests map only) — **SHOULD-FIX** for regression confidence, not a current code defect.

---

## 9. Map Correctness Result

**PASS**

- Map is a **final** field on `SupplierRefundSettlementUiNotifier` (132–133); not recreated on `reset()`.
- Keys are SHA-256 fingerprint strings; `putIfAbsent` per intent.
- `clearSettlementKey` removes one slot only.

Map growth from abandoned failed intents: **OPTIONAL** (same as B28).

---

## 10. Backend Boundary Result

**PASS**

- `SupplierRefundSettlementService`, supplier refund DAO, schema/migrations: **no diff** in B29 scope.
- Dialog unchanged.
- Only financial write path remains `settleCredit` with idempotency key from UI orchestration.

---

## 11. Test Quality Result

**18 tests** — re-run this review: **18/18 passed**.

| Area | Assessment |
|------|------------|
| Fingerprint / isolation | Strong unit coverage (T1–T6, T15) |
| Sticky map | T7–T8, T11–T13 |
| Reset survives map | T9 direct; T10 notifier + reopen |
| Double submit | T16 Completer (not `Future.delayed`) |
| Post-commit replay | T14 service-level only |
| Conflict via notifier | Not covered end-to-end |

Tests prove invariants they target; critical **post-commit success + notifier reopen** path is under-proven (SHOULD-FIX).

---

## 12. Regression Result

Verified during implementation (reconfirmed B29 suite):

| Suite | Result |
|-------|--------|
| B29 | **18/18** |
| SR 3.3 UI step 3.1 | Pass |
| B28 | Pass |
| SR 3.0 | Pass except **J** (schema 35 vs app 51 — pre-existing, not B29) |

---

## 13. Encoding Result

**PASS** — new/changed Dart artifacts checked: UTF-8, **0 NULL bytes**, start bytes `69-6D-70` (`imp`).

---

## 14. Scope Result

**PASS** — production: fingerprint helper, idempotency state, provider only. Tests: `supplier_refund_settlement_idempotency_b29_test.dart`. Docs: implementation report. No schema/backend/dialog changes.

---

## 15. Findings Summary

### BLOCKER

None.

### SHOULD-FIX

| ID | Finding |
|----|---------|
| SF-01 | **T14** does not cover end-to-end notifier lifecycle after **successful** commit + `reset()`/reopen with same intent; it uses manual sticky state + service only. |
| SF-02 | **T10** covers **pre-commit failure** + reopen, not post-commit success + UI ambiguity while relying on uncleared key (notifier clears on success by design). |
| SF-03 | **Clear-before-invalidate order:** if invalidation throws after `clearSettlementKey`, UI failure + lost sticky binding (B28 parity; duplicate retry risk). |
| SF-04 | No notifier test for **`idempotencyKeyConflict`** → key retained, no rotation. |

### OPTIONAL

| ID | Finding |
|----|---------|
| OF-01 | Sticky map growth on distinct failed fingerprints (accepted B28 limitation). |
| OF-02 | Process-death in-memory map loss (documented out of scope). |
| OF-03 | 6dp hash vs raw amount edge within 0.0001 tolerance (B28 parity). |

---

## 16. Final Verdict

Implementation matches **approved Option C** design and B28 architecture. No blocker correctness defects found in source. Test gaps and invalidation ordering are meaningful but do not block merge readiness at review-pass stage.

**B29 REVIEW PASS WITH SHOULD-FIX**

---

## 17. Resolution (Review-Pass Fixes)

| ID | Status | Resolution |
|----|--------|------------|
| SF-01 | **Resolved** | Notifier test `SF-01/SF-02 post-commit refresh failure retains key reopen replay one REFUND` — commit via real service, simulated refresh failure, key retained, reset/reopen, same UUID, replay, one REFUND. |
| SF-02 | **Resolved** | Covered by the same notifier test (post-commit success path + UI refresh failure). **T10** retained for pre-commit failure. |
| SF-03 | **Resolved** | `submit()` now runs `supplierRefundPostSuccessRefreshProvider` **before** `clearSettlementKey`. Refresh failure leaves sticky binding; retry reuses key and backend replays. |
| SF-04 | **Resolved** | Notifier test `SF-04 conflict retains sticky UUID without rotation` — seeded idempotency conflict, submit fails, same key retained, no new UUID mint. |

**Verification (post-fix):** B29 **20/20**; SR 3.3 UI step 3.1 pass; B28 pass; SR 3.0 pass except historical **J** (schema 35 vs 51). Analyzer clean on provider. Schema **51** unchanged. No backend/DAO/dialog changes.

---

## 18. Post-Fix Status

Original findings in §15 remain for audit history. All **SHOULD-FIX** items above are implemented and verified.

**Pending:** Final Audit (not started).

**Review-pass fixes:** **COMPLETE** — does not supersede §16 historical verdict until Final Audit.
