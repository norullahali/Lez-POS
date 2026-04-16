// lib/features/pos/providers/pos_products_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../products/models/product_model.dart';
import '../../products/providers/products_provider.dart';
import '../models/search_result.dart';
import '../services/product_search_engine.dart';

/// Holds the in-memory state of POS products.
class PosProductsState {
  final Map<int, ProductModel> productsMap;
  final Map<String, int> barcodeIndex;
  final bool isFullyLoaded;

  PosProductsState({
    required this.productsMap,
    required this.barcodeIndex,
    this.isFullyLoaded = false,
  });

  PosProductsState copyWith({
    Map<int, ProductModel>? productsMap,
    Map<String, int>? barcodeIndex,
    bool? isFullyLoaded,
  }) {
    return PosProductsState(
      productsMap: productsMap ?? this.productsMap,
      barcodeIndex: barcodeIndex ?? this.barcodeIndex,
      isFullyLoaded: isFullyLoaded ?? this.isFullyLoaded,
    );
  }
}

/// A dedicated cache for the POS to hold 50,000+ products in memory.
class PosProductsNotifier extends AsyncNotifier<PosProductsState> {
  // We keep mutable maps internally for fast insertions without triggering massive deep copies
  final Map<int, ProductModel> _internalMap = {};
  final Map<String, int> _internalBarcodeIndex = {};
  bool _isBackgroundLoading = false;

  /// Single engine instance, owned by this notifier.
  final ProductSearchEngine _searchEngine = ProductSearchEngine();

  @override
  Future<PosProductsState> build() async {
    final repo = ref.watch(productsRepositoryProvider);

    // Step 1: Fast initial load (First 100 products)
    final initialBatch = await repo.getLimit(100);
    _integrateBatch(initialBatch);

    // Step 2: Spawn background load for the rest
    _startBackgroundLoad();

    return PosProductsState(
      productsMap: Map.of(_internalMap),
      barcodeIndex: Map.of(_internalBarcodeIndex),
      isFullyLoaded: false,
    );
  }

  void _integrateBatch(List<ProductModel> batch) {
    for (final p in batch) {
      if (p.id != null) {
        _internalMap[p.id!] = p;
        if (p.barcode.isNotEmpty) {
          _internalBarcodeIndex[p.barcode] = p.id!;
        }
      }
    }
  }

  Future<void> _startBackgroundLoad() async {
    if (_isBackgroundLoading) return;
    _isBackgroundLoading = true;

    try {
      final repo = ref.read(productsRepositoryProvider);
      int offset = 100; // We already loaded 100
      const batchSize = 1000;

      while (true) {
        // Yield to event loop to avoid freezing UI
        await Future.delayed(const Duration(milliseconds: 10));

        final batch = await repo.getLimit(batchSize, offset: offset);
        if (batch.isEmpty) break;

        _integrateBatch(batch);
        offset += batchSize;

        // Update state every 5000 items to keep UI reference fresh
        if (offset % 5000 == 0) {
          state = AsyncValue.data(PosProductsState(
            productsMap: Map.of(_internalMap),
            barcodeIndex: Map.of(_internalBarcodeIndex),
            isFullyLoaded: false,
          ));
        }
      }

      // Final update – rebuild search index with complete dataset
      _searchEngine.buildIndex(_internalMap);

      state = AsyncValue.data(PosProductsState(
        productsMap: Map.of(_internalMap),
        barcodeIndex: Map.of(_internalBarcodeIndex),
        isFullyLoaded: true,
      ));

      debugPrint('[PosProducts] Fully loaded ${_internalMap.length} products. Search index built.');
    } catch (e, st) {
      debugPrint('[PosProducts] Background load error: $e\n$st');
    } finally {
      _isBackgroundLoading = false;
    }
  }

