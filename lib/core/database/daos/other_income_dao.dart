import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/other_income_categories_table.dart';
import '../tables/other_income_records_table.dart';

part 'other_income_dao.g.dart';

class OtherIncomePageResult {
  const OtherIncomePageResult({
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

@DriftAccessor(tables: [OtherIncomeCategories, OtherIncomeRecords])
class OtherIncomeDao extends DatabaseAccessor<AppDatabase>
    with _$OtherIncomeDaoMixin {
  OtherIncomeDao(super.db);

  // ── Categories ────────────────────────────────────────────────────────────

  Future<int> createCategory(OtherIncomeCategoriesCompanion entry) =>
      into(otherIncomeCategories).insert(entry);

  Future<bool> updateCategory(OtherIncomeCategoriesCompanion entry) =>
      update(otherIncomeCategories).replace(entry);

  Future<OtherIncomeCategory?> getCategoryById(int id) =>
      (select(otherIncomeCategories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<List<OtherIncomeCategory>> getCategories({bool activeOnly = true}) {
    final query = select(otherIncomeCategories)
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    if (activeOnly) {
      query.where((c) => c.isActive.equals(true));
    }
    return query.get();
  }

  // ── Records ───────────────────────────────────────────────────────────────

  Future<int> createIncome(OtherIncomeRecordsCompanion entry) =>
      into(otherIncomeRecords).insert(entry);

  Future<bool> updateIncome(OtherIncomeRecordsCompanion entry) =>
      update(otherIncomeRecords).replace(entry);

  Future<bool> voidIncome(int id) async {
    final rows =
        await (update(otherIncomeRecords)..where((e) => e.id.equals(id)))
            .write(
      OtherIncomeRecordsCompanion(
        isVoided: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return rows > 0;
  }

  Future<OtherIncomeRecord?> getIncomeById(int id) =>
      (select(otherIncomeRecords)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  // ── Paged query ───────────────────────────────────────────────────────────

  Future<OtherIncomePageResult> getIncomePaged({
    required int page,
    required int pageSize,
    bool includeVoided = false,
    int? categoryId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    // ── Count ──
    final countExpr = otherIncomeRecords.id.count();
    final countQuery = selectOnly(otherIncomeRecords)
      ..addColumns([countExpr]);
    if (!includeVoided) {
      countQuery.where(otherIncomeRecords.isVoided.equals(false));
    }
    if (categoryId != null) {
      countQuery.where(otherIncomeRecords.categoryId.equals(categoryId));
    }
    if (dateFrom != null) {
      countQuery
          .where(otherIncomeRecords.receivedAt.isBiggerOrEqualValue(dateFrom));
    }
    if (dateTo != null) {
      countQuery
          .where(otherIncomeRecords.receivedAt.isSmallerOrEqualValue(dateTo));
    }

    final countRow = await countQuery.getSingle();
    final totalCount = countRow.read(countExpr) ?? 0;

    if (totalCount == 0) {
      return OtherIncomePageResult(
        items: const [],
        totalCount: 0,
        page: page,
        pageSize: pageSize,
      );
    }

    // ── Data ──
    final offset = page * pageSize;
    final query = select(otherIncomeRecords)
      ..orderBy([
        (e) => OrderingTerm.desc(e.receivedAt),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(pageSize, offset: offset);
    if (!includeVoided) query.where((e) => e.isVoided.equals(false));
    if (categoryId != null) {
      query.where((e) => e.categoryId.equals(categoryId));
    }
    if (dateFrom != null) {
      query.where((e) => e.receivedAt.isBiggerOrEqualValue(dateFrom));
    }
    if (dateTo != null) {
      query.where((e) => e.receivedAt.isSmallerOrEqualValue(dateTo));
    }

    final items = await query.get();
    return OtherIncomePageResult(
      items: items,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  Future<(int activeCount, double totalAmount, int voidedCount, int categoryCount)>
      getIncomeSummary() async {
    final row = await customSelect(
      'SELECT '
      'COUNT(CASE WHEN ir.is_voided = 0 THEN 1 END) AS active_count, '
      'COALESCE(SUM(CASE WHEN ir.is_voided = 0 THEN ir.amount END), 0.0) AS total_amount, '
      'COUNT(CASE WHEN ir.is_voided = 1 THEN 1 END) AS voided_count, '
      '(SELECT COUNT(*) FROM other_income_categories WHERE is_active = 1) AS category_count '
      'FROM other_income_records ir',
      readsFrom: {otherIncomeRecords, otherIncomeCategories},
    ).getSingle();
    return (
      (row.data['active_count'] as int?) ?? 0,
      (row.data['total_amount'] as num?)?.toDouble() ?? 0.0,
      (row.data['voided_count'] as int?) ?? 0,
      (row.data['category_count'] as int?) ?? 0,
    );
  }
}
