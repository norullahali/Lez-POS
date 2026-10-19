# B30 Final Audit Report — Customer Manual Return UI Operation-Intent Idempotency

**Audit date:** 2026-10-19  
**Project:** Lez POS  
**Branch:** `main`

---

## 1. Baseline and current HEAD

| Item | Value |
|------|--------|
| **Known baseline (pre-B30 commit)** | `da030ab538015ee44661f17c2869ecb902dd3ac8` |
| **Current `git rev-parse HEAD`** | `da030ab538015ee44661f17c2869ecb902dd3ac8` |
| **Interpretation** | B30 work exists only in the **working tree** (modified + untracked files). No B30 commit has been created yet. |

**Database schema version:** **51** (`lib/core/database/app_database.dart`: `int get schemaVersion => 51;`)

---

## 2. Workspace status (`git status --short`)

### 2.1 Tracked modifications (B30 production)

| Path | Status |
|------|--------|
| `lib/features/returns/screens/customer_returns_screen.dart` | `M` (manual-return path only; vs baseline) |

### 2.2 Untracked — B30 deliverables

| Path | Role |
|------|------|
| `lib/features/returns/customer_manual_return_idempotency.dart` | B30 sticky map + submit runner |
| `test/customer_manual_return_idempotency_b30_test.dart` | B30 test matrix (14 tests) |
| `docs/b30_discovery_report.md` | Discovery |
| `docs/b30_design_review.md` | Approved design |
| `docs/b30_implementation_report.md` | Implementation + verification + review fixes |
| `docs/b30_review_pass.md` | Review Pass (historical verdict preserved) |
| `docs/b30_final_audit_report.md` | This audit |

### 2.3 Untracked — **not** part of B30 (preserved; untouched by this audit)

Examples from workspace listing (non-exhaustive): other `docs/b*_*.md`, `docs/customer_returns_*`, `docs/post_b*_project_discovery.md`, `tool/fix_ui_overrides.dart`, `tool/patch_*.dart`, `tool/write_post_b2_discovery.py`, build/cache artifacts if present.

**Audit action:** No git clean, reset, checkout, or staging performed.

### 2.4 Baseline diff (tracked production)

```text
git diff da030ab538015ee44661f17c2869ecb902dd3ac8 --stat
 lib/features/returns/screens/customer_returns_screen.dart | 90 +++++++++++-----------
 1 file changed, 46 insertions(+), 44 deletions(-)
```

```text
git diff da030ab… -- lib/core/services/manual_return_service.dart
git diff da030ab… -- lib/core/services/manual_return_fingerprint.dart
git diff da030ab… -- lib/core/database/
(empty — no backend/schema diff)
```

**Review Fixes confirmation:** No additional tracked production files beyond `customer_returns_screen.dart` since baseline.

---

## 3. Design compliance (Option A)

Sources read: `docs/b30_design_review.md`, `docs/b30_implementation_report.md`, `docs/b30_review_pass.md`, production + test source.

| Requirement | Evidence |
|-------------|----------|
| Fingerprint uses existing `ManualReturnFingerprint` | `computeManualReturnIntentFingerprint` → `ManualReturnFingerprint.compute` with same normalization (`customer_manual_return_idempotency.dart:18–25`) |
| Sticky `fingerprintHash → UUID` | `CustomerManualReturnIdempotencyState._keysByFingerprint` + `prepareReturnKey` |
| Dialog reopen / reset does not clear map | `_showCustomerReturnDialog` has no map clear; runner is field on screen state (`customer_returns_screen.dart:95–96`, `:334+`) |
| Pre-commit failure retains key | Runner catch → `serviceFailure`; no `clearReturnKey` |
| Real conflict retains key | Conflict branch; no clear (`:130–131`); B30 T8 real service test |
| Post-commit refresh failure retains key | `postSuccessRefreshFailed`; clear deferred (`:122–126`) |
| Clear only after service + refresh success | `clearReturnKey` after successful `postSuccessRefresh` (`:128–129`) |
| Only completed fingerprint slot cleared | T10 runner integration (two pending fps) |
| Intentional identical new return → new UUID | T11; `putIfAbsent` after slot cleared |
| In-flight guard | `_inFlight` + dialog save disabled via `inFlight` |
| Quick-return separate | `_quickReturnIdempotencyKey`, `_submitQuickReturn`, `_showQuickReturnDialog` unchanged in structure; not wired to B30 runner |
| No schema/DAO/service/supplier changes | Empty git diff on backend paths; supplier paths not in B30 file set |

**Compliance verdict:** **Meets approved Option A.**

---

## 4. Financial correctness evidence

**Service remains authoritative:** UI only supplies `idempotencyKey` and payload to `ManualReturnService.processManualReturn`; seal/replay/conflict logic unchanged in service (no diff vs baseline).

