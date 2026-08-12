# Supplier Returns SR.3.3 Step 3.1 — UI Refund Foundation

**Date:** 2026-08-12  
**Phase:** SR.3.3 Step 3.1  
**Schema:** 31 → 31 (no migration)

---

## Objective

Add the UI foundation for settling supplier accumulated credit via the certified `SupplierRefundSettlementService.settleCredit()` path. This step introduces credit visibility, a refund entry point, an RTL settlement dialog, Riverpod UI state, Arabic error mapping, and double-submit protection — without modifying accounting architecture.

---

## UI Architecture

```
SupplierReturnDetailDialog
  → supplierAvailableCreditProvider (read-only)
  → showSupplierRefundSettlementDialog
  → SupplierRefundSettlementUiNotifier.submit()
  → SupplierRefundSettlementService.settleCredit()
  → supplier_transactions (REFUND)
  → derived Cash Ledger SUPPLIER_REFUND (Step 2 UNION)
```

**Financial writes from UI:** 0  
**Cash Ledger direct writes from UI:** 0

---

## Files

| File | Role |
|------|------|
| `lib/features/returns/providers/supplier_refund_settlement_provider.dart` | Service provider, credit read provider, ephemeral UI notifier |
| `lib/features/returns/utils/supplier_refund_settlement_messages.dart` | Arabic failure mapper |
| `lib/features/returns/screens/widgets/supplier_refund_settlement_dialog.dart` | RTL refund dialog |
| `lib/features/returns/screens/widgets/supplier_return_detail_dialog.dart` | Credit visibility + `استرداد من المورد` entry |
| `test/supplier_refund_settlement_ui_sr_3_3_step_3_1_test.dart` | Focused Step 3.1 tests |

---

## Provider / State Architecture

- `supplierRefundSettlementServiceProvider` — canonical settlement service
- `supplierAvailableCreditProvider(supplierId)` — read-only aggregate credit display
- `supplierRefundSettlementProvider` — ephemeral dialog state (not persisted)

States: idle → submitting → success | failure

On success: increments `supplierReturnsRefreshProvider`, invalidates credit provider.

---

## Service Boundary

UI calls **only** `SupplierRefundSettlementService.settleCredit()`.

UI does **not** call DAOs, write supplier_transactions, write Cash Ledger rows, or mutate balances authoritatively.

UX validation (`validateRefundAmountText`) is display-only; service remains authoritative.

---

## Arabic Error Mapping

`supplierRefundSettlementFailureMessage()` maps all `SupplierRefundSettlementFailure` codes to Arabic UI text. No raw exception strings are shown.

---

## Double-Submit Protection

`submit()` sets `submitting` status synchronously before validation/service await. Second concurrent submit is ignored while submitting.

---

## Financial Side-Effect Boundary

| Action | Supplier txns | Cash Ledger |
|--------|---------------|-------------|
| Open detail / dialog | unchanged | unchanged |
| UX validation failure | unchanged | unchanged |
| Successful settlement | 1 REFUND via service | 1 derived SUPPLIER_REFUND |

---

## Schema

`schemaVersion = 31`. No tables, columns, indexes, or migrations.

---

## Tests

### Step 3.1 focused (13/13 PASS)

A–L per spec plus opening-dialog side-effect guard.

### Full regression (107/107 PASS)

SR.1 (11) + SR.2 (11) + Hardening (4) + SR.3.1 (18) + SR.3.2 Step 1 (11) + SR.3.2 Step 2 (12) + SR.3.3 Step 1 (13) + SR.3.3 Step 2 (14) + SR.3.3 Step 3.1 (13)

---

## Validation Results

| Check | Result |
|-------|--------|
| `dart format` (Step 3.1 files only) | PASS |
| `flutter analyze` (Step 3.1 scope) | 0 errors, 0 warnings |
| `flutter build windows --debug` | PASS |

---

## Deferred Items

- DEF-01: Full refund workflow polish (Step 3.2+)
- DEF-02: Generic idempotency framework
- DEF-03: Per-return `settled_amount` tracking
- Supplier profile screen refund entry (future step)

---

## Final Status

**READY FOR REVIEW PASS** — implementation only, not certified.
