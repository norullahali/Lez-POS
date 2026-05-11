# Review: Inventory Read Fix

**Date:** 2026-05-11
**Scope:** Inventory module only
**Files modified:** 3
**No UI files were modified.**

---

## Root Cause — Why the Inventory Showed Stale Stock Values

Two separate problems were stacked.

### Problem 1 — Wrong data source (fixed in Phase 2)
All inventory queries were deriving stock from SUM(stock_ledger.quantity_change) via GROUP BY aggregations and LEFT JOINs. After Phase 2 those queries were rewritten to read products.current_stock directly.

### Problem 2 — No reactivity (fixed here)
Even after Problem 1 was fixed, the inventory screen still showed old values after a sale or purchase because:

- InventoryNotifier was an AsyncNotifier — it fires a single Future when the provider is first built, then stores the result. It never watches the database for changes. When products.current_stock is decremented by a sale, the notifier keeps its frozen snapshot.
- lowStockProvider was a FutureProvider with the same one-shot behavior.

Neither provider was invalidated when sales/purchases wrote to products.current_stock, so both displayed data from the last time they were manually loaded.

The fix converts both to streaming providers that subscribe directly to the products table via Drift reactive query system. Drift automatically re-emits the query result every time the table is written to so any sale, purchase, return, adjustment, or opening-stock write now updates the inventory screen in real time.

---

## Modified Files

---

### 1. lib/core/database/daos/stock_dao.dart

**Change:** Added watchLowStockProducts() — the streaming counterpart of the existing getLowStockProducts().

Old (one-shot Future only, no stream):

    Future<List<Map<String, dynamic>>> getLowStockProducts() async { ... }

New (reactive stream added alongside):

    Stream<List<Map<String, dynamic>>> watchLowStockProducts() {
      return customSelect('''
        SELECT id, name, barcode, min_stock, unit, category_id, current_stock
        FROM products
        WHERE is_active = 1 AND current_stock < min_stock
        ORDER BY current_stock ASC
      ''', readsFrom: {products}).watch().map(
            (rows) => rows.map((r) => r.data).toList(),
          );
    }

Reads from: {products} (no ledger join)
Why: Drift .watch() subscribes to the products table. Every write to products.current_stock triggers a new emission. The low-stock list self-updates without any manual invalidation.

---

### 2. lib/features/inventory/repositories/inventory_repository.dart

Changes:
1. Extracted _toOverviewItem(Product p) helper to remove duplication.
2. Added watchStockOverview() — reactive stream version of getStockOverview().
3. Added watchLowStockProducts() — delegates to stockDao.watchLowStockProducts().

Old getStockOverview() (inline mapping, no stream):

    Future<List<StockOverviewItem>> getStockOverview() async {
      final products = await _db.productsDao.getAllProducts();
      return products.map((p) {
        return StockOverviewItem(
          productId: p.id, name: p.name, ...currentStock: p.currentStock,
          stockValue: p.currentStock * p.costPrice,
        );
      }).toList();
    }

New — shared helper and stream methods added:

    Future<List<StockOverviewItem>> getStockOverview() async {
      final products = await _db.productsDao.getAllProducts();
      return products.map(_toOverviewItem).toList();
    }

    Stream<List<StockOverviewItem>> watchStockOverview() {
      return _db.productsDao.watchAllProducts().map(
        (rows) => rows.map(_toOverviewItem).toList(),
      );
    }

    Stream<List<Map<String, dynamic>>> watchLowStockProducts() {
      return _db.stockDao.watchLowStockProducts();
    }

    StockOverviewItem _toOverviewItem(Product p) => StockOverviewItem(
      productId: p.id, name: p.name, barcode: p.barcode,
      currentStock: p.currentStock, minStock: p.minStock,
      unit: p.unit, costPrice: p.costPrice, sellPrice: p.sellPrice,
      stockValue: p.currentStock * p.costPrice,
    );

Why: watchAllProducts() is a Drift-generated stream that watches the products table. Any write to products.current_stock (from purchases, sales, adjustments) causes it to emit a fresh list.

