# Customer Returns — Phase C Step 2.3 — Customer Refund UI Foundation

## Objective

Build the UI foundation for settling accumulated customer credit as a cash refund, strictly on top of the certified Step 2.1 settlement service and Step 2.2 derived Cash Ledger integration.

**UI financial writes: 0**

**All financial settlement persistence is delegated to `CustomerRefundSettlementService.settleCredit()`.**

## UI Architecture

```
Customer Profile / CustomerCreditRefundEntry
  -> customerAvailableCreditProvider (read-only)
  -> showCustomerRefundSettlementDialog
  -> CustomerRefundSettlementUiNotifier.submit()
  -> CustomerRefundSettlementService.settleCredit()
  -> customer_transactions REFUND
  -> FinancialLedgerRepository UNION (Step 2.2)
  -> CUSTOMER_REFUND OUTFLOW
```

## Provider Architecture

- `customerAvailableCreditProvider(customerId)` — read-only; `balance < 0 ? -balance : 0`
- `customerRefundSettlementServiceProvider` — wraps canonical Step 2.1 service
- `customerRefundSettlementProvider` — ephemeral UI state (idle/submitting/success/failure)
- `invalidateCustomerRefundDisplays()` — refreshes credit, balance, history after success

## Service Boundary

UI MUST NOT write `customer_transactions`, DAO rows, or Cash Ledger directly. All persistence goes through `settleCredit()` only.

## Credit Semantics

- Negative customer balance = business owes customer
- Available credit = `-balance` when balance < 0
- UI display is read-only; service validates authoritative credit

## Error Mapping

All `CustomerRefundSettlementFailure` codes map to Arabic via `customerRefundSettlementFailureMessage()`. No raw exceptions shown.

## Double-Submit Protection

`submit()` sets `submitting` synchronously before any await. Concurrent calls are ignored via generation counter + `isSubmitting` guard.

## Success Lifecycle

1. `settleCredit()` succeeds
2. Invalidate credit/balance/history providers
3. Close dialog
4. Arabic success snackbar

## Failure Lifecycle

Remain in dialog, preserve draft, show mapped Arabic error, no financial side effects.

## Cash Ledger Boundary

Step 2.3 does not write Cash Ledger. Successful refunds produce derived `CUSTOMER_REFUND` through Step 2.2 UNION only.

## Test Matrix (A–R)

| ID | Assertion |
|----|-----------|
| A | Credit displayed correctly |
| B | Zero credit disables entry |
| C | Positive credit enables entry |
| D | Profile credit read = zero writes |
| E | Dialog open = zero writes |
| F | Full refund -> service |
| G | Partial refund -> service |
| H | Double submit ignored |
| I | Invalid amount -> no service call |
| J–L | Arabic failure mapping |
| M | Return not found / mismatch mapping |
| N | Success refreshes credit/history |
| O | Failure preserves draft |
| P | UI via service not direct DAO |
| Q | No direct Cash Ledger write |
| R | Derived CUSTOMER_REFUND event |

## Validation Results

- Focused Step 2.3: **18/18 PASS**
- Regression (Step 1 + 2.1 + 2.2 + supplier refund suites): **107/107 PASS**
- `dart format`: PASS
- `dart analyze` (Step 2.3 scope): 0 errors, 0 warnings (6 pre-style `prefer_const_constructors` infos in dialog overlay copied from supplier pattern)
- `flutter build windows --debug`: PASS
- Schema: **31** unchanged

## Deferred Items

- Return-linked refund entry from customer return detail screen (optional `returnId`/`returnLabel` supported in dialog; profile entry uses `returnId = null`)
- Review Pass / Final Audit / commit
