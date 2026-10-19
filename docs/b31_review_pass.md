# B31 Review Pass — Customer Quick Return UI Operation-Intent Idempotency

**Date:** 2026-10-19
**Mode:** READ-ONLY (no production/test/schema/git changes)
**Baseline HEAD:** `336dd3f1df1742615c9da278f6d012bce8cc9398` (equals `origin/main`)
**Schema:** 51
**References:** `docs/b31_design_review.md`, `docs/b31_implementation_report.md`, `docs/b30_review_pass.md`

Implementation report used as pointers only; conclusions below are from independent source inspection, diffs, and test re-runs.

---

## 1. Workspace and baseline

| Check | Result |
|-------|--------|
| Branch HEAD | `336dd3f1df1742615c9da278f6d012bce8cc9398` |
| `origin/main` | Same SHA |
| B31 committed? | **No** — B31 artifacts remain uncommitted (expected) |
| Tracked diff vs HEAD | `M lib/features/returns/screens/customer_returns_screen.dart` only |
| Untracked B31 | `customer_quick_return_idempotency.dart`, `customer_quick_return_idempotency_b31_test.dart`, `docs/b31_implementation_report.md`, design/discovery docs |
| Unexpected tracked changes | None beyond quick-return screen path |
| `git diff --check` (tracked) | Clean |

---

## 2. Independent source review

### 2.1 Architecture

| Requirement | Evidence |
|-------------|----------|
| Dedicated quick runner/state | `_quickReturnSubmitRunner` + `CustomerQuickReturnSubmitRunner` separate from `_manualReturnSubmitRunner` (`customer_returns_screen.dart:85–88`) |
| Fingerprint delegation | `computeQuickReturnIntentFingerprint` → `QuickReturnFingerprint.compute` with `roundAmount` / `normalizeReason` (`customer_quick_return_idempotency.dart:17–24`) |
| Service parity | Same field order and normalization as `PosSaleService.processQuickReturn` (`pos_sale_service.dart:325–336`) |
| No session in fingerprint | Intent fields match service contract only; no session parameter added |
| `approvedByUserId` | On `QuickReturnSubmitIntent`; set in `_submitQuickReturn` after approval branch (`customer_returns_screen.dart:161–172`, `566–583`) |
| Stable `refundAmount` | Computed once in dialog (`productPrice * qty`, L546–552); stored on payload → intent → service (L165–187) |
| No clear on dialog open | `_clearQuickReturnAttempt` removed; `_showQuickReturnDialog` no longer clears (`diff` vs HEAD) |
| No clear on conflict / failure / refresh failure | Runner returns outcomes without `clearReturnKey`; screen `switch` only shows snackbars (L202–232) |
| Clear after success + refresh | `clearReturnKey(fingerprintHash)` only after `postSuccessRefresh` succeeds (`customer_quick_return_idempotency.dart:119–126`) |
| Selective clear | Per-fingerprint `remove`, not map-wide |
| In-flight guard | `_inFlight` in runner (`:105–107`, `:115`, `:131–133`); dialog button uses `_quickReturnSubmitRunner.inFlight` (L534) |
| Cancel / approval cancel | Dialog cancel → `payload == null` → no `_submitQuickReturn` (L564); approval `approver == null` → return before submit (L577–578) — **no** `prepareReturnKey` until `submit()` |
| Manual path isolation | `git diff HEAD -- customer_returns_screen.dart`: manual block unchanged; separate UUID constants and runners |

### 2.2 Scope boundary

`git diff HEAD -- lib/core/services lib/core/database lib/features/returns/customer_manual_return_idempotency.dart`: **empty**.

Backend idempotency remains authoritative in `PosSaleService.processQuickReturn`; UI layer is Option A sticky map only (per design).

### 2.3 UI / exception handling

- **Conflict:** `QuickReturnIdempotencyConflictException` → `idempotencyConflict`; sticky key retained; snackbar does not clear map.
- **Post-commit refresh failure:** Distinct outcome and snackbar (“تم الاسترجاع لكن تعذر تحديث العرض…”); key retained for replay.
- **Service failure:** Generic snackbar (no longer surfaces `e.toString()`); key retained. Matches B30 manual pattern; does not affect financial idempotency.
- **Success on idempotent replay:** `invokeService` uses `.then((_) {})`; replay still runs refresh and clears slot after refresh — correct for “complete success” UX.

No code path in screen or runner clears sticky state on failure outcomes.

---

## 3. Design compliance matrix (§11)

| # | Condition | Verdict |
|---|-----------|---------|
| 1 | Separate quick runner/state | **Met** |
| 2 | Remove dialog-open sticky clear | **Met** |
| 3 | Defer clear until post-success refresh | **Met** |
| 4 | Retain key on conflict and post-commit refresh failure | **Met** |
| 5 | Include `approvedByUserId` when passed to service | **Met** |
| 6 | No service/schema changes | **Met** |

---

## 4. Financial correctness (integration tests)

Reviewed `test/customer_quick_return_idempotency_b31_test.dart` and re-ran suite. Critical cases use **real** `PosSaleService` + `AppDatabase.test` (not mocked replay for DB invariants).

