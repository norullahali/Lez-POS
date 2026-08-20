# Customer Returns Phase C Step 2.4 — Return-Linked Customer Refund Entry

## Objective

Allow users to open an eligible customer return from the Customer Returns list and initiate a cash refund in return context, reusing the certified Step 2.1–2.3 refund architecture without new financial write paths.

## Architecture

```
Customer Returns List (tap)
  -> CustomerReturnDetailDialog
  -> CustomerCreditRefundEntry (returnId + returnLabel)
  -> customerAvailableCreditProvider
  -> showCustomerRefundSettlementDialog
  -> CustomerRefundSettlementUiNotifier.submit()
  -> CustomerRefundSettlementService.settleCredit()
  -> customer_transactions REFUND (reference_id = returnId)
  -> FinancialLedgerRepository UNION
  -> CUSTOMER_REFUND OUTFLOW
```

## Data Flow

- Read-only detail via CustomerReturnReadRepository
- Customer resolution: customer_returns.original_invoice_id -> sales_invoices.customer_id -> customers
- UI resolution is display/eligibility only; service validates on submit

## Eligibility

Refund entry shown when:

- originalInvoiceId is not null
- customer resolves and customerId != 1 (not general customer)
- available credit > 0 (existing Step 2.3 entry gating)

Not eligible: manual/unlinked returns, general customer, partial returns without customer_returns row.

## Refund Semantics

- customer_returns.total = goods return value (metadata only)
- Refundable amount = aggregate customer credit (balance < 0 ? -balance : 0)
- User-entered refund amount; NOT pre-filled from return total
- No per-return settled_amount tracking

## Return Linkage

- returnId = customer_returns.id
- returnLabel = return_number
- Step 2.1 validates return ownership via invoice customer match

## Financial Safety

- UI financial writes = 0
- All persistence via settleCredit()
- No direct Cash Ledger writes
- No schema changes

## Tests (A–N)

14/14 focused tests in customer_return_linked_refund_ui_phase_c_step_2_4_test.dart

## Regression

139/139 PASS (Step 2.4 + Step 2.3 + Step 2.1 + Step 2.2 + Step 1 + supplier suites)

## Schema

schemaVersion = 31 unchanged

## Known Limitations

- Partial returns (sale_item_returns only) have no customer_returns.id for linkage
- Manual returns without invoice cannot use return-linked refund
- Multiple REFUND rows may reference same returnId; no per-return cap

## Deferred

- Invoice details dialog refund entry
- per-return settled_amount tracking
- idempotency framework