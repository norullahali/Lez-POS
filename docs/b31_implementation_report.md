# B31 Implementation Report — Customer Quick Return UI Operation-Intent Idempotency

**Date:** 2026-10-19
**Baseline HEAD:** `336dd3f1df1742615c9da278f6d012bce8cc9398` (matches `origin/main`)
**Schema:** 51 (unchanged)
**Design reference:** `docs/b31_design_review.md`
**Discovery reference:** `docs/b31_discovery_report.md`

**Verification verdict:** **B31 IMPLEMENTATION VERIFIED**

---

## 1. Files changed

| File | Action |
|------|--------|
| `lib/features/returns/customer_quick_return_idempotency.dart` | **Added** — fingerprint helper, sticky state, submit runner |
| `lib/features/returns/screens/customer_returns_screen.dart` | **Modified** — quick-return path only |
| `test/customer_quick_return_idempotency_b31_test.dart` | **Added** — T1–T14 matrix |
| `docs/b31_implementation_report.md` | **Added** — this report |

**Unchanged (verified):** `PosSaleService`, `QuickReturnFingerprint`, DAO/table definitions, migrations, `customer_manual_return_idempotency.dart`, B30 manual-return screen wiring, B9 test sources.

---

## 2. Design conditions (§11)

| # | Condition | Evidence |
|---|-----------|----------|
| 1 | Separate quick runner/state from manual | `_quickReturnSubmitRunner` distinct from `_manualReturnSubmitRunner` |
| 2 | Remove dialog-open sticky clear | `_showQuickReturnDialog` no longer clears keys |
| 3 | Defer `clearReturnKey` until post-success refresh | Runner clears only after `postSuccessRefresh` succeeds |
| 4 | Retain key on conflict and post-commit refresh failure | T6/T7, T8, synthetic T8; screen conflict snackbar without clear |
| 5 | Include `approvedByUserId` in intent when passed to service | `QuickReturnSubmitIntent` + `_submitQuickReturnAfterApproval` unchanged order |
| 6 | No service/schema changes | `git diff` empty under `lib/core/services` and `lib/core/database` |

---

## 3. Fingerprint and approval semantics

- `computeQuickReturnIntentFingerprint` delegates to `QuickReturnFingerprint.compute` with `roundAmount` / `normalizeReason` parity with `PosSaleService.processQuickReturn`.
- Fields: `productId`, `quantity`, `refundAmount`, `reason`, `userId`, `approvedByUserId` (no session).
- Final `QuickReturnSubmitIntent` is built inside `_submitQuickReturn`, which is invoked only after the manager approval branch in `_submitQuickReturnAfterApproval` (cancel → no submit, no bind).
- Dialog payload `refundAmount` is passed through unchanged for both fingerprint and service call.

---

## 4. Lifecycle / financial evidence

- Sticky `fingerprintHash → UUID` via `CustomerQuickReturnIdempotencyState`.
- `CustomerQuickReturnSubmitRunner` enforces `_inFlight`, outcomes: success, postSuccessRefreshFailed, idempotencyConflict, serviceFailure, skippedInFlight.
- Integration tests use real `PosSaleService` + `AppDatabase.test` for T5–T8, T10–T11, T14.

---

## 5. Test commands and results

| Command | Result |
|---------|--------|
| `flutter test test/customer_quick_return_idempotency_b31_test.dart` | **16/16 passed** |
| `flutter test test/customer_manual_return_idempotency_b30_test.dart` | **14/14 passed** (regression sentinel) |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart --name "15)"` | **1/1 passed** |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart` | **26 passed, 4 failed** (see §6) |
| `dart analyze` (changed production + test files via IDE analyzer) | **No issues** |

---

## 6. B9 regressions (not modified in B31)

| Test | Classification |
|------|----------------|
| 22) migration v40 -> v41 creates table | **Expected (A)** — schema pin expects 50, app is 51 |
| 23) fresh v41 schema includes table | **Expected (A)** — same |
| 29) B2-B8 regression sentinel on v41 | **Expected (A)** — same |
| 27) UI conflict clears key for next attempt | **Expected (B)** — B31 retains sticky key on conflict; test expects new UUID on retry |

Service idempotency tests (1–21 incl. 15) remain green in full B9 run except the four above.

---

## 7. Analyzer, schema, encoding, diff

- `app_database.dart` `schemaVersion` remains **51**.
- NULL-byte check on new/changed Dart: **0** null bytes; UTF-8 (no UTF-16 BOM).
- `git diff --check` on tracked changes: **clean**.
- Manual-return code path: only contextual lines in diff; `_submitManualReturn` body not altered for B31 behavior.

---

## 8. Limitations

- No widget-level screen test for post-refresh failure (same optional gap as B30).
- `skippedInFlight` is silent (no snackbar).
- B9 UI test 27 will fail until a future B9 UI hygiene pass updates the contract assertion.

---

## 9. Final verdict

**B31 IMPLEMENTATION VERIFIED** — approved Option A UI idempotency for quick return is implemented; backend and B30 manual path unchanged; B31 test matrix green; B9 failures classified as pre-existing schema pins and expected UI contract change on test 27.