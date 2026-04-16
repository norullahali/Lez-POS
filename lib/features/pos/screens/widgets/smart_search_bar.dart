// lib/features/pos/screens/widgets/smart_search_bar.dart
//
// Smart Search Bar widget for the POS screen.
//
// Features:
//   • 250 ms debounce while typing, instant on Enter.
//   • Overlay dropdown below the field showing ranked search results.
//   • Highlighted matched text via RichText / TextSpan.
//   • Up/Down arrow key navigation inside the dropdown.
//   • Enter key adds the selected/first result to the cart.
//   • Escape closes the overlay without adding.
//   • Tap outside to dismiss.
//   • "No results found" empty state.
//   • F2 shortcut re-focuses the field.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../products/models/product_model.dart';
import '../../models/search_result.dart';
import '../../providers/pos_products_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Providers for overlay state (kept outside the widget so siblings can read)
// ─────────────────────────────────────────────────────────────────────────────

/// Index of the keyboard-selected row in the search dropdown. -1 = none.
final _searchFocusedIndexProvider = StateProvider<int>((ref) => -1);

// ─────────────────────────────────────────────────────────────────────────────
// SmartSearchBar – public widget consumed by PosScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Drop-in replacement for the old `_SearchPanel`.
///
/// [onProductSelected] is called when the user presses Enter or taps a result.
/// The caller (PosScreen) handles the cart-add logic—keeping this widget pure.
class SmartSearchBar extends ConsumerStatefulWidget {
  final void Function(ProductModel) onProductSelected;
  final void Function(String barcode) onBarcodeSubmit;

  const SmartSearchBar({
    super.key,
    required this.onProductSelected,
    required this.onBarcodeSubmit,
  });

  @override
  ConsumerState<SmartSearchBar> createState() => _SmartSearchBarState();
}

class _SmartSearchBarState extends ConsumerState<SmartSearchBar> {
  final _ctrl = TextEditingController();
  final _fieldFocusNode = FocusNode();
  final _overlayLayerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fieldFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _fieldFocusNode.removeListener(_onFocusChange);
    _fieldFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  // ── Focus handling ─────────────────────────────────────────────────────────

  void _onFocusChange() {
    if (!_fieldFocusNode.hasFocus) {
      // Small delay so tapping a result row registers before overlay disappears
      Future.delayed(const Duration(milliseconds: 150), _removeOverlay);
    } else {
      // Re-show overlay if there are results
      _maybeShowOverlay();
    }
  }

  // ── Text input ────────────────────────────────────────────────────────────

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(posSearchQueryProvider.notifier).state = value;
      ref.read(_searchFocusedIndexProvider.notifier).state = -1;
      _maybeShowOverlay();
    });
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final results = ref.read(smartSearchResultsProvider);

    if (results.isNotEmpty) {
      // If user navigated with arrows, use that; otherwise use first result
      final idx = ref.read(_searchFocusedIndexProvider).clamp(0, results.length - 1);
      widget.onProductSelected(results[idx].product);
      _clearSearch();
    } else {
      // No smart results → fall back to barcode scan path
      widget.onBarcodeSubmit(trimmed);
      _clearSearch();
    }
  }

  // ── Keyboard navigation ───────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final results = ref.read(smartSearchResultsProvider);
    if (results.isEmpty) return KeyEventResult.ignored;

    final currentIdx = ref.read(_searchFocusedIndexProvider);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final next = (currentIdx + 1).clamp(0, results.length - 1);
      ref.read(_searchFocusedIndexProvider.notifier).state = next;
      _refreshOverlay();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final prev = (currentIdx - 1).clamp(0, results.length - 1);
      ref.read(_searchFocusedIndexProvider.notifier).state = prev;
      _refreshOverlay();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearSearch();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Overlay management ────────────────────────────────────────────────────

  void _maybeShowOverlay() {
    final query = ref.read(posSearchQueryProvider);
    if (query.trim().isEmpty) {
      _removeOverlay();
      return;
    }
    if (_overlayEntry == null) {
      _showOverlay();
    } else {
      _refreshOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _SearchOverlay(
      layerLink: _overlayLayerLink,
      onSelect: (product) {
        widget.onProductSelected(product);
        _clearSearch();
      },
    ));
    overlay.insert(_overlayEntry!);
  }

  void _refreshOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  void _clearSearch() {
    _ctrl.clear();
    ref.read(posSearchQueryProvider.notifier).state = '';
    ref.read(_searchFocusedIndexProvider.notifier).state = -1;
    _removeOverlay();
    _fieldFocusNode.requestFocus();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Request focus from outside (F2 shortcut).
  void requestFocus() => _fieldFocusNode.requestFocus();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CompositedTransformTarget(
        link: _overlayLayerLink,
        child: KeyboardListener(
          focusNode: FocusNode(skipTraversal: true),
          onKeyEvent: (e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f2) {
              _fieldFocusNode.requestFocus();
            }
          },
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: TextField(
              controller: _ctrl,
              focusNode: _fieldFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المنتج أو الباركود أو الفئة... (F2)',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                        onPressed: _clearSearch,
                      )
                    : const Icon(Icons.qr_code_scanner_rounded, color: Colors.white38),
                filled: true,
                fillColor: AppColors.posPanelLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent, width: 2),
                ),
              ),
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchOverlay – the floating dropdown beneath the search field
// ─────────────────────────────────────────────────────────────────────────────

