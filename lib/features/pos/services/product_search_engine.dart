// lib/features/pos/services/product_search_engine.dart
//
// Smart in-memory product search engine.
//
// Design goals:
//   • Normalisation is precomputed once at index-build time – NEVER per query.
//   • Incremental search: if the new query extends the previous one, we filter
//     the previous result set instead of scanning all 50k products.
//   • Lightweight index structs – products are referenced by id, not copied.
//   • Levenshtein fuzzy matching with early-exit optimisation.
//   • Extensible: synonyms map + multi-language hooks built in.
//
// Performance target: < 50 ms for 50,000 products.

import 'package:flutter/material.dart';
import '../../products/models/product_model.dart';
import '../models/search_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Arabic normalisation helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Strips Arabic diacritics (tashkeel / harakat) and normalises alef variants.
/// Input → fully lowercase, diacritic-free, alef-normalised string.
String normalizeArabic(String input) {
  // Lower-case first (handles Latin too)
  String s = input.toLowerCase();

  // Remove Arabic diacritics (U+064B – U+065F, U+0670)
  s = s.replaceAll(
    RegExp(r'[\u064B-\u065F\u0670]'),
    '',
  );

  // Normalise alef variants → bare alef (ا)
  s = s.replaceAll(RegExp(r'[أإآٱ]'), 'ا');

  // Normalise teh marbuta → ha (optional – helps with some Arabic plurals)
  s = s.replaceAll('ة', 'ه');

  // Normalise waw with hamza
  s = s.replaceAll('ؤ', 'و');

  // Normalise ya with hamza
  s = s.replaceAll('ئ', 'ي');

  return s;
}

// ─────────────────────────────────────────────────────────────────────────────
// Levenshtein distance (optimised with two-row DP)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the Levenshtein edit distance between [a] and [b].
/// Uses two-row rolling DP → O(min(|a|,|b|)) space.
/// Returns early if the minimum possible distance already exceeds [maxDistance].
int _levenshtein(String a, String b, {int maxDistance = 3}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Keep the shorter string in `b` to minimise memory
  if (a.length < b.length) {
    final tmp = a;
    a = b;
    b = tmp;
  }

  final bLen = b.length;
  final aLen = a.length;

  // If length difference alone exceeds threshold – bail early
  if (aLen - bLen > maxDistance) return aLen - bLen;

  List<int> prev = List<int>.generate(bLen + 1, (i) => i);
  List<int> curr = List<int>.filled(bLen + 1, 0);

  for (int i = 1; i <= aLen; i++) {
    curr[0] = i;
    int rowMin = i;

    for (int j = 1; j <= bLen; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1,      // deletion
        curr[j - 1] + 1,  // insertion
        prev[j - 1] + cost, // substitution
      ].reduce((a, b) => a < b ? a : b);

      if (curr[j] < rowMin) rowMin = curr[j];
    }

    // Early exit if best possible distance in this row exceeds threshold
    if (rowMin > maxDistance) return rowMin;

    // Swap rows
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[bLen];
}

// ─────────────────────────────────────────────────────────────────────────────
// Pre-built index entry (lightweight – stores ints/strings, no product copy)
// ─────────────────────────────────────────────────────────────────────────────

class _IndexEntry {
  final int productId;          // key into the products map
  final String normName;        // precomputed: normalizeArabic(product.name)
  final String normBarcode;     // precomputed: barcode.toLowerCase()
  final String normCategory;    // precomputed: normalizeArabic(categoryName ?? '')

