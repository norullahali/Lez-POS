# Customer Returns Phase C Step 2.5 — Invoice Details Customer Cash Refund Entry

Implementation date: 2026-09-21
Baseline: Step 2.4 commit 4edea58

## 1. Objective

Add customer cash refund entry to the Invoice Details Dialog, reusing certified Step 2.3 refund UI and Step 2.1/2.2 financial architecture. Users can refund aggregate customer credit from the primary invoice workflow without a new financial path.

## 2. Existing Architecture Reused

- CustomerCreditRefundEntry
- showCustomerRefundSettlementDialog
- CustomerRefundSettlementUiNotifier
- customerAvailableCreditProvider
- CustomerRefundSettlementService.settleCredit()
- customerRefundSettlementFailureMessage()
- CUSTOMER_REFUND Cash Ledger UNION (Step 2.2)

## 3. Invoice Details Integration

When invoice detail resolves a real customer (customerId not null and not 1), the dialog shows section:

استرداد نقدي للعميل -> CustomerCreditRefundEntry

Placement: after totals card, before return metadata / partial return sections.

Read-model change: InvoiceDetailHeader now includes optional customerId from sales_invoices.customer_id (read-only SQL addition).

Provider rename: _partialReturnQtysProvider -> invoicePartialReturnQtysProvider (public, test-overridable; behavior unchanged).

## 4. Customer Eligibility

Refund section visible when:

- customerId != null
- customerId != 1 (not general customer)

Credit gating (button enabled/disabled) uses existing CustomerCreditRefundEntry + customerAvailableCreditProvider semantics.

## 5. Credit Semantics

- Display: aggregate available credit from customerAvailableCreditProvider
- Settlement: CustomerRefundSettlementService re-reads calculateBalanceFromTransactions inside transaction
- Invoice total / return total / debt are NOT used as refund amount

## 6. returnId Decision

Step 2.5 MVP: returnId and returnLabel are NOT passed (null).

Rationale: Invoice Details partial-return path does not produce a safe customer_returns.id. No invoice ID, sale_item_returns ID, or fabricated IDs are passed.

Aggregate-credit refund without return linkage matches certified Step 2.3 profile behavior.

## 7. UI Flow

InvoiceDetailsDialog -> invoiceDetailProvider -> _InvoiceDetailBody
  -> (eligible customer) CustomerCreditRefundEntry
  -> showCustomerRefundSettlementDialog
  -> submit() -> settleCredit(returnId: null)

## 8. Financial Write Boundary

Zero writes on: dialog open, entry display, credit read, dialog open with draft.

Successful refund: exactly one REFUND row via CustomerRefundSettlementService only.

## 9. Error Handling

Reuses customerRefundSettlementFailureMessage(). Failures preserve draft; success invalidates credit/balance/history via existing entry lifecycle.

## 10. Success Lifecycle

Existing CustomerCreditRefundEntry success path: invalidate providers, SnackBar تم استرداد المبلغ للعميل بنجاح, close dialog.

## 11. Tests

File: test/customer_invoice_refund_ui_phase_c_step_2_5_test.dart

Matrix A-R (18 tests):

- Widget integration via InvoiceDetailsDialog with provider overrides
- tester.runAsync for Drift seeding in widget tests
- invoicePartialReturnQtysProvider override to avoid widget-test DB deadlock
- customerAvailableCreditProvider override with real computed credit pattern where needed

Result: 18/18 PASS

## 12. Regression

Batch 1 (Customer Phase C Steps 1-2.5): 103/103 PASS

Command:
flutter test test/customer_return_phase_c_step_1_test.dart test/customer_refund_settlement_phase_c_step_2_test.dart test/customer_refund_cash_ledger_phase_c_step_2_2_test.dart test/customer_refund_settlement_ui_phase_c_step_2_3_test.dart test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart test/customer_invoice_refund_ui_phase_c_step_2_5_test.dart -j 1

Batch 2 (supplier refund): 54/54 PASS

Total: 157/157 PASS

## 13. Analyzer

Scoped flutter analyze on Step 2.5 files:

- 0 errors
- 0 warnings
- 1 pre-existing info: use_build_context_synchronously (invoice_details_dialog.dart:148, pre-existing full-return path)
- Step 2.5 test unnecessary_import fixed

## 14. Format

dart format --set-exit-if-changed on Step 2.5 scope files: exit 0

## 15. Windows Build

flutter build windows --debug: PASS

## 16. Schema

schemaVersion = 31 unchanged. No migration.

## 17. Known Limitations

- No returnId from Invoice Details (partial returns use sale_item_returns; customer_returns linkage deferred)
- No per-return refund cap
- No financial idempotency framework

## 18. Deferred Work

- Partial-return / customer_returns linkage for return-linked invoice refunds
- per-return settled_amount tracking
- financial idempotency framework
- CustomerReturnService refactor

---

IMPLEMENTATION COMPLETE — READY FOR REVIEW PASS