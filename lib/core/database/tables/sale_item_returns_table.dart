import 'package:drift/drift.dart';
import 'sale_items_table.dart';
import 'products_table.dart';

// Partial return line-item record.
// One row per product-quantity unit returned from a specific sale line.
// Original sale_items rows are NEVER modified - this table is the ledger of
// what has been returned, keyed back to the exact sale line.
class SaleItemReturns extends Table {
  IntColumn get id => integer().autoIncrement()();

  // The invoice that was originally sold.
  // Plain integer (no ORM FK) to avoid a diamond dependency with saleItemId->SaleItems->SalesInvoices.
  // Referential integrity is maintained via the saleItemId -> SaleItems cascade chain.
  IntColumn get saleInvoiceId => integer()();

  // The exact sale line being (partially) returned.
  IntColumn get saleItemId =>
      integer().references(SaleItems, #id, onDelete: KeyAction.cascade)();

  // Denormalized for fast stock lookups without joining back to sale_items.
  IntColumn get productId => integer().references(Products, #id)();

  // Qty being returned in this record (always positive).
  RealColumn get returnedQuantity => real()();

  // Unit price at the time of return (snapshot from original sale line).
  RealColumn get unitPriceAtReturn => real()();

  // returnedQuantity * unitPriceAtReturn
  RealColumn get returnTotal => real()();

  // Optional reason / note for this return line.
  TextColumn get returnReasonNote => text().nullable()();

  // User who processed the return.
  IntColumn get returnedByUserId =>
      integer().customConstraint('REFERENCES users(id)')();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Index> get indexes => [
        Index(
          'sir_invoice_idx',
          'CREATE INDEX IF NOT EXISTS sir_invoice_idx ON sale_item_returns (sale_invoice_id)',
        ),
        Index(
          'sir_item_idx',
          'CREATE INDEX IF NOT EXISTS sir_item_idx ON sale_item_returns (sale_item_id)',
        ),
        Index(
          'sir_product_idx',
          'CREATE INDEX IF NOT EXISTS sir_product_idx ON sale_item_returns (product_id)',
        ),
      ];
}