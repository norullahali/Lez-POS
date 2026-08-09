// lib/features/returns/providers/supplier_return_draft_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../models/supplier_return_draft_models.dart';
import '../repositories/supplier_return_read_repository.dart';

final supplierReturnReadRepositoryProvider =
    Provider<SupplierReturnReadRepository>((ref) {
  return SupplierReturnReadRepository(AppDatabase.instance);
});

enum SupplierReturnDraftStep { selectPurchase, editLines }

class SupplierReturnDraftState {
  final SupplierReturnDraftStep step;
  final List<SupplierReturnPurchaseOption> purchases;
  final String searchQuery;
  final SupplierReturnPurchaseOption? selectedPurchase;
  final List<SupplierReturnDraftLine> lines;
  final String reason;
  final String notes;
  final bool loadingPurchases;
  final bool loadingLines;
  final String? errorMessage;
  final Map<int, String?> lineErrors;

  const SupplierReturnDraftState({
    this.step = SupplierReturnDraftStep.selectPurchase,
    this.purchases = const [],
    this.searchQuery = '',
    this.selectedPurchase,
    this.lines = const [],
    this.reason = '',
    this.notes = '',
    this.loadingPurchases = false,
    this.loadingLines = false,
    this.errorMessage,
    this.lineErrors = const {},
  });

  List<SupplierReturnPurchaseOption> get filteredPurchases {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return purchases;
    return purchases.where((p) {
      return p.displayInvoiceNumber.toLowerCase().contains(q) ||
          p.supplierName.toLowerCase().contains(q);
    }).toList();
  }

  bool get hasReturnableLines => lines.any((l) => l.returnableQty > 0.0001);

  bool get hasSelectedQty => lines.any((l) => l.selectedReturnQty > 0.0001);

  double get draftTotal => lines.fold(0.0, (sum, l) => sum + l.lineDraftTotal);

  bool get hasLineErrors =>
      lineErrors.values.any((e) => e != null && e.isNotEmpty);

  bool get canProceed => hasReturnableLines && hasSelectedQty && !hasLineErrors;

  SupplierReturnDraftState copyWith({
    SupplierReturnDraftStep? step,
    List<SupplierReturnPurchaseOption>? purchases,
    String? searchQuery,
    SupplierReturnPurchaseOption? selectedPurchase,
    bool clearSelectedPurchase = false,
    List<SupplierReturnDraftLine>? lines,
    String? reason,
    String? notes,
    bool? loadingPurchases,
    bool? loadingLines,
    String? errorMessage,
    bool clearError = false,
    Map<int, String?>? lineErrors,
  }) {
    return SupplierReturnDraftState(
      step: step ?? this.step,
      purchases: purchases ?? this.purchases,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedPurchase: clearSelectedPurchase
          ? null
          : (selectedPurchase ?? this.selectedPurchase),
      lines: lines ?? this.lines,
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
      loadingPurchases: loadingPurchases ?? this.loadingPurchases,
      loadingLines: loadingLines ?? this.loadingLines,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lineErrors: lineErrors ?? this.lineErrors,
    );
  }
}

class SupplierReturnDraftNotifier extends Notifier<SupplierReturnDraftState> {
  int _loadPurchasesGeneration = 0;
  int _loadLinesGeneration = 0;

  @override
  SupplierReturnDraftState build() => const SupplierReturnDraftState();

  SupplierReturnReadRepository get _repo =>
      ref.read(supplierReturnReadRepositoryProvider);

  void _invalidateLineLoads() => _loadLinesGeneration++;

  void _invalidatePurchaseLoads() => _loadPurchasesGeneration++;

  Future<void> loadPurchases() async {
    final generation = ++_loadPurchasesGeneration;
    state = state.copyWith(loadingPurchases: true, clearError: true);
    try {
      final purchases = await _repo.getEligiblePurchases();
      if (!_isCurrentPurchaseLoad(generation)) return;
      state = state.copyWith(
        purchases: purchases,
        loadingPurchases: false,
      );
    } catch (_) {
      if (!_isCurrentPurchaseLoad(generation)) return;
      state = state.copyWith(
        loadingPurchases: false,
        errorMessage: 'تعذر تحميل فواتير المشتريات',
      );
    }
  }

  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value);
  }

  Future<void> selectPurchase(SupplierReturnPurchaseOption purchase) async {
    final generation = ++_loadLinesGeneration;
    state = state.copyWith(
      selectedPurchase: purchase,
      lines: const [],
      lineErrors: const {},
      loadingLines: true,
      clearError: true,
      step: SupplierReturnDraftStep.editLines,
    );

    try {
      final lines = await _repo.loadDraftLines(purchase.purchaseInvoiceId);
      if (!_isCurrentLineLoad(generation)) return;
      state = state.copyWith(lines: lines, loadingLines: false);
    } catch (_) {
      if (!_isCurrentLineLoad(generation)) return;
      state = state.copyWith(
        loadingLines: false,
        errorMessage: 'تعذر تحميل بنود فاتورة الشراء',
        step: SupplierReturnDraftStep.selectPurchase,
        clearSelectedPurchase: true,
      );
    }
  }

  void backToPurchaseSelection() {
    _invalidateLineLoads();
    state = state.copyWith(
      step: SupplierReturnDraftStep.selectPurchase,
      clearSelectedPurchase: true,
      lines: const [],
      lineErrors: const {},
      loadingLines: false,
      clearError: true,
    );
  }

  void setReason(String value) => state = state.copyWith(reason: value);

  void setNotes(String value) => state = state.copyWith(notes: value);

  void setLineQuantity(int purchaseItemId, double quantity) {
    final updated = state.lines.map((line) {
      if (line.purchaseItemId != purchaseItemId) return line;
      return line.copyWith(selectedReturnQty: quantity);
    }).toList();

    final errors = Map<int, String?>.from(state.lineErrors);
    final line = updated.firstWhere((l) => l.purchaseItemId == purchaseItemId);
    errors[purchaseItemId] = validateDraftLineQuantity(line, quantity);

    state = state.copyWith(lines: updated, lineErrors: errors);
  }

  void reset() {
    _invalidatePurchaseLoads();
    _invalidateLineLoads();
    state = const SupplierReturnDraftState();
  }

  bool _isCurrentPurchaseLoad(int generation) =>
      generation == _loadPurchasesGeneration;

  bool _isCurrentLineLoad(int generation) => generation == _loadLinesGeneration;
}

final supplierReturnDraftProvider =
    NotifierProvider<SupplierReturnDraftNotifier, SupplierReturnDraftState>(
  SupplierReturnDraftNotifier.new,
);
