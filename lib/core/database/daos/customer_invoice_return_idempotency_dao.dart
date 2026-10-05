// lib/core/database/daos/customer_invoice_return_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_invoice_return_idempotency_table.dart';

part 'customer_invoice_return_idempotency_dao.g.dart';

@DriftAccessor(tables: [CustomerInvoiceReturnIdempotency])
class CustomerInvoiceReturnIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerInvoiceReturnIdempotencyDaoMixin {
  CustomerInvoiceReturnIdempotencyDao(super.db);

  Future<CustomerInvoiceReturnIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(customerInvoiceReturnIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int? customerId,
    required int saleInvoiceId,
    required String returnType,
    required int? customerReturnId,
    required int? primaryReferenceId,
    required String executionPath,
  }) =>
      into(customerInvoiceReturnIdempotency).insert(
        CustomerInvoiceReturnIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          customerId: Value(customerId),
          saleInvoiceId: saleInvoiceId,
          returnType: returnType,
          customerReturnId: Value(customerReturnId),
          primaryReferenceId: Value(primaryReferenceId),
          executionPath: executionPath,
        ),
      );
}