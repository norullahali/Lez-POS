# B24 REVIEW PASS

**Date:** 2026-10-13
**Mode:** REVIEW ONLY — no code/test/schema/doc edits, no commit, no push
**Baseline:** `856f9a8e95e33f47432c1563637de7487bce607d` @ schema **v50**
**References:** `docs/b24_discovery_report.md`, `docs/b24_design_review.md`, `docs/b24_implementation_report.md`

---

## 1. Review Scope

Hostile review of B24 (C24-01) implementation: sticky POS cart-panel debt settlement idempotency key aligned with B6, without backend/schema changes.

---

## 2. Production Path Verification

| Step | Verified |
|------|----------|
| `_CartPanelState._settleDebt` (~667) | PASS |
| `PosRepository.settleDebt` (~104–115) | PASS — thin delegate |
| `CustomerAccountService.processPayment` | PASS — **unchanged** in git diff |
| `customer_payment_idempotency` | PASS — **unchanged** |

**Production callers of `settleDebt(` in `lib/`:** exactly **one** — cart icon `onPressed` (~1103) → `_settleDebt(...)`.

**Other customer `processPayment` paths:** `CustomerPaymentsScreen` only (separate UI channel; not a POS settle bypass).

**Verdict:** **PASS**

---

## 3. Sticky Key Verification

**Production evidence (`pos_screen.dart`):**

- Key state: `_settleDebtIdempotency` field on `_CartPanelState` (~605–606), not recreated per dialog.
- Minting: `prepareKey(..., generateUuid: _settleDebtUuid.v4)` (~725–729) uses `??=` inside helper — **not** `v4()` on every submit.
- Dialog closes before API (~714–720); sticky state survives `await showDialog` because it lives on `State`.
- **Reopen after failure:** new `_settleDebt` invocation reuses same `PosSettleDebtIdempotencyState` instance → `prepareKey` with unchanged `(customerId, amount, note)` → **same key** (helper test 2 / 13; production wiring is direct field reuse).
- Success: `onSuccessfulPayment()` (~739) after awaited `settleDebt` — clears key for fresh and B6 replay (no branch on `idempotentReplay`; completion implies success).
- Generic failure: `catch (e)` (~755–760) — **no** reset.
- Conflict: `onIdempotencyConflict()` (~748).
- `finally` (~762–764): only `_settleDebtInFlight = false` — **key not cleared**.

**Verdict:** **PASS**

---

## 4. Intent Binding Verification

**Helper `matchesBoundIntent` / `prepareKey` (`settle_debt_idempotency.dart`):**

| Parameter | Semantics | B6-aligned |
|-----------|-----------|------------|
| `customerId` | exact | YES |
| `amount` | `abs(delta) <= 0.0001` | YES (`posSettleDebtAmountTolerance`) |
| `note` | `note.trim()` vs stored `boundNote` | YES — matches B6 `normalizedNote` |

**Production:** fixed `kPosSettleDebtNote` passed to both `prepareKey` and `settleDebt` (~728, 737).

**Invalidation:** `prepareKey` calls `resetAttempt()` when key exists and intent mismatches (~49–55) **before** mint/use — old key cannot be sent with changed customer/amount/note.

**Verdict:** **PASS**

---

## 5. Failure / Replay Verification

| Scenario | Code behavior | Verdict |
|----------|---------------|---------|
| Generic exception | Key retained; in-flight cleared in `finally` | PASS |
| Success / replay | `onSuccessfulPayment()` clears key | PASS |
| Conflict | `onIdempotencyConflict()` clears key + error snackbar | PASS |
| Key in `finally` | Not cleared | PASS |

**Verdict:** **PASS**

---

## 6. Concurrency Verification

- `_settleDebtInFlight` guard at start of `_settleDebt` (~669) — second entry while API pending returns before dialog/`prepareKey`.
- `prepareKey` invoked once per confirmed submit (~725).
- `generateUuid` not invoked on reuse (`uuidSeq` test 2).

`canStartSettleDebtSubmit` documents the guard; production uses inline `if (_settleDebtInFlight) return`.

**Verdict:** **PASS**

---

## 7. Helper Review

