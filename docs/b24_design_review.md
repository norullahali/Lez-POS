# B24 DESIGN REVIEW

**Date:** 2026-10-13
**Mode:** DESIGN ONLY — no production/test/schema changes, no commit, no push
**Baseline:** `856f9a8e95e33f47432c1563637de7487bce607d` @ schema **v50**
**Discovery candidate:** C24-01 — POS in-cart customer debt settlement intent protection
**Discovery report:** `docs/b24_discovery_report.md`

---

## 1. Design Review Summary

B24 closes a **UI channel gap** on an already-protected B6 backend. The POS cart-panel debt settlement path mints a **new UUID on every confirmed submit**, so a retry after an ambiguous failure can post a **second payment**. The fix is **sticky idempotency key + bound intent parameters** on the widget state that owns `_settleDebt`, with **no** backend, schema, or repository changes.

**Naming correction (code truth):** `_settleDebt` lives on **`_CartPanelState`** inside `lib/features/pos/screens/pos_screen.dart`, not on a separate `PosScreen` state class. There is **one production entry point** (cart-panel settle-debt icon).

**Verdict:** **DESIGN APPROVED** (implementation-ready; see Section 20).

---

## 2. Current Production Flow

| Step | Location | Behavior |
|------|----------|----------|
| 1 | `_CartPanelState` cart header (~1079–1095) | Settle icon when selected customer `id != 1` and balance `> 0` |
| 2 | `_settleDebt(customerId, currentBalance, customerName)` (~664) | Early exit if `_settleDebtInFlight` |
| 3 | Dialog | Amount in `TextField`; **no note field** |
| 4 | Confirm | Dialog closes **before** DB call |
| 5 | Post-dialog (~718–754) | **`_settleDebtUuid.v4()` every time**; `settleDebt(...)` |
| 6 | `PosRepository.settleDebt` (~104–115) | `CustomerAccountService.processPayment` |
| 7 | B6 | `customer_payment_idempotency` insert or replay |

| Parameter | Source | Mutable before retry? |
|-----------|--------|------------------------|
| `customerId` | Cart at button press | Yes |
| `amount` | Dialog after confirm | Yes (each dialog open) |
| `note` | Constant `'تسوية دين من POS'` (~729) | No user input |

After failure, user reopens settle via icon; API runs outside dialog; only `_CartPanelState` persists retry state.

---

## 3. B6 Idempotency Contract

**Service:** `CustomerAccountService.processPayment` (`customer_account_service.dart`).

**Table:** `customer_payment_idempotency` — PK `idempotency_key`; columns `customer_id`, `amount`, `note`, `customer_transaction_id`.

**No SHA fingerprint column.** Replay guard is `_parametersMatch` (~139–149):

| Parameter | Rule |
|-----------|------|
| `customerId` | Exact |
| `amount` | abs delta `<= 0.0001` |
| `note` | Exact on `(note ?? '').trim()` |

Same key + match → `idempotentReplay: true`, no second PAYMENT. Same key + mismatch → `CustomerPaymentIdempotencyConflictException` (tests 4–5). Different keys → independent payments (test 6). Amount `<= 0` → `ArgumentError`, no row (test 7).

`PosRepository.settleDebt` is pass-through; B6 test **15** proves replay with sticky caller key and note `'تسوية دين من POS'`.

---

## 4. Root Cause of C24-01

Line ~722 assigns `final idempotencyKey = _settleDebtUuid.v4();` on every confirm → B6 sees a new payment per attempt.

**Reference:** `CustomerPaymentsScreen` uses `_idempotencyKey ??= v4()`, clears on success only (~75, 92), retains on error (~101–110), resets on customer change (~173–176). POS must also invalidate on **amount** change (re-entered each dialog).

---

## 5. Proposed Architecture

B6 authoritative; UI-only alignment.

```
_CartPanelState
  _settleDebtInFlight (existing)
  _settleDebtIdempotencyKey
  bound snapshot: customerId, amount, note

On submit after dialog confirm:
  if key != null && intent != snapshot → reset
  key ??= Uuid.v4(); update snapshot
  settleDebt(key, ...)
  success (incl. replay) → reset
  generic failure → retain
  conflict → reset

Repository / service / DAO / table: unchanged
```

Optional: `@visibleForTesting` pure helper in same library for B24 unit tests (not a new backend service).

---

## 6. Idempotency Key Lifecycle

