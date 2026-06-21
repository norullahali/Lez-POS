import '../models/expense_record.dart';

class ExpensePage {
  const ExpensePage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<ExpenseRecord> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;
}