  /// O(1) Barcode lookup from memory
  Future<ProductModel?> findByBarcode(String barcode) async {
    final st = state.valueOrNull;
    if (st == null) return null;

    final id = st.barcodeIndex[barcode];
    if (id != null) {
      return st.productsMap[id];
    }

    // Fallback to DB if not found (in case it was just added but not synced yet)
    final repo = ref.read(productsRepositoryProvider);
    final product = await repo.findByBarcode(barcode);
    if (product != null && product.id != null) {
      _internalMap[product.id!] = product;
      if (product.barcode.isNotEmpty) _internalBarcodeIndex[product.barcode] = product.id!;
      _rebuildIndex();
      state = AsyncValue.data(PosProductsState(
        productsMap: Map.of(_internalMap),
        barcodeIndex: Map.of(_internalBarcodeIndex),
        isFullyLoaded: st.isFullyLoaded,
      ));
    }
    return product;
  }

  /// Syncs an individual product to cache (called when saving/updating a product globally)
  void syncProduct(ProductModel product) {
    if (product.id == null) return;

    _internalMap[product.id!] = product;
    if (product.barcode.isNotEmpty) {
      _internalBarcodeIndex[product.barcode] = product.id!;
    }

    _rebuildIndex();

    final st = state.valueOrNull;
    if (st != null) {
      state = AsyncValue.data(PosProductsState(
        productsMap: Map.of(_internalMap),
        barcodeIndex: Map.of(_internalBarcodeIndex),
        isFullyLoaded: st.isFullyLoaded,
      ));
    }
  }

  void removeProduct(int id) {
    final p = _internalMap.remove(id);
    if (p != null && p.barcode.isNotEmpty) {
      _internalBarcodeIndex.remove(p.barcode);
    }

    _rebuildIndex();

    final st = state.valueOrNull;
    if (st != null) {
      state = AsyncValue.data(PosProductsState(
        productsMap: Map.of(_internalMap),
        barcodeIndex: Map.of(_internalBarcodeIndex),
        isFullyLoaded: st.isFullyLoaded,
      ));
    }
  }

  /// Whether the search engine has had its index built at least once.
  bool _indexBuilt = false;

  /// Performs an in-memory smart search using [ProductSearchEngine].
  /// Returns up to [maxResults] ranked [SearchResult]s.
  /// Safe to call from any provider – never touches the database.
  List<SearchResult> searchProducts(String query, {int maxResults = 20}) {
    // Build initial index on first search call if not yet done
    if (!_indexBuilt && _internalMap.isNotEmpty) {
      _searchEngine.buildIndex(_internalMap);
      _indexBuilt = true;
    }
    return _searchEngine.search(query, maxResults: maxResults);
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  void _rebuildIndex() {
    _searchEngine.buildIndex(_internalMap);
  }
}

final posProductsProvider =
    AsyncNotifierProvider<PosProductsNotifier, PosProductsState>(PosProductsNotifier.new);

// ── Search Query State ─────────────────────────────────────────────────────

/// Raw user-typed query string (debounced by the UI layer).
final posSearchQueryProvider = StateProvider<String>((ref) => '');

// ── Category Filter State ──────────────────────────────────────────────────

final posCategoryFilterProvider = StateProvider<int?>((ref) => null);

// ── Smart Search Results Provider ─────────────────────────────────────────

/// Returns a ranked [List<SearchResult>] from the in-memory engine.
/// Watches [posSearchQueryProvider] and recomputes only when the query changes.
/// Returns empty list when query is empty (grid takes over display).
final smartSearchResultsProvider = Provider<List<SearchResult>>((ref) {
  final query = ref.watch(posSearchQueryProvider);
  if (query.trim().isEmpty) return [];

  final notifier = ref.read(posProductsProvider.notifier);
  return notifier.searchProducts(query);
});

// ── Filtered Products Provider (unchanged – used for grid / category mode) ─

/// Returns all products matching the active category filter (no query search).
/// Used by the grid when the search overlay is NOT active.
final filteredPosProductsProvider = Provider<List<ProductModel>>((ref) {
  final posStateAsync = ref.watch(posProductsProvider);
  final posState = posStateAsync.valueOrNull;

  if (posState == null) return [];

  final query = ref.watch(posSearchQueryProvider).toLowerCase();
  final categoryId = ref.watch(posCategoryFilterProvider);

  final allProducts = posState.productsMap.values;

  return allProducts.where((p) {
    final matchCategory = categoryId == null || p.categoryId == categoryId;
    if (!matchCategory) return false;

    if (query.isEmpty) return true;
    return p.name.toLowerCase().contains(query) || p.barcode.contains(query);
  }).toList();
});
