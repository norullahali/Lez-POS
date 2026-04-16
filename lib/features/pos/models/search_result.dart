// lib/features/pos/models/search_result.dart
import 'package:flutter/material.dart';
import '../../products/models/product_model.dart';

/// Priority ranking for search results – lower index = higher priority.
enum SearchRank {
  exactBarcode,  // 0 – highest priority
  exactName,     // 1
  startsWith,    // 2
  contains,      // 3
  fuzzy,         // 4 – lowest priority
}

/// A single search hit returned by [ProductSearchEngine].
class SearchResult {
  /// The matched product (a lightweight reference, NOT a copy of all 50 k products).
  final ProductModel product;

  /// Relevance rank used for sorting.
  final SearchRank rank;

  /// Pre-built inline spans for the product name with match highlighted.
  /// Rendered by [RichText] / [Text.rich].
  final List<TextSpan> nameSpans;

  /// Which field produced the best match: 'name' | 'barcode' | 'category'.
  final String matchedField;

  const SearchResult({
    required this.product,
    required this.rank,
    required this.nameSpans,
    required this.matchedField,
  });
}
