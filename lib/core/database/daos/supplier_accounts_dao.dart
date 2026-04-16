// lib/core/database/daos/supplier_accounts_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/supplier_accounts_table.dart';
import '../tables/supplier_transactions_table.dart';
import '../tables/suppliers_table.dart';

part 'supplier_accounts_dao.g.dart';

@DriftAccessor(tables: [SupplierAccounts, SupplierTransactions, Suppliers])
class SupplierAccountsDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierAccountsDaoMixin {
  SupplierAccountsDao(super.db);

  // ─────────────────────────────────────────────────────
  // Balance queries
  // ─────────────────────────────────────────────────────

  Stream<double> watchBalance(int supplierId) {
    return (select(supplierAccounts)
          ..where((a) => a.supplierId.equals(supplierId)))
        .watchSingleOrNull()
        .map((row) => row?.currentBalance ?? 0.0);
  }

  Future<double> getBalance(int supplierId) async {
    final row = await (select(supplierAccounts)
          ..where((a) => a.supplierId.equals(supplierId)))
        .getSingleOrNull();
    return row?.currentBalance ?? 0.0;
  }

  Future<double> calculateBalanceFromTransactions(int supplierId) async {
    final sumExp = supplierTransactions.amount.sum();
    final query = selectOnly(supplierTransactions)
      ..addColumns([sumExp])
      ..where(supplierTransactions.supplierId.equals(supplierId));
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0.0;
  }

  // ─────────────────────────────────────────────────────
  // Transaction writing
  // ─────────────────────────────────────────────────────

  Future<void> addTransaction({
    required int supplierId,
    required String type, // 'PURCHASE' | 'PAYMENT' | 'ADJUSTMENT'
    required double amount, // positive = increases debt, negative = decreases debt
    int? referenceId,
    String note = '',
  }) async {
    await transaction(() async {
      // 1. Append to ledger
      await into(supplierTransactions).insert(
        SupplierTransactionsCompanion(
          supplierId: Value(supplierId),
          type: Value(type),
          amount: Value(amount),
          referenceId: Value(referenceId),
          note: Value(note),
        ),
      );

      // 2. Re-calculate balance
      final newBalance = await calculateBalanceFromTransactions(supplierId);

      // 3. Upsert
      final existing = await (select(supplierAccounts)
            ..where((a) => a.supplierId.equals(supplierId)))
          .getSingleOrNull();

      if (existing != null) {
        await (update(supplierAccounts)
              ..where((a) => a.id.equals(existing.id)))
            .write(
          SupplierAccountsCompanion(
            currentBalance: Value(newBalance),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await into(supplierAccounts).insert(
          SupplierAccountsCompanion(
            supplierId: Value(supplierId),
            currentBalance: Value(newBalance),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────
  // History queries
  // ─────────────────────────────────────────────────────

  Stream<List<SupplierTransaction>> watchHistory(int supplierId, {int limit = 50}) {
    return (select(supplierTransactions)
          ..where((t) => t.supplierId.equals(supplierId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<SupplierTransaction>> getHistory(int supplierId, {int limit = 50}) {
    return (select(supplierTransactions)
          ..where((t) => t.supplierId.equals(supplierId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  // ─────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────

  Future<double> getTotalOutstanding() async {
    final sumExp = supplierAccounts.currentBalance.sum();
    final query = selectOnly(supplierAccounts)
      ..addColumns([sumExp])
      ..where(supplierAccounts.currentBalance.isBiggerThanValue(0));
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getTopCreditors({int limit = 20}) async {
    final result = await customSelect(
      '''
      SELECT s.id, s.name, s.phone, sa.current_balance, sa.updated_at
      FROM suppliers s
      JOIN supplier_accounts sa ON sa.supplier_id = s.id
      WHERE sa.current_balance > 0
      ORDER BY sa.current_balance DESC
      LIMIT $limit
      ''',
      readsFrom: {suppliers, supplierAccounts},
    ).get();
    return result.map((r) => r.data).toList();
  }

  Future<Map<String, double>> getAgingBuckets(int supplierId) async {
    final now = DateTime.now();
    final history = await getHistory(supplierId, limit: 200);

    double bucket1 = 0, bucket2 = 0, bucket3 = 0;

    for (final tx in history) {
      if (tx.type != 'PURCHASE' || tx.amount <= 0) continue;
      final days = now.difference(tx.createdAt).inDays;
      if (days <= 7) {
        bucket1 += tx.amount;
      } else if (days <= 30) {
        bucket2 += tx.amount;
      } else {
        bucket3 += tx.amount;
      }
    }
    return {'0_7': bucket1, '8_30': bucket2, '30_plus': bucket3};
  }
}
