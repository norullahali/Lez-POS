import 'package:drift/drift.dart';

/// Daily atomic sequence counter for POS sales invoice numbers (B4).
class SalesInvoiceDailySequences extends Table {
  /// Calendar day key in `YYYYMMDD` form.
  TextColumn get dayPrefix => text()();

  /// Last allocated numeric suffix for [dayPrefix].
  IntColumn get lastNumber => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {dayPrefix};
}