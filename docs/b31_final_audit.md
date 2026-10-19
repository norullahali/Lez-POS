# B31 Final Audit — Customer Quick Return UI Operation-Intent Idempotency

**Date:** 2026-10-19
**Milestone:** B31
**Mode:** READ-ONLY FINAL AUDIT (no code/test/doc edits except this file)
**Workflow stage:** Final Audit → eligible next step: **Commit Preparation** (not executed in this task)

**References:** `docs/b31_design_review.md`, `docs/b31_implementation_report.md`, `docs/b31_review_pass.md`

---

## 1. Baseline and workspace safety

| Check | Evidence |
|-------|----------|
| Branch | `main` |
| HEAD | `336dd3f1df1742615c9da278f6d012bce8cc9398` |
| `origin/main` | `336dd3f1df1742615c9da278f6d012bce8cc9398` |
| HEAD == origin/main | **Yes** (matches expected baseline) |
| B31 committed | **No** (uncommitted workspace as required) |
| Tracked diff vs HEAD | **One file:** `lib/features/returns/screens/customer_returns_screen.dart` (56 insertions, 56 deletions) |
| `git diff --check HEAD` | **Clean** (no trailing-space/conflict markers reported) |

### Untracked files (inventory)

**B31 milestone artifacts (this delivery):**

| Path | Role |
|------|------|
| `lib/features/returns/customer_quick_return_idempotency.dart` | Production helper |
| `test/customer_quick_return_idempotency_b31_test.dart` | B31 test matrix |
| `docs/b31_design_review.md` | Approved design |
| `docs/b31_discovery_report.md` | Discovery |
| `docs/b31_implementation_report.md` | Implementation evidence |
| `docs/b31_review_pass.md` | Independent review pass |
| `docs/b31_final_audit.md` | This audit |

**Pre-existing unrelated untracked (not part of B31 commit scope unless explicitly chosen later):** other `docs/b*_*.md`, `docs/customer_returns_*`, `docs/post_b*_*.md`, `tool/*.dart`, `tool/*.py`, etc. (present before B31; preserved untouched).

**Unexpected tracked changes:** None beyond the customer returns screen quick-return path.

**B30 / unrelated modules:** `git diff HEAD -- lib/core lib/features/returns/customer_manual_return_idempotency.dart` is **empty**. No tracked edits to B30 helper, services, DAOs, schema, or migrations.

---

## 2. Approved scope verification

| Expected B31 surface | Status |
|---------------------|--------|
| `lib/features/returns/customer_quick_return_idempotency.dart` | Present (untracked new) |
| `lib/features/returns/screens/customer_returns_screen.dart` | Only tracked production change; diff limited to quick-return imports, runner wiring, `_submitQuickReturn`, `_showQuickReturnDialog` (removed `_clearQuickReturnAttempt`, pending payload matching) |
| `test/customer_quick_return_idempotency_b31_test.dart` | Present (untracked new) |
| B31 docs | Present (untracked) |

**Production file count changed at HEAD:** 1 (`customer_returns_screen.dart`).

**Manual return (B30):** `_submitManualReturn` and `_manualReturnSubmitRunner` usage unchanged in diff hunks (no +/- on manual submit body). `customer_manual_return_idempotency.dart` not modified in workspace vs HEAD.

**Out of scope (confirmed unchanged in tracked diff):** `PosSaleService`, `QuickReturnFingerprint`, DAO/tables/migrations, supplier/invoice returns, POS session guards, unrelated features.

---

## 3. Design and financial safety (independent)

Verified against `docs/b31_design_review.md` and source.

