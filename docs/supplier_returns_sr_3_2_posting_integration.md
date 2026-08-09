# Supplier Returns SR.3.2 — Posting Integration (Step 1)

## Objective

Connect the SR.3.1 ephemeral draft UI to the certified SR.2 posting service without moving business rules into the UI layer.

## Architecture

```
SupplierReturnsScreen
  -> showCreateSupplierReturnDialog()
  -> SupplierReturnDraftNotifier (Riverpod)
       validate draft (UX)
       buildPostingInputFromDraft()
       SupplierReturnService.postPurchaseLinkedReturn()
  -> SR.2 atomic transaction (unchanged)
```

The UI is not authoritative for financial correctness. All purchase/supplier/stock/accounting validation remains in `SupplierReturnService`.

## Dependency injection

| Provider | Role |
|----------|------|
| `supplierReturnServiceProvider` | Canonical `SupplierReturnService(AppDatabase.instance)` |
| `supplierReturnReadRepositoryProvider` | SR.3.1 read path (unchanged) |
| `supplierReturnsRefreshProvider` | `StateProvider<int>` tick incremented after successful post |

**Decision:** Reused Riverpod `Provider` pattern consistent with `supplierReturnReadRepositoryProvider`. No second service architecture and no direct DB writes from widgets.

## Input mapping

`buildPostingInputFromDraft()` maps:

- `supplierId` / `purchaseInvoiceId` from selected purchase option
- Lines: `{ purchaseItemId, quantity }` for selected qty > 0 only
- Optional trimmed `reason` / `notes`

The UI does **not** send unit cost, productId, or accounting amounts. SR.2 derives those from purchase items.

## Posting lifecycle

`SupplierReturnPostingStatus`: `idle` | `posting` | `success` | `failure`

- `canSave` = `canProceed && !isLoading && !isPosting`
- `_postGeneration` token ignores stale async completions after reset/navigation
- Dialog: `PopScope(canPop: !isPosting)`, Arabic overlay "جاري حفظ المرتجع..."

## Double-submit protection

1. `submitReturn()` returns early when `!canSave`
2. Posting state sets `isPosting` before await
3. Second tap while posting: `canSave` false -> ignored
4. Tests use `RecordingSupplierReturnService` + `Completer` hold

## Success path

After service success only:

1. `supplierReturnsRefreshProvider` incremented
2. Dialog closes with `true`
3. Screen shows SnackBar: "تم حفظ مرتجع المورد بنجاح"
4. Draft reset on dialog close (`showCreateSupplierReturnDialog().then(reset)`)

## Failure path

On `SupplierReturnPostingException`:

- Dialog stays open
- Draft preserved (lines/qty)
- Arabic message via `supplierReturnPostingFailureMessage()`
- Posting state -> `failure`, user may retry

## Arabic failure mapping

| Code | Message |
|------|---------|
| purchaseNotFound | فاتورة الشراء غير موجودة |
| supplierNotFound | المورد غير موجود |
| supplierMismatch | المورد لا يطابق فاتورة الشراء |
| emptyLines | يجب تحديد بنود للإرجاع |
| purchaseItemNotFound | بند الشراء غير موجود |
| purchaseItemInvoiceMismatch | بند الشراء لا ينتمي إلى هذه الفاتورة |
| invalidQuantity | كمية الإرجاع غير صالحة |
| quantityExceedsReturnable | الكمية تتجاوز المتاح للإرجاع |
| stockInsufficient | تعذر خصم الكمية من المخزون |
| supplierAccountingFailure | تعذر تسجيل حركة المورد |

Raw exception text is never shown to users.

## Refresh behavior

`SupplierReturnsScreen` watches `supplierReturnsRefreshProvider`. Refresh tick increments only after successful `submitReturn()`. Opening the dialog does not refresh.

## Financial side-effect boundaries

| Layer | Writes |
|-------|--------|
| UI / draft provider | None (read + service call only) |
| SupplierReturnService | SupplierReturns, items, stock, supplier accounting |

Cash Ledger: **no change** — goods return alone still creates zero cash events (SR.2 certified).

## Schema

**31 -> 31** — no migration, no new tables.

## Tests

`test/supplier_return_posting_integration_sr_3_2_test.dart` (11 tests):

- A-J posting integration scenarios
- `buildPostingInputFromDraft` unit test

Regression suites (all green):

- SR.1: 11/11
- SR.2: 11/11
- Hardening: 4/4
- SR.3.1: 18/18
- SR.3.2: 11/11

## Deferred work

- Cash refund settlement
- Returns list/history UI
- Export / reports
- Idempotency keys
- Manual return workflow redesign
- Batch returnable optimization