| ID | Design claim | Evidence |
|----|--------------|----------|
| A | Pre-commit failure + safe retry | **T5**: synthetic pre-commit throw; key retained; second submit calls real `processQuickReturn`; `returnCount == 1`, `calls == 2` |
| B | Commit then refresh failure, retry same key | **T6/T7**: real service commit; refresh throws once; key non-null |
| C | One return, one stock delta after retry | **T6/T7**: `returnCount == 1`, `stockLevel == initialStock + 1` after both attempts |
| D | Real same-key different-payload conflict | **T8 real**: seal qty 1 with K; runner submit qty 2 reusing K |
| E | No extra return/stock on conflict | **T8 real**: counts and stock unchanged after conflict outcome |
| F | Conflict retains fp→key binding | **T8 real**: `keyForFingerprint(intentConflict.fingerprintHash) == sealedKey` |
| G | Success clears only completed fp slot | **T10**: two fingerprints; complete one; pending binding unchanged; map size 1 |
| H | Later identical return → new key, second row/stock | **T11**: `mintSeq == 2`, `returnCount == 2`, stock +2 |
| I | Concurrency via Completer | **T9**: `Completer` gate; second `skippedInFlight`; `calls == 1` |
| J | Approval in fingerprint + service | **T14 unit**: null vs 99 different hash; **T14 integration**: sealed row `fingerprintHash == intent.fingerprintHash` with real manager user FK |

Synthetic **T8s** retained for fast runner-path conflict retention (acceptable per design optional row).

---

## 5. Test execution (review re-run)

| Command | Outcome |
|---------|---------|
| `flutter test test/customer_quick_return_idempotency_b31_test.dart` | **16/16 passed** |
| `flutter test test/customer_manual_return_idempotency_b30_test.dart` | **14/14 passed** |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart --name "15)"` | **1/1 passed** |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart` | **26 passed, 4 failed** |
| `dart analyze` (B31 production + test files) | **No issues** |

---

## 6. B9 failure classification (verified, tests not edited)

| Test | Assertion (source) | Cause | Classification |
|------|-------------------|-------|----------------|
| **22** migration v40→v41 | `expect(migrated.schemaVersion, 50)` (`b9_test.dart:603`) | App `schemaVersion` is **51** | **Expected (A)** schema pin drift — not introduced by B31 |
| **23** fresh v41 schema | `expect(db.schemaVersion, 50)` (`:608`) | Same | **Expected (A)** |
| **29** B2–B8 sentinel | `expect(regressionDb.schemaVersion, 50)` (`:615`) | Same | **Expected (A)** |
| **27** UI conflict clears key | After conflict, second submit expects **different** UUID (`keysUsed[0] isNot keysUsed[1]`, `:1109–1110`) | B31 **retains** sticky key on conflict (design §4.4) | **Expected (B)** contract change — same class as B10/27 after B30 |

**Other B9 UI tests:** **28** (“opening new dialog clears previous pending key”) **passes** under B31: scenario cancels dialog without ever calling `submit`, so no key was bound; one submit → one key. Title reflects pre-B31 behavior but assertion still valid.

Service idempotency tests **1–21** (including **15**) pass within the full B9 run except tests **22, 23, 29** above.

No unexplained failures beyond the four classified rows.

---

## 7. B30 regression

| Check | Result |
|-------|--------|
| B30 suite | **14/14 passed** (review re-run) |
| Manual helper file | No diff vs HEAD |
| Screen manual path | `_submitManualReturn` body unchanged in B31 diff (only quick-return hunk + imports) |
| Quick path pre-B30 | Old `_quickReturnIdempotencyKey` / `_clearQuickReturnAttempt` removed; manual sticky runner untouched |

---

## 8. Analyzer, schema, encoding

| Check | Result |
|-------|--------|
| `schemaVersion` | **51** (`app_database.dart:221`) |
| NULL bytes (B31 Dart files) | **0** |
| Encoding | UTF-8 (`import` lead bytes `69 6D 70`) |
| `git diff --check` | Clean on tracked changes |

---

## 9. Findings by severity

### BLOCKER

None.

### SHOULD-FIX

None. B31 test matrix already includes runner-level **T10** and real-service **T8** (items that were SHOULD-FIX for B30 at initial review).

### OPTIONAL

1. **Widget-level** quick-return lifecycle test through `CustomerReturnsScreen` (post-refresh failure / conflict retention UI), mirroring optional B30 gap — runner + DB coverage is sufficient for financial safety today.
2. **`skippedInFlight`** user feedback (silent return; design P3).
3. **B9 hygiene:** Update schema pins (22, 23, 29) to 51 and UI test **27** (and optionally rename **28**) in a future B9 pass — out of B31 scope.
4. **Generic `serviceFailure` snackbar** hides underlying validation errors (parity with B30 manual UX).

---

## 10. Final verdict

**B31 REVIEW PASS**

Implementation matches the approved B31 design on fingerprint contract, sticky lifecycle, manager-approval ordering, post-commit financial safety (real service/DB in T5–T8, T10–T11), concurrency control, and scope boundaries. No duplicate-return or duplicate-stock defect identified under the approved single-screen model. B9 failures are explained and classified; B30 remains intact.

Review Pass complete — no fixes applied.