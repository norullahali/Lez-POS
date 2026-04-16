// lib/core/database/daos/customer_accounts_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/customer_accounts_table.dart';
import '../tables/customer_transactions_table.dart';
import '../tables/customers_table.dart';

part 'customer_accounts_dao.g.dart';

@DriftAccessor(tables: [CustomerAccounts, CustomerTransactions, Customers])
class CustomerAccountsDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerAccountsDaoMixin {
  CustomerAccountsDao(super.db);

  // ─────────────────────────────────────────────────────
  // Balance queries
  // ─────────────────────────────────────────────────────

  /// Stream of current balance for a specific customer.
  Stream<double> watchBalance(int customerId) {
    return (select(customerAccounts)
          ..where((a) => a.customerId.equals(customerId)))
        .watchSingleOrNull()
        .map((row) => row?.currentBalance ?? 0.0);
  }

  /// One-shot read of balance.
  Future<double> getBalance(int customerId) async {
    final row = await (select(customerAccounts)
          ..where((a) => a.customerId.equals(customerId)))
        .getSingleOrNull();
    return row?.currentBalance ?? 0.0;
  }

  /// Calculate balance directly from transactions (authoritative).
  Future<double> calculateBalanceFromTransactions(int customerId) async {
    final sumExp = customerTransactions.amount.sum();
    final query = selectOnly(customerTransactions)
      ..addColumns([sumExp])
      ..where(customerTransactions.customerId.equals(customerId));
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0.0;
  }

  // ─────────────────────────────────────────────────────
  // Transaction writing (all balance-altering ops)
  // ─────────────────────────────────────────────────────

  /// Core method — always call inside a Drift transaction.
  /// Signs: SALE = +amount (balance grows), PAYMENT = -amount (balance shrinks),
  /// RETURN = -amount (balance shrinks), ADJUSTMENT = explicit signed amount.
  Future<void> addTransaction({
    required int customerId,
    required String type, // 'SALE' | 'PAYMENT' | 'ADJUSTMENT' | 'RETURN'
    required double amount, // already signed correctly
    int? referenceId,
    String note = '',
  }) async {
    await transaction(() async {
      // 1. Append to immutable ledger
      await into(customerTransactions).insert(
        CustomerTransactionsCompanion(
          customerId: Value(customerId),
          type: Value(type),
          amount: Value(amount),
          referenceId: Value(referenceId),
          note: Value(note),
        ),
      );

      // 2. Re-calculate authoritative balance from all transactions
      final newBalance = await calculateBalanceFromTransactions(customerId);

      // 3. Upsert customer_accounts row safely honoring the unique customer_id
      final existing = await (select(customerAccounts)
            ..where((a) => a.customerId.equals(customerId)))
          .getSingleOrNull();

      if (existing != null) {
        await (update(customerAccounts)
              ..where((a) => a.id.equals(existing.id)))
            .write(
          CustomerAccountsCompanion(
            currentBalance: Value(newBalance),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await into(customerAccounts).insert(
          CustomerAccountsCompanion(
            customerId: Value(customerId),
            currentBalance: Value(newBalance),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Record a SALE on credit.
  Future<void> recordSale({
    required int customerId,
    required double amount,
    required int invoiceId,
    String note = '',
  }) => addTransaction(
        customerId: customerId,
        type: 'SALE',
        amount: amount, // positive — increases debt
        referenceId: invoiceId,
        note: note,
      );

  /// Record a PAYMENT reducing the balance.
  Future<void> recordPayment({
    required int customerId,
    required double amount,
    String note = '',
  }) => addTransaction(
        customerId: customerId,
        type: 'PAYMENT',
        amount: -amount, // negative — decreases debt
        note: note,
      );

  /// Record an ADJUSTMENT with mandatory reason (can be + or -).
  Future<void> adjustBalance({
    required int customerId,
    required double signedAmount,
    required String reason,
  }) => addTransaction(
        customerId: customerId,
        type: 'ADJUSTMENT',
        amount: signedAmount,
        note: reason,
      );

  /// Record a RETURN reducing the balance (reversing a sale).
  Future<void> recordReturn({
    required int customerId,
    required double amount,
    required int returnId,
    String note = '',
  }) =>
      addTransaction(
        customerId: customerId,
        type: 'RETURN',
        amount: -amount, // negative — decreases debt
        referenceId: returnId,
        note: note,
      );

  // ─────────────────────────────────────────────────────
  // History queries
  // ─────────────────────────────────────────────────────

  /// Stream of full transaction history for one customer, newest first.
  Stream<List<CustomerTransaction>> watchHistory(int customerId, {int limit = 50}) {
    return (select(customerTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<CustomerTransaction>> getHistory(int customerId, {int limit = 50}) {
    return (select(customerTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  // ─────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────

  /// Stream of all customers with non-zero balances, ordered by balance desc.
  Stream<List<CustomerAccount>> watchAllDebtors() {
    return (select(customerAccounts)
          ..where((a) => a.currentBalance.isBiggerThanValue(0))
          ..orderBy([(a) => OrderingTerm.desc(a.currentBalance)]))
        .watch();
  }

  Future<double> getTotalOutstanding() async {
    final sumExp = customerAccounts.currentBalance.sum();
    final query = selectOnly(customerAccounts)
      ..addColumns([sumExp])
      ..where(customerAccounts.currentBalance.isBiggerThanValue(0));
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0.0;
  }

  /// Top debtors with customer info — for reports screen.
  Future<List<Map<String, dynamic>>> getTopDebtors({int limit = 20}) async {
    final result = await customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.credit_limit, ca.current_balance, ca.updated_at
      FROM customers c
      JOIN customer_accounts ca ON ca.customer_id = c.id
      WHERE ca.current_balance > 0 AND c.id != 1
      ORDER BY ca.current_balance DESC
      LIMIT $limit
      ''',
      readsFrom: {customers, customerAccounts},
    ).get();
    return result.map((r) => r.data).toList();
  }

  /// Aging buckets: number of days since the FIRST unpaid SALE transaction.
  /// Returns counts for 0-7d, 8-30d, 30+d.
  Future<Map<String, double>> getAgingBuckets(int customerId) async {
    final now = DateTime.now();
    final history = await getHistory(customerId, limit: 200);

    double bucket1 = 0, bucket2 = 0, bucket3 = 0; // 0-7, 8-30, 30+

    for (final tx in history) {
      if (tx.type != 'SALE' || tx.amount <= 0) continue;
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

  // ─────────────────────────────────────────────────────
  // Credit limit check (utility)
  // ─────────────────────────────────────────────────────

  /// Returns true if adding [extraAmount] to this customer's balance would
  /// exceed their credit_limit (0 = no limit, always returns false).
  Future<bool> wouldExceedCreditLimit(int customerId, double extraAmount) async {
    final customer = await (select(customers)
          ..where((c) => c.id.equals(customerId)))
        .getSingleOrNull();
    if (customer == null || customer.creditLimit <= 0) return false;
    final balance = await getBalance(customerId);
    return (balance + extraAmount) > customer.creditLimit;
  }
}