### 4.1 Tests using real `ManualReturnService` + `AppDatabase.test`

| Test | Financial claim |
|------|-----------------|
| **T5** | Pre-commit failure; retry with real service → 1 return row |
| **T6/T7** | Commit + stock +1; refresh fails; retry replays → **1** return, stock **+1** (not +2) |
| **T10 (runner)** | One successful commit; selective map clear |
| **T8 real service conflict** | Seal qty 1; conflict on same key qty 2 → **1** return, stock unchanged, key retained |
| **T11** | Two intentional successes → **2** returns, stock **+2** |
| **T9** | Real service after Completer gate (concurrency) |

### 4.2 Tests not using full DB financial path

| Test | Role |
|------|------|
| T1–T3 | Fingerprint unit |
| T4, T13 | Map key binding |
| T8 synthetic | Runner outcome on thrown conflict |
| T12 | State map isolation |

**No credible duplicate-return or duplicate-stock path** identified for the single-screen, single-process model under approved design.

---

## 5. Test execution (this audit)

### 5.1 B30 suite

```text
flutter test test/customer_manual_return_idempotency_b30_test.dart
00:01 +14: All tests passed!
```

### 5.2 B10 targeted service conflict tests

```text
flutter test test/customer_manual_return_idempotency_b10_test.dart --plain-name "changed product"
flutter test … --plain-name "changed quantity"
flutter test … --plain-name "changed unitPrice"
flutter test … --plain-name "changed reason"
flutter test … --plain-name "changed user"
```

Each run: **All tests passed!** (tests 10–13 and 28).

### 5.3 B10 full suite

```text
flutter test test/customer_manual_return_idempotency_b10_test.dart
00:12 +26 -4: Some tests failed.
```

| Test | Outcome | Classification | Evidence |
|------|---------|----------------|----------|
| **21** migration v41 → v42 | Fail | **Verified baseline issue (schema pin)** | `expect(migrated.schemaVersion, 50)` at `b10_test.dart:579` → `Actual: <51>` |
| **22** fresh v42 schema | Fail | **Verified baseline issue (schema pin)** | `expect(db.schemaVersion, 50)` at `:584` |
| **29** B2–B9 sentinel on v42 | Fail | **Verified baseline issue (schema pin)** | `expect(regressionDb.schemaVersion, 50)` at `:591` |
| **27** UI conflict clears key | Fail | **Expected B30 contract change** | Asserts new UUID after conflict + identical resubmit (`:1143`); B30 retains sticky key (design lifecycle F; B30 T8) |

**Not B30 service regressions:** Tests **1–20**, **23–26**, **28**, **30** pass in full run (26 passing total).

---

## 6. Static and integrity checks

| Check | Result |
|-------|--------|
| `dart analyze lib/features/returns/customer_manual_return_idempotency.dart lib/features/returns/screens/customer_returns_screen.dart test/customer_manual_return_idempotency_b30_test.dart` | **No issues found!** |
| Schema version | **51** (unchanged) |
| NULL bytes | **0** on B30 production + B30 test files |
| `git diff --check` on `customer_returns_screen.dart` | **Clean** (no conflict markers reported) |

Documentation claims (14/14 B30, Review Fixes verified) **match** observed test runs in this audit.

---

## 7. Scope and security

- **No secrets/credentials** in B30 production or test files (manual review of file set).
- **No schema/migration** changes in B30 diff.
- **Manual-return UI path only** in `customer_returns_screen.dart` diff; quick-return uses separate idempotency fields.
- **Supplier-return** code paths not modified in B30 artifact list.

---

## 8. Non-blocking observations

1. **Committed HEAD still at baseline** — B30 must be committed as an explicit changeset when authorized.
2. **B10 test 27** obsolete vs B30 UI policy; full B10 green requires a future scoped B10 test update (out of B30 scope).
3. **B10 tests 21/22/29** schema pin hygiene (50 vs 51) — pre-existing, not introduced by B30.
4. **No widget-level B30 test** for full `CustomerReturnsScreen` post-refresh failure; runner + real service tests cover financial invariants (noted in Review Pass §15 optional items).
5. **Unrelated untracked docs/tools** remain in workspace; not part of B30 commit scope unless user chooses otherwise.

---

## 9. Blockers

**None.**

---

## 10. Final verdict

**B30 FINAL AUDIT PASSED**

B30 implementation, tests, and documentation are consistent with the approved design, financial invariants are backed by real-service integration tests, scope boundaries hold, and all four B10 full-suite failures are explained with source-level evidence (three schema pins, one expected UI contract change). No unexplained B30 regression or scope violation remains.

---

*Audit mode: read-only. No production code, tests (other than this report file), schema, staging, commit, or push.*