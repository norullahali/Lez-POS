import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/invoice_history_query.dart';
import '../models/invoice_detail.dart';
import '../models/invoice_history_row.dart';
import '../repositories/invoice_history_repository.dart';

final invoiceHistoryRepositoryProvider =
    Provider<InvoiceHistoryRepository>((ref) {
  return InvoiceHistoryRepository(AppDatabase.instance);
});

final invoiceHistoryUiProvider =
    NotifierProvider<InvoiceHistoryUiNotifier, InvoiceHistoryQuery>(
  InvoiceHistoryUiNotifier.new,
);

final invoiceHistoryPageProvider =
    FutureProvider.autoDispose<InvoiceHistoryPage>((ref) async {
  final q = ref.watch(invoiceHistoryUiProvider);
  return ref.read(invoiceHistoryRepositoryProvider).fetchPage(q);
});

final invoiceHistoryCashiersProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.read(invoiceHistoryRepositoryProvider).listCashierNames();
});

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<InvoiceDetailData, int>((ref, invoiceId) async {
  return ref
      .read(invoiceHistoryRepositoryProvider)
      .fetchInvoiceDetail(invoiceId);
});

class InvoiceHistoryUiNotifier extends Notifier<InvoiceHistoryQuery> {
  @override
  InvoiceHistoryQuery build() {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(const Duration(days: 30));
    return InvoiceHistoryQuery(dateFrom: from, dateTo: to);
  }

  void applySearch(String s) {
    state = state.copyWith(search: s.trim(), page: 0);
  }

  void setDateRange(DateTime? from, DateTime? to, {bool clear = false}) {
    if (clear) {
      state = state.copyWith(clearDateRange: true, page: 0);
      return;
    }
    state = state.copyWith(dateFrom: from, dateTo: to, page: 0);
  }

  void setCashier(String? name) {
    if (name == null || name.trim().isEmpty) {
      state = state.copyWith(clearCashier: true, page: 0);
    } else {
      state = state.copyWith(cashierName: name.trim(), page: 0);
    }
  }

  void setPaymentMethod(String? code) {
    if (code == null || code.isEmpty) {
      state = state.copyWith(clearPayment: true, page: 0);
    } else {
      state = state.copyWith(paymentMethod: code, page: 0);
    }
  }

  void setPage(int page) {
    state = state.copyWith(page: page);
  }

  void resetToDefaultRange() {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(const Duration(days: 30));
    state = InvoiceHistoryQuery(dateFrom: from, dateTo: to);
  }
}
