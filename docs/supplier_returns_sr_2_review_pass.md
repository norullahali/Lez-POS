# Supplier Returns SR.2 — Review Pass

**Date:** 2026-08-06
**Mode:** Read-only architecture review (no code changes)
**Schema:** 31 (unchanged)

## Executive Summary

SR.2 delivers a correct, atomic purchase-linked Supplier Return posting workflow via SupplierReturnService.postPurchaseLinkedReturn(). Transaction ownership, TOCTOU-safe returnable quantity enforcement, duplicate-line aggregation, rollback on stock/accounting failure, and Cash Ledger isolation are verified PASS.

No BLOCKERS found. One REQUIRES HARDENING item: ReturnsDao.saveSupplierReturn() remains callable and can bypass SR.2 business rules if used by future production code. Today there are zero production callers (SR.1 tests only), so risk is latent.

**Final Decision: GO TO HARDENING**

## Canonical Service Review — PASS

SupplierReturnService is the canonical boundary. Zero production callers today. UI placeholder only.

| Path | Production callers | SR.2 enforcement |
|------|-------------------|------------------|
| SupplierReturnService.postPurchaseLinkedReturn | None (tests) | Full |
| ReturnsDao.saveSupplierReturn | None (SR.1 tests) | Structural only — bypass risk |
| ReturnsDao.persistSupplierReturn | Service only | Requires enclosing transaction |

## Transaction Ownership — PASS

Single outer _db.transaction() in postPurchaseLinkedReturn(). persistSupplierReturn() and recordReturnInTransaction() do not open nested transactions. Rollback verified by tests G and H.

saveSupplierReturn() opens its own transaction when called directly — isolated from SR.2 canonical path.

## DAO API Safety — MEDIUM (latent bypass)

saveSupplierReturn() skips returnable-qty caps and supplier accounting but still posts stock. No production callers today. Hardening: deprecate for purchase-linked use; SR.3 must use service only.

## Accounting Poster Test Seam — SAFE

Production default (_accountingPoster == null) always calls recordReturnInTransaction(). Hook used only in test H. Optional hardening: @visibleForTesting factory.

## Returnable Quantity — PASS

getReturnableQuantityForPurchaseItem() called inside transaction. Duplicate 6+6 aggregated to 12, rejected when returnable=10 (test F). Line-level isolation preserved (SR.1 test E).

## Trusted Cost — PASS

unitCost from PurchaseItem; productId derived from purchase line. UI cannot inject cost. productMismatch enum exists but never thrown (NON-BLOCKING dead code).

## Supplier Accounting — PASS / ACCEPTED

recordReturnInTransaction: type RETURN, amount -returnValue.
Balance = SUM(supplier_transactions.amount).
Test A: 100 -> return 10 -> 90. Sign correct.

Fully paid purchase (debtAmount=0): RETURN still posts; balance may go negative (supplier credit). Ledger-consistent. No Cash In. Classification: ACCEPTED.

## Cash Ledger Boundary — PASS (0 events)

FinancialLedgerRepository UNION includes supplier_transactions WHERE type = PAYMENT only. RETURN excluded. Test J confirms zero new cash ledger entries.

## Stock Exactly Once — PASS

One RETURN_OUT + StockGuard per aggregated purchaseItemId. No duplicate writes. Test I: 2 lines -> 2 ledger rows.

## Rollback / Atomicity — PASS

Validation, stock, and accounting failures leave zero partial state (tests B,D,E,F,G,H).

## Failure Contract — PASS (minor gaps)

All meaningful codes thrown except productMismatch (dead). supplierAccountingFailure wraps inner exception in message (NON-BLOCKING).

## Legacy Compatibility — PASS

saveSupplierReturn() preserved for SR.1/manual. Nullable purchaseItemId unchanged. Service requires purchase linkage.

## Customer Returns Regression — PASS

Customer methods unchanged in ReturnsDao. SR.1 11/11 PASS.

## Test Quality — PASS

SR.2 tests A-J exercise real service/DB behavior with side-effect assertions. SR.1 foundation intact. Minor gap: no fully-paid return credit test (NON-BLOCKING).

## Schema — PASS (31, unchanged)

## Scope — PASS (no UI, no cash refund, no reports)

## Findings Summary

| ID | Class | Finding |
|----|-------|---------|
| F-01 | REQUIRES HARDENING | saveSupplierReturn bypass path |
| F-02 | NON-BLOCKING | productMismatch enum unused |
| F-03 | NON-BLOCKING | English error messages |
| F-04 | NON-BLOCKING | Raw exception in accounting failure message |
| F-05 | ACCEPTED | Fully-paid return -> negative supplier credit |
| F-06 | DEFERRED SR.3+ | Idempotency keys |
| F-07 | DEFERRED SR.3+ | Cash refund settlement |
| F-08 | DEFERRED SR.3+ | Credit UX |

BLOCKERS: 0 | REQUIRES HARDENING: 1 | NON-BLOCKING: 3 | ACCEPTED: 1 | DEFERRED: 3

## Hardening Recommendations

1. Deprecate/guard saveSupplierReturn for purchase-linked use
2. @visibleForTesting for accountingPoster seam
3. Remove unused productMismatch enum or document why reserved
4. Add fully-paid purchase return test
5. Arabic-localize exception messages before SR.3 UI

## Validation

SR.1: 11/11 PASS | SR.2: 11/11 PASS | flutter analyze: 0 errors | Windows build: PASS

## Readiness Score: 91 / 100

## Final Decision: GO TO HARDENING