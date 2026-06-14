import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../models/cash_ledger_summary.dart';
import '../repositories/financial_ledger_repository.dart';
import 'cash_ledger_filter_provider.dart';

final financialLedgerRepositoryProvider = Provider<FinancialLedgerRepository>((ref) {
  return FinancialLedgerRepository(AppDatabase.instance);
});

final cashLedgerSummaryProvider =
    FutureProvider.autoDispose<CashLedgerSummary>((ref) async {
  final filter = ref.watch(cashLedgerFilterProvider);
  final cache = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), cache.close);
  return ref.read(financialLedgerRepositoryProvider).getSummary(filter);
});

final cashLedgerEntriesProvider =
    FutureProvider.autoDispose<CashLedgerPage>((ref) async {
  final filter = ref.watch(cashLedgerFilterProvider);
  final cache = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), cache.close);
  return ref.read(financialLedgerRepositoryProvider).getEntries(filter);
});