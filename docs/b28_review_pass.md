# B28 Review Pass — Customer Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-15  
**Mode:** READ-ONLY review (no production/test/schema edits, no commit, no push)  
**Baseline HEAD:** `9ff31d2d67e87e788abc25508de45a85cd68d569`  
**Schema:** 51  

---

## 1. Executive summary

B28 implementation matches approved **Option C**: `CustomerRefundSettlementIdempotencyState` on `CustomerRefundSettlementUiNotifier`, fingerprint at submit, sticky map survives `reset()`, no backend/schema changes. Code inspection and tests support the primary post-commit reopen scenario at the **state + service** layer; **notifier-level** end-to-end proof is thinner.

**Verdict:** **B28 REVIEW PASS: PASS WITH OPTIONAL NOTES**

| Class | Count |
|-------|-------|
| BLOCKER | 0 |
| SHOULD-FIX | 0 |
| OPTIONAL | 4 |

Ready for Final Audit with optional follow-ups documented below.

---

## 2. Design conformance

| Requirement | Result | Evidence |
|-------------|--------|----------|
| A. Option C / notifier owner | PASS | `settlementIdempotency` on `CustomerRefundSettlementUiNotifier` |
| B. Survives `reset()` | PASS | `reset()` only `state = null`; map on notifier field |
| C. `init()` no UUID | PASS | `init()` builds `CustomerRefundSettlementUiState` without key |
| D. submit pipeline | PASS | validate → note normalize → `compute` → `prepareSettlementKey` → `settleCredit` |
| E. Success/replay clears slot | PASS | `clearSettlementKey(fingerprintHash)` after successful `settleCredit` |
| F. Failures retain key | PASS | catch paths do not clear map |
| G. Conflict retains key | PASS | `idempotencyKeyConflict` in catch; no clear |
| H. No `finally` clear | PASS | no `finally` in `submit()` |
| I. No SharedPreferences | PASS | in-memory map only |
| J. No schema change | PASS | no `app_database` diff |
| K. No service semantic change | PASS | `customer_refund_settlement_service.dart` untouched in diff |

---

## 3. Actual diff / scope verification

**Tracked modified:** `lib/features/customers/providers/customer_refund_settlement_provider.dart` (+25/−7)

**Untracked B28 (expected):**
- `lib/features/customers/customer_refund_settlement_idempotency.dart`
- `lib/core/services/customer_refund_settlement_intent_fingerprint.dart`
- `test/customer_refund_settlement_idempotency_b28_test.dart`
- B28 docs

**Untouched (verified):** `customer_refund_settlement_dialog.dart`, `CustomerRefundSettlementService`, DAO/table, migrations, `app_database.dart`.

---

## 4. Fingerprint audit

**Service** (`_fingerprintMatches`): `customerId` exact; `amount` within **0.0001**; `returnId` nullable equality; `note` equals stored normalized `(note ?? '').trim()`.

**UI** (`CustomerRefundSettlementIntentFingerprint.compute`): same four fields; note normalized identically; `returnId` in JSON; amount via `_round` (6 dp) then SHA-256.

**Not included in hash:** display-only fields (confirmed).

**Alignment:** Submit passes `noteForService` and `parsedAmount` consistent with service inputs. Null vs empty note → same hash (T9).

**Note (non-blocking):** Hash uses **6 dp canonical amount**, not tolerance buckets. Two amounts within 0.0001 but differing at 6 dp produce **different hashes** → different sticky keys → service allows two REFUNDs (different-key semantics, pre-existing). Same parsed amount text on reopen → same hash → same key. **Not a B28 regression**; optional future tolerance-bucketing if product requires.

---

## 5. Lifecycle audit

| Scenario | Verdict |
|----------|---------|
| K1 commit, UI ambiguous, `reset()`, reopen same intent | **PASS (code)** — map retains K1; `prepareSettlementKey` reuses |
| Same intent replay | **PASS** — T5 service + sticky map |
| Material amount / note / returnId / customer | **PASS** — new hash → new UUID (T7–T10, T15) |
| null vs empty note | **PASS** — T9 |
| Conflict | **PASS** — no clear in catch (T11 state-level) |
| Failure | **PASS** — no clear (T4) |
| Success | **PASS** — clear single fingerprint (T12) |
| Validation failure | **PASS (code)** — `prepareSettlementKey` after validation; no service call |

**Dialog:** `PopScope(canPop: !isSubmitting)` prevents dismiss/`reset()` while submit in flight, reducing stale `_submitGeneration` completion risk.

---

## 6. Multi-intent map audit

