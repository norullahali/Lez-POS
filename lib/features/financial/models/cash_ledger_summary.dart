import 'cash_ledger_event.dart';

class CashLedgerSummary {
  const CashLedgerSummary({
    required this.totalInflow,
    required this.totalOutflow,
    required this.netCashFlow,
    required this.transactionCount,
  });

  final double totalInflow;
  final double totalOutflow;
  final double netCashFlow;
  final int transactionCount;

  double get computedNetCashFlow => totalInflow - totalOutflow;

  bool get isNetConsistent =>
      (computedNetCashFlow - netCashFlow).abs() < 0.01;

  static const empty = CashLedgerSummary(
    totalInflow: 0,
    totalOutflow: 0,
    netCashFlow: 0,
    transactionCount: 0,
  );
}

class CashLedgerPage {
  const CashLedgerPage({
    required this.entries,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<CashLedgerEvent> entries;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;

  bool get hasNextPage => (page + 1) * pageSize < totalCount;
  bool get hasPreviousPage => page > 0;

  static const empty = CashLedgerPage(
    entries: [],
    totalCount: 0,
    page: 0,
    pageSize: 50,
  );
}