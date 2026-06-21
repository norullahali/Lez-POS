import 'package:drift/drift.dart';

import 'expense_categories_table.dart';
import 'pos_sessions_table.dart';
import 'users_table.dart';

class ExpenseRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(ExpenseCategories, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get expenseDate => dateTime()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get sessionId =>
      integer().nullable().references(PosSessions, #id)();
  IntColumn get createdBy =>
      integer().references(UsersTable, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index(
          'expense_records_category_idx',
          'CREATE INDEX IF NOT EXISTS expense_records_category_idx ON expense_records (category_id)',
        ),
        Index(
          'expense_records_paid_at_idx',
          'CREATE INDEX IF NOT EXISTS expense_records_paid_at_idx ON expense_records (paid_at)',
        ),
        Index(
          'expense_records_session_idx',
          'CREATE INDEX IF NOT EXISTS expense_records_session_idx ON expense_records (session_id)',
        ),
        Index(
          'expense_records_voided_idx',
          'CREATE INDEX IF NOT EXISTS expense_records_voided_idx ON expense_records (is_voided)',
        ),
      ];
}