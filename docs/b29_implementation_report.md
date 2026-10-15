# B29 Implementation Report — Supplier Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-15  
**Baseline:** `b6db87d49f1c49d051ac7587ee128609f22625e0`  
**Schema:** 51 (unchanged)

## Implementation Summary

Implemented Option C (B28 mirror): submit-time intent fingerprint, notifier-owned sticky `fingerprintHash -> UUID` map, no UUID on dialog `init()`, key cleared only after successful `settleCredit` (including replay). Backend service/DAO/schema untouched.

## Files Changed

| File | Change |
|------|--------|
| `lib/core/services/supplier_refund_settlement_intent_fingerprint.dart` | **Added** |
| `lib/features/suppliers/supplier_refund_settlement_idempotency.dart` | **Added** |
| `lib/features/returns/providers/supplier_refund_settlement_provider.dart` | **Modified** |
| `test/supplier_refund_settlement_idempotency_b29_test.dart` | **Added** |
| `docs/b29_implementation_report.md` | **Added** |

No changes to `SupplierRefundSettlementService`, supplier refund DAO, migrations, or dialog.

## Key Lifecycle

- `init()` / dialog open: no idempotency UUID
- `submit()`: validate → `noteForService` → fingerprint → `prepareSettlementKey` → `settleCredit`
- Success / replay: `supplierRefundPostSuccessRefreshProvider` runs after successful `settleCredit`; `clearSettlementKey(fingerprintHash)` only after refresh succeeds (SF-03)
- Failure / conflict: retain map entry, no UUID rotation
- `reset()`: clears nullable UiState only; sticky map on notifier persists

## Fingerprint Contract

Matches service `_fingerprintMatches`: `supplierId`, `amount` (service receives parsed amount; hash uses 6dp canonicalization), nullable `returnId`, `note` as `(note ?? '').trim()`.

## Test Results

| Suite | Result |
|-------|--------|
| `test/supplier_refund_settlement_idempotency_b29_test.dart` | **20/20 passed** (incl. SF-01/02 post-commit notifier test, SF-04 conflict test) |
| `test/supplier_refund_settlement_ui_sr_3_3_step_3_1_test.dart` | **All passed** (with B29 provider) |
| `test/customer_refund_settlement_idempotency_b28_test.dart` | **All passed** |
| `test/supplier_refund_idempotency_sr_3_0_test.dart` | **Passed except J** (pre-existing: expects schema **35**, app **51**) |

T14 post-commit replay (sticky key, one REFUND) covered in B29 service-replay group. T16 double-submit uses Completer gate (UI test G pattern).

## Analyzer

No issues on changed production Dart files (`analyze_files`).

## Schema Verification

`app_database.dart` `schemaVersion` remains **51**. No migration files modified.

## Scope Verification

`git diff --name-only` tracked production change: `supplier_refund_settlement_provider.dart` only. New files listed above. No backend/schema/DAO edits.

## Known Non-Blocking Notes

- SR 3.0 test **J** (schema v35 pin) remains a historical hygiene failure unrelated to B29.
- B29 tests override `supplierAccountsDaoProvider` in notifier groups to avoid `AppDatabase.instance` during invalidates (same pattern as SR 3.1 UI tests).
- New Dart files written via editor were converted to **UTF-8 without BOM** before test runs (avoid UTF-16 `main` load failures on Windows).

## Verdict

**B29 IMPLEMENTATION COMPLETE**