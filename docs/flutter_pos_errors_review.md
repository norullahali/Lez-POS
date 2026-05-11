# Flutter POS Project — Printing System Errors: Full Review & Fix Log

Date: 2026-04-25

---

## 1. Background

The project had a broken printing system caused by mixing two separate implementations:

| System | Files / Types |
|--------|---------------|
| Old (dead) | `ReceiptData`, `ReceiptItem`, `printing_service.dart` |
| New (active) | `InvoiceItem`, `InvoiceData`, `receipt_service.dart`, `invoice_pdf_builder_clean.dart` |

The old system left no actual code behind (no definitions, no usages). However, the new system was itself internally inconsistent, causing compile errors.

---

## 2. File Map (lib/ relevant to printing)

```
lib/
+-- core/
|   +-- services/
|   |   +-- receipt_service.dart          <- top-level printSale() function
|   +-- utils/
|       +-- invoice_pdf_builder_clean.dart <- PDF generation class
+-- features/
    +-- pos/
        +-- models/
        |   +-- invoice_models.dart        <- InvoiceItem / InvoiceData definitions
        +-- providers/
        |   +-- pos_provider.dart          <- CartNotifier.checkout()
        +-- screens/
            +-- pos_screen.dart            <- checkout UI, calls printSale()
```

---

## 3. All Identified Errors

### 3.1 invoice_pdf_builder_clean.dart (4 errors)

Error 1 — Imports after class declarations
  import 'dart:typed_data', import 'package:pdf/...' etc. appeared on lines 46-50,
  AFTER class bodies. This is invalid Dart syntax.

Error 2 — Duplicate InvoiceItem class
  The file redefined InvoiceItem (using qty, unitPrice, lineTotal) while ALSO importing
  invoice_models.dart which defined the same name — duplicate symbol error.

Error 3 — Duplicate InvoiceData class
  Same issue as Error 2 for InvoiceData.

Error 4 — Wrong relative import path
  import '../models/invoice_models.dart' from lib/core/utils/ resolves to
  lib/core/models/invoice_models.dart — that file does not exist.

---

### 3.2 invoice_models.dart (2 errors)

Error 5 — InvoiceItem field mismatch
  Defined with: quantity (int), price (double)
  Used everywhere as: qty (double), unitPrice (double), lineTotal (double)
  Every call site was a constructor mismatch / compile error.

Error 6 — InvoiceData missing store fields
  Only had: invoiceNumber, date, items, total
  receipt_service.dart was passing: storeName, phone, address, logoBytes,
  customerName, cashierName — all missing from the class definition.

---

### 3.3 receipt_service.dart (2 errors)

Error 7 — Wrong import path for models
  import '../models/invoice_models.dart' from lib/core/services/ resolves to
  lib/core/models/invoice_models.dart — that file does not exist.

Error 8 — InvoiceData built without required total field
  The InvoiceData(...) constructor call omitted total, which was a required named parameter.

---

### 3.4 pos_provider.dart (2 errors)

Error 9 — Duplicate imports
  invoice_pdf_builder_clean.dart imported twice:
    import '../../../core/utils/invoice_pdf_builder_clean.dart';
    import 'package:lez_pos/core/utils/invoice_pdf_builder_clean.dart';

Error 10 — Dead printing code with wrong field names
  checkout() built an InvoiceItem list using the OLD fields (quantity, price)
  inside a try-catch block but NEVER called printSale. The code was unreachable dead code.

---

### 3.5 pos_screen.dart (3 errors)

Error 11 — _printReceiptFromSnapshot uses undefined variables
  The method body referenced: activeCartSnapshot, selectedCustomer, data
  None of these were parameters or locals of that method.

Error 12 — Non-existent field lineDiscount
  A second InvoiceItem(...) constructor call inside _printReceiptFromSnapshot used:
    lineDiscount: i.discount
  The field lineDiscount does not exist on any InvoiceItem definition in the project.

Error 13 — _printReceiptFromSnapshot was never called
  The method was defined but had zero call sites anywhere in the project.
  It was entirely dead broken code.

---

## 4. Root-Cause Summary

All errors trace to one core mistake:

invoice_pdf_builder_clean.dart was written as a self-contained file, defining its OWN
InvoiceItem/InvoiceData (with qty/unitPrice/lineTotal), but it ALSO imported
invoice_models.dart which defined the same class names — causing duplicate symbol errors.

When pos_screen.dart then adopted the PDF builder's field names (qty, unitPrice, lineTotal)
while importing invoice_models.dart (which still had quantity, price), the mismatch
cascaded into every file in the printing pipeline.

---

## 5. Fix Plan (applied in order)

Step 1 — invoice_models.dart
  Make this the single source of truth.
  - InvoiceItem: rename quantity->qty (double), price->unitPrice, add lineTotal
  - InvoiceData: add storeName, phone, address, logoBytes, customerName, cashierName
                 make date optional (default: DateTime.now())
                 add import 'dart:typed_data' at top

Step 2 — invoice_pdf_builder_clean.dart
  Clean file structure.
  - Move ALL imports to the very top of the file
  - Delete the duplicate InvoiceItem and InvoiceData class bodies
  - Fix import path: ../models/invoice_models.dart
                  -> ../../features/pos/models/invoice_models.dart

Step 3 — receipt_service.dart
  Fix import and missing field.
  - Fix import path to point at features/pos/models/invoice_models.dart
  - Compute total before building InvoiceData:
      final total = items.fold(0.0, (sum, e) => sum + e.lineTotal);
  - Remove unused date: DateTime.now() from constructor call (now has default)

