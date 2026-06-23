import '../models/other_income_record.dart';

class OtherIncomePage {
  const OtherIncomePage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<OtherIncomeRecord> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;
}
