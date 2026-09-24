# Customer Returns Phase C Step 2.9 — Invoice Details Linked Refund Wiring

Implementation date: 2026-09-24
Baseline: e27df04 (schema 33)

## 1. Objective

Wire Invoice Details existing CustomerCreditRefundEntry to the invoice-linked customer_returns header when one exists. When linked, pass returnId and returnLabel so Steps 2.4 / 2.7B / 2.7C / 2.8A per-return cap and remaining UI activate. When no header exists, preserve aggregate-only behavior (returnId: null, returnLabel: null).

No financial mutation changes. No schema change.

## 2. Read Path

InvoiceDetailsDialog -> invoiceLinkedCustomerReturnProvider(invoiceId) -> CustomerReturnReadRepository.findInvoiceLinkedHeader(invoiceId) -> ReturnsDao.findCustomerReturnByOriginalInvoiceId(invoiceId) -> _InvoiceCustomerRefundEntry -> CustomerCreditRefundEntry(returnId, returnLabel)

## 3. Production Changes

- lib/features/invoices/widgets/invoice_details_dialog.dart — provider, _InvoiceCustomerRefundEntry, invalidation after partial/full return
- lib/features/returns/repositories/customer_return_read_repository.dart — findInvoiceLinkedHeader
- lib/features/returns/models/customer_return_history_models.dart — displayCustomerReturnNumber helper

## 4. Eligibility and Fallback

Refund section gate unchanged: _isInvoiceRefundCustomerEligible (customerId != null && != 1). returnId/returnLabel only when lookup succeeds. Loading/error -> aggregate-only. Legacy partial without header -> returnId null.

## 5. returnLabel

displayCustomerReturnNumber: non-empty returnNumber, else #id — same as Customer Return Detail.

## 6. Invalidation

_onPartialReturnDone and _confirmFullReturn invalidate invoiceLinkedCustomerReturnProvider after successful completion.

## 7. Financial Boundary (Unchanged)

CustomerRefundSettlementService remains sole REFUND mutation boundary. No changes to CustomerAccountsDao, PartialReturnService, ReturnsDao posting, cash ledger, credit cap, settled_amount.

## 8. Tests

test/customer_invoice_linked_refund_ui_phase_c_step_2_9_test.dart (12 tests A-K)
Updated test/customer_invoice_refund_ui_phase_c_step_2_5_test.dart — invoiceLinkedCustomerReturnProvider override null in baseOverrides.

Step 2.4 linked refund suite unchanged.
