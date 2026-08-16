# Customer Returns - Comprehensive Assessment

| Field | Value |
|-------|-------|
| **Date** | August 16, 2026 |
| **Assessment Mode** | READ-ONLY |
| **Project** | Lez POS (Flutter / Drift / SQLite) |
| **Schema Version** | 31 |
| **Branch** | main (ahead of origin/main by 8 commits) |

## 1. Executive Summary

Customer Returns exists and is operational for goods/stock flows, but is not architecturally unified like Supplier Returns SR.1-SR.3.3. Primary workflow: Smart Return Lookup -> Invoice Details -> Full or Partial Return. Secondary screen /customer-returns supports manual/quick returns but was removed from sidebar navigation (commit f4d3b8d).

Goods return is implemented with atomic DB transactions and audit logging. Customer credit reversal works only for full returns on credit sales (debt_amount > 0). Partial returns do not adjust customer receivables. Cash refunds are derived via return_audit_logs in Cash Ledger UNION. No customer refund settlement service (unlike Supplier SR.3.3).

Zero dedicated Customer Returns tests. Supplier Returns has 11+ test files.

Production readiness score: 62/100. Recommended next phase: C - Customer Credit Accounting. Final decision: REQUIRES HARDENING.

## 2. Git / Project Baseline

- Branch: main @ 56f62ef, ahead of origin by 8 commits (Supplier Returns SR.3.3)
- Working tree: only .flutter-plugins-dependencies modified
- Customer return commits: 7772589, f4d3b8d (nav removed), 14985a5, e2068fe, 92134fe

## 3. Current Architecture

Multiple entry points without CustomerReturnService:
- Invoice History -> Smart Return Lookup -> InvoiceDetailsDialog (full: ReturnsDao.returnFullSaleInvoice; partial: PartialReturnService)
- CustomerReturnsScreen: manual saveCustomerReturn, quick processQuickReturn
- POS: processSale negative qty
- Dead: PosSaleService.processReturn (unused)

No CustomerReturnService, no read repository, UI calls DAO directly (unlike SupplierReturnService pattern).

## 4. Database / Schema

Schema v31. Tables: customer_returns, customer_return_items, sale_item_returns, return_audit_logs, sales_invoices, stock_ledger, customer_transactions. No schema changes required for current functionality.

## 5. Business Logic

Full return: stock, audit, invoice status, credit reversal if debt > 0. Gap: DAO does not block full return after partial (UI does).

Partial return: qty validation, stock, audit, invoice status. No customer accounting.

Manual return: stock OK; invoice field unused; price 0.0.

Quick return: stock + audit + manager approval.

## 6. Customer Accounting

GOODS RETURN: implemented. CUSTOMER CREDIT: full credit returns only. CASH REFUND: derived from audit logs.

Partial returns on credit sales do not post customer_transactions RETURN (BLOCKER F-02).

## 7. Cash Ledger

RETURN_REFUND outflow from return_audit_logs with dedup when customer_transactions RETURN exists for same invoice. Read-only UNION. No customer REFUND settlement txn type.

## 8. Customer History

Profile shows RETURN as generic label. Return analytics and cash ledger include returns. No profile refund entry.

## 9. UI / UX / Navigation

Route /customer-returns exists (pos.refund) but not in sidebar. Invoice dialog is primary path with full/partial UI, RTL, loading states. No detail dialog on customer returns list.

## 10. Providers / State

customerReturnsProvider, partialReturnServiceProvider, analytics providers. Direct DAO from widgets.

## 11. Trust Boundary

Quick refund amount computed in UI. Manual price hardcoded 0. Returnable qty and full totals authoritative in service/DAO.

## 12. Atomicity

Drift transactions with rollback. Risks: full after partial at DAO level; manual zero amounts; POS+invoice double count.

## 13. Test Audit

Customer Returns tests: 0. cash_ledger_forensic_runtime_test.dart FAILED (harness debug variable issue, pre-existing).

## 14. Static Analysis

flutter analyze: 119 issues, 0 errors, none in customer return files. Build not run.

## 15. Performance

LIMIT 100 list, LIMIT 60 lookup, acceptable for POS. Minor N+1 in partial validation.

## 16. Regression

Protected: ReturnAuditLogsDao, FinancialLedgerRepository, CustomerAccountsDao. Reference: SupplierReturnService.

## 17. Findings

| ID | Finding | Classification |
|----|---------|----------------|
| F-01 | No tests | REQUIRES HARDENING |
| F-02 | Partial no credit reversal | BLOCKER |
| F-03 | No refund settlement | DEFERRED |
| F-04 | Full return ignores partial at DAO | REQUIRES HARDENING |
| F-05 | Manual invoice field unused | NON-BLOCKING |
| F-06 | Manual price 0 | REQUIRES HARDENING |
| F-07 | Nav removed | NON-BLOCKING |
| F-08 | UI calls DAO | REQUIRES HARDENING |
| F-09 | Dead processReturn | ACCEPTED |
| F-10 | Cash via audit UNION | ALREADY IMPLEMENTED |
| F-11 | Full credit RETURN txn | ALREADY IMPLEMENTED |
| F-12 | Duplicate full blocked | ALREADY IMPLEMENTED |
| F-13 | Partial validation | ALREADY IMPLEMENTED |
| F-14 | Smart lookup | ALREADY IMPLEMENTED |
| F-15 | Analytics dashboard | ALREADY IMPLEMENTED |
| F-16 | Profile RETURN label | NON-BLOCKING |
| F-17 | Permission mismatch | NON-BLOCKING |
| F-18 | Quick refund in UI | REQUIRES HARDENING |
| F-19 | POS+invoice double count | DEFERRED |
| F-20 | No detail dialog | DEFERRED |
| F-21 | No StockGuard | NON-BLOCKING |
| F-22 | Nested txn recordReturn | ACCEPTED |

## 18. Production Readiness Score: 62/100

Blockers: F-02. Dimensions: goods 85, financial 40, integrity 70, architecture 35, UX 65.

## 19. Already Implemented

Full/partial invoice returns, smart lookup, audit logs, analytics, cash ledger RETURN_REFUND, full credit reversal, activity logging, quick/manual returns (stock).

## 20. Deferred Work

Refund settlement, profile entry, detail dialog, CustomerReturnService, deduplication, nav policy, reversal, idempotency.

## 21. Recommended Next Phase

Phase C - Customer Credit Accounting: proportional debt reversal for partial returns on credit invoices.

## 22. Final Decision

REQUIRES HARDENING. Ready for implementation planning of Customer Credit Accounting + test hardening. Not production-complete for financial parity.

End of read-only assessment.