  const _IndexEntry({
    required this.productId,
    required this.normName,
    required this.normBarcode,
    required this.normCategory,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Text highlighting helper
// ─────────────────────────────────────────────────────────────────────────────

const TextStyle _normalStyle = TextStyle(
  color: Colors.white,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);

const TextStyle _highlightStyle = TextStyle(
  color: Color(0xFFFFA726), // AppColors.accentLight
  fontSize: 14,
  fontWeight: FontWeight.w700,
);

/// Splits [text] into highlighted [TextSpan]s based on where [query] appears.
/// [normText] is the pre-normalised version of [text] for position detection.
List<TextSpan> _buildHighlightSpans(String text, String normText, String normQuery) {
  if (normQuery.isEmpty) {
    return [TextSpan(text: text, style: _normalStyle)];
  }

  final idx = normText.indexOf(normQuery);
  if (idx == -1) {
    // Fuzzy match – highlight the closest portions we can find by word
    return [TextSpan(text: text, style: _normalStyle)];
  }

  final spans = <TextSpan>[];
  if (idx > 0) {
    spans.add(TextSpan(text: text.substring(0, idx), style: _normalStyle));
  }
  final end = (idx + normQuery.length).clamp(0, text.length);
  spans.add(TextSpan(text: text.substring(idx, end), style: _highlightStyle));
  if (end < text.length) {
    spans.add(TextSpan(text: text.substring(end), style: _normalStyle));
  }
  return spans;
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductSearchEngine
// ─────────────────────────────────────────────────────────────────────────────

class ProductSearchEngine {
  // ── Index ─────────────────────────────────────────────────────────────────

  /// Flat list of index entries – built once, rebuilt when cache refreshes.
  List<_IndexEntry> _index = [];

  /// Pointer to the authoritative product map (passed in from PosProductsState).
  Map<int, ProductModel> _productsMap = {};

  // ── Synonyms (extensible hook) ────────────────────────────────────────────

  /// Map from a normalised synonym → list of normalised expansions.
  /// e.g. {'كولا': ['كوكا كولا', 'pepsi']}
  Map<String, List<String>> synonyms = {};

  // ── Incremental search cache ───────────────────────────────────────────────

  /// The query used in the last search call.
  String _lastQuery = '';

  /// The index entries that survived the last search (reused for incremental).
  List<_IndexEntry> _lastCandidates = [];

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Rebuilds the search index from [productsMap].
  /// MUST be called whenever the in-memory cache changes.
  /// All normalisation is done here – NOT in [search].
  void buildIndex(Map<int, ProductModel> productsMap) {
    _productsMap = productsMap;

    final entries = <_IndexEntry>[];
    for (final p in productsMap.values) {
      if (p.id == null) continue;
      entries.add(_IndexEntry(
        productId: p.id!,
        normName: normalizeArabic(p.name),
        normBarcode: p.barcode.toLowerCase(),
        normCategory: normalizeArabic(p.categoryName ?? ''),
      ));
    }
    _index = entries;

    // Invalidate incremental cache
    _lastQuery = '';
    _lastCandidates = [];
  }

  /// Registers or updates the synonyms map.
  /// Keys and values should already be normalised.
  void setSynonyms(Map<String, List<String>> synonymMap) {
    synonyms = synonymMap;
  }

  /// Searches the index for [rawQuery] and returns up to [maxResults] results
  /// sorted by [SearchRank].
  ///
  /// Incremental optimisation:
  ///   If [rawQuery] is an extension of [_lastQuery], we only scan
  ///   [_lastCandidates] instead of the full [_index].
  List<SearchResult> search(String rawQuery, {int maxResults = 20}) {
    final normQuery = normalizeArabic(rawQuery.trim());

    if (normQuery.isEmpty) {
      _lastQuery = '';
      _lastCandidates = [];
      return [];
    }

    // ── Synonym expansion ─────────────────────────────────────────────────
    final expandedQueries = _expandSynonyms(normQuery);

    // ── Incremental candidate selection ──────────────────────────────────
    final List<_IndexEntry> candidates;
    if (_lastQuery.isNotEmpty && normQuery.startsWith(_lastQuery) && _lastCandidates.isNotEmpty) {
      // The query grew – previous candidates are a safe superset
      candidates = _lastCandidates;
    } else {
      candidates = _index;
    }

    // ── Fuzzy threshold: allow 1 typo for queries ≥ 4 chars, 2 for ≥ 6 ──
    final int fuzzyMax = normQuery.length >= 6 ? 2 : (normQuery.length >= 4 ? 1 : 0);

    // ── Score every candidate ─────────────────────────────────────────────
    final scored = <({_IndexEntry entry, SearchRank rank, String field})>[];

    for (final entry in candidates) {
      SearchRank? rank;
      String field = 'name';

      // We test all expanded queries and take the best rank
      for (final q in expandedQueries) {
        SearchRank? r;
        String f = 'name';

        // 1. Exact barcode
        if (entry.normBarcode == q) {
          r = SearchRank.exactBarcode;
          f = 'barcode';
        }
        // 2. Exact name
        else if (entry.normName == q) {
          r = SearchRank.exactName;
        }
        // 3. Starts-with (name, barcode, category)
        else if (entry.normName.startsWith(q) ||
            entry.normBarcode.startsWith(q) ||
            entry.normCategory.startsWith(q)) {
          r = SearchRank.startsWith;
          if (entry.normBarcode.startsWith(q)) {
            f = 'barcode';
          } else if (entry.normCategory.startsWith(q)) {
            f = 'category';
          }
        }
        // 4. Contains (name, barcode, category)
        else if (entry.normName.contains(q) ||
            entry.normBarcode.contains(q) ||
            entry.normCategory.contains(q)) {
          r = SearchRank.contains;
          if (entry.normBarcode.contains(q)) {
            f = 'barcode';
          } else if (entry.normCategory.contains(q)) {
            f = 'category';
          }
        }
        // 5. Fuzzy (only on name tokens, skip if threshold = 0)
        else if (fuzzyMax > 0) {
          if (_fuzzyMatches(entry.normName, q, fuzzyMax)) {
            r = SearchRank.fuzzy;
          } else if (_fuzzyMatches(entry.normCategory, q, fuzzyMax)) {
            r = SearchRank.fuzzy;
            f = 'category';
          }
        }

        // Take the best rank across expanded queries
        if (r != null && (rank == null || r.index < rank.index)) {
          rank = r;
          field = f;
        }
      }

      if (rank != null) {
        scored.add((entry: entry, rank: rank, field: field));
      }
    }

    // ── Sort by rank ──────────────────────────────────────────────────────
    scored.sort((a, b) => a.rank.index.compareTo(b.rank.index));

    // ── Build SearchResult objects (top N only) ───────────────────────────
    final results = <SearchResult>[];
    final limit = scored.length < maxResults ? scored.length : maxResults;

    for (int i = 0; i < limit; i++) {
      final s = scored[i];
      final product = _productsMap[s.entry.productId];
      if (product == null) continue;

      results.add(SearchResult(
        product: product,
        rank: s.rank,
        nameSpans: _buildHighlightSpans(product.name, s.entry.normName, normQuery),
        matchedField: s.field,
      ));
    }

    // ── Update incremental cache ──────────────────────────────────────────
    _lastQuery = normQuery;
    // Store only surviving entries for next incremental pass
    _lastCandidates = scored.map((s) => s.entry).toList();

    return results;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Expands [normQuery] with any registered synonyms, returning a set of
  /// normalised query strings to test.
  List<String> _expandSynonyms(String normQuery) {
    final result = <String>{normQuery};
    for (final entry in synonyms.entries) {
      if (normQuery.contains(entry.key)) {
        for (final expansion in entry.value) {
          result.add(normQuery.replaceAll(entry.key, expansion));
        }
      }
    }
    return result.toList();
  }

  /// Returns true if [query] fuzzy-matches any word-token in [normText]
  /// within [maxDist] edits, OR if the whole [normText] is within maxDist.
  bool _fuzzyMatches(String normText, String query, int maxDist) {
    if (normText.isEmpty) return false;

    // Check full string first
    if (_levenshtein(normText, query, maxDistance: maxDist) <= maxDist) return true;

    // Check individual space-separated tokens
    for (final token in normText.split(' ')) {
      if (token.isEmpty) continue;
      if (_levenshtein(token, query, maxDistance: maxDist) <= maxDist) return true;
    }

    return false;
  }
}
