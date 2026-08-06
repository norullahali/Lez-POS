# Supplier Returns SR.2 — Atomic Posting Workflow

## Executive Summary

Phase SR.2 implements the canonical atomic business posting workflow for purchase-linked Supplier Returns. One service invocation validates purchase/supplier/items/returnable quantities, persists the return (RETURN_OUT stock path), and posts supplier accounting inside one Drift transaction. Any failure rolls back everything.

## Existing Architecture Reused

- ReturnsDao.getReturnableQuantityForPurchaseItem() — SR.1 line-level returnable qty
- ReturnsDao.persistSupplierReturn() — header/items + RETURN_OUT + StockGuard
- ReturnsDao.saveSupplierReturn() — SR.1 structural wrapper (unchanged)
- PurchasesDao / SuppliersDao — trusted lookups
- SupplierAccountsDao.applyTransaction() + recordReturnInTransaction() — type RETURN, negative amount
- StockGuard.deductStock() — canonical stock deduction
- PartialReturnService — orchestration pattern

## Service Ownership

Canonical service: SupplierReturnService (lib/core/services/supplier_return_service.dart)

Future UI -> SupplierReturnService.postPurchaseLinkedReturn() -> AppDatabase.transaction()

## Posting Input Contract

SupplierReturnPostingInput: supplierId, purchaseInvoiceId, lines[], optional returnDate/notes/reason/returnNumber.

SupplierReturnPostingLine: purchaseItemId, quantity (>0).

Derived from DB: productId, productName, unitCost, totals.

## Header Validation

Purchase exists; supplier exists; purchase.supplierId matches input; at least one line.

## Item Validation

Purchase item exists; belongs to header invoice; qty > 0; returnable qty checked inside transaction; no silent clamping.

## Duplicate-Line Policy

aggregatePostingLines() sums duplicate purchaseItemId before validation (6+6 cannot bypass cap of 10).

## Stock Posting

Single path via persistSupplierReturn(): RETURN_OUT + StockGuard. No duplicate movement.

## Supplier Accounting Semantics

recordReturnInTransaction(): type RETURN, amount -returnValue, reference returnId.

returnValue = SUM(qty x purchaseItem.unitCost).

Unpaid/partial: reduces payable. Fully paid: ledger may go negative (supplier credit). No auto cash refund.

## Cash Ledger Boundary

NO Cash Ledger event for goods return alone. RETURN type excluded from FinancialLedgerRepository cash UNION.

## Atomic Transaction Design

Single _db.transaction wraps validation, persistSupplierReturn, recordReturnInTransaction. No nested transaction in persist or in-transaction accounting.

## Rollback Guarantees

Stock or accounting failure rolls back return, items, ledger, stock, supplier txn (tests G, H).

## Failure Contract

SupplierReturnPostingException / SupplierReturnPostingFailure enum covers all spec cases.

## Idempotency

No framework added. Single invocation is atomic; duplicate UI submit risk deferred to SR.3.

## Customer Returns Regression

Customer return paths unchanged. SR.1 tests 11/11 PASS.

## Tests

test/supplier_return_posting_service_test.dart — cases A-J + aggregatePostingLines.

SR.1: 11/11 | SR.2: 11/11 | Total: 22/22 PASS

## Files Created

- lib/core/services/supplier_return_service.dart
- test/supplier_return_posting_service_test.dart
- docs/supplier_returns_sr_2_atomic_posting_workflow.md

## Files Modified

- lib/core/database/daos/returns_dao.dart
- lib/core/database/daos/supplier_accounts_dao.dart

## Schema Confirmation

31 -> 31 unchanged.

## Validation Results

dart format PASS | flutter analyze 0 errors | windows debug build PASS

## Deferred SR.3+

UI, supplier cash refund settlement, reports, audit log, idempotency keys.

## Final Decision

SR.2 COMPLETE — GO for SR.2 Review Pass
