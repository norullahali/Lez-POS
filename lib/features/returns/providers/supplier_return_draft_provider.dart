// lib/features/returns/providers/supplier_return_draft_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supplier_return_service.dart';
import '../models/supplier_return_draft_models.dart';
import '../repositories/supplier_return_read_repository.dart';
import '../utils/supplier_return_posting_messages.dart';
import 'supplier_return_service_provider.dart';

final supplierReturnReadRepositoryProvider =
    Provider<SupplierReturnReadRepository>((ref) {
  return SupplierReturnReadRepository(AppDatabase.instance);
});

enum SupplierReturnDraftStep { selectPurchase, editLines }

enum SupplierReturnPostingStatus { idle, posting, success, failure }

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
  final SupplierReturnPostingStatus postingStatus;
  final String? postingErrorMessage;
  final int? lastPostedReturnId;

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
    this.postingStatus = SupplierReturnPostingStatus.idle,
    this.postingErrorMessage,
    this.lastPostedReturnId,
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

  bool get isPosting => postingStatus == SupplierReturnPostingStatus.posting;

  bool get isLoading => loadingPurchases || loadingLines;

  bool get canSave => canProceed && !isLoading && !isPosting;

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
    SupplierReturnPostingStatus? postingStatus,
    String? postingErrorMessage,
    bool clearPostingError = false,
    int? lastPostedReturnId,
    bool clearLastPostedReturnId = false,
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
      postingStatus: postingStatus ?? this.postingStatus,
      postingErrorMessage: clearPostingError
          ? null
          : (postingErrorMessage ?? this.postingErrorMessage),
      lastPostedReturnId: clearLastPostedReturnId
          ? null
          : (lastPostedReturnId ?? this.lastPostedReturnId),
    );
  }
}

class SupplierReturnDraftNotifier extends Notifier<SupplierReturnDraftState> {
  int _loadPurchasesGeneration = 0;
  int _loadLinesGeneration = 0;
  int _postGeneration = 0;

  @override
  SupplierReturnDraftState build() => const SupplierReturnDraftState();

  SupplierReturnReadRepository get _repo =>
      ref.read(supplierReturnReadRepositoryProvider);

  SupplierReturnService get _postingService =>
      ref.read(supplierReturnServiceProvider);

  void _invalidateLineLoads() => _loadLinesGeneration++;

  void _invalidatePurchaseLoads() => _loadPurchasesGeneration++;

  void _invalidatePosts() => _postGeneration++;

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
      clearPostingError: true,
      postingStatus: SupplierReturnPostingStatus.idle,
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
      clearPostingError: true,
      postingStatus: SupplierReturnPostingStatus.idle,
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

    state = state.copyWith(
      lines: updated,
      lineErrors: errors,
      clearPostingError: true,
      postingStatus: SupplierReturnPostingStatus.idle,
    );
  }

  /// Posts the current draft via the certified SR.2 service.
  /// Returns true only after successful service completion.
  Future<bool> submitReturn() async {
    if (!state.canSave) return false;

    final purchase = state.selectedPurchase;
    if (purchase == null) return false;

    final input = buildPostingInputFromDraft(
      purchase,
      state.lines,
      reason: state.reason,
      notes: state.notes,
    );
    if (input == null) return false;

    final generation = ++_postGeneration;
    state = state.copyWith(
      postingStatus: SupplierReturnPostingStatus.posting,
      clearPostingError: true,
    );

    try {
      final returnId = await _postingService.postPurchaseLinkedReturn(input);
      if (!_isCurrentPost(generation)) return false;

      ref.read(supplierReturnsRefreshProvider.notifier).state++;
      state = state.copyWith(
        postingStatus: SupplierReturnPostingStatus.success,
        lastPostedReturnId: returnId,
      );
      return true;
    } on SupplierReturnPostingException catch (e) {
      if (!_isCurrentPost(generation)) return false;
      state = state.copyWith(
        postingStatus: SupplierReturnPostingStatus.failure,
        postingErrorMessage: supplierReturnPostingFailureMessage(e.code),
      );
      return false;
    } catch (_) {
      if (!_isCurrentPost(generation)) return false;
      state = state.copyWith(
        postingStatus: SupplierReturnPostingStatus.failure,
        postingErrorMessage: 'تعذر حفظ المرتجع',
      );
      return false;
    }
  }

  void reset() {
    _invalidatePurchaseLoads();
    _invalidateLineLoads();
    _invalidatePosts();
    state = const SupplierReturnDraftState();
  }

  bool _isCurrentPurchaseLoad(int generation) =>
      generation == _loadPurchasesGeneration;

  bool _isCurrentLineLoad(int generation) => generation == _loadLinesGeneration;

  bool _isCurrentPost(int generation) => generation == _postGeneration;
}

final supplierReturnDraftProvider =
    NotifierProvider<SupplierReturnDraftNotifier, SupplierReturnDraftState>(
  SupplierReturnDraftNotifier.new,
);