| Requirement | Independent evidence |
|-------------|---------------------|
| Dedicated quick sticky state + runner | `CustomerQuickReturnIdempotencyState`, `CustomerQuickReturnSubmitRunner`; screen field `_quickReturnSubmitRunner` separate from `_manualReturnSubmitRunner` |
| Fingerprint = `QuickReturnFingerprint.compute` + normalization | `computeQuickReturnIntentFingerprint` mirrors service (`roundAmount`, `normalizeReason`, fields incl. `approvedByUserId`) |
| Stable `refundAmount` | Dialog computes once → `QuickReturnPayload.refundAmount` → intent → `processQuickReturn` same fields |
| No session in fingerprint | Intent/service fields only |
| Dialog open/cancel does not clear binding | No map clear on `_showQuickReturnDialog`; cancel returns before `_submitQuickReturn` |
| Approval cancel: no submit, no bind | `approver == null` → return (L577–578); `prepareReturnKey` only inside `submit()` |
| Retain key on service failure, conflict, post-commit refresh failure | Runner: no `clearReturnKey` in catch branches; refresh failure returns before clear |
| Clear only after service success + refresh success | `clearReturnKey` after successful `postSuccessRefresh` only |
| Selective clear | `clearReturnKey(fingerprintHash)` per completed intent |
| In-flight duplicate blocked | `_inFlight` + `skippedInFlight`; dialog disables on `inFlight` |
| Intentional identical return after full success | New UUID after slot cleared (T11) |
| No silent premature clear | Screen outcome `switch` has no sticky-map mutations |

Financial authority remains **service-level** idempotency; UI sticky map is Option A overlay per approved design.

---

## 4. Test evidence (audit re-run)

Commands executed during this audit:

| Command | Outcome |
|---------|---------|
| `flutter test test/customer_quick_return_idempotency_b31_test.dart` | **16/16 passed** (combined run with B30 below) |
| `flutter test test/customer_manual_return_idempotency_b30_test.dart` | **14/14 passed** (30 total in single invocation) |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart --name "15)"` | **1/1 passed** |
| `flutter test test/customer_quick_return_idempotency_b9_test.dart` | **26 passed, 4 failed** |
| `dart analyze` (B31 prod + test paths) | **No issues** |
| Schema | **51** (`app_database.dart`) |
| NULL bytes / encoding (B31 Dart) | **0** null bytes; UTF-8 (`105,109,112` = `imp`) |
| `git diff --check HEAD` | **Clean** |

### B9 four failures — verified assertions (tests not edited)

| Test | Source assertion | Root cause | Classification |
|------|------------------|------------|----------------|
| **22** | `expect(migrated.schemaVersion, 50)` | Current app schema **51** | Obsolete pin — **not a B31 defect** |
| **23** | `expect(db.schemaVersion, 50)` | Same | Obsolete pin |
| **29** | `expect(regressionDb.schemaVersion, 50)` | Same | Obsolete pin |
| **27** | `expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]))` after conflict then retry | B31 retains sticky key on conflict (approved contract) | Obsolete UI expectation — **not a B31 defect** |

Service idempotency tests **1–21** (including **15**) pass within the full B9 run except **22, 23, 29**. UI test **28** passes under B31 (cancel without submit never bound a key).

Integration tests **T5–T8, T10–T11, T14** use real `PosSaleService` + `AppDatabase.test` for return/stock invariants (audit inspected test source; not mocked DB replay for critical paths).

---

## 5. Findings by severity

### BLOCKER

None.

### SHOULD-FIX

None for B31 production correctness or approved scope. Review Pass identified no SHOULD-FIX; audit confirms.

### OPTIONAL (documented, non-gating)

1. Future B9 hygiene: update schema pins (22, 23, 29) to 51; revise UI test 27 for sticky-key contract.
2. Optional widget-level quick-return lifecycle test (screen + runner).
3. Optional UX for `skippedInFlight` and generic `serviceFailure` snackbar (B30 parity).

These do **not** block Commit Preparation.

---

## 6. Final verdict

**B31 FINAL AUDIT PASS**

B31 is **eligible to proceed to Commit Preparation**. This audit did **not** stage, commit, or push. Only `docs/b31_final_audit.md` was added.

---

## 7. Commit Preparation readiness (informational only)

When Commit Preparation runs, expected explicit paths (no `git add .`):

- `lib/features/returns/customer_quick_return_idempotency.dart`
- `lib/features/returns/screens/customer_returns_screen.dart`
- `test/customer_quick_return_idempotency_b31_test.dart`
- B31 documentation as agreed (design, discovery, implementation, review pass, final audit)

Exclude unrelated untracked docs/tools unless explicitly in scope.

Final Audit complete.