class _SearchOverlay extends ConsumerWidget {
  final LayerLink layerLink;
  final void Function(ProductModel) onSelect;

  const _SearchOverlay({required this.layerLink, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(smartSearchResultsProvider);
    final focusedIdx = ref.watch(_searchFocusedIndexProvider);
    final query = ref.watch(posSearchQueryProvider);

    // Dismiss when query cleared
    if (query.trim().isEmpty) return const SizedBox.shrink();

    return Positioned(
      width: 0,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 56), // field height ≈ 56
        child: TapRegion(
          onTapOutside: (_) {
            // Let the focus listener handle it
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 640,
                maxHeight: 420,
              ),
              decoration: BoxDecoration(
                color: AppColors.posPanel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: results.isEmpty
                  ? _buildEmptyState()
                  : _buildResultsList(results, focusedIdx),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: Colors.white24, size: 40),
          SizedBox(height: 10),
          Text(
            'لا توجد نتائج',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'جرب كلمات مختلفة أو تحقق من التهجئة',
            style: TextStyle(color: Colors.white24, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<SearchResult> results, int focusedIdx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(
            children: [
              Text(
                '${results.length} نتيجة',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              const Text(
                '↑↓ تنقل • Enter  للإضافة • Esc للإغلاق',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        // Results
        Flexible(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (ctx, i) => _SearchResultRow(
              result: results[i],
              isSelected: i == focusedIdx,
              onTap: () => onSelect(results[i].product),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchResultRow – a single row in the dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _SearchResultRow extends StatelessWidget {
  final SearchResult result;
  final bool isSelected;
  final VoidCallback onTap;

  const _SearchResultRow({
    required this.result,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = result.product;
    final isLow = p.currentStock <= 0;

    return GestureDetector(
      onTap: isLow ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: isSelected
            ? AppColors.posHighlight
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Rank badge icon
            _RankBadge(rank: result.rank),
            const SizedBox(width: 10),
            // Product name (highlighted) + category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: result.nameSpans),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((p.categoryName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.categoryName!,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Price + stock
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_formatPrice(p.sellPrice)} د.ع',
                  style: const TextStyle(
                    color: AppColors.accentLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                _StockBadge(stock: p.currentStock, isLow: isLow),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    // Simple formatting: integer if whole number, else 2 decimal places
    if (price == price.truncateToDouble()) {
      return price.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
    return price.toStringAsFixed(2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final SearchRank rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (rank) {
      SearchRank.exactBarcode => (Icons.qr_code_rounded, const Color(0xFF4CAF50)),
      SearchRank.exactName => (Icons.check_circle_rounded, AppColors.accent),
      SearchRank.startsWith => (Icons.skip_next_rounded, const Color(0xFF42A5F5)),
      SearchRank.contains => (Icons.search_rounded, Colors.white38),
      SearchRank.fuzzy => (Icons.auto_fix_high_rounded, Colors.white24),
    };

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final double stock;
  final bool isLow;
  const _StockBadge({required this.stock, required this.isLow});

  @override
  Widget build(BuildContext context) {
    if (isLow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('نفد المخزون', style: TextStyle(color: Colors.red, fontSize: 10)),
      );
    }
    return Text(
      'المخزون: ${stock.toInt()}',
      style: const TextStyle(color: Colors.white38, fontSize: 11),
    );
  }
}
