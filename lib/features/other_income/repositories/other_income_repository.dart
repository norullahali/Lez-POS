import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../core/services/activity_logger_service.dart';
import '../../../core/services/other_income_mutation_fingerprint.dart';
import '../../../core/services/other_income_mutation_save_service.dart';
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

  /// Test-only update path. Production must use
  /// [OtherIncomeMutationSaveService.processUpdate].
  @visibleForTesting
  Future<void> updateIncomeForTest({
    required String idempotencyKey,
    required OtherIncomeRecord record,
    required int updatedBy,
  }) async {
    if (record.id == null) {
      throw ArgumentError('OtherIncomeRecord.id is required for update');
    }
    final fp = OtherIncomeMutationFingerprint.computeUpdate(
      otherIncomeRecordId: record.id!,
      categoryId: record.categoryId,
      amount: record.amount,
      incomeDate: record.incomeDate,
      receivedAt: record.receivedAt,
      notes: record.notes,
      updatedBy: updatedBy,
      sessionId: record.sessionId,
    );
    await OtherIncomeMutationSaveService(_db).processUpdate(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      otherIncomeRecordId: record.id!,
      categoryId: record.categoryId,
      amount: record.amount,
      incomeDate: record.incomeDate,
      receivedAt: record.receivedAt,
      notes: record.notes,
      updatedBy: updatedBy,
      sessionId: record.sessionId,
    );
  }

  /// Test-only void path. Production must use
  /// [OtherIncomeMutationSaveService.processVoid].
  @visibleForTesting
  Future<void> voidIncomeForTest({
    required String idempotencyKey,
    required int otherIncomeRecordId,
    required int voidedBy,
  }) async {
    final fp = OtherIncomeMutationFingerprint.computeVoid(
      otherIncomeRecordId: otherIncomeRecordId,
      voidedBy: voidedBy,
    );
    await OtherIncomeMutationSaveService(_db).processVoid(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      otherIncomeRecordId: otherIncomeRecordId,
      voidedBy: voidedBy,
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
