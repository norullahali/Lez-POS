import 'package:drift/drift.dart';

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../core/services/activity_logger_service.dart';
import '../models/other_income_category.dart';
import '../models/other_income_page.dart';
import '../models/other_income_record.dart';
import '../models/other_income_summary.dart';

class OtherIncomeRepository {
  OtherIncomeRepository(this._db) {
    _activityLogger = ActivityLoggerService(_db);
  }

  final db.AppDatabase _db;
  late final ActivityLoggerService _activityLogger;

  // ── Categories ────────────────────────────────────────────────────────────

  Future<int> createCategory(OtherIncomeCategory category) async {
    final id = await _db.otherIncomeDao.createCategory(
      db.OtherIncomeCategoriesCompanion(
        name: Value(category.name),
        description: Value(category.description),
        isActive: Value(category.isActive),
      ),
    );
    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.incomeCategoryCreated,
      category: ActivityCategories.financial,
      entityType: 'other_income_category',
      entityId: id,
      title: '\u0625\u0636\u0627\u0641\u0629 \u0641\u0626\u0629 \u0625\u064a\u0631\u0627\u062f',
      description: category.name,
    );
    return id;
  }

  Future<void> updateCategory(OtherIncomeCategory category) async {
    if (category.id == null) {
      throw ArgumentError('OtherIncomeCategory.id is required for update');
    }
    await _db.otherIncomeDao.updateCategory(
      db.OtherIncomeCategoriesCompanion(
        id: Value(category.id!),
        name: Value(category.name),
        description: Value(category.description),
        isActive: Value(category.isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _activityLogger.logEntityUpdate(
      activityType: ActivityTypes.incomeCategoryUpdated,
      category: ActivityCategories.financial,
      entityType: 'other_income_category',
      entityId: category.id!,
      title: '\u062a\u0639\u062f\u064a\u0644 \u0641\u0626\u0629 \u0625\u064a\u0631\u0627\u062f',
      description: category.name,
    );
  }

  Future<List<OtherIncomeCategory>> listCategories({
    bool activeOnly = true,
  }) async {
    final rows =
        await _db.otherIncomeDao.getCategories(activeOnly: activeOnly);
    return rows.map(OtherIncomeCategory.fromDrift).toList();
  }

  // ── Records ───────────────────────────────────────────────────────────────

  Future<int> createIncome(OtherIncomeRecord record) async {
    final id = await _db.otherIncomeDao.createIncome(
      db.OtherIncomeRecordsCompanion(
        categoryId: Value(record.categoryId),
        amount: Value(record.amount),
        incomeDate: Value(record.incomeDate),
        receivedAt: Value(record.receivedAt),
        notes: Value(record.notes),
        sessionId: Value(record.sessionId),
        createdBy: Value(record.createdBy),
      ),
    );
    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.incomeCreated,
      category: ActivityCategories.financial,
      entityType: 'other_income_record',
      entityId: id,
      title: '\u062a\u0633\u062c\u064a\u0644 \u0625\u064a\u0631\u0627\u062f',
      description: record.amount.toStringAsFixed(2),
    );
    return id;
  }

  /// Updates a non-voided income record inside a Drift transaction (TOCTOU-safe).
  ///
  /// Rules:
  ///   - Throws [StateError] if the record does not exist.
  ///   - Throws [StateError] if the record is already voided.
  ///   - Always forces isVoided = false on the companion — caller value ignored.
  Future<void> updateIncome(OtherIncomeRecord record) async {
    if (record.id == null) {
      throw ArgumentError('OtherIncomeRecord.id is required for update');
    }
    db.OtherIncomeRecord? before;
    await _db.transaction(() async {
      final fetched = await _db.otherIncomeDao.getIncomeById(record.id!);
      if (fetched == null) throw StateError('Other income record not found');
      if (fetched.isVoided) throw StateError('Cannot update voided income');
      before = fetched;
      await _db.otherIncomeDao.updateIncome(
        db.OtherIncomeRecordsCompanion(
          id: Value(record.id!),
          categoryId: Value(record.categoryId),
          amount: Value(record.amount),
          incomeDate: Value(record.incomeDate),
          receivedAt: Value(record.receivedAt),
          notes: Value(record.notes),
          sessionId: Value(record.sessionId),
          createdBy: Value(record.createdBy),
          updatedAt: Value(DateTime.now()),
          // Hardcoded: updateIncome must never perform a void.
          isVoided: const Value(false),
        ),
      );
    });
    if (before == null) return;
    await _activityLogger.logEntityUpdate(
      activityType: ActivityTypes.incomeUpdated,
      category: ActivityCategories.financial,
      entityType: 'other_income_record',
      entityId: record.id!,
      title: '\u062a\u0639\u062f\u064a\u0644 \u0625\u064a\u0631\u0627\u062f',
      description: '${before!.amount} -> ${record.amount}',
    );
  }

  /// Voids an income record inside a Drift transaction (TOCTOU-safe).
  ///
  /// Uses logWarning (not logInfo) — voiding is a destructive, irreversible operation.
  /// Early-returns silently if the record is already voided (idempotent guard).
  Future<void> voidIncome(int id) async {
    db.OtherIncomeRecord? before;
    await _db.transaction(() async {
      final fetched = await _db.otherIncomeDao.getIncomeById(id);
      if (fetched == null) throw StateError('Other income record not found');
      if (fetched.isVoided) return;
      before = fetched;
      final voided = await _db.otherIncomeDao.voidIncome(id);
      if (!voided) throw StateError('Failed to void income record');
    });
    if (before == null) return;
    await _activityLogger.logWarning(
      activityType: ActivityTypes.incomeVoided,
      category: ActivityCategories.financial,
      action: 'void',
      title: '\u0625\u0644\u063a\u0627\u0621 \u0625\u064a\u0631\u0627\u062f',
      description: before!.notes.isNotEmpty
          ? before!.notes
          : before!.amount.toStringAsFixed(2),
      entityType: 'other_income_record',
      entityId: id,
    );
  }

  // ── Single record ─────────────────────────────────────────────────────────

  /// Returns a single income record by ID, or null if not found.
  /// Read-only — no writes, no activity logging.
  Future<OtherIncomeRecord?> getIncomeById(int id) async {
    final row = await _db.otherIncomeDao.getIncomeById(id);
    if (row == null) return null;
    return OtherIncomeRecord.fromDrift(row);
  }

  // ── Paged query ───────────────────────────────────────────────────────────

  Future<OtherIncomePage> getIncomePaged({
    required int page,
    required int pageSize,
    bool includeVoided = false,
    int? categoryId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final result = await _db.otherIncomeDao.getIncomePaged(
      page: page,
      pageSize: pageSize,
      includeVoided: includeVoided,
      categoryId: categoryId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return OtherIncomePage(
      items: result.items.map(OtherIncomeRecord.fromDrift).toList(),
      totalCount: result.totalCount,
      page: result.page,
      pageSize: result.pageSize,
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  Future<OtherIncomeSummary> getSummary() async {
    final (activeCount, totalAmount, voidedCount, categoryCount) =
        await _db.otherIncomeDao.getIncomeSummary();
    return OtherIncomeSummary(
      activeCount: activeCount,
      totalAmount: totalAmount,
      voidedCount: voidedCount,
      categoryCount: categoryCount,
    );
  }
}
