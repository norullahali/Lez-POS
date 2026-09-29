// lib/core/database/daos/customer_payment_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_payment_idempotency_table.dart';

part 'customer_payment_idempotency_dao.g.dart';

@DriftAccessor(tables: [CustomerPaymentIdempotency])
class CustomerPaymentIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerPaymentIdempotencyDaoMixin {
  CustomerPaymentIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<CustomerPaymentIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(customerPaymentIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required int customerId,
    required double amount,
    required String note,
    required int customerTransactionId,
  }) =>
      into(customerPaymentIdempotency).insert(
        CustomerPaymentIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          customerId: customerId,
          amount: amount,
          note: Value(note),
          customerTransactionId: customerTransactionId,
        ),
      );
}