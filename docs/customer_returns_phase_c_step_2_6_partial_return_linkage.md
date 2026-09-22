# Customer Returns Phase C Step 2.6 — Partial Return Customer Return Linkage

Implementation date: 2026-09-22
Baseline: Step 2.5 commit fbd3ca4
Schema: 31 unchanged

## 1. Problem

Partial returns used sale_item_returns as the operational ledger but never created a customer_returns document. Full returns (clean path) created customer_returns, but any invoice with prior partial returns delegated to PartialReturnService and returned no header.

## 2. Previous Partial-Return Architecture

PartialReturnService.processPartialReturn() inside one transaction: sale_item_returns, stock restore, audit, RETURN txn (credit only, reference_id = first sale_item_returns.id), invoice status. No customer_returns writes.

## 3. New customer_returns Linkage

Inside the same transaction after sale_item_returns loop and before credit reversal:

- ReturnsDao.upsertPartialReturnDocumentHeader() find-or-create one header per original_invoice_id
- ReturnsDao.appendCustomerReturnDocumentLines() append snapshot lines for current batch

## 4. One Header Per Invoice

First batch creates header; later batches reuse and increment total; returnAllRemaining uses same path; full return after partial does not create second header; clean full return unchanged.

## 5. Stock / RETURN / Refund — Unchanged

Stock on sale_item_returns path only. RETURN reference_id remains sale_item_returns.id. No settlement or ledger changes.

## 6. Cash Invoices

Document created; no RETURN transaction when debtAmount == 0.

## 7. Historical Data

Forward-only. No backfill.

## 8. Deferred

settled_amount, FK column, CustomerReturnService refactor, Invoice Details returnId wiring.

## 9. Validation

Focused 19/19, Customer 122/122, Supplier 54/54, Total 176/176, Analyzer 0/0, Format PASS, Build PASS, Schema 31.

IMPLEMENTATION COMPLETE — READY FOR REVIEW