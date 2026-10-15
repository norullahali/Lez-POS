# B29 Design Review — Supplier Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-15  
**Mode:** DESIGN ONLY (no production/test/schema/git changes)  
**Baseline HEAD / origin/main:** `b6db87d49f1c49d051ac7587ee128609f22625e0`  
**Schema:** 51  
**Discovery reference:** docs/b29_discovery_report.md  
**Prior milestone:** B28 CLOSED (customer refund settlement UI intent idempotency)

---

## 1. Executive Summary

Verified current supplier refund settlement UI mints a **new UUID on every `init()`**, stores it on **`SupplierRefundSettlementUiState.idempotencyKey`**, and **`reset()`** nulls UI state when the dialog closes. Backend **`SupplierRefundSettlementService.settleCredit`** is already correct: single transaction, key-scoped replay, fingerprint conflict, seal race retry, aggregate credit cap via atomic SQL.

**B29 closes the UI operation-intent lifecycle gap** by adopting **Option C** (mirror B28): a **notifier-owned sticky map** from **deterministic intent fingerprint → UUID**, computed **at submit** from the exact parameters sent to the service. **No backend, DAO, schema, or dialog structural changes** are required.

**Recommended implementation shape:** `SupplierRefundSettlementIntentFingerprint` + `SupplierRefundSettlementIdempotencyState` + changes to `SupplierRefundSettlementUiNotifier` only (remove eager UUID from `init()` / `UiState`).

---

## 2. Verified Current Architecture

### 2.1 UI orchestration — supplier_refund_settlement_provider.dart

| Element | Verified behavior |
|--------|-------------------|
| init() | Resets _submitGeneration; builds UiState with idempotencyKey: v4() (L148). |
| reset() | state = null (L154-157). No sticky map. |
| submit() | isSubmitting guard; _submitGeneration; service uses current.idempotencyKey from init (L212-218). Success does not clear key. Failure retains draft. |
| UiState.idempotencyKey | copyWith cannot change key; amount/note edits do not rotate key (conflict risk). |

### 2.2 Dialog — supplier_refund_settlement_dialog.dart

init on open; reset on any pop (L31-34). PopScope(canPop: !isSubmitting). note: trim empty to null (provider L217).

### 2.3 Service — supplier_refund_settlement_service.dart

tolerance 0.0001; normalizedNote = (note ?? '').trim(); single transaction; replay/conflict; seal race; atomic aggregate credit insert.

### 2.4 Entry points

Supplier profile: returnId null. Return detail: returnId = detail.id. returnId fixed for dialog lifetime.

### 2.5 Tests

SR 3.0 (incl. test F different keys), UI SR 3.3 step 3.1, B28 template tests.

---

## 3. Exact Vulnerability

K1 commits REFUND; reset/reopen; K2 new v4(); same params; second REFUND (SR test F). Secondary: same K1 after amount change causes idempotencyKeyConflict.

---

## 4. Service Fingerprint Contract (authoritative)

_fingerprintMatches (L260-272):

- supplierId: int equality
- amount: abs(delta) <= 0.0001
- returnId: nullable equality (null != concrete id)
- note: existing.note == (note ?? '').trim()

UI fingerprint must use noteForService = note.trim().isEmpty ? null : note.trim() then normalized (note ?? '').trim() for hash.

Amount in hash: double.parse(value.toStringAsFixed(6)) (B28). Service receives parsedAmount double.

---

## 5. State Ownership (Option C)

Sticky map on SupplierRefundSettlementUiNotifier (same as B28). Map<String,String> fingerprintHash -> UUID. Survives reset(). Remove idempotencyKey from UiState.

---

## 6. Options Analysis

| Option | Correctness | Retry/reopen | Complexity | Schema | Process death | Backend | Verdict |
|--------|-------------|--------------|------------|--------|---------------|---------|---------|
| A — Dialog-local UUID | Poor | Lost on dispose | Low | None | Lost | Unchanged | Reject |
| B — UUID in UiState (current) | Poor | Lost on `reset()` | Low | None | Lost | Unchanged | Broken baseline |
| C — Notifier sticky map + fingerprint | Closes primary gap | Survives `reset()`/reopen | Medium (B28 proven) | None | Same as B28 | Unchanged | **SELECTED** |
| D — SharedPreferences / durable pending | High | Survives death | High | Optional | Better | Semantics risk | Out of scope |
| E — DB UNIQUE business fingerprint | High | Durable | High | Migration | Good | Authority shift | Reject |

---

## 7. Selected Design

Add supplier_refund_settlement_intent_fingerprint.dart and supplier_refund_settlement_idempotency.dart. Modify provider: key at submit via prepareSettlementKey; clear on success after await; retain on failure/conflict; no UUID rotation on conflict. Dialog unchanged. Service/DAO/schema unchanged. Add b29 test file.

---

## 8. Key Lifecycle

See B28 pattern: no key on init; validation no map touch; submit binds fp; success/replay clear; failure/conflict retain; reset clears UI only; reopen same fp reuses key.

---

## 9. Material vs Non-Material Changes

Material: supplierId, returnId, parsed amount, noteForService. Non-material: names, labels, availableCredit display, amountText formatting if parse equal. Fingerprint-at-submit only.

---

## 10. Success / Failure / Conflict Semantics

Success/replay: clear slot. Failure/conflict: retain, no rotation. Post-commit ambiguity: K1 retained across reset/reopen -> replay -> one REFUND.

---

## 11. Concurrency Model

UI: isSubmitting + _submitGeneration (SR 3.1 G). B29 blocks different-key same-intent. Service unchanged (SR 3.0).

---

## 12. Multi-Entry / Return Linkage

returnId in fingerprint; aggregate vs linked isolated; returnId immutable in dialog. No new return-cap UI (supplier differs from customer B28).

---

## 13. Backend Boundary

No changes to SupplierRefundSettlementService, DAO, table, schema, REFUND semantics.

---

## 14. Process-Death Decision

Accept B28 limitation: in-memory map lost on process death after commit; out of scope for durable store.

---

## 15. Test Matrix

T1-T16 as discovery spec (fingerprint unit, sticky state, post-commit one REFUND, returnId isolation, generation safety). Reuse SR 3.0 and UI 3.1 suites. Completers not Future.delayed.

---

## 16. Implementation Surface

New: intent fingerprint, idempotency state, b29 tests. Modify: supplier_refund_settlement_provider.dart. No change: dialog, service.

---

## 17. Risks

Fingerprint drift: SHOULD-FIX via T8-T10. Clear before commit: BLOCKER if wrong. Backend accidental edit: SHOULD-FIX. Map growth: OPTIONAL. No design BLOCKER.

---

## 18. Scope / Out-of-Scope

In: supplier refund UI intent idempotency. Out: B28 customer, schema, service redesign, process-death store, loyalty, closed session, Phase C M/N.

---

## 19. B28 Comparison

Same Option C lifecycle; supplierId vs customerId; no maxReturnRefundable UI; supplier service has no return-cap SQL. Dialog reset-on-close identical.

---

## 20. Final Verdict

**B29 DESIGN VERDICT: DESIGN APPROVED**
