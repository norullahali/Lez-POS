# B29 Final Audit — Supplier Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-15  
**Mode:** READ-ONLY audit (no code/test/schema/git changes)  
**Audit baseline commit:** `b6db87d49f1c49d051ac7587ee128609f22625e0`  
**Schema:** 51  
**References:** `docs/b29_design_review.md`, `docs/b29_implementation_report.md`, `docs/b29_review_pass.md`

---

## Executive Summary

B29 implements approved **Option C** (B28 mirror) for supplier refund settlement UI operation-intent idempotency. Source review, regression test re-run, analyzer, encoding checks, and git scope review confirm financial safety and backend boundary. Review-pass fixes SF-01–SF-04 are verified in production code and tests. No blockers identified.

---

## 1. Design Conformance

Verified against `docs/b29_design_review.md`:

| Requirement | Evidence | Result |
|-------------|----------|--------|
| Notifier-owned sticky map | `settlementIdempotency` on `SupplierRefundSettlementUiNotifier` (final field) | PASS |
| UUID only at submit | `prepareSettlementKey` after validation in `submit()`; no UUID in `init()` | PASS |
| No UUID in UiState | `SupplierRefundSettlementUiState` has no `idempotencyKey` | PASS |
| `reset()` preserves map | `reset()` sets `state = null` only | PASS |
| Success clears after refresh | Lines 252–256: refresh provider then `clearSettlementKey` | PASS |
| Failure/conflict retain key | Catch paths do not clear or rotate | PASS |
| Backend unchanged | No diff on service/DAO/schema/dialog | PASS |
| Process-death limitation | In-memory map only (design + review OF-02) | PASS (documented) |

**Minor extension (non-redesign):** `supplierRefundPostSuccessRefreshProvider` extracts post-success refresh for SF-03 and testability; default behavior matches pre-B29 invalidates.

---

## 2. Review-Fix Verification

| Fix | Verification | Result |
|-----|--------------|--------|
| **SF-01** | Test `SF-01/SF-02 post-commit refresh failure...`: real `settleCredit`, refresh throws, key retained, reset/reopen, same UUID, one REFUND | PASS |
| **SF-02** | Same notifier-level test; no `Future.delayed`; **T10** pre-commit path retained | PASS |
| **SF-03** | Production order: `settleCredit` → `supplierRefundPostSuccessRefreshProvider` → `clearSettlementKey` → success state (lines 243–261) | PASS |
| **SF-04** | Test `SF-04 conflict retains sticky UUID without rotation`: conflict, key retained, `uuidMints == 0` | PASS |

---

## 3. Financial Safety

| Question | Assessment | Result |
|----------|------------|--------|
| A. Duplicate UUID paths (double submit, reset/reopen, post-commit failure, conflict, dialog reopen) | Double submit blocked; sticky map survives reset; post-commit refresh failure retains key (SF-03); success clears only after refresh | PASS |
| B. Two intents → one UUID | `putIfAbsent` per fingerprint hash; distinct fingerprints → distinct slots | PASS |
| C. Two intents share fingerprint | Only if service-equivalent params (by design); SHA-256 over canonical JSON | PASS |
| D. `returnId` isolation | Fingerprint includes nullable `returnId`; tests T5/T15 | PASS |
| E. Amount/hash vs service | Same `amount` and `noteForService` passed to `compute` and `settleCredit` | PASS |

**Residual (non-blocking):** After **successful** full submit (refresh OK, key cleared), reopening the **same** fingerprint mints a new UUID — legitimate new operation if credit remains (B28/design). Process death loses map (documented).

No duplicate-REFUND path identified under approved UI lifecycle.

---

## 4. Fingerprint Audit

`SupplierRefundSettlementIntentFingerprint.compute` mirrors `SupplierRefundSettlementService._fingerprintMatches`:

- `supplierId`: exact in JSON payload  
- `amount`: service receives `parsedAmount`; hash uses `_round` to 6dp (B28 pattern)  
- `returnId`: nullable in payload  
- `note`: `(note ?? '').trim()` — matches service via `noteForService` pipeline in `submit()`

**PASS**

---

## 5. Key Lifecycle Audit

| Phase | Behavior in source | PASS |
|-------|---------------------|------|
| OPEN | No UUID in `init()` | ✓ |
| FIRST SUBMIT | Fingerprint → `prepareSettlementKey` | ✓ |
| IN FLIGHT | `isSubmitting` guard | ✓ |
| SUCCESS | Refresh → clear → success | ✓ |
| REPLAY | Same as success (service replay) | ✓ |
| FAILURE | No clear in catch | ✓ |
| CONFLICT | No clear; no rotation | ✓ |
| RESET | UI null only | ✓ |
| REOPEN | Same fingerprint → same key while slot retained | ✓ |

---

## 6. Concurrency Audit

- `isSubmitting` (lines 200, 87–88)  
- `_submitGeneration` (lines 202, 250, 264, 273)  
- B29 **T16** uses `Completer` gate (no `Future.delayed` in B29 suite)  
- Service concurrent same-key covered in B29 SR replay group  

**PASS**

---

## 7. Backend Boundary

`git diff HEAD -- lib/` tracked change: **`supplier_refund_settlement_provider.dart` only**.

Untracked B29 production additions (not yet committed):

- `lib/core/services/supplier_refund_settlement_intent_fingerprint.dart`
- `lib/features/suppliers/supplier_refund_settlement_idempotency.dart`

No modifications to `SupplierRefundSettlementService`, supplier refund DAO, `app_database` migrations, or dialog.

**Schema:** `schemaVersion => 51` unchanged.

**PASS**

---

## 8. Test Audit (re-run this audit)

| Suite | Result |
|-------|--------|
| B29 | **20/20 passed** |
| SR 3.3 UI step 3.1 | All passed |
| B28 | All passed |
| SR 3.0 | All passed **except J** (expects schema **35**, app **51** — pre-existing, unrelated) |

Combined run: **57 passed, 1 failed** (SR 3.0 J only).

---

## 9. Analyzer / Static Checks

`analyze_files` on all three B29 production files: **0 errors**.

---

## 10. File Encoding

| File | NULL bytes | UTF-16 | BOM |
|------|------------|--------|-----|
| `supplier_refund_settlement_intent_fingerprint.dart` | 0 | No | No |
| `supplier_refund_settlement_idempotency.dart` | 0 | No | No |
| `supplier_refund_settlement_provider.dart` | 0 | No | No |
| `supplier_refund_settlement_idempotency_b29_test.dart` | 0 | No | No |

**PASS**

---

## 11. Scope Audit

**Expected B29 production (4 files, 3 new + 1 modified):** matches working tree.

**Expected test:** `test/supplier_refund_settlement_idempotency_b29_test.dart` (untracked).

**Docs:** `b29_design_review.md`, `b29_implementation_report.md`, `b29_review_pass.md`, this audit (B29-related untracked docs).

**Unrelated untracked:** other `docs/*`, `tool/*` — pre-existing; not modified by audit.

**PASS**

---

## 12. Documentation Audit

- Design review: Option C, lifecycle, backend boundary — consistent with code.  
- Implementation report: updated for SF-03 ordering and 20/20 tests.  
- Review pass: §16 historical **B29 REVIEW PASS WITH SHOULD-FIX** preserved; §17–18 resolution of SF-01–SF-04 documented.

**PASS**

---

## 13. Git Safety

- **No** staging, commit, or push performed.  
- **HEAD:** `b6db87d49f1c49d051ac7587ee128609f22625e0`  
- **Tracked modification:** `supplier_refund_settlement_provider.dart`  
- **Untracked B29 artifacts:** new lib/test/docs as listed above  

**PASS**

---

## 14. Final Audit Checklist

| ID | Invariant | Result |
|----|-----------|--------|
| I1 | Design conformance | **PASS** |
| I2 | Fingerprint correctness | **PASS** |
| I3 | Sticky key lifecycle | **PASS** |
| I4 | Reset/reopen persistence | **PASS** |
| I5 | Post-commit ambiguity (notifier test + SF-03 ordering) | **PASS** |
| I6 | Refresh-failure retention | **PASS** |
| I7 | Conflict retention | **PASS** |
| I8 | Double-submit protection | **PASS** |
| I9 | ReturnId isolation | **PASS** |
| I10 | Financial duplicate prevention (approved lifecycle) | **PASS** |
| I11 | Backend boundary | **PASS** |
| I12 | Schema 51 | **PASS** |
| I13 | B29 tests 20/20 | **PASS** |
| I14 | Regression tests (SR J excluded) | **PASS** |
| I15 | Analyzer | **PASS** |
| I16 | Encoding | **PASS** |
| I17 | Scope | **PASS** |
| I18 | Documentation | **PASS** |
| I19 | Git cleanliness (no accidental staging) | **PASS** |
| I20 | Commit readiness (artifacts present; user commit pending) | **PASS** |

---

## Non-Blocking Notes

1. **SR 3.0 test J** — schema version pin at 35 vs app 51; historical; not a B29 regression.  
2. **Process-death** — in-memory sticky map not durable (accepted B28/B29 scope).  
3. **6dp hash vs service tolerance** — B28 parity; no practical duplicate path identified in audit.  
4. **`supplierRefundPostSuccessRefreshProvider`** — production hook for refresh ordering; default path unchanged for end users.

---

## Final Verdict

All checklist items **PASS**. No blockers. Non-blocking notes documented above.

**B29 FINAL AUDIT PASS WITH NON-BLOCKING NOTES**