`Map<String, String>` keyed by fingerprint hash: independent slots (T15); `clearSettlementKey` removes one entry (T12); `init`/`reset` do not clear map. **PASS.**

Map growth from abandoned failed intents is bounded by distinct hashes; no correctness requirement to prune in B28.

---

## 7. Concurrency audit

- `isSubmitting` + `_submitGeneration` unchanged.
- Stale completion: if generation mismatches after `reset()`/`init()`, success path returns early **before** `clearSettlementKey` — key retained when DB committed (correct for replay).
- Stale completion with matching generation: blocked in practice while dialog open (`canPop: false` during submit).
- Sticky clear uses **local** `fingerprintHash` from submit closure — cannot clear a different slot unless generations collide (mitigated by UI).

**PASS** with optional defense-in-depth note (OPTIONAL F-03).

---

## 8. Backend boundary audit

No changes to service, DAO, table, REFUND/caps/ledger logic. B28 is UI/orchestration only. **PASS.**

---

## 9. Core post-commit ambiguity scenario

**Proven:** T3 (same hash reuse), T5 (commit + same key → replay, one REFUND), code path (map survives `reset()`).

**Gap:** No **ProviderContainer** test exercising `submit()` → `reset()` → `init()` → `submit()` with mocked/real service. Implementation appears correct; **OPTIONAL F-01** (stronger proof before audit if desired).

---

## 10. Test review

**B28:** 15 tests, no `Future.delayed()`. Categories covered: fresh/reuse/reopen(T3)/retain/replay/different fp/amount/returnId/note/conflict/success/replay clear/concurrency(T16).

**Gaps (optional):** explicit T14 notifier validation-no-service; service-level conflict + retained sticky key; amount **0.0001** boundary; full notifier reset/reopen (F-01).

---

## 11. Phase C M/N investigation

**M)** Migrates simulated **v33 → expects `schemaVersion` 34** after open.  
**N)** Expects **`db.schemaVersion == 34`** on fresh test DB.

**Current app:** schema **51**. Tests fail on **version number assertion only** (table/index behavior still valid at 51).

**B28 impact:** None — no migration/database edits.

**Baseline:** Failures reproduce on **9ff31d2** without B28 production changes (historical pin to Step 3.0 era).

**Classification:** **PASS** (pre-existing, unrelated to B28). **OPTIONAL F-02:** update M/N to assert v51 or current table/index presence without pinning 34.

**Suite result:** **14/16** passed; **47/49** combined with B28 + UI Step 2.3.

---

## 12. Static / hygiene

| Check | Result |
|-------|--------|
| `dart analyze` (3 production files) | **No issues found** |
| `git diff --check` | Clean (CRLF warning only) |
| UTF-8 / no BOM | PASS (105,109,112…) |
| TODO/debugPrint in B28 prod | None |
| B24/B27 shared code | None modified |

---

## 13. Correctness Q&A

| Q | Answer |
|---|--------|
| Q1 Same intent after dialog reset reuse key? | **Yes** (map survives `reset()`) |
| Q2 Commit + UI ambiguity → second REFUND? | **No** for same intent/key (service replay); **Yes** if key cleared then new UUID (see F-04 edge) |
| Q3 Two material intents share key? | **No** (different hashes) |
| Q4 Conflict silently rotate UUID? | **No** |
| Q5 Failure clear key? | **No** |
| Q6 Stale async clear newer intent key? | **Unlikely** (generation + PopScope); not proven by test |
| Q7 `reset()` destroy sticky state? | **No** |
| Q8 Backend financial semantics changed? | **No** |
| Q9 Process-death limitation? | **Yes** — in-memory only, documented |
| Q10 Issues not in tests? | Notifier E2E (F-01); clear-before-invalidate ordering (F-04 optional) |

---

## 14. Findings

### BLOCKER
None.

### SHOULD-FIX
None (implementation matches approved design; no demonstrated correctness defect).

### OPTIONAL

| ID | Finding |
|----|---------|
| F-01 | Add notifier-level test: submit → `reset()` → same intent → same key → replay |
| F-02 | Phase C M/N: stale schema version 34 vs 51 (hygiene) |
| F-03 | Consider bumping `_submitGeneration` on `reset()`/`init()` instead of assign 0 (defense in depth) |
| F-04 | `clearSettlementKey` runs before `invalidateCustomerDisplays`; if invalidate threw after commit, key already cleared (low likelihood; mirror B27 ordering class) |

---

## 15. Remediation

No mandatory code changes for Review Pass. Optional: F-01 before Final Audit; F-02 in separate hygiene commit.

---

## 16. Final verdict

**B28 REVIEW PASS: PASS WITH OPTIONAL NOTES**
