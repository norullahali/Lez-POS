# Supplier Returns SR.3.2 Step 2 - History / List UI

Date: 2026-08-10

## Scope

Read-only supplier returns history/list on certified SR.2 + SR.3.2 Step 1 posting integration.

## Architecture

SupplierReturnsScreen -> supplierReturnsListProvider -> SupplierReturnReadRepository.listSupplierReturns() -> ReturnsDao.listSupplierReturnsHistory()

Posting boundary unchanged: Create dialog -> SupplierReturnService.postPurchaseLinkedReturn()

## Refresh

Successful post increments supplierReturnsRefreshProvider and reloads list. Failed post and dialog open do not refresh.

## Side effects from list/history

SupplierReturn writes: 0 | Stock: 0 | Supplier accounting: 0 | Cash Ledger: 0 | Posting calls: 0 | Schema: 31

## Tests

test/supplier_return_history_list_sr_3_2_step_2_test.dart (12 tests A-L)

## Deferred

Pagination, cash refund, reports/export, idempotency, manual return redesign.