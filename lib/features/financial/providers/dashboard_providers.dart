// ── Dashboard Provider Architecture ──────────────────────────────────────────
//
// Reactivity model: FutureProvider.autoDispose (consistent with Cash Ledger).
//
// Providers rebuild when:
//   1. A watched Riverpod state changes (e.g. dashboardFilterProvider updates).
//   2. The provider is disposed and re-subscribed (user navigates away and back).
//
// Providers do NOT stream-refresh automatically on SQLite writes.
// A sale, payment, or expense created while the dashboard is displayed will NOT
// push an update to these providers in real time.
//
// This is intentional and consistent with the Cash Ledger (cashLedgerSummaryProvider
// and cashLedgerEntriesProvider have identical behavior).
//
// Phase 8 upgrade path: migrate to StreamProvider + Drift watch() queries for
// true streaming reactivity. No provider graph changes are required for that migration.
// ─────────────────────────────────────────────────────────────────────────────

import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/database/app_database.dart";
import "../models/cash_ledger_event.dart";
import "../models/cash_ledger_filter.dart";
import "../models/financial_dashboard_cash_flow.dart";
import "../models/financial_dashboard_current_state.dart";
import "../models/financial_dashboard_summary.dart";
import "../repositories/financial_dashboard_repository.dart";
import "cash_ledger_providers.dart";
import "dashboard_filter_provider.dart";

// ── Repository providers ──────────────────────────────────────────────────

final financialDashboardRepositoryProvider =
    Provider<FinancialDashboardRepository>((ref) {
  return FinancialDashboardRepository(AppDatabase.instance);
});

// ── Cash Balance (cached 45 s) ────────────────────────────────────────────

/// All-time Cash Ledger net -- the calculated cash balance.
/// ONLY dashboard provider that uses keepAlive caching (45 s).
final dashboardCashBalanceProvider = FutureProvider.autoDispose<double>((ref) async {
  final cache = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), cache.close);
  final summary =
      await ref.read(financialLedgerRepositoryProvider).getSummaryAllTime();
  return summary.netCashFlow;
});

// ── Period Cash Flow (no cache) ───────────────────────────────────────────

/// Period cash-flow KPIs from Cash Ledger UNION. Watches dashboardFilterProvider.
/// DO NOT couple to cashLedgerFilterProvider.
final dashboardCashFlowProvider =
    FutureProvider.autoDispose<FinancialDashboardCashFlow>((ref) async {
  final filter = ref.watch(dashboardFilterProvider);
  final ledger = ref.read(financialLedgerRepositoryProvider);

  final cashLedgerFilter = CashLedgerFilter(dateFilter: filter.dateFilter);

  final summaryFuture = ledger.getSummary(cashLedgerFilter);
  final balanceFuture = ref.read(dashboardCashBalanceProvider.future);

  final summary = await summaryFuture;
  final cashBalance = await balanceFuture;

  return FinancialDashboardCashFlow(
    totalInflow: summary.totalInflow,
    totalOutflow: summary.totalOutflow,
    netCashFlow: summary.netCashFlow,
    cashBalance: cashBalance,
  );
});

// ── Current State (no cache) ──────────────────────────────────────────────

/// Debt (always current) + supplementary (period) KPIs.
/// Watches dashboardFilterProvider.
/// DO NOT couple to cashLedgerFilterProvider.
final dashboardCurrentStateProvider =
    FutureProvider.autoDispose<FinancialDashboardCurrentState>((ref) async {
  final filter = ref.watch(dashboardFilterProvider);
  final repo = ref.read(financialDashboardRepositoryProvider);

  final range = filter.resolvedRange;
  final start = _startOfDay(range.start);
  final end = _endExclusive(range.end);

  final debtFuture = repo.getCurrentState();
  final suppFuture = repo.getSupplementaryKpis(start: start, end: end);

  final debt = await debtFuture;
  final supp = await suppFuture;

  return FinancialDashboardCurrentState(
    customerDebt: debt.customerDebt,
    supplierDebt: debt.supplierDebt,
    totalSales: supp.totalSales,
    cardSales: supp.cardSales,
    sessionDifference: supp.sessionDifference,
  );
});

// ── Summary (combines both) ───────────────────────────────────────────────

/// Combined snapshot. Watches both sub-providers.
final dashboardSummaryProvider =
    FutureProvider.autoDispose<FinancialDashboardSummary>((ref) async {
  final cashFlowFuture = ref.watch(dashboardCashFlowProvider.future);
  final currentStateFuture = ref.watch(dashboardCurrentStateProvider.future);

  final cashFlow = await cashFlowFuture;
  final currentState = await currentStateFuture;

  return FinancialDashboardSummary(
    cashFlow: cashFlow,
    currentState: currentState,
    generatedAt: DateTime.now(),
  );
});

// ── Recent Activity (no cache) ────────────────────────────────────────────

/// Top 10 Cash Ledger entries for the period. Watches dashboardFilterProvider.
/// Uses financialLedgerRepositoryProvider directly.
/// NEVER reuses cashLedgerEntriesProvider -- that is coupled to cashLedgerFilterProvider.
final dashboardRecentActivityProvider =
    FutureProvider.autoDispose<List<CashLedgerEvent>>((ref) async {
  final filter = ref.watch(dashboardFilterProvider);
  final ledger = ref.read(financialLedgerRepositoryProvider);

  final recentFilter = CashLedgerFilter(
    dateFilter: filter.dateFilter,
    page: 0,
    pageSize: 10,
    sortDescending: true,
  );

  final page = await ledger.getEntries(recentFilter);
  return page.entries;
});

// ── Private date helpers ──────────────────────────────────────────────────

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _endExclusive(DateTime d) =>
    _startOfDay(d).add(const Duration(days: 1));