| Question | Assessment |
|----------|------------|
| UI-only? | YES — no DB, no B6 calls |
| Hidden backend semantics? | NO |
| Tolerance / note | Matches B6 |
| Inconsistent with production intent? | NO — production passes same triple as repository |
| Complexity | Minimal (~70 lines) |

**Note (OPTIONAL):** `@visibleForTesting` on a class used in production is slightly misleading; not a correctness defect.

**Verdict:** **PASS** (one OPTIONAL annotation nit)

---

## 8. Integration Test Assessment

**Gap stated:** no full widget test for `_settleDebt`.

**Assessment:** **Helper-only coverage is sufficient.**

Reason: production integration reduces to (1) persistent `State` field + (2) `prepareKey` only on post-dialog confirm. Test **13** models cancel/reopen as two `prepareKey` calls without reset — equivalent to failure → reopen → same intent. Mis-wiring would require resetting state on dialog open/cancel or minting in `build()` — absent in code review.

**Verdict:** **PASS** — widget test not required for B24 correctness.

---

## 9. B6 Contract Verification

- No new idempotency table, DAO, or service changes in diff.
- No duplicate conflict/replay logic in B24 helper (only UI parameter binding).
- B6 test **15** still validates `PosRepository.settleDebt` replay with sticky key.

**Verdict:** **PASS**

---

## 10. Dispose / State Lifetime Assessment

Pending key lost when `_CartPanelState` is disposed (route/panel teardown).

**Classification:** **acceptable**

- Normal rebuild: `State` preserved — key retained.
- Payment already sealed in B6 if success occurred before dispose; UI key loss does not double-pay.
- Ambiguous retry after dispose: operator can use Customer Payments screen (separate channel).
- No business requirement for cross-session POS settle retry persistence.

**Verdict:** **PASS**

---

## 11. Regression Results

| Suite | Result (this review run) |
|-------|--------------------------|
| B24 `pos_settle_debt_idempotency_b24_test.dart` | **15/15 pass** (included in combined run) |
| B6 `customer_payment_idempotency_b6_test.dart` | **15/15 pass** |
| B5 `pos_sale_idempotency_b5_test.dart` | **11/11 pass** |
| **Total** | **41/41 pass** |
| `analyze_files` (`lib/features/pos`, B6 service) | **0 errors** |
| `git diff --check` | **clean** |
| `schemaVersion` | **50** (unchanged) |
| Generated DB / migration diff | **none** |

---

## 12. Static Bypass Search

| Search | Result |
|--------|--------|
| `settleDebt(` in `lib/` | `pos_repository.dart` definition + `pos_screen.dart` single caller |
| `processPayment(` customer path in POS | Only via `PosRepository.settleDebt` |
| Alternate POS in-cart debt payment | **None found** |

**Verdict:** **PASS**

---

## 13. File Scope Verification

| Expected | Status |
|----------|--------|
| `lib/features/pos/screens/pos_screen.dart` | Modified (tracked) |
| `lib/features/pos/settle_debt_idempotency.dart` | New (untracked) |
| `test/pos_settle_debt_idempotency_b24_test.dart` | New (untracked) |
| `docs/b24_implementation_report.md` | New (untracked) |
| B6 / schema / repository | **Not modified** |

**Verdict:** **PASS**

---

## 14. Findings by Severity

| ID | Finding | Severity |
|----|---------|----------|
| F1 | Sticky key lifecycle matches approved B24 design | **PASS** |
| F2 | Dialog-close-before-API + State-held key enables retry without remint | **PASS** |
| F3 | Intent invalidation before submit prevents old-key/changed-intent | **PASS** |
| F4 | B6 unchanged; single production settle path | **PASS** |
| F5 | Helper-only tests sufficient for integration glue | **PASS** |
| F6 | Dispose loses pending UI key — acceptable | **PASS** |
| F7 | Arabic amount normalization omitted — safe for B24 scope | **PASS** |
| F8 | `@visibleForTesting` on production-used class | **OPTIONAL** |

**BLOCKER:** none
**SHOULD-FIX:** none
**REQUIRED FIXES:** none

---

## 15. Required Fixes

None.

---

## 16. Final Review Verdict

**REVIEW PASS**

Implementation satisfies approved B24 design. C24-01 retry/financial-integrity objective is met in production wiring; regressions green; scope contained.

---

**End of B24 review pass.**
