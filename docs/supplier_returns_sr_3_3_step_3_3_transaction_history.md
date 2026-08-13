# SR.3.3 Step 3.3 — Supplier Transaction History Display

**Date:** 2026-08-13  
**Phase:** SR.3.3 Step 3.3  
**Schema:** 31 → 31 (no migration)

## Objective

Correctly distinguish PURCHASE, PAYMENT, RETURN, and REFUND rows in the Supplier Profile transaction history (Ledger tab). Presentation-only — no financial architecture changes.

## Display Contract

| Type | Default Arabic label | Icon | Amount styling |
|------|---------------------|------|----------------|
| PURCHASE | شراء | shopping_cart_rounded | Payable / error (+ prefix when positive) |
| PAYMENT | دفعة للمورد | payments_rounded | Payment / success |
| RETURN | مرتجع بضاعة | assignment_return_rounded | Goods return / warning |
| REFUND | استرداد نقدي | call_received_rounded | Cash inflow / success (+ prefix) |

When `note` is non-empty, the note is shown as the title. For RETURN/REFUND with `referenceId`, subtitle includes `مرجع: #id`.

## Architecture

```
supplierHistoryProvider (read-only)
  → SupplierTransactionsTab
  → SupplierTransactionListTile
  → resolveSupplierTransactionPresentation()
```

No writes to supplier_transactions, Cash Ledger, balances, or settlement services.

## Files

| File | Role |
|------|------|
| `lib/features/suppliers/utils/supplier_transaction_display.dart` | Type → presentation mapping |
| `lib/features/suppliers/screens/widgets/supplier_transactions_tab.dart` | Ledger tab + list tile widget |
| `lib/features/suppliers/screens/supplier_profile_screen.dart` | Uses SupplierTransactionsTab |
| `test/supplier_transaction_history_sr_3_3_step_3_3_test.dart` | Step 3.3 tests (10) |

## Protected (unchanged)

- SupplierRefundSettlementService
- SupplierReturnService
- SupplierAccountsDao / ReturnsDao
- FinancialLedgerRepository / CashLedgerEventType
- Refund UI stack (Step 3.1 / 3.2)
- Schema / migrations

## Test Results

| Suite | Result |
|-------|--------|
| Step 3.3 focused | 10/10 PASS |
| Full SR regression | 131/131 PASS |

## Validation

| Check | Result |
|-------|--------|
| dart format (Step 3.3 files) | PASS (2 files reformatted) |
| flutter analyze (Step 3.3 scope) | 0 errors / 0 warnings / 1 info (pre-existing avoid_print in profile screen) |
| flutter build windows --debug | PASS |
| Schema | 31 unchanged |

## Status

**READY FOR REVIEW PASS** — implementation complete, not certified.