| Event | Key | Snapshot |
|-------|-----|----------|
| After success | null | cleared |
| Dialog cancel | unchanged | unchanged |
| First confirm submit | mint if null | set |
| Retry same intent after error | reuse | unchanged |
| Success (fresh or replay) | clear | clear |
| Generic failure | retain | retain |
| ConflictException | clear | clear |
| Parameter change (§7) | clear then mint on submit | replace |

Mint on **submit**, not dialog open.

---

## 7. Intent Change Rules

At submit, compare to bound snapshot with B6 rules.

| Change | Action |
|--------|--------|
| customerId | Invalidate → new key |
| amount | Invalidate → new key |
| note | Fixed in UI; invalidate if constant ever changes |

Never submit same key with changed parameters without prior invalidation (B6 would conflict).

---

## 8. Retry / Failure Semantics

| Case | Behavior |
|------|----------|
| A. In-flight double submit | `_settleDebtInFlight` |
| B. Committed, UI error, retry same intent | Same key → B6 replay |
| C. Amount changed | Invalidate before call → new key |
| D. Customer changed | Invalidate → new key |
| E. Note changed | N/A today (fixed note) |
| F. Cancel after failed attempt | Retain key (no submit) |
| G. New settlement after success | Key cleared on prior success |
| H. Rebuild | State fields persist; no mint in `build()` |

Treat `idempotentReplay` as success (snackbar + clear key). **Do not** clear key in `finally`. On conflict: error snackbar + reset attempt state.

---

## 9. Concurrency Semantics

Panel-level in-flight guard; B6 handles same-key seal races. No cross-device shared POS intent.

---

## 10. UI State Ownership

Sticky key + snapshot on **`_CartPanelState`**. Not repository, global provider, or SharedPreferences. Dispose clears pending UI intent (acceptable edge case).

---

## 11. Backend Impact

**None** for `CustomerAccountService`, DAO, table, `PosRepository.settleDebt`.

---

## 12. Schema / Migration Impact

**No** schema bump, table, DAO, service, exception, or result type. UI-only lifecycle.

---

## 13. Exact Files Expected to Change

| File | Change |
|------|--------|
| `lib/features/pos/screens/pos_screen.dart` | Sticky key + intent binding in `_CartPanelState` |
| `test/pos_settle_debt_idempotency_b24_test.dart` | New lifecycle tests |

---

## 14. Test Strategy

**B24 file:** Test intent/key resolver with deterministic keys — mint, reuse, clear on success, retain on failure, invalidate on customer/amount/note mismatch, conflict reset, second intent after clear.

**B6 regression:** Replay, conflict, two keys, `PosRepository.settleDebt` (test 15) — do not duplicate.

**Widget tests:** Optional; helper unit tests preferred.

---

## 15. Invariants

| ID | Invariant |
|----|-----------|
| I1 | One active intent ↔ one key until cleared |
| I2 | Same intent retry reuses key |
| I3 | Success (incl. replay) clears key |
| I4 | Failure retains key (except conflict) |
| I5 | Parameter change invalidates before submit |
| I6 | In-flight prevents double API call |
| I7 | B6 authoritative |
| I8 | No second idempotency table |
| I9 | No schema migration |
| I10 | Same-intent retry cannot double-pay |
| I11 | No mint in `build()` / `finally` |
| I12 | POS note remains fixed settle string |

---

## 16. Risk Analysis

Stale key in local variable; clear in `finally`; amount/customer change without invalidation; panel dispose with pending key (acceptable). **Implementation quality:** add Arabic digit normalization for amount parse (parity with payments screen) when touching file — non-blocking.

---

## 17. Rejected Alternatives

POS idempotency table; SharedPreferences; backend dedupe window; stateless repository holding key; new key on every dialog open; retain key on conflict after parameter edit.

---

## 18. Implementation Plan

1. State fields + `_resetSettleDebtAttempt()`.
2. `_prepareSettleDebtKey(...)` with tolerance `0.0001`.
3. Replace per-attempt `v4()`.
4. Success and conflict → reset; generic error → retain.
5. Extract testable helper + B24 tests.
6. Run B6 + B24 + analyzer.

---

## 19. Review Checklist

Sticky `??=`; B6 parameter binding; success/failure/conflict key rules; no backend/schema changes; single entry point; B24 tests not duplicating B6; replay = success.

---

## 20. Final Design Verdict

**DESIGN APPROVED**

Implementation-ready. Apply Arabic amount normalization as optional quality fix in the same change set.

---

**End of B24 design review.**