Step 4 — pos_provider.dart
  Remove all dead printing code.
  - Delete duplicate import of invoice_pdf_builder_clean.dart
  - Delete unused import of receipt_service.dart
  - Delete the dead try-catch block in checkout() that built InvoiceItem
    objects with old field names but never called printSale

Step 5 — pos_screen.dart
  Remove broken dead method and unused imports.
  - Delete entire _printReceiptFromSnapshot method
  - Remove redundant import of invoice_pdf_builder_clean.dart
  - Remove orphaned import of cart_session.dart

---

## 6. Final State of Each File

---- invoice_models.dart ----

import 'dart:typed_data';

class InvoiceItem {
  final String name;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  InvoiceItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });
}

class InvoiceData {
  final String invoiceNumber;
  final DateTime date;
  final List<InvoiceItem> items;
  final double total;
  final String storeName;
  final String? phone;
  final String? address;
  final Uint8List? logoBytes;
  final String? customerName;
  final String? cashierName;

  InvoiceData({
    required this.invoiceNumber,
    required this.items,
    required this.storeName,
    required this.total,
    this.phone,
    this.address,
    this.logoBytes,
    this.customerName,
    this.cashierName,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}


---- invoice_pdf_builder_clean.dart (imports + structure) ----

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import '../../features/pos/models/invoice_models.dart';

enum ReceiptPaperSize { thermal58, thermal80, a4 }

class InvoicePdfBuilderClean {
  Future<Uint8List> buildInvoice(InvoiceData data, { ReceiptPaperSize paperSize }) async { ... }
  pw.Widget _buildTable(InvoiceData data, pw.Font font) { ... }
  pw.Widget _cell(String text, pw.Font font, {bool isHeader}) { ... }
  pw.Widget _kvRow(String label, String value, pw.Font font, {bool bold}) { ... }
  String _formatDate(DateTime date) { ... }
  String _safe(num? value) { ... }
}


---- receipt_service.dart ----

import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import '../utils/invoice_pdf_builder_clean.dart';
import '../database/app_database.dart';
import '../services/settings_service.dart';
import '../../features/pos/models/invoice_models.dart';

Future<void> printSale({
  required String invoiceNumber,
  required List<InvoiceItem> items,
  String? customerName,
  double? loyaltyPoints,
}) async {
  try {
    // loads storeName, phone, address, logoPath from SettingsService
    // reads logo file into Uint8List if path exists
    // computes: final total = items.fold(0.0, (sum, e) => sum + e.lineTotal);
    // builds InvoiceData(invoiceNumber, items, storeName, total, phone, address, logoBytes, customerName)
    // calls InvoicePdfBuilderClean().buildInvoice(pdfData, paperSize: thermal80)
    // calls Printing.layoutPdf(onLayout: pdfBytes)
  } catch (e) {
    print('PRINT ERROR: $e');
  }
}


---- pos_provider.dart (removed lines) ----

REMOVED imports:
  import '../../../core/utils/invoice_pdf_builder_clean.dart';
  import '../../../core/services/receipt_service.dart';
  import 'package:lez_pos/core/utils/invoice_pdf_builder_clean.dart';

REMOVED dead block from inside checkout():
  try {
    final invoiceItems = active.items.map((item) => InvoiceItem(
      name: item.product.name,
      quantity: item.effectiveQuantity.toInt(),   // <- wrong field name
      price: item.unitPrice,                       // <- wrong field name
    )).toList();
    // printSale was NEVER called here
  } catch (e) { print('PRINT ERROR: $e'); }


---- pos_screen.dart (removed lines) ----

REMOVED imports:
  import 'package:lez_pos/core/utils/invoice_pdf_builder_clean.dart';
  import '../models/cart_session.dart';

REMOVED method _printReceiptFromSnapshot():
  - used undefined variable: activeCartSnapshot
  - used undefined variable: selectedCustomer
  - used undefined variable: data
  - used non-existent field: lineDiscount
  - was never called anywhere in the project

---

## 7. Verified Clean State

After all fixes, ReadLints reported 0 errors across all 5 modified files.

Remaining (pre-existing, unrelated) warnings in pos_screen.dart:
  - L646 [WARNING] The value of the local variable 'pointsAfter' isn't used.
  - L659 [WARNING] The value of the local variable 'currentDebt' isn't used.
  - L663 [WARNING] The value of the local variable 'cashierName' isn't used.
These are in the loyalty/debt section and are unrelated to printing.

---

## 8. Printing Flow (after fix)

pos_screen.dart  (checkout button pressed)
  |
  +-- ref.read(cartProvider.notifier).checkout(...)   <- saves sale to DB
  |
  +-- builds List<InvoiceItem> from activeCartSnapshot.items
  |     InvoiceItem(name: ..., qty: ..., unitPrice: ..., lineTotal: ...)
  |
  +-- await printSale(invoiceNumber, items, customerName)
        |  [lib/core/services/receipt_service.dart]
        +-- loads storeName / phone / address / logoBytes from SettingsService
        +-- computes total = items.fold(0.0, (sum, e) => sum + e.lineTotal)
        +-- builds InvoiceData(invoiceNumber, items, storeName, total, ...)
        +-- InvoicePdfBuilderClean().buildInvoice(pdfData, paperSize: thermal80)
        |     [lib/core/utils/invoice_pdf_builder_clean.dart]
        |     renders table rows using item.qty / item.unitPrice / item.lineTotal
        +-- Printing.layoutPdf(onLayout: (format) async => pdfBytes)
