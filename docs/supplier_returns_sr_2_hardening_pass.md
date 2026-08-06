# Supplier Returns SR.2 — Hardening Pass

**Date:** 2026-08-06
**Schema:** 31 (unchanged)

## Executive Summary

SR.2 Hardening closes review finding **F-01** by rejecting purchase-linked input on `ReturnsDao.saveSupplierReturn()` and directing callers to `SupplierReturnService.postPurchaseLinkedReturn()`. Legacy manual unlinked returns remain supported. Additional hardening: `@visibleForTesting` accounting seam, removed dead `productMismatch` enum, sanitized accounting failure message, fully-paid supplier credit regression test.

**Final Decision: GO TO FINAL AUDIT**

## Review Findings Addressed

| ID | Action | Status |
|----|--------|--------|
| F-01 | Guard saveSupplierReturn against purchase linkage | **CLOSED** |
| F-02 | productMismatch enum | **REMOVED** |
| F-03 | English messages | **ACCEPTED** (typed codes for SR.3 UI) |
| F-04 | Raw exception in accounting failure | **CLOSED** |
| F-05 | Fully-paid credit semantics | **CERTIFIED** (new test) |
| F-06–F-08 | Idempotency, cash refund, credit UX | **DEFERRED SR.3+** |

## F-01 DAO Bypass Resolution

**Before:** saveSupplierReturn() could post purchase-linked returns without returnable-qty enforcement or supplier accounting.

**After:**
- `@Deprecated` on saveSupplierReturn()
- Throws `SupplierReturnDirectPostingForbiddenException` when header.purchaseInvoiceId is set OR any item has purchaseItemId
- Manual unlinked returns (no purchase linkage) still work

**Caller audit:** Zero production callers confirmed. Tests only.

## Canonical Service Boundary

**ONLY production entry for NEW purchase-linked returns:**
`SupplierReturnService.postPurchaseLinkedReturn()`

Documented in service file header. SR.3 UI must use this path.

## Legacy / Manual Compatibility

**PRESERVED** — saveSupplierReturn() accepts unlinked manual returns (no purchaseInvoiceId, no purchaseItemId). Verified by SR.1 test D and hardening test C.

## persistSupplierReturn Contract

Explicitly documented as low-level primitive:
- No business orchestration
- No transaction ownership
- Caller-validated data inside caller transaction
- Not UI-facing

## Accounting Test Seam

`SupplierReturnService.withAccountingPoster()` marked `@visibleForTesting`. Production constructor always uses recordReturnInTransaction().

## Failure Contract Hardening

- Removed unused productMismatch enum value
- supplierAccountingFailure message: fixed string without inner exception text

## Fully-Paid Supplier Credit Test

Hardening test certifies: purchase debt 50 → payment 50 → balance 0 → return 20 → balance -20, zero Cash Ledger events.

## Cash Ledger / Atomicity / Stock

Unchanged from SR.2 implementation. Cash Ledger events from goods return: **0**. Single transaction. One RETURN_OUT per line.

## Customer Returns Regression

No changes to customer return methods. All SR.1 + SR.2 tests PASS.

## Schema Freeze

31 → 31. No migration.

## Tests Added

`test/supplier_return_hardening_test.dart` (4 tests):
- F-01 A: DAO bypass rejected, zero side effects
- F-01 B: Service path succeeds
- F-01 C: Manual unlinked preserved
- Fully-paid credit + zero cash ledger

## Files Created

- test/supplier_return_hardening_test.dart
- docs/supplier_returns_sr_2_hardening_pass.md

## Files Modified

- lib/core/database/daos/returns_dao.dart
- lib/core/services/supplier_return_service.dart
- test/supplier_return_returnable_quantity_test.dart
- test/supplier_return_posting_service_test.dart

## Validation Results

| Check | Result |
|-------|--------|
| SR.1 tests | 11/11 PASS |
| SR.2 tests | 11/11 PASS |
| Hardening tests | 4/4 PASS |
| flutter analyze (modified files) | 0 errors |
| Windows debug build | PASS |

## Remaining Accepted Items

- English domain error strings (localization in SR.3)
- Negative supplier credit on fully-paid returns (ledger-consistent)
- No idempotency framework

## Deferred SR.3+

UI, cash refund settlement, reports, idempotency keys

## Readiness Score: 97 / 100

## Final Decision: GO TO FINAL AUDIT