// lib/core/database/tables/return_audit_logs_table.dart
//
// Immutable append-only audit ledger for every customer return operation.
// Rows are NEVER updated or deleted after insertion.
import 'package:drift/drift.dart';

class ReturnAuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Always set explicitly from Dart (avoids SQLite TEXT timestamp default).
  DateTimeColumn get createdAt => dateTime()();

  /// Discriminator: 'full' | 'partial' | 'smart_lookup' | 'manual_future'
  TextColumn get returnType => text()();

  // -- Reference links ------------------------------------------------------
  // All nullable FKs use customConstraint to avoid drift_dev diamond-FK issues.

  IntColumn get invoiceId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES sales_invoices(id)')();

  /// Null for full returns (the whole invoice is returned, not a single line).
  IntColumn get saleItemId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES sale_items(id)')();

  IntColumn get productId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES products(id)')();

  // -- Quantities / amounts -------------------------------------------------
  RealColumn get returnedQuantity =>
      real().withDefault(const Constant(0.0))();

  RealColumn get returnedAmount =>
      real().withDefault(const Constant(0.0))();

  // -- Actor snapshots ------------------------------------------------------
  IntColumn get cashierUserId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES users(id)')();

  /// Denormalized — survives user record rename/deletion.
  TextColumn get cashierNameSnapshot => text().nullable()();

  IntColumn get sessionId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES pos_sessions(id)')();

  IntColumn get customerId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES customers(id)')();

  /// Denormalized — survives customer record rename/deletion.
  TextColumn get customerNameSnapshot => text().nullable()();

  // -- Return context -------------------------------------------------------
  TextColumn get returnReason => text().nullable()();
  TextColumn get returnNote => text().nullable()();

  // -- Stock snapshot (captured at return time) -----------------------------
  RealColumn get stockBefore => real().nullable()();
  RealColumn get stockAfter => real().nullable()();

  // -- Source reference -----------------------------------------------------
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();

  // -- Future-ready extensions ----------------------------------------------
  TextColumn get deviceInfo => text().nullable()();
  TextColumn get metadataJson => text().nullable()();

  List<Index> get indexes => [
        Index(
          'ral_created_at_idx',
          'CREATE INDEX IF NOT EXISTS ral_created_at_idx'
          ' ON return_audit_logs (created_at)',
        ),
        Index(
          'ral_cashier_idx',
          'CREATE INDEX IF NOT EXISTS ral_cashier_idx'
          ' ON return_audit_logs (cashier_user_id)',
        ),
        Index(
          'ral_invoice_idx',
          'CREATE INDEX IF NOT EXISTS ral_invoice_idx'
          ' ON return_audit_logs (invoice_id)',
        ),
        Index(
          'ral_product_idx',
          'CREATE INDEX IF NOT EXISTS ral_product_idx'
          ' ON return_audit_logs (product_id)',
        ),
      ];
}
