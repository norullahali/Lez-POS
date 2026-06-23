import 'package:drift/drift.dart';

import 'other_income_categories_table.dart';
import 'pos_sessions_table.dart';
import 'users_table.dart';

class OtherIncomeRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(OtherIncomeCategories, #id)();
  RealColumn get amount =>
      real().customConstraint('NOT NULL CHECK (amount > 0)')();
  DateTimeColumn get incomeDate => dateTime()();
  DateTimeColumn get receivedAt => dateTime()();
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
          'other_income_records_category_idx',
          'CREATE INDEX IF NOT EXISTS other_income_records_category_idx'
          ' ON other_income_records (category_id)',
        ),
        Index(
          'other_income_records_received_at_idx',
          'CREATE INDEX IF NOT EXISTS other_income_records_received_at_idx'
          ' ON other_income_records (received_at)',
        ),
        Index(
          'other_income_records_session_idx',
          'CREATE INDEX IF NOT EXISTS other_income_records_session_idx'
          ' ON other_income_records (session_id)',
        ),
        Index(
          'other_income_records_voided_idx',
          'CREATE INDEX IF NOT EXISTS other_income_records_voided_idx'
          ' ON other_income_records (is_voided)',
        ),
      ];
}
