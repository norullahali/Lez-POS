# SR.3.3 Step 3.2 — Supplier Profile Refund Entry

## Objective

Add a Supplier Profile entry point for **استرداد من المورد** that reuses the certified SR.3.3 Step 3.1 refund UI foundation.

## Architecture

Supplier Profile → SupplierCreditRefundEntry → supplierAvailableCreditProvider → showSupplierRefundSettlementDialog → SupplierRefundSettlementUiNotifier → SupplierRefundSettlementService.settleCredit() → supplier_transactions REFUND → FinancialLedgerRepository UNION → SUPPLIER_REFUND.

## Entry Point

- Screen: `lib/features/suppliers/screens/supplier_profile_screen.dart`
- Widget: `lib/features/returns/screens/widgets/supplier_credit_refund_entry.dart`
- Button: استرداد من المورد (enabled when credit > 0)
- Profile flow uses `returnId: null` (aggregate credit)

## Reused Step 3.1 Components

Dialog, notifier, providers, and Arabic failure mapper from Step 3.1. Shared `SupplierCreditRefundEntry` is also used in return detail dialog.

## Provider Flow

On success, `invalidateSupplierRefundDisplays(ref, supplierId)` refreshes credit, balance, and history providers.

## Settlement Boundary

UI does not write supplier_transactions, call DAO write methods, or write Cash Ledger directly. All writes go through `SupplierRefundSettlementService.settleCredit()`.

## Schema

31 → 31 (no migration).

## Tests

`test/supplier_refund_settlement_profile_sr_3_3_step_3_2_test.dart` (A–N, 14 tests).

## Confirmation

UI does not write financial data directly.