# Supplier Returns SR.3.1 — UI Workflow & Read Contract Foundation

## Executive Summary

Phase SR.3.1 replaces the Supplier Returns creation placeholder with a real **read + in-memory draft** workflow. The user selects an original purchase invoice, loads purchase lines with SR.1 returnable quantities, and prepares return quantities in ephemeral Riverpod state. **No posting, persistence, stock, accounting, or Cash Ledger side effects occur.**

Schema remains **31 → 31**. Certified SR.2 write path is untouched.

## Existing UI Audit

| Element | Location | Finding |
|---------|----------|---------|
| Supplier Returns screen | lib/features/returns/screens/supplier_returns_screen.dart | Arabic header, empty-state list preserved |
| + مرتجع مورد button | Same file | Previously showed SnackBar placeholder |
| Placeholder SnackBar | Removed | Was: مرتجعات الموردين سيتم إضافتها قريباً |
| Dialog pattern | smart_return_lookup_dialog.dart | 960x720 desktop dialog, RTL, AppColors |
| Riverpod | purchaseFormProvider | NotifierProvider for form state |

## Existing Purchase Read APIs

Reused from PurchasesDao: getAllInvoices(), getItemsForInvoice(), getInvoiceById().
Reused from SuppliersDao: getSupplierById().
Reused from SR.1 ReturnsDao: getReturnableQuantityForPurchaseItem().

No new write APIs.

## Files Reused

PurchasesDao, SuppliersDao, ReturnsDao, AppColors, AppTheme, PurchaseStatus, SupplierReturnsScreen layout.

## Files Created

- lib/features/returns/models/supplier_return_draft_models.dart
- lib/features/returns/repositories/supplier_return_read_repository.dart
- lib/features/returns/providers/supplier_return_draft_provider.dart
- lib/features/returns/screens/widgets/create_supplier_return_dialog.dart
- test/supplier_return_draft_sr_3_1_test.dart
- docs/supplier_returns_sr_3_1_ui_read_foundation.md

## Files Modified

- lib/features/returns/screens/supplier_returns_screen.dart

## Read Model Architecture

SupplierReturnPurchaseOption: purchaseInvoiceId, supplierId, supplierName, invoiceNumber, purchaseDate, totalAmount, status.

SupplierReturnDraftLine: purchaseItemId, productId, productName, purchasedQty, alreadyReturnedQty, returnableQty, unitCost, selectedReturnQty.

validateDraftLineQuantity(): UI convenience only.

## Purchase Eligibility Rule

Eligible when: invoice exists, supplierId != null, supplier row exists, status != CANCELLED.

## Purchase Selector Workflow

Tap مرتجع مورد -> CreateSupplierReturnDialog -> search/select purchase -> load lines.

## Purchase Item Loading

getItemsForInvoice + getReturnableQuantityForPurchaseItem per line. Exact purchaseItemId linkage.

## Returnable Quantity Integration

Uses SR.1 ReturnsDao.getReturnableQuantityForPurchaseItem only. No duplicated math.

## Draft State Ownership

SupplierReturnDraftNotifier (NotifierProvider): ephemeral, not persisted, reset on close.

## Quantity Validation

selectedReturnQty >= 0 and <= returnableQty. canProceed requires valid selections.

## Draft Total Semantics

Presentation only: sum(selectedReturnQty * unitCost). Not authoritative for posting.

## Loading / Error / Empty States

Loading spinners, Arabic empty/error messages, zero-returnable banner, save button disabled (SR.3.2).

## Performance Notes

N+1 getReturnableQuantityForPurchaseItem per line accepted for SR.3.1. Batch API deferred.

## Financial Side-Effect Confirmation

No SupplierReturn, stock, supplier accounting, or Cash Ledger changes. Service not called.

## Schema Confirmation

31 -> 31 unchanged.

## SR.1 Regression

11 / 11 PASS

## SR.2 Regression

11 / 11 PASS

## Hardening Regression

4 / 4 PASS

Certified total: 26 / 26 PASS

## New Tests

12 / 12 PASS in test/supplier_return_draft_sr_3_1_test.dart (A-J plus validation/total/widget).

## Validation Results

dart format: PASS
flutter analyze: 105 pre-existing issues, no SR.3.1 errors
flutter build windows --debug: PASS

## Deferred SR.3 Work

SR.3.2 posting wire-up, history list, reports, cash refund, manual returns.

## Readiness for Review Pass

GO