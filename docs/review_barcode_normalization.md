# Review: Barcode Normalization

**Date:** 2026-05-11
**Problem:** Products saved with Arabic/Persian digits in the barcode field
(e.g. 456457 stored as 456457 in Arabic) could not be found by scanners
that emit English digits, and vice versa.

---

## Normalization Method

Utility: lib/core/utils/number_parser.dart
Extension method: String.normalizeBarcode()

Converts Eastern Arabic digits (U+0660-U+0669) and Persian digits
(U+06F0-U+06F9) to ASCII digits (0-9). All other characters pass through
unchanged.

Examples:
  Input              Output
  456457 (Arabic)  456457
  123 (Persian)      123
  ABC-789 (Arabic) ABC-789
  mixed-456          mixed-456  (ASCII already, no change)

Implementation:
  String normalizeBarcode() {
    const english = ['0','1','2','3','4','5','6','7','8','9'];
    const arabic  = ['0','1','2','3','4','5','6','7','8','9'];  // Eastern Arabic
    const persian = ['0','1','2','3','4','5','6','7','8','9'];  // Persian
    String result = this;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(arabic[i], english[i]);
      result = result.replaceAll(persian[i], english[i]);
    }
    return result;
  }

---

## Database Migration (v17 -> v18)

File: lib/core/database/app_database.dart
Schema version bumped: 17 -> 18

Migration SQL (applied once on upgrade):
  UPDATE products SET barcode =
    REPLACE(REPLACE(...20x REPLACE for each Arabic/Persian digit...))
  WHERE barcode IS NOT NULL AND barcode != ''

This normalizes all EXISTING barcodes in the products table to ASCII digits.
SQLite REPLACE() is idempotent: rows already using English digits are unchanged.

---

## Where Normalization Is Applied

### WRITE path (normalize before storing)

File: lib/features/products/repositories/products_repository.dart
  add()    -- barcode: Value(model.barcode.normalizeBarcode())
  update() -- barcode: Value(model.barcode.normalizeBarcode())
  Note: All DB inserts/updates flow through this repository.

File: lib/features/products/screens/widgets/product_form_dialog.dart
  _submit() -- barcode: _barcodeCtrl.text.trim().normalizeBarcode()
  Note: User-facing form where products are created/edited.

### READ path (normalize before lookup/comparison)

File: lib/features/products/repositories/products_repository.dart
  findByBarcode(barcode) -- normalizes input: barcode.trim().normalizeBarcode()
  search(query)          -- normalizes query:  query.normalizeBarcode()

File: lib/features/pos/providers/pos_products_provider.dart
  _integrateBatch()
    Index key: p.barcode.normalizeBarcode() stored as the map key.
    All Arabic-digit barcodes are stored in the in-memory index as English.
  findByBarcode(barcode)
    Lookup key: barcode.trim().normalizeBarcode() before index lookup.
    DB fallback also passes normalized form to repo.findByBarcode().
  syncProduct(product)
    Index key: product.barcode.normalizeBarcode()
  removeProduct(id)
    Index key: p.barcode.normalizeBarcode() for correct key removal.
  filteredPosProductsProvider
    query = posSearchQueryProvider.normalizeBarcode().toLowerCase()
    Ensures the grid filter also handles Arabic-digit queries.

File: lib/features/pos/services/product_search_engine.dart
  buildIndex()
    normBarcode: p.barcode.normalizeBarcode().toLowerCase()
    Normalizes barcodes when building the pre-computed search index.
  search(rawQuery)
    normQuery = normalizeArabic(rawQuery.trim().normalizeBarcode())
    Digits normalized BEFORE passing to the Arabic text normalizer.

File: lib/features/purchases/screens/purchase_form_screen.dart
  _addByBarcode(barcode)
    barcode = barcode.normalizeBarcode() applied immediately after trim.
    (Also includes stability fixes: await dialog, re-entrancy guard,
     ValueListenableBuilder for reactive dropdown.)
  Dropdown filter (ValueListenableBuilder builder)
    query = textValue.text.normalizeBarcode()
    p.barcode.normalizeBarcode().contains(query)
    Both sides normalized for comparison.

---

## Before / After Examples

Scenario 1: Product saved with Arabic barcode, scanned with English digits
  Stored barcode:  456457
  Scanner input:   456457
  Before fix:      No match (exact SQL comparison fails)
  After fix:       Match (migration converts stored to 456457;
                   lookup normalizes input to 456457)

Scenario 2: Product saved with English barcode, user types Arabic digits
  Stored barcode:  456457
  User types:      456457
  Before fix:      No match
  After fix:       Match (query normalized to 456457 before lookup)

Scenario 3: New product saved via form with Arabic digits in barcode field
  User types:      456457
  Before fix:      Stored as 456457
  After fix:       Stored as 456457 (normalized on submit)

Scenario 4: POS in-memory search with Arabic digits
  Query:           456
  Index normBarcode: 456 (was 456)
  Before fix:      normBarcode (456) != normQuery (456) -> no match
  After fix:       Both 456 -> exact barcode match -> SearchRank.exactBarcode

---

## Files NOT Modified

  lib/core/database/daos/products_dao.dart
    The DAO executes SQL exactly as given. Normalization happens above it in
    the repository layer, keeping the DAO simple and single-purpose.

  lib/features/pos/screens/pos_screen.dart
    onBarcodeSubmit is a no-op stub. The SmartSearchBar handles barcodes
    through its own onSubmitted -> onBarcodeSubmit path which feeds into
    the already-normalized search engine.

  lib/features/pos/screens/widgets/smart_search_bar.dart
    The bar passes rawQuery to posSearchQueryProvider. Normalization happens
    inside product_search_engine.dart and pos_products_provider.dart.

  All stock, sales, returns, customers, reports, settings files
    Out of scope.

---

## Layers of Defense (defense in depth)

  Layer 1 (DB migration):   One-time fix of all existing Arabic barcodes.
  Layer 2 (write normalize): All future saves store English-digit barcodes.
  Layer 3 (read normalize):  All lookups normalize input, so even if a
                             barcode somehow reaches the DB un-normalized,
                             searches will still try the normalized form.