---

### 3. lib/features/inventory/providers/inventory_provider.dart

#### InventoryNotifier — AsyncNotifier converted to StreamNotifier

Before (one-shot, frozen after first load):

    class InventoryNotifier extends AsyncNotifier<List<StockOverviewItem>> {
      @override
      Future<List<StockOverviewItem>> build() async {
        // Called ONCE — frozen until explicit invalidateSelf()
        return await ref.watch(inventoryRepositoryProvider).getStockOverview();
      }

      Future<void> adjust({...}) async {
        await ref.read(inventoryRepositoryProvider).createAdjustment(...);
        ref.invalidateSelf(); // manual trigger required after every write
      }
    }

    final inventoryNotifierProvider =
        AsyncNotifierProvider<InventoryNotifier, List<StockOverviewItem>>(InventoryNotifier.new);

After (reactive, auto-updates on every current_stock change):

    class InventoryNotifier extends StreamNotifier<List<StockOverviewItem>> {
      @override
      Stream<List<StockOverviewItem>> build() {
        return ref.watch(inventoryRepositoryProvider).watchStockOverview();
      }

      Future<void> adjust({...}) async {
        await ref.read(inventoryRepositoryProvider).createAdjustment(...);
        // No invalidateSelf() — stream auto-updates when current_stock is written
      }
    }

    final inventoryNotifierProvider =
        StreamNotifierProvider<InventoryNotifier, List<StockOverviewItem>>(InventoryNotifier.new);

Why: StreamNotifier.build() returns a Stream. Riverpod keeps the subscription alive and converts each emission into AsyncValue.data(...). The screen inventoryAsync.when(loading, error, data) works identically — no UI change needed.

#### lowStockProvider — FutureProvider converted to StreamProvider

Before (one-shot):

    final lowStockProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return await ref.watch(inventoryRepositoryProvider).getLowStockProducts();
    });

After (reactive):

    final lowStockProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
      return ref.watch(inventoryRepositoryProvider).watchLowStockProducts();
    });

Why: StreamProvider keeps the subscription active. When a sale decrements current_stock below min_stock, Drift re-evaluates WHERE current_stock < min_stock and emits the updated list. The low-stock tab uses lowStockAsync.when(...) which works identically for both FutureProvider and StreamProvider.

---

## Files NOT Modified

| File | Reason |
|------|--------|
| inventory_screen.dart | Uses .when(loading, error, data) on AsyncValue. Both StreamNotifierProvider and StreamProvider return AsyncValue. No changes needed. |
| inventory_provider.dart — expiringProductsProvider | Expiry data (product_batches) is not written by any stock operation; one-shot load is appropriate. |
| stock_dao.dart — getLowStockProducts() | Kept for backward compatibility. watchLowStockProducts() added alongside. |
| All products, purchases, POS, printing files | Out of scope per task rules. |

---

## Reactivity Chain After the Fix

    Sale / Purchase / Adjustment / Opening Stock
            |
            v
    UPDATE products SET current_stock = ...  (inside DB transaction)
            |
            v  Drift detects write to products table
            |
            +---> watchAllProducts() ---> watchStockOverview() ---> InventoryNotifier ---> _StockOverviewTab re-renders
            |
            +---> watchLowStockProducts() ---> lowStockProvider ---> _LowStockTab re-renders

No manual refresh() call is required from anywhere in the app.

---

## Confirmation — Inventory Now Uses current_stock Only

| Inventory Component | Data source |
|--------------------|-------------|
| Overview table (_StockOverviewTab) | products.current_stock via watchAllProducts() stream |
| Low-stock list (_LowStockTab) | products.current_stock via WHERE current_stock < min_stock stream |
| Summary cards (total items, total value, low-stock count) | Computed from StockOverviewItem.currentStock — same stream |
| Adjustments product list (_AdjustmentsTab) | products.current_stock via productsNotifierProvider |
| stock_ledger reads remaining in inventory module | NONE — ledger is no longer queried for any live